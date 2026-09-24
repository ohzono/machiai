#!/usr/bin/env swift
// Renders the Machiai app icon into an .appiconset directory.
// Usage: swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.appiconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 body with ~185/1024 corner radius.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = s * 185 / 1024

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: NSColor.black.withAlphaComponent(0.28).cgColor)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bodyPath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 0.36, green: 0.39, blue: 0.86, alpha: 1).cgColor,
        NSColor(srgbRed: 0.20, green: 0.21, blue: 0.55, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.restoreGState()

    func bubble(_ rect: CGRect, tailLeft: Bool, fill: NSColor) {
        let r = rect.height * 0.28
        let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        let tail = NSBezierPath()
        let tx = tailLeft ? rect.minX + rect.width * 0.22 : rect.maxX - rect.width * 0.22
        let dir: CGFloat = tailLeft ? -1 : 1
        tail.move(to: CGPoint(x: tx - rect.width * 0.08, y: rect.minY + 1))
        tail.line(to: CGPoint(x: tx + dir * rect.width * 0.10, y: rect.minY - rect.height * 0.22))
        tail.line(to: CGPoint(x: tx + rect.width * 0.08, y: rect.minY + 1))
        tail.close()
        fill.setFill()
        path.fill()
        tail.fill()
    }

    func glyph(_ text: String, in rect: CGRect, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: text, attributes: attrs)
        let b = str.size()
        str.draw(at: CGPoint(x: rect.midX - b.width / 2, y: rect.midY - b.height / 2 + size * 0.02))
    }

    // Back bubble: your words (あ).
    let back = CGRect(x: s * 0.22, y: s * 0.47, width: s * 0.40, height: s * 0.28)
    bubble(back, tailLeft: true, fill: NSColor.white.withAlphaComponent(0.30))
    glyph("あ", in: back, size: s * 0.16, color: NSColor.white.withAlphaComponent(0.95), weight: .semibold)

    // Front bubble: in English (A).
    let front = CGRect(x: s * 0.38, y: s * 0.25, width: s * 0.42, height: s * 0.30)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.02,
                  color: NSColor.black.withAlphaComponent(0.25).cgColor)
    bubble(front, tailLeft: false, fill: .white)
    ctx.restoreGState()
    glyph("A", in: front, size: s * 0.18, color: NSColor(srgbRed: 0.24, green: 0.25, blue: 0.64, alpha: 1), weight: .bold)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = pt * scale
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try render(px).write(to: outDir.appendingPathComponent(name))
        images.append(["size": "\(pt)x\(pt)", "idiom": "mac", "filename": name, "scale": "\(scale)x"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(outDir.path)")
