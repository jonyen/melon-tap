# Melon Tap

Rank the watermelons in a store bin by knuckle-tapping them, then record how each one
actually turned out after you cut it.

Thumping a melon is folklore with real physics behind it, but the feedback loop is broken:
you find out whether you were right an hour later, at home, with no record of what the melon
sounded like. Melon Tap closes that loop. The Apple Watch does the capture and scoring in the
store; the iPhone keeps the archive and takes the ground-truth label at home.

## It ranks, it does not judge

A melon's resonant frequency depends on its mass and diameter as much as on its ripeness, so a
large ripe melon and a small unripe one can ring at the same pitch. Absolute verdicts need a
mass estimate and calibration data that no published research supports for watermelon —
the classic acoustic firmness index `f²·m^(2/3)` works on apple, pear, and mango but correlates
weakly here.

So the app never claims "this melon is ripe." It claims "of the five you tapped, this one is
most likely the ripest." Melons in one bin are usually the same variety and a similar size, so
the size term is roughly constant and score differences are dominated by ripeness.

## How it works

**In the store.** Press the Watch face against the rind, tap Capture, then knuckle-tap the melon
three times beside it. The Watch records ~4 seconds through both its microphone and its
accelerometer, extracts features on-wrist, scores the melon, and shows it ranked against the
other melons captured in the same session. The phone stays in your pocket.

**At home.** After cutting a melon, open the phone app and label it ripe, unripe, overripe, or
mushy. The label attaches to the stored features and to the raw recording.

Riper flesh is softer and less dense, so it resonates lower and damps faster. The scorer treats
lower peak frequency, faster envelope decay, and energy skewed toward the low band as evidence of
ripeness. Of the three taps, the one whose composite deviates most from the other two is dropped
and the remaining two are averaged, which absorbs a mishit or a stray noise burst.

Raw signals are stored alongside the extracted features on purpose. Features can be re-extracted
with a better extractor later; a discarded recording cannot.

## Requirements

- Apple Watch Series 8 or later, watchOS 11+. The 800 Hz accelerometer stream comes from
  `CMBatchedSensorManager`, which needs Series 8 hardware and an active HealthKit workout
  session. Older Watches fall back to microphone-only capture and say so explicitly.
- iPhone, iOS 18+.
- Xcode 16+ (Swift 6), plus [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`.
- No third-party dependencies anywhere in the project.

Sample rate is the reason for the hardware floor. Watermelon fundamentals fall between roughly
50 and 300 Hz; the 800 Hz stream has a Nyquist limit of 400 Hz and covers that band cleanly. The
ordinary `CMMotionManager` path caps at 100 Hz and would alias the signal into nonsense, so it is
never used for capture.

## Build

The Xcode project is generated, not committed (`*.xcodeproj` is gitignored):

```sh
xcodegen generate
open MelonTap.xcodeproj
```

Then set your own `DEVELOPMENT_TEAM` in `project.yml` and build the `MelonTap` scheme to a paired
iPhone. The watchOS app is embedded in the iOS app and installs alongside it.

This is a personal build installed from Xcode — no App Store review, no onboarding, no privacy
policy, no analytics.

### Tests

The whole signal pipeline lives in `MelonKit`, a platform-free Swift package with no UI and no
I/O, so it tests off-device on macOS:

```sh
swift test --package-path MelonKit
```

The feature extractor is verified against synthesized decaying sinusoids with known frequency and
decay constants, the onset detector against fixtures with hand-marked tap positions and added
background noise, and the scorer for ordering invariants — lowering peak frequency or shortening
decay must move a melon toward the ripe end.

Capture, sync, and storage are verified manually against real melons. There is no way to unit-test
whether a wrist-worn accelerometer pressed against a rind measures ripeness; only cutting melons
answers that.

### App icon

`Tools/makeicon.swift` renders the 1024pt master icon (a watermelon slice) from code. It takes an
output path:

```sh
swift Tools/makeicon.swift iOS/Assets.xcassets/AppIcon.appiconset/icon.png
swift Tools/makeicon.swift Watch/Assets.xcassets/AppIcon.appiconset/icon.png
```

## Layout

```
MelonKit/          Swift package: the entire signal pipeline. No UI, no platform frameworks, no I/O.
  AnalysisConstants.swift   Every tunable number, in one file
  Spectrum.swift            FFT wrapper over Accelerate/vDSP
  FeatureExtractor.swift    Window + sample rate in, ChannelFeatures out. Pure function.
  OnsetDetector.swift       Tap transient finder, sample-rate agnostic
  PhysicsScorer.swift       The only RipenessScorer in v1
iOS/               The archive and the labeling interface. Owns SwiftData storage.
Watch/             The capture device and the in-store display.
Tools/             Icon generation.
docs/              Design spec and implementation plan.
```

Both apps depend on MelonKit, so feature extraction and scoring exist in exactly one place.
`RipenessScorer` is a protocol so a nearest-neighbor scorer over logged melons, and later a Core ML
model, can be dropped in without touching capture, storage, or UI.

Onsets are detected on the accelerometer stream, which has a sharper transient and less ambient
energy than the microphone. Those timestamps then window both channels, so the two channels
describe the same three taps.

The Watch scores and ranks locally — nothing in the in-store flow waits on the phone. Features
(~1 KB per melon) go over `WCSession.sendMessage`, falling back to `transferUserInfo` when the
phone is unreachable. Raw audio and accelerometer arrays go through `transferFile`, which delivers
opportunistically.

## Tuning

Every threshold and weight lives in `MelonKit/Sources/MelonKit/AnalysisConstants.swift`, each one
documented with how it was arrived at. Retuning happens there and nowhere else.

Two constants are explicitly marked `UNVALIDATED`:

- `accelerometerChannelWeight` (0.65) — the accelerometer is weighted above the microphone on the
  theory that contact vibration is immune to store noise. This is a guess.
- `outlierDeviationThreshold` (0.15) — the mishit-rejection threshold, calibrated against a
  synthetic fixture rather than real mishit data. It fires silently and discards a third of a
  capture's evidence when it does.

Both stand until logged melons with outcome labels contradict them.

## Known risk

The accelerometer channel is unvalidated. No shipping app uses contact vibration this way, and the
research supporting it used laboratory instrumentation rather than a watch pressed against fruit by
hand. Press force may well dominate the signal. The channel may turn out to be the entire value of
this app, or it may turn out to be noise — the logging design exists precisely so the answer is
discoverable rather than assumed.

## Not in v1

- Visual ripeness check from a photo (field spot color, webbing, sheen).
- Nearest-neighbor scoring against previously labeled melons, once enough are logged.
- A Core ML model trained on the accumulated dataset.
- Absolute ripe/unripe verdicts.
- TestFlight distribution, which would collect ground truth faster.

See `docs/superpowers/specs/2026-08-06-melon-tap-design.md` for the full design rationale.
