import Testing
import Runtime

@Suite("Activation rule")
struct ActivationRuleTests {
    func ready() -> ActivationInputs {
        var i = ActivationInputs()
        i.targetFrontmost = true
        i.tapInstalled = true
        return i
    }

    @Test func actsOnlyWhenEverythingIsGreen() {
        #expect(ActivationRule.isActive(ready()))
        var i = ready(); i.enabled = false
        #expect(!ActivationRule.isActive(i))
        i = ready(); i.targetFrontmost = false
        #expect(!ActivationRule.isActive(i))
        i = ready(); i.injectorHealthy = false
        #expect(!ActivationRule.isActive(i))
        i = ready(); i.tapInstalled = false
        #expect(!ActivationRule.isActive(i))
        i = ready(); i.permissions.accessibility = .denied
        #expect(!ActivationRule.isActive(i))
    }

    @Test func gateIsOptionalOnlyWhenNotRequired() {
        var i = ready()
        i.tapInstalled = false
        i.tapRequired = false
        #expect(ActivationRule.isActive(i))
    }

    @Test func onlyThePermissionsPostingNeedsBlock() {
        var i = ready()
        i.permissions.inputMonitoring = .denied            // the gate's grant: shows up as the gate missing instead
        #expect(ActivationRule.isActive(i))
        i.postingRequires = [.postEvents]
        i.permissions.accessibility = .denied
        #expect(ActivationRule.isActive(i))
        i.permissions.postEvents = .denied
        #expect(ActivationRule.blockers(i) == [.missingPermission(.postEvents)])
    }

    @Test func blockersComeInFixOrder() {
        var i = ActivationInputs()
        i.enabled = false
        i.permissions.accessibility = .denied
        i.injectorHealthy = false
        #expect(ActivationRule.blockers(i) == [.disabled, .missingPermission(.accessibility), .injectorUnavailable,
                                               .gateNotInstalled, .targetNotFrontmost])
    }
}
