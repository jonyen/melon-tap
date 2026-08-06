# Melon Tap — Design

**Date:** 2026-08-06
**Status:** Approved for planning

## Problem

Picking a ripe watermelon by thumping it is folklore with real physics behind it, but the
feedback loop is broken: you learn whether you were right an hour later, at home, with no
record of what the melon sounded like. This app closes that loop. In the store it ranks the
melons in front of you; at home you record how each one actually turned out.

## Prior art

Several iPhone apps already score watermelon ripeness from a tap — Melon Aid, Watermelon
Sounds Ripe, Melony, and iWatermelon Deluxe (2011). All of them are black boxes: one verdict,
no visible features, no record of whether the verdict was right. iWatermelon asks for the
melon's size and color, which is a tell that its author hit the same size confound described
below.

The research is less encouraging than the app listings suggest. The classic acoustic firmness
index for spherical fruit, f²·m^(2/3), works well on apple, pear, and mango but correlates
weakly on watermelon — thick rind, large volume, and a non-uniform interior all break the
assumptions. Recent sensor work (MDPI Sensors, 2026) gets usable accuracy only by combining
acoustic and vibration signals and feeding the result to a trained model.

Two conclusions shape this design. There is no published threshold worth copying, so the app
should compare melons against each other rather than against an absolute number. And since a
trained model is where this eventually has to go, every capture must be logged in a form that
can train one later.

## Scope

Version one is a personal build, installed from Xcode onto one iPhone and one Apple Watch.
No App Store review, no onboarding, no privacy policy. Capture is acoustic and vibrational —
no camera. A visual ripeness check (field spot color, webbing) is explicitly out of scope.

## What it does

**In the store.** Press the Watch face against the rind and tap Capture, then knuckle-tap the
melon three times beside it. The Watch records the taps through both its microphone and its
accelerometer, extracts features on-wrist, scores the melon, and shows it ranked against the
other melons captured in the same session. The phone stays in your pocket.

**At home.** After cutting a melon, open the phone app and label it: ripe, unripe, overripe,
or mushy. That label attaches to the stored recording and features.

## The size confound

A melon's resonant frequency depends on its mass and diameter as much as on its ripeness. A
large ripe melon and a small unripe one can ring at the same pitch, which is why an absolute
verdict needs a mass estimate and careful calibration that no public data supports.

Ranking melons within a single bin sidesteps this. Melons in one bin are usually the same
variety and a similar size, so the size term is roughly constant and differences in the score
are dominated by ripeness. The app therefore never claims "this melon is ripe" — it claims
"of the five you tapped, this one is most likely the ripest."

## Architecture

Three targets:

- **MelonKit** — a Swift package holding the entire signal pipeline. No UI, no platform
  frameworks, no I/O. Both apps depend on it, so feature extraction and scoring exist in
  exactly one place and are unit-tested off-device.
- **Melon Tap (iOS)** — the archive and the labeling interface. Owns persistent storage.
- **Melon Tap (watchOS)** — the capture device and the in-store display.

### MelonKit

`OnsetDetector` takes a sample buffer and a sample rate and returns the start indices of tap
transients, found by short-time energy rise against an adaptive noise floor. Onsets below an
amplitude threshold are rejected, which discards cart rumble and nearby conversation. Sample-rate
agnostic, so the same detector serves the 44.1 kHz microphone stream and the 800 Hz
accelerometer stream.

`FeatureExtractor` is a pure function: a window and its sample rate in, a `ChannelFeatures`
value out. It computes the dominant peak frequency within a 20–400 Hz band, the spectral
centroid, the envelope decay rate, and the ratio of low-band to high-band energy. FFT via
Accelerate/vDSP. Being stateless and platform-free, it is testable against synthesized signals
with known properties.

`RipenessScorer` is a protocol taking a melon's taps and returning a score plus a per-feature
breakdown. `PhysicsScorer` is the only implementation in version one. The protocol exists so
that a nearest-neighbor scorer over logged melons, and later a Core ML model, can be dropped in
without touching capture, storage, or UI.

### Scoring

Riper flesh is softer and less dense, so it resonates lower and damps faster. `PhysicsScorer`
therefore treats lower peak frequency, faster envelope decay, and energy skewed toward the low
band as evidence of ripeness, and combines them into a weighted composite. Every weight lives
in a single constants file.

Each melon yields two `ChannelFeatures` per tap — one microphone, one accelerometer — across
three taps. The tap whose composite deviates most from the other two is discarded and the
remaining two are averaged, which absorbs a mishit or a stray noise burst.

