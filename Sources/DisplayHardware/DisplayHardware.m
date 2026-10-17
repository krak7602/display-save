#import "DisplayHardware.h"
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#include <string.h>

static NSString *const DSErrorKey = @"DisplaySaveRotationError";

static void DSSetError(NSString *message) {
    [NSThread currentThread].threadDictionary[DSErrorKey] = message;
}

const char *DSRotationLastError(void) {
    NSString *message = [NSThread currentThread].threadDictionary[DSErrorKey];
    return message ? message.UTF8String : "The rotation request was rejected without additional detail.";
}

static Class DSDisplayClass(void) {
    static dispatch_once_t once;
    static Class displayClass;
    dispatch_once(&once, ^{
        // Intentionally keep the framework loaded for the lifetime of the process.
        void *handle = dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_LAZY | RTLD_LOCAL);
        if (handle) {
            displayClass = NSClassFromString(@"MPDisplay");
        }
    });
    return displayClass;
}

bool DSRotationAvailable(void) {
    Class cls = DSDisplayClass();
    return cls != Nil &&
        class_getInstanceMethod(cls, NSSelectorFromString(@"initWithCGSDisplayID:")) != NULL &&
        class_getInstanceMethod(cls, NSSelectorFromString(@"setOrientation:")) != NULL;
}

static const char *DSUnqualifiedType(const char *type) {
    while (*type && strchr("rnNoORV", *type)) { ++type; }
    return type;
}

static BOOL DSSetIntegerArgument(NSInvocation *invocation, NSMethodSignature *signature, uint32_t value) {
    if (signature.numberOfArguments != 3) { return NO; }
    const char *type = DSUnqualifiedType([signature getArgumentTypeAtIndex:2]);
    if (strcmp(type, @encode(int)) == 0 || strcmp(type, @encode(unsigned int)) == 0) {
        uint32_t argument = value;
        [invocation setArgument:&argument atIndex:2];
        return YES;
    }
    if (strcmp(type, @encode(long)) == 0 || strcmp(type, @encode(unsigned long)) == 0) {
        unsigned long argument = value;
        [invocation setArgument:&argument atIndex:2];
        return YES;
    }
    if (strcmp(type, @encode(long long)) == 0 || strcmp(type, @encode(unsigned long long)) == 0) {
        unsigned long long argument = value;
        [invocation setArgument:&argument atIndex:2];
        return YES;
    }
    return NO;
}

bool DSSetRotation(CGDirectDisplayID display, int degrees) {
    @autoreleasepool {
        DSSetError(@"");
        if (degrees != 0 && degrees != 90 && degrees != 180 && degrees != 270) {
            DSSetError(@"Only rotations of 0°, 90°, 180°, and 270° are supported.");
            return false;
        }
        if (!CGDisplayIsOnline(display)) {
            DSSetError(@"The display disconnected before rotation. Reconnect it and try again.");
            return false;
        }
        if (!DSRotationAvailable()) {
            DSSetError(@"This macOS version does not expose the MonitorPanel rotation interface. Set rotation in System Settings instead.");
            return false;
        }

        void *allocation = NULL;
        id panel = nil;
        @try {
            Class cls = DSDisplayClass();
            // NSInvocation does not model init-family ownership for ARC. Hold
            // the allocation explicitly until init consumes it, then transfer
            // the retained result back to ARC.
            allocation = (__bridge_retained void *)[cls alloc];
            __unsafe_unretained id allocated = (__bridge id)allocation;
            SEL initializer = NSSelectorFromString(@"initWithCGSDisplayID:");
            NSMethodSignature *signature = [allocated methodSignatureForSelector:initializer];
            if (!signature || strcmp(DSUnqualifiedType(signature.methodReturnType), @encode(id)) != 0) {
                DSSetError(@"MonitorPanel changed its display initializer ABI. Set rotation in System Settings instead.");
                return false;
            }
            NSInvocation *initialize = [NSInvocation invocationWithMethodSignature:signature];
            initialize.target = allocated;
            initialize.selector = initializer;
            if (!DSSetIntegerArgument(initialize, signature, display)) {
                DSSetError(@"MonitorPanel changed its display-ID argument ABI. Set rotation in System Settings instead.");
                return false;
            }
            [initialize invoke];
            allocation = NULL; // init consumed the allocation, even if it returns nil.
            void *initialized = NULL;
            [initialize getReturnValue:&initialized];
            panel = CFBridgingRelease(initialized);
            if (!panel) {
                DSSetError(@"MonitorPanel could not open this display. Reconnect it or set rotation in System Settings.");
                return false;
            }

            SEL canRotate = NSSelectorFromString(@"canChangeOrientation");
            if ([panel respondsToSelector:canRotate]) {
                NSMethodSignature *capability = [panel methodSignatureForSelector:canRotate];
                const char *resultType = capability ? DSUnqualifiedType(capability.methodReturnType) : "";
                if (!capability || capability.numberOfArguments != 2 ||
                    (strcmp(resultType, @encode(BOOL)) != 0 && strcmp(resultType, @encode(bool)) != 0)) {
                    DSSetError(@"MonitorPanel changed its rotation capability ABI. Set rotation in System Settings instead.");
                    return false;
                }
                NSInvocation *query = [NSInvocation invocationWithMethodSignature:capability];
                query.target = panel;
                query.selector = canRotate;
                [query invoke];
                BOOL supported = NO;
                [query getReturnValue:&supported];
                if (!supported) {
                    DSSetError(@"This display or its driver does not support rotation. Choose a preset with its current orientation or use System Settings.");
                    return false;
                }
            }

            SEL setter = NSSelectorFromString(@"setOrientation:");
            signature = [panel methodSignatureForSelector:setter];
            if (!signature || strcmp(DSUnqualifiedType(signature.methodReturnType), @encode(void)) != 0) {
                DSSetError(@"MonitorPanel changed its rotation setter ABI. Set rotation in System Settings instead.");
                return false;
            }
            NSInvocation *rotate = [NSInvocation invocationWithMethodSignature:signature];
            rotate.target = panel;
            rotate.selector = setter;
            if (!DSSetIntegerArgument(rotate, signature, (uint32_t)degrees)) {
                DSSetError(@"MonitorPanel changed its orientation argument ABI. Set rotation in System Settings instead.");
                return false;
            }
            [rotate invoke];
            return true;
        } @catch (NSException *exception) {
            DSSetError([NSString stringWithFormat:@"MonitorPanel rejected rotation (%@): %@. Set rotation in System Settings instead.", exception.name, exception.reason ?: @"no reason supplied"]);
            return false;
        }
        @finally {
            if (allocation) { CFRelease(allocation); }
        }
    }
}
