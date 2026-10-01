import AppKit
import AVFoundation
import CoreGraphics

enum FilmCrop: String, CaseIterable {
    case notch, panel, full

    func rect(in view: CGSize) -> CGRect {
        switch self {
        case .notch: CGRect(x: view.width / 2 - 220, y: 0, width: 440, height: 180)
        case .panel: CGRect(origin: .zero, size: view)
        case .full: CGRect(x: -170, y: 0, width: view.width + 340, height: view.height + 40)
        }
    }
}

struct FilmStage {
    let view: CGSize
    let scale: CGFloat
    let cutout: CGSize?
    let crop: FilmCrop
    let backdrop: CGImage?

    var canvas: CGRect { crop.rect(in: view) }

    var pixelSize: (width: Int, height: Int) {
        let r = canvas
        return (Int((r.width * scale / 2).rounded()) * 2, Int((r.height * scale / 2).rounded()) * 2)
    }

    func compose(_ panel: CGImage, pointer: CGPoint?) -> CGImage? {
        let size = pixelSize
        guard let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        let r = canvas
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(size.height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -r.minX, y: -r.minY)

        ctx.setFillColor(CGColor(red: 0.12, green: 0.125, blue: 0.14, alpha: 1))
        ctx.fill(r)
        if let backdrop { draw(backdrop, in: backdropRect(backdrop), on: ctx) }
        draw(panel, in: CGRect(origin: .zero, size: view), on: ctx)
        if let pointer { drawCursor(at: pointer, on: ctx) }
        if let cutout { drawCutout(cutout, on: ctx) }
        return ctx.makeImage()
    }

    private func backdropRect(_ image: CGImage) -> CGRect {
        let width = max(1280, canvas.width)
        let height = width * CGFloat(image.height) / CGFloat(image.width)
        return CGRect(x: view.width / 2 - width / 2, y: 0, width: width, height: height)
    }

    private func draw(_ image: CGImage, in rect: CGRect, on ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    static func arrow(at tip: CGPoint) -> CGPath {
        let outline: [(CGFloat, CGFloat)] = [(0, 0), (0, 16.5), (4, 12.6), (6.8, 19), (9.6, 17.8), (6.9, 11.6), (12, 11.6)]
        let path = CGMutablePath()
        path.addLines(between: outline.map { CGPoint(x: tip.x + $0.0, y: tip.y + $0.1) })
        path.closeSubpath()
        return path
    }

    private func drawCursor(at tip: CGPoint, on ctx: CGContext) {
        let arrow = Self.arrow(at: tip)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1 * scale), blur: 2 * scale, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(arrow)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(arrow)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(1.1)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    static func cutout(_ size: CGSize, centeredAt midX: CGFloat, corner: CGFloat = 9, fillet: CGFloat = 3) -> CGPath {
        let x0 = midX - size.width / 2, x1 = midX + size.width / 2, h = size.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x0 - fillet, y: 0))
        path.addQuadCurve(to: CGPoint(x: x0, y: fillet), control: CGPoint(x: x0, y: 0))
        path.addLine(to: CGPoint(x: x0, y: h - corner))
        path.addQuadCurve(to: CGPoint(x: x0 + corner, y: h), control: CGPoint(x: x0, y: h))
        path.addLine(to: CGPoint(x: x1 - corner, y: h))
        path.addQuadCurve(to: CGPoint(x: x1, y: h - corner), control: CGPoint(x: x1, y: h))
        path.addLine(to: CGPoint(x: x1, y: fillet))
        path.addQuadCurve(to: CGPoint(x: x1 + fillet, y: 0), control: CGPoint(x: x1, y: 0))
        path.closeSubpath()
        return path
    }

    private func drawCutout(_ size: CGSize, on ctx: CGContext) {
        ctx.addPath(Self.cutout(size, centeredAt: view.width / 2))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
    }
}

@MainActor
final class FilmVideo {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let fps: Int32
    private let size: (width: Int, height: Int)

    init(url: URL, width: Int, height: Int, fps: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 12,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: fps,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        self.fps = Int32(fps)
        self.size = (width, height)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CGImage, frame: Int) {
        guard let pool = adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: size.width, height: size.height,
                               bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
    }

    func finish() async throws {
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }
}
