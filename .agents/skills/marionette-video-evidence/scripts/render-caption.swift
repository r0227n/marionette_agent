import AppKit
import Foundation

// Render literal UTF-8 text for an evidence overlay; no shell/filter syntax.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard (5...6).contains(args.count),
      let width = Int(args[1]), let height = Int(args[2]),
      (320...4096).contains(width), (200...8192).contains(height)
else { fail("Usage: render-caption <width 320...4096> <height 200...8192> <text-file> <new.png> [font-size 16...160]") }

let input = URL(fileURLWithPath: args[3]).standardizedFileURL
let output = URL(fileURLWithPath: args[4]).standardizedFileURL
guard input.resolvingSymlinksInPath() != output.resolvingSymlinksInPath(),
      !FileManager.default.fileExists(atPath: output.path)
else { fail("Output must be new and different from input") }
guard let text = try? String(contentsOf: input, encoding: .utf8),
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
else { fail("Input must be nonempty UTF-8 text") }

let margin = CGFloat(width) * 0.03
let requestedFontSize = args.count == 6 ? Double(args[5]) : min(160, max(16, Double(width) / 22))
guard let requestedFontSize, requestedFontSize.isFinite,
      (16...160).contains(requestedFontSize) else { fail("Invalid font size") }
let fontSize = CGFloat(requestedFontSize)
let style = NSMutableParagraphStyle()
style.lineBreakMode = .byWordWrapping
style.lineSpacing = fontSize * 0.2
style.paragraphSpacing = fontSize * 0.25
let attributed = NSAttributedString(string: text, attributes: [
    .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
    .foregroundColor: NSColor.white,
    .paragraphStyle: style,
])
let textWidth = CGFloat(width) - 2 * margin
let measured = attributed.boundingRect(
    with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)
guard ceil(measured.height) <= CGFloat(height) - 2 * margin else {
    fail("Caption does not fit; shorten it or increase panel dimensions")
}
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fail("Cannot allocate caption bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(srgbRed: 0.055, green: 0.08, blue: 0.13, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
NSColor(srgbRed: 0.25, green: 0.85, blue: 0.92, alpha: 1).setFill()
NSRect(x: margin, y: CGFloat(height) - margin - 8, width: textWidth, height: 8).fill()
attributed.draw(
    with: NSRect(x: margin, y: (CGFloat(height) - ceil(measured.height)) / 2,
                 width: textWidth, height: ceil(measured.height)),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fail("Cannot encode caption PNG")
}
do {
    try png.write(to: output, options: .withoutOverwriting)
} catch {
    fail("Cannot write new caption PNG")
}
