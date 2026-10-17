#!/usr/bin/env swift
import AppKit
import PDFKit

// Original Display Save artwork, drawn only from geometric paths. The two
// staggered landscape displays are shared by both app and menu.
// Run from any directory: swift scripts/generate-assets.swift
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fileManager = FileManager.default
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let assets = root.appendingPathComponent("Sources/DisplaySave/Assets", isDirectory: true)
let scratch = root.appendingPathComponent(".build/asset-generation-\(UUID().uuidString)", isDirectory: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func rounded(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fill(_ path: NSBezierPath, with color: NSColor) {
    color.setFill()
    path.fill()
}

func gradient(_ path: NSBezierPath, from start: NSColor, to end: NSColor, angle: CGFloat) {
    NSGradient(starting: start, ending: end)!.draw(in: path, angle: angle)
}

// All coordinates are in a 22 x 18 unit canvas, including transparent screen
// cutouts. No white masking fills: template tint must preserve the interiors.
func drawMonitors(in rect: NSRect, shell: NSColor, glass: Bool) {
    NSGraphicsContext.saveGraphicsState()
    let placement = NSAffineTransform()
    placement.translateX(by: rect.minX, yBy: rect.minY)
    placement.scaleX(by: rect.width / 22, yBy: rect.height / 18)
    placement.concat()

    let rear = NSRect(x: 1.1, y: 6.2, width: 14.8, height: 9.6)
    let front = NSRect(x: 9.5, y: 2.3, width: 11.4, height: 7.8)

    func screen(_ frame: NSRect, foreground: Bool) {
        let opening = frame.insetBy(dx: 0.9, dy: 0.9)
        if glass {
            gradient(
                rounded(opening, radius: 0.25),
                from: foreground ? color(0.10, 0.31, 0.47) : color(0.07, 0.21, 0.36),
                to: foreground ? color(0.17, 0.62, 0.67) : color(0.11, 0.42, 0.51),
                angle: 65
            )
        }
        let bezel = rounded(frame, radius: 0.8)
        bezel.append(rounded(opening, radius: 0.25))
        bezel.windingRule = .evenOdd
        fill(bezel, with: shell)
    }

    // A transparent separation around the foreground screen preserves depth
    // in the monochrome template without an opaque masking rectangle.
    NSGraphicsContext.saveGraphicsState()
    let rearClip = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 22, height: 18))
    rearClip.append(rounded(front.insetBy(dx: -0.55, dy: -0.55), radius: 1.35))
    rearClip.windingRule = .evenOdd
    rearClip.addClip()
    screen(rear, foreground: false)
    fill(rounded(NSRect(x: 7.5, y: 3.4, width: 1.4, height: 3.1), radius: 0.2), with: shell)
    fill(rounded(NSRect(x: 5.4, y: 2.8, width: 5.6, height: 0.9), radius: 0.4), with: shell)
    NSGraphicsContext.restoreGraphicsState()

    screen(front, foreground: true)
    fill(rounded(NSRect(x: 14.4, y: 0.8, width: 1.6, height: 1.8), radius: 0.2), with: shell)
    fill(rounded(NSRect(x: 11.7, y: 0.2, width: 6.9, height: 0.85), radius: 0.4), with: shell)
    NSGraphicsContext.restoreGraphicsState()
}

func png(width: Int, height: Int, draw: () -> Void) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "DisplaySaveAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create bitmap context"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.cgContext.setShouldAntialias(true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DisplaySaveAssets", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot encode PNG"])
    }
    return data
}

