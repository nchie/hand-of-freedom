import GestureCore

public struct TouchDeviceInfo: Sendable, Codable, Equatable {
    public var index: Int
    public var isBuiltIn: Bool
    public init(index: Int, isBuiltIn: Bool) { self.index = index; self.isBuiltIn = isBuiltIn }
}

public enum TouchSourceError: Error, Sendable, Equatable {
    case frameworkUnavailable(String)
    case noBuiltInDevice
    case startFailed(Int32)
}

public protocol TouchFrameSink: AnyObject, Sendable {
    /// Called on the source's own thread for every frame. Must return in microseconds and never block.
    func handle(_ frame: TouchFrame)
}

public protocol TouchSource: AnyObject, Sendable {
    var devices: [TouchDeviceInfo] { get }
    /// The sink is set on the first start and kept for the life of the source.
    func start(sink: any TouchFrameSink) throws(TouchSourceError)
    /// Returns only when no callback is running and no further frame will reach the sink.
    func stop()
    /// stop, re-enumerate, start again with the same sink. Used after wake.
    func restart() throws(TouchSourceError)
    /// Contacts dropped by sanity checks since start. Non-zero suggests the private layout changed.
    var rejectedContacts: Int32 { get }
}

extension TouchSource {
    public var rejectedContacts: Int32 { 0 }
}
