import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

// mp4 -> animated GIF, cropping a region and scaling to a target width.
// usage: gifmaker in.mp4 out.gif fps width cropX cropY cropW cropH

let a = CommandLine.arguments
guard a.count >= 5 else {
    FileHandle.standardError.write("usage: gifmaker in.mp4 out.gif fps width [cropX cropY cropW cropH] [--from S] [--dur S]\n".data(using: .utf8)!)
    exit(2)
}
var startAt: Double = 0
var window: Double = -1
if let i = a.firstIndex(of: "--from"), i + 1 < a.count { startAt = Double(a[i+1]) ?? 0 }
if let i = a.firstIndex(of: "--dur"), i + 1 < a.count { window = Double(a[i+1]) ?? -1 }
let inURL = URL(fileURLWithPath: a[1])
let outURL = URL(fileURLWithPath: a[2])
let fps = Double(a[3]) ?? 15
let targetW = Int(a[4]) ?? 640
var crop: CGRect? = nil
if a.count >= 9 {
    crop = CGRect(x: Double(a[5])!, y: Double(a[6])!, width: Double(a[7])!, height: Double(a[8])!)
}

let asset = AVURLAsset(url: inURL)
let sem = DispatchSemaphore(value: 0)
var duration: Double = 0
var natural = CGSize.zero

Task {
    duration = try await asset.load(.duration).seconds
    if let track = try await asset.loadTracks(withMediaType: .video).first {
        natural = try await track.load(.naturalSize)
    }
    sem.signal()
}
sem.wait()

guard duration > 0, natural != .zero else {
    FileHandle.standardError.write("could not read the video\n".data(using: .utf8)!)
    exit(1)
}

let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600)
gen.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 600)

let span = window > 0 ? min(window, duration - startAt) : duration - startAt
let frameCount = Int(span * fps)
let delay = 1.0 / fps

guard let dest = CGImageDestinationCreateWithURL(
    outURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil
) else {
    FileHandle.standardError.write("could not create the gif\n".data(using: .utf8)!)
    exit(1)
}

CGImageDestinationSetProperties(dest, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
] as CFDictionary)

let frameProps = [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay,
                                    kCGImagePropertyGIFDelayTime: delay]
] as CFDictionary

var written = 0
for i in 0..<frameCount {
    let t = CMTime(seconds: startAt + Double(i) * delay, preferredTimescale: 600)
    guard var cg = try? gen.copyCGImage(at: t, actualTime: nil) else { continue }

    if let c = crop, let cropped = cg.cropping(to: c) { cg = cropped }

    let srcW = CGFloat(cg.width), srcH = CGFloat(cg.height)
    let scale = CGFloat(targetW) / srcW
    let outW = targetW, outH = Int((srcH * scale).rounded())

    guard let ctx = CGContext(
        data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { continue }
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    guard let scaled = ctx.makeImage() else { continue }

    CGImageDestinationAddImage(dest, scaled, frameProps)
    written += 1
}

guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write("could not finalize the gif\n".data(using: .utf8)!)
    exit(1)
}

let bytes = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0
print("\(written) frames · \(Int(natural.width))x\(Int(natural.height)) source · \((bytes ?? 0)/1024) KB")