The accelerometer channel is weighted above the microphone channel, on the theory that contact
vibration is immune to store noise. This weighting is a guess. It stands until the logged data
contradicts it, and it is one number to change when it does.

### Watch capture

The 800 Hz accelerometer stream comes from `CMBatchedSensorManager`, which requires Apple Watch
Series 8 or later and an active HealthKit workout session. Capture therefore starts an
`HKWorkoutSession` of type `.other`, runs the microphone via `AVAudioEngine` and the
accelerometer together for roughly four seconds, then ends the session without finishing the
workout builder, so nothing is written to Health.

Sample rate matters here. Watermelon fundamentals fall between roughly 50 and 300 Hz. The
800 Hz batched stream has a Nyquist limit of 400 Hz and covers that band cleanly. The ordinary
`CMMotionManager` path caps at 100 Hz and would alias the signal into nonsense, so it is never
used for capture.

Onsets are detected on the accelerometer stream, which has a sharper transient and less ambient
energy than the microphone. The onset timestamps then window both channels, so the two channels
describe the same three taps.

### Sync

The Watch scores and ranks locally and displays the ranking on the wrist; nothing about the
in-store experience waits on the phone.

Extracted features are small, roughly a kilobyte per melon, and go to the phone through
`WCSession.sendMessage` as soon as they exist, falling back to `transferUserInfo` when the phone
is unreachable. Raw audio and accelerometer arrays are large and go through `transferFile`,
which delivers opportunistically. Nothing in the user-facing flow blocks on file transfer.

### Storage

The phone owns the archive, in SwiftData. A `Session` represents one bin visit and holds many
`Melon` records. A `Melon` holds its three taps' `ChannelFeatures` for both channels, the
composite score, its rank within the session, references to the raw audio and accelerometer
files in the app's documents directory, an optional note, and an optional `Outcome` — ripe,
unripe, overripe, or mushy — recorded after cutting.

Storing raw signals alongside features is deliberate. Features can be re-extracted with a better
extractor later; a discarded recording cannot.

## Interface

**Watch.** One capture screen: a Capture button, a countdown while recording, then the melon's
score and its rank among the melons captured so far. A short list shows the session's melons
ordered best first.

**Phone, three screens.** A session list. A melon detail view showing the raw feature numbers
and a spectrum plot for both channels, so the physics can be inspected rather than trusted. A
history view listing melons that have no outcome label yet, each one label-able in a single tap.

## Failure modes

- Apple Watch Series 7 or older: `CMBatchedSensorManager` is unavailable. The Watch falls back
  to microphone-only capture and says so explicitly rather than silently scoring one channel.
- HealthKit permission denied: same fallback, same explicit message.
- Fewer than three clean onsets detected: the app refuses to score and asks for a retap. A
  score built from one ambiguous transient is worse than no score.
- Ambient noise floor too high for the microphone channel: warn, and score on accelerometer
  alone.
- Microphone or motion permission denied at first launch: explain what is needed and link to
  Settings.
- Watch unreachable: features and files queue in `WCSession` and deliver later. No capture is
  lost.

## Testing

MelonKit is tested properly, because it is the part that can be tested properly. The feature
extractor is verified against synthesized decaying sinusoids with known frequency and decay
constants. The onset detector is verified against a recorded clip with hand-marked tap positions
and added background noise. The scorer is verified for ordering invariants — that lowering peak
frequency or shortening decay moves a melon toward the ripe end.

Capture, sync, and storage are verified manually against real melons. There is no way to unit-test
whether a wrist-worn accelerometer pressed against a rind measures ripeness; only cutting melons
answers that.

## Known risk

The accelerometer channel is unvalidated. No shipping app uses contact vibration this way, and
the research supporting it used laboratory instrumentation rather than a watch pressed against
fruit by hand. Press force may well dominate the signal. The channel may turn out to be the
entire value of this app or it may turn out to be noise, and the logging design exists precisely
so that the answer is discoverable rather than assumed.

## Deferred

- Visual ripeness check from a photo — field spot color, webbing, sheen.
- Nearest-neighbor scoring against previously labeled melons, once enough are logged.
- A Core ML model trained on the accumulated dataset.
- Absolute ripe/unripe verdicts, which require mass normalization and calibration data that
  does not yet exist.
- TestFlight distribution to other people, which would collect ground truth faster.
