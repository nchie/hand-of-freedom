import Testing
import GestureCore
import Runtime

@Suite("Status presentation")
struct StatusPresentationTests {
    func status(_ blockers: [ActivationBlocker], active: Bool = false) -> PipelineStatus {
        var s = PipelineStatus()
        s.blockers = blockers
        s.active = active
        s.profileName = active ? "World of Warcraft" : nil
        return s
    }

    func show(_ s: PipelineStatus, _ phase: EngineState.Phase = .idle) -> StatusPresentation {
        .make(s, phase: phase, targetName: "World of Warcraft")
    }

    @Test func readyWaitingAndDragging() {
        #expect(show(status([], active: true)) == .init(symbol: .ready, dimmed: false, headline: "Ready in World of Warcraft"))
        #expect(show(status([.targetNotFrontmost])) == .init(symbol: .waiting, dimmed: true, headline: "Waiting for World of Warcraft"))
        #expect(show(status([], active: true), .dragging(.right, members: 2)).headline == "Dragging right, 2 fingers")
        #expect(show(status([], active: true), .dragging(.right, members: 2)).symbol == .dragging)
    }

    @Test func faultsNeedAttentionWhetherOrNotTheGameIsFrontmost() {
        #expect(show(status([.missingPermission(.accessibility), .gateNotInstalled, .targetNotFrontmost])).needsAttention)
        #expect(show(status([.injectorUnavailable])).needsAttention)
        var s = status([], active: true)
        s.trackpadDataSuspicious = true
        #expect(show(s).needsAttention)
        s.trackpadDataSuspicious = false
        s.tapUnstable = true
        #expect(show(s).needsAttention)
    }

    @Test func disabledWinsOverEverything() {
        #expect(show(status([.disabled, .missingPermission(.accessibility)])).symbol == .disabled)
    }
}
