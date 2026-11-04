import AppKit
import AVFoundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let asset = AVURLAsset(url: input)
guard let track = asset.tracks(withMediaType: .video).first else {
    fail("Video track missing")
}
let reader = try AVAssetReader(asset: asset)
let frames = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
reader.add(frames)
guard reader.startReading() else { fail("Video reader did not start: \(String(describing: reader.error))") }
let context = CIContext(options: [.useSoftwareRenderer: true])
var samples: [[String: Any]] = []
var thumbnails: [(Double, CGImage)] = []
var nextThumbnail = CommandLine.arguments.count > 3
    ? max(0, Double(CommandLine.arguments[3]) ?? 0) : 0.0
while let sample = frames.copyNextSampleBuffer() {
    guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
    let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
    CVPixelBufferLockBaseAddress(pixels, .readOnly)
    let bytes = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
    let width = CVPixelBufferGetWidth(pixels)
    let height = CVPixelBufferGetHeight(pixels)
    let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
    var white = 0, dark = 0, total = 0
    for y in stride(from: height / 10, to: height * 9 / 10, by: 12) {
        for x in stride(from: width / 10, to: width * 9 / 10, by: 12) {
            let index = y * rowBytes + x * 4
            let rgb = [bytes[index], bytes[index + 1], bytes[index + 2]]
            if rgb.allSatisfy({ $0 >= 242 }) { white += 1 }
            if rgb.allSatisfy({ $0 <= 48 }) { dark += 1 }
            total += 1
        }
    }
    CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
    samples.append(["seconds": time, "whiteFraction": Double(white) / Double(total),
                    "darkFraction": Double(dark) / Double(total)])
    if time >= nextThumbnail && thumbnails.count < 20 {
        let image = CIImage(cvPixelBuffer: pixels)
        if let cg = context.createCGImage(image, from: image.extent) {
            thumbnails.append((time, cg))
        }
        nextThumbnail += 0.2
    }
}
guard reader.status == .completed else { fail("Incomplete video read: \(String(describing: reader.error))") }
let cell = NSSize(width: 210, height: 480)
let sheet = NSImage(size: NSSize(width: cell.width * 5, height: cell.height * 4))
sheet.lockFocus()
NSColor.white.setFill()
NSRect(origin: .zero, size: sheet.size).fill()
for (index, item) in thumbnails.enumerated() {
    let x = Double(index % 5) * cell.width
    let y = sheet.size.height - Double(index / 5 + 1) * cell.height
    let image = NSImage(cgImage: item.1, size: .zero)
    image.draw(in: NSRect(x: x, y: y + 22, width: 210, height: 458))
    NSString(format: "%.3f s", item.0).draw(at: NSPoint(x: x + 4, y: y + 3),
        withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])
}
sheet.unlockFocus()
let bitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.deletingPathExtension().appendingPathExtension("json"))
print("Decoded \(samples.count) frames, last timestamp \(samples.last?["seconds"] ?? "missing"); contact sheet: \(output.path)")
