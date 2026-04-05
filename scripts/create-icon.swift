#!/usr/bin/env swift
// Generates AppIcon.icns — document page + "MD" title + content lines
import Cocoa

let iconsetPath = "/tmp/MarkdownReader.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func createIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let accent = NSColor(red: 0.85, green: 0.48, blue: 0.29, alpha: 1.0)

    // ── 1. Background: warm gradient rounded rect ──
    let bg1 = NSColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1.0)
    let bg2 = NSColor(red: 0.89, green: 0.86, blue: 0.81, alpha: 1.0)
    let cornerRadius = s * 0.22
    let bgRect = NSRect(x: 0, y: 0, width: s, height: s)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    if let gradient = NSGradient(starting: bg1, ending: bg2) {
        gradient.draw(in: bgPath, angle: -90)
    }
    NSColor(red: 0.82, green: 0.79, blue: 0.74, alpha: 0.7).setStroke()
    bgPath.lineWidth = max(1, s * 0.008)
    bgPath.stroke()

    // ── 2. White page with drop shadow ──
    let pageInsetX = s * 0.17
    let pageInsetBottom = s * 0.12
    let pageInsetTop = s * 0.10
    let pageRect = NSRect(
        x: pageInsetX, y: pageInsetBottom,
        width: s - pageInsetX * 2,
        height: s - pageInsetBottom - pageInsetTop
    )
    let pageRadius = s * 0.04

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.02)
    shadow.shadowBlurRadius = s * 0.06
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: pageRect, xRadius: pageRadius, yRadius: pageRadius).fill()
    ctx.restoreGState()

    NSColor(red: 0.88, green: 0.86, blue: 0.83, alpha: 0.5).setStroke()
    let pagePath = NSBezierPath(roundedRect: pageRect, xRadius: pageRadius, yRadius: pageRadius)
    pagePath.lineWidth = max(0.5, s * 0.004)
    pagePath.stroke()

    // ── 3. "MD" text on the page ──
    let mdFontSize = s * 0.19
    let mdFont = NSFont.systemFont(ofSize: mdFontSize, weight: .heavy)
    let mdAttrs: [NSAttributedString.Key: Any] = [
        .font: mdFont,
        .foregroundColor: accent,
        .kern: s * 0.008
    ]
    let mdStr: NSString = "MD"
    let mdSize = mdStr.size(withAttributes: mdAttrs)
    let mdX = pageRect.minX + (pageRect.width - mdSize.width) / 2
    let mdY = pageRect.maxY - mdSize.height - s * 0.06
    mdStr.draw(at: NSPoint(x: mdX, y: mdY), withAttributes: mdAttrs)

    // Thin accent underline below "MD"
    accent.setFill()
    let underlineY = mdY - s * 0.025
    let underlineW = mdSize.width * 1.1
    let underlineH = max(1.5, s * 0.015)
    let underlineX = pageRect.minX + (pageRect.width - underlineW) / 2
    NSBezierPath(roundedRect: NSRect(x: underlineX, y: underlineY, width: underlineW, height: underlineH),
                 xRadius: underlineH / 2, yRadius: underlineH / 2).fill()

    // ── 4. Content lines below "MD" ──
    let contentInset = s * 0.07
    let contentLeft = pageRect.minX + contentInset
    let contentWidth = pageRect.width - contentInset * 2
    let lineH = max(1.5, s * 0.02)
    let lineGap = s * 0.043
    let lineColor = NSColor(red: 0.80, green: 0.78, blue: 0.74, alpha: 0.9)
    lineColor.setFill()

    let startY = underlineY - lineGap * 1.2
    let lengths: [CGFloat] = [0.92, 0.75, 0.85, 0.60, 0.80, 0.70]
    for (i, pct) in lengths.enumerated() {
        let y = startY - CGFloat(i) * lineGap
        if y < pageRect.minY + s * 0.04 { break }
        let w = contentWidth * pct
        NSBezierPath(roundedRect: NSRect(x: contentLeft, y: y, width: w, height: lineH),
                     xRadius: lineH / 2, yRadius: lineH / 2).fill()
    }

    image.unlockFocus()
    return image
}

let specs: [(name: String, size: Int)] = [
    ("icon_16x16",       16),  ("icon_16x16@2x",    32),
    ("icon_32x32",       32),  ("icon_32x32@2x",    64),
    ("icon_128x128",     128), ("icon_128x128@2x",  256),
    ("icon_256x256",     256), ("icon_256x256@2x",  512),
    ("icon_512x512",     512), ("icon_512x512@2x",  1024)
]

for spec in specs {
    let image = createIcon(size: spec.size)
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(spec.name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", "/tmp/AppIcon.icns"]
try! process.run()
process.waitUntilExit()
print(process.terminationStatus == 0 ? "Icon created: /tmp/AppIcon.icns" : "Failed")