func appIcon(size: Int) throws -> Data {
    try png(width: size, height: size) {
        NSGraphicsContext.saveGraphicsState()
        let scale = CGFloat(size) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()

        let tile = rounded(NSRect(x: 96, y: 96, width: 832, height: 832), radius: 184)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(0.02, 0.08, 0.17, alpha: 0.3)
        shadow.shadowBlurRadius = 25
        shadow.shadowOffset = NSSize(width: 0, height: -13)
        shadow.set()
        fill(tile, with: color(0.05, 0.18, 0.29))
        NSGraphicsContext.restoreGraphicsState()
        gradient(tile, from: color(0.04, 0.16, 0.30), to: color(0.08, 0.49, 0.57), angle: 55)

        // A quiet inset edge gives the tile definition without extra symbols.
        let edge = rounded(NSRect(x: 99, y: 99, width: 826, height: 826), radius: 181)
        color(0.72, 0.96, 1, alpha: 0.20).setStroke()
        edge.lineWidth = 3
        edge.stroke()

        let artwork = NSRect(x: 156, y: 250, width: 712, height: 582.55)
        NSGraphicsContext.saveGraphicsState()
        let monitorShadow = NSShadow()
        monitorShadow.shadowColor = color(0, 0.04, 0.10, alpha: 0.3)
        monitorShadow.shadowBlurRadius = 14
        monitorShadow.shadowOffset = NSSize(width: 0, height: -8)
        monitorShadow.set()
        drawMonitors(in: artwork, shell: color(0.91, 0.98, 1), glass: true)
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
    }
}

func writeStatusPDF() throws {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 22, height: 18)
    guard let consumer = CGDataConsumer(data: data),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw NSError(domain: "DisplaySaveAssets", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create PDF context"])
    }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    drawMonitors(in: mediaBox, shell: .black, glass: false)
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()

    // Strip ambient document metadata and use fixed, project-only values.
    guard let document = PDFDocument(data: data as Data) else {
        throw NSError(domain: "DisplaySaveAssets", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot reopen generated PDF"])
    }
    document.documentAttributes = [
        PDFDocumentAttribute.titleAttribute: "Display Save status icon",
        PDFDocumentAttribute.creatorAttribute: "Display Save asset generator",
        PDFDocumentAttribute.creationDateAttribute: Date(timeIntervalSince1970: 0),
        PDFDocumentAttribute.modificationDateAttribute: Date(timeIntervalSince1970: 0),
    ]
    guard let result = document.dataRepresentation() else {
        throw NSError(domain: "DisplaySaveAssets", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot encode PDF"])
    }
    try result.write(to: assets.appendingPathComponent("StatusIcon.pdf"), options: .atomic)
}

func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(at: NSPoint(x: (640 - size.width) / 2, y: y), withAttributes: attributes)
}

func writeDMGBackground() throws {
    let data = try png(width: 640, height: 420) {
        gradient(NSBezierPath(rect: NSRect(x: 0, y: 0, width: 640, height: 420)),
                 from: color(0.91, 0.96, 0.97), to: color(0.98, 0.99, 1), angle: 90)
        drawCentered("Display Save", y: 349, font: .systemFont(ofSize: 27, weight: .semibold), color: color(0.10, 0.23, 0.30))

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 285, y: 210))
        arrow.line(to: NSPoint(x: 355, y: 210))
        arrow.move(to: NSPoint(x: 343, y: 222))
        arrow.line(to: NSPoint(x: 355, y: 210))
        arrow.line(to: NSPoint(x: 343, y: 198))
        arrow.lineWidth = 3
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        color(0.30, 0.50, 0.56).setStroke()
        arrow.stroke()

        drawCentered("Drag to Applications", y: 48, font: .systemFont(ofSize: 15, weight: .medium), color: color(0.25, 0.39, 0.44))
    }
    try data.write(to: resources.appendingPathComponent("DMGBackground.png"), options: .atomic)
}

try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: scratch) }
let iconset = scratch.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let destination = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try appIcon(size: points * scale).write(to: destination)
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", resources.appendingPathComponent("AppIcon.icns").path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    throw NSError(domain: "DisplaySaveAssets", code: Int(iconutil.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}
try writeStatusPDF()
try writeDMGBackground()
print("Generated Resources/AppIcon.icns, Resources/DMGBackground.png, and Sources/DisplaySave/Assets/StatusIcon.pdf")
