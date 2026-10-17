#ifndef DISPLAY_HARDWARE_H
#define DISPLAY_HARDWARE_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

bool DSRotationAvailable(void);
// Submits a request; callers must asynchronously verify CGDisplayRotation.
bool DSSetRotation(CGDirectDisplayID display, int degrees);
// UTF-8 detail for the last rejected request on the calling thread.
const char *DSRotationLastError(void);

#ifdef __cplusplus
}
#endif

#endif
