import CoreFoundation
import Foundation

/// A dedicated user-interactive thread with its own run loop for the event tap, so a busy main thread
/// can never delay or time out the tap.
public final class TapThread: @unchecked Sendable {
    public private(set) var runLoop: CFRunLoop?
    private var thread: Thread?

    public init() {}

    /// Starts the thread and returns once its run loop exists. `everySecond` runs on that thread.
    public func start(everySecond: @escaping @Sendable () -> Void) {
        guard thread == nil else { return }
        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [self] in
            let rl = CFRunLoopGetCurrent()!
            let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 1, 1, 0, 0) { _ in
                everySecond()
            }
            CFRunLoopAddTimer(rl, timer, .commonModes)
            self.runLoop = rl
            ready.signal()
            CFRunLoopRun()
        }
        t.name = "hof.tap"
        t.qualityOfService = .userInteractive
        t.start()
        ready.wait()
        thread = t
    }

    public func stop() {
        if let runLoop { CFRunLoopStop(runLoop) }
        thread = nil
        runLoop = nil
    }
}
