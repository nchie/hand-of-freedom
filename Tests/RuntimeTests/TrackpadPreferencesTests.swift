import Testing
import Runtime

@Suite("Trackpad preferences")
struct TrackpadPreferencesTests {
    /// This Mac at the time of writing: three-finger swipes on Mission Control and full-screen apps, no three-finger drag.
    let thisMac = ["TrackpadThreeFingerDrag": 0, "TrackpadThreeFingerHorizSwipeGesture": 2, "TrackpadThreeFingerVertSwipeGesture": 2]

    @Test func swipesAreFineWhileGesturesAreSwallowed() {
        #expect(TrackpadPreferences.conflicts(in: thisMac, threeFingersMapped: true, swallowGestures: true).isEmpty)
        #expect(TrackpadPreferences.conflicts(in: thisMac, threeFingersMapped: true, swallowGestures: false) == [.threeFingerSwipes])
    }

    @Test func threeFingerDragAlwaysConflicts() {
        var prefs = thisMac
        prefs["TrackpadThreeFingerDrag"] = 1
        #expect(TrackpadPreferences.conflicts(in: prefs, threeFingersMapped: true, swallowGestures: true) == [.threeFingerDrag])
    }

    @Test func nothingConflictsWhenThreeFingersAreOff() {
        let prefs = ["TrackpadThreeFingerDrag": 1, "TrackpadThreeFingerVertSwipeGesture": 2]
        #expect(TrackpadPreferences.conflicts(in: prefs, threeFingersMapped: false, swallowGestures: false).isEmpty)
    }
}
