# AniiStudio: Touch on Mac readiness

Research date: November 1, 2026. Target-device validation: Friday, November 6, after Kevin's MacBook Pro arrives. This is a researched implementation plan and source audit, not a claim of tested touchscreen support.

## Verified Apple guidance

Apple's October 28 announcement confirms direct Touch on MacBook Pro with PROLED XDR Display and availability beginning November 6. Single-finger interactions can be translated into clicks; custom multi-finger interactions need appropriate gesture handling. Keep keyboard and trackpad workflows first-class.

- [Hardware announcement](https://www.apple.com/newsroom/2026/10/apple-unveils-groundbreaking-macbook-pro-with-proled-xdr-display/)
- [Touch on Mac developer hub](https://developer.apple.com/touch-on-mac/)
- [Design for touch on Mac](https://developer.apple.com/videos/play/tech-talks/111456/)
- [Bring Touch to your Mac app](https://developer.apple.com/videos/play/tech-talks/111468/)

Apple's AppKit guidance recommends moving custom mouse tracking to gesture recognizers. Direct multi-touch does not arrive through ordinary mouse event monitors. Recognizers need explicit cancellation handling; a stuck recognizer can leave input blocked. An iPad over Sidecar provides an earlier test route if compatible hardware/software is available, but does not replace testing the built-in display.

- [Adopting gesture recognizers](https://developer.apple.com/documentation/appkit/adopting-gesture-recognizers-in-your-app)
- [TN3212: Sidecar touch](https://developer.apple.com/documentation/technotes/tn3212-adopting-gesture-recognizers-for-sidecar-touch-support)

Apple's HIG favors a consistent Mac layout across input types, larger invisible tap targets rather than universally larger visual controls, standard controls where suitable, and alternatives to hover or keyboard-modified actions. Our touch design should preserve the existing visual direction.

- [Gestures HIG](https://developer.apple.com/design/human-interface-guidelines/gestures)
- [GestureInputKinds](https://developer.apple.com/documentation/swiftui/gestureinputkinds)

## Local SDK verification

Current tools report Xcode 27.2, build 27B52. The installed SDK declares NSScreen.TouchCapabilities.multiTouch, NSGestureRecognizer.allowedTouchTypes and SwiftUI GestureInputKinds.directTouch/pointer. The inspected NSWindow header does not declare disablesDirectTouchSystemGestures. Apple's developer hub currently labels Xcode27.3 beta Coming soon. Do not introduce unverified symbol names or opt the whole app into a native-touch declaration prematurely. Keep the macOS14 deployment target with availability guards for new APIs.

## Audit and implementation order

| Priority | Area | Current source finding | Planned work |
|---|---|---|---|
| 1 | Homeland canvas | HomelandSceneKitView.swift overrides mouseDown/Dragged/Up and uses a4-point drag threshold | Introduce a gesture intent layer shared by recognizers and pointer handling; preserve current pointer behavior during migration |
| 1 | Cancellation | Existing cancelObjectDrag restores camera/cursor and discards preview | Reuse this rollback path for cancelled gestures, window changes and a second finger |
| 1 | Creature viewer | CreatureStage3D.swift uses SceneKit default camera control | Validate direct drag orbit and pinch zoom; coordinate new recognizers with SceneKit to prevent duplicate camera updates |
| 2 | Roster and toolbar | Small icon buttons, turntable switch and storage controls | Expand hit areas without crowding or overlapping neighbors; maintain scroll responsiveness |
| 2 | Selection and hover | Hover highlight and keyboard shortcuts supplement selection | Keep persistent selection outlines; expose visible Focus, Reset Camera, Snap and precision controls |
| 2 | Placement | Move preview is separate from live Apply | Touch edits remain local previews; camera navigation must never dispatch a game change |
| 3 | Performance | Models use continuous rendering while visible | Measure input latency, frame pacing and power; pause offscreen/hidden stages where safe |

Proposed canvas interactions, pending device validation:

- Tap selects an object or roster card.
- Navigate mode: one-finger drag orbits, pinch zooms, two-finger pan translates the camera.
- Move Preview mode: one-finger drag moves only the selected object on its ground plane; pinch/two-finger gestures stay camera-only.
- Long press opens secondary actions, with an ordinary visible menu alternative.
- Rotation/height remain accessible through explicit controls until gesture conflicts are tested.
- Each touch sequence has one owner. Beginning a multi-finger camera gesture must cancel an object drag rather than commit it.

## Before Friday

Extract/test selection-versus-drag thresholds, gesture ownership, cancellation, axis locks and zoom limits as pure interaction logic. Add availability-gated recognizers in a development build and regression-test mouse, trackpad, keyboard, snapping and Undo. Audit overlays for event interception. Preserve the signed working app and fresh-map snapshots.

## Friday hardware acceptance

Record exact Mac model, macOS build, SDK and display scaling. Verify taps near edges, fast input switching, simultaneous gestures, scroll-versus-selection, long press, model zoom limits, external-display window moves and cancelled drags. Check Jeburst, Fulmintis and Sugartini at multiple sizes. Run placement tests in preview only first, then separately authorize any live save. Test touch responsiveness under game/renderer load and with Reduce Motion enabled.

Research-pass status: research and audit complete; direct built-in-display behavior remains untested. The implementation checkpoint below records the subsequent gesture implementation. No game state changed.

## Implementation checkpoint — November 1

Shared `SceneDirectTouchController` now attaches direct-only AppKit recognizers on macOS 27. One-finger drag orbits; Homeland move-preview can drag the selected object and rolls back on cancellation. Two-finger drag pans Homeland; pinch zooms both views with finite bounded distance. Creature translation stays disabled to preserve centering, and touch interaction stops its turntable. Existing mouse/trackpad responder paths remain in place. Scene changes and detached windows cancel touch gestures.

Direct hardware acceptance remains pending November 6. Verify tap selection, move-preview confirm/cancel, adding a second finger mid-drag, pinch direction, two-finger pan, model framing, and switching between direct touch and mouse/trackpad. Recognizers intentionally serialize gestures; simultaneous pinch-and-pan is not enabled. Test every supported display scaling and a narrow inspector. No live-game writes were introduced.
