import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// Reads the game's marker for the controller. `MarkerCapture` is the one implementation; tests use fakes.
public protocol MarkerSource: AnyObject, Sendable {
    /// Starts reading the marker in the largest on-screen window of the app. `onReading` is called on a
    /// private queue for every captured frame, nil when the marker is not in it. `onStop` is called if
    /// the system ends the capture, for example when the window goes away.
    func start(bundleIdentifier: String, onReading: @escaping @Sendable (MarkerState?) -> Void,
               onStop: @escaping @Sendable () -> Void) async throws
    func stop() async
}

public enum MarkerCaptureError: Error, Sendable, Equatable, CustomStringConvertible {
    case notPermitted
    case windowNotFound
    case failed(String)

    public var description: String {
        switch self {
        case .notPermitted: "Screen Recording is not allowed"
        case .windowNotFound: "the game has no window on screen"
        case .failed(let message): message
        }
    }
}

/// Streams a small region at the top centre of the game's window and decodes the addon's marker in
/// every frame. Only that region is captured, never the rest of the screen. Needs Screen Recording.
public final class MarkerCapture: NSObject, MarkerSource, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// The region searched, in points, centred at the top of the window: the marker sits at the top
    /// edge, or below the title bar of a titled window.
    public static let searchSize = CGSize(width: 160, height: 64)

    private let queue = DispatchQueue(label: "hof.marker-capture", qos: .userInteractive)
    private var stream: SCStream?
    // Capture queue only.
    private var decoder = MarkerDecoder()
    private var onReading: @Sendable (MarkerState?) -> Void = { _ in }
    private var onStop: @Sendable () -> Void = {}

    public override init() {}

    public func start(bundleIdentifier: String, onReading: @escaping @Sendable (MarkerState?) -> Void,
                      onStop: @escaping @Sendable () -> Void) async throws {
        guard CGPreflightScreenCaptureAccess() else { throw MarkerCaptureError.notPermitted }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw MarkerCaptureError.failed("listing windows failed: \(error.localizedDescription)")
        }
        let candidates = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == bundleIdentifier && $0.isOnScreen && $0.windowLayer == 0
        }
        guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            throw MarkerCaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let size = Self.searchSize
        let rect = CGRect(x: max(0, (window.frame.width - size.width) / 2), y: 0,
                          width: min(size.width, window.frame.width), height: min(size.height, window.frame.height))
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        config.showsCursor = false
        config.queueDepth = 4

        queue.sync {
            decoder = MarkerDecoder()
            self.onReading = onReading
            self.onStop = onStop
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            throw MarkerCaptureError.failed("starting the capture failed: \(error.localizedDescription)")
        }
        self.stream = stream
    }

    public func stop() async {
        guard let stream else { return }
        self.stream = nil
        queue.sync { onReading = { _ in }; onStop = {} }
        try? await stream.stopCapture()
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return }
        switch status {
        case .complete:
            guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
            let hit = decoder.decode(base, width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb),
                                     bytesPerRow: CVPixelBufferGetBytesPerRow(pb))
            onReading(hit?.state)
        case .idle:
            // Nothing changed on screen, so the last reading still holds; repeat it to keep it fresh.
            onReading(decoder.last?.state)
        default:
            break
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.onStop() }
    }
}
