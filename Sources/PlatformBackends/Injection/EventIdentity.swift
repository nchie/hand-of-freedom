/// What the event tap extracts from a CGEvent to decide whether we posted it. CoreGraphics stops here.
public struct EventIdentity: Sendable, Equatable, BitwiseCopyable {
    /// kCGEventSourceUnixProcessID: our pid for events generated from IOHIDPostEvent.
    public var sourcePID: Int64
    /// kCGEventSourceUserData.
    public var sourceUserData: Int64

    public init(sourcePID: Int64, sourceUserData: Int64) {
        self.sourcePID = sourcePID
        self.sourceUserData = sourceUserData
    }
}
