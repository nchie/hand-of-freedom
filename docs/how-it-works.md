# How it works

## From touch to mouse input

```
trackpad ─► MultitouchSupport callback ─► HotLoop ─► GestureEngine ─► IOHIDPostEvent ─► the game
                                             │ atomics          │ ring buffer
                                             ▼                  ▼
                              event tap, watchdog, UI     trace writer (clips, sessions)
```

Everything that decides and sends input runs synchronously inside the MultitouchSupport callback, on
the framework's own thread: one trackpad frame in, at most four posted events out, no thread hop. Other
threads talk to it only through atomics and a lock-free ring buffer.

## Targets

| Target | Owns |
|---|---|
| `CMultitouchSupport` (C) | The private framework: `dlopen`, the `MTTouch` layout, the callback trampoline. The only place it appears. |
| `CHIDInject` (C) | `IOHIDPostEvent`: buttons, relative moves, scroll. |
| `GestureCore` | The gesture engine and the gate policy. Standard library only: no Foundation, no clocks, no allocation per frame. |
| `PlatformBackends` | Touch source, injector, event tap, marker capture (ScreenCaptureKit). |
| `Runtime` | Hot loop, cross-thread primitives, traces and replay, settings, `PipelineController` (lifecycle, permissions, faults). |
| `HandOfFreedomApp` | The menu bar app (SwiftUI). |
| `hof` | Developer CLI: `log`, `record`, `replay`, `live`, `permissions`, `probe`, `check`. |

Rule of thumb: gesture decisions go in `GestureCore`; anything touching IOKit, CoreGraphics events or a
private framework goes in `PlatformBackends`; threads, timers, files and atomics go in `Runtime`.

## Hot-path rules

Inside the touch callback: no heap allocation, no locks, no Objective-C, no strings or logging, no calls
back into MultitouchSupport. Every type touched per frame is `BitwiseCopyable`. A release-build test
counts allocations while replaying frames and fails on any.

The activation flag is read before the config mailbox, and the controller publishes a config before
raising the flag, so the first active frame already uses it.

## The gesture engine

`GestureEngine.process` is pure and deterministic: the same frames, configs and flags always give the
same outputs. It never reads a clock; every window is counted in frames. That is what makes recorded
traces replay exactly. Stages, in order:

- **ContactTracker**: contacts by id, with short-lived ghosts for dropouts.
- **ContactClassifier**: palms by size and shape, thumbs by when and where they land. Roles are sticky.
- **FingerCounter**: counts fingers; decides lifts by phase, not by a missing count.
- **PairGeometry** and **PinchController**: the spread between two fingers. A leaky baseline absorbs slow
  drift during a turn; a real pinch emits scroll ticks (zoom).
- **GroupMotion**: the fingers' shared movement. While pinching, movement along the finger axis that the
  fingers do not share is dropped, so a pinch does not turn the camera.
- **DragController**: the state machine. `idle → armed → dragging → suspended`. The button goes down only
  after 0.5 mm of travel, so a tap is never a click; the button and fingers are fixed at the press, so a
  grazing finger cannot switch buttons; the first finger to lift ends the drag, so the end of a turn is
  never a click. A gesture can also be routed away from the game (see below).
- **MotionMapper**: millimetres to pixels, carrying the sub-pixel remainder.

## Scrolling

While the tool acts, an event tap holds back the trackpad's own scroll and gesture events, so they do
not fight the turn. A gesture can instead be routed:

- **scroll**: nothing is pressed; the tap lets that gesture's scroll events through, momentum included,
  and the window under the pointer scrolls natively.
- **ignore**: nothing happens at all.

The route comes from a held key (Settings › Gestures) or from the game itself. The addon in
`Addon/HandOfFreedom` draws three 4-pixel squares at the top centre of the game: magenta, a state colour,
yellow. Green means the world, blue a window that takes the mouse wheel, red any other window. The app
captures only a 160×64 pt strip of the game's window and decodes them. A reading older than 2 s is
ignored, and then gestures turn as usual.

## Traces

The hot loop pushes every frame, output, posted event and state change into the ring. The trace writer
drains it into JSON Lines (`.hoftrace.jsonl`): a rolling 30-second window for clips, or a whole session.
`hof replay` runs a trace through a fresh engine and regenerates every decision, which is how thresholds
were tuned and how bug-report clips are read.

## Facts that shaped the design

- **IOHIDPostEvent, not CGEvent.** The game ignores the delta fields of posted CGEvents and derives
  motion from cursor positions, and it warps its hidden cursor during mouselook, so position-based events
  make the camera jump. IOHIDPostEvent posts relative motion the way a real mouse does. It is deprecated
  but still works on macOS 26; its replacement, IOHIDUserDevice, needs a restricted entitlement.
- **Accessibility is the only grant needed.** Without it, IOHIDPostEvent returns success but nothing
  arrives, and the event tap cannot be created. Input Monitoring only matters to listen-only taps, which
  only `hof probe` uses.
- **Our own events** carry our process id in `eventSourceUnixProcessID`; the tap uses it to let them pass.
- **The game's interface stops below the notch** (64 px on a 14-inch MacBook Pro), but the world is drawn
  to the top edge. The marker anchors to the world, so it sits hidden behind the notch.
- **Fingers lift unevenly and shrink while lifting.** A lifting contact's centre slides toward the
  fingertip, so frames where a finger has shrunk below 70 % of its peak size add no drag-start travel.
- **macOS 26 SwiftUI window sizing.** Letting a `Form` or `TabView` size its window loops layout and
  crashes, so windows have fixed content sizes.
- **Ad hoc signatures change with every build**, and macOS ties privacy grants to the exact build.
