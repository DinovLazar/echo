//
//  AudioManager.swift
//  ECHO
//
//  Phase 2.04 (Generative move-audio — the signature feature). The whole first
//  audio pass for ECHO, in one MainActor-owned `AVAudioEngine`. Every successful
//  step plays a soft pitched-percussion tick — one per moving entity (the player
//  and each echo that stepped), fired *simultaneously* so a busy turn is heard as a
//  chord and a recorded run is heard as a rhythm. Because echoes replay their moves
//  in lockstep, a solved room re-voices itself as a small loop of percussion the
//  player composed by solving it (Plan §5/§14, "the signature feature").
//
//  Three restrained event sounds round out the pass, each timed to the 2.03
//  animation beat already playing: the **fold** (warm, weighty — lands on the §6c
//  hit-pause), the **death** (a calm, muted puff — lands on the §6d particle fizz),
//  and the **solve** (a short gentle resolving figure — lands as you reach the exit).
//
//  Architecture (D-045): one `AVAudioEngine` with a small pool of `AVAudioPlayerNode`s
//  into the main mixer, all playing short `AVAudioPCMBuffer`s that are **procedurally
//  synthesized once at startup** — no bundled audio files, so the public repo stays
//  asset-free and every pitch is exact and tunable in code. The engine and its
//  (non-`Sendable`) nodes are owned by this `@MainActor` type and touched only from
//  `MainActor`, so the Swift 6 concurrency checks stay clean; there is deliberately
//  **no** `AVAudioSourceNode` real-time render block (that would put synthesis on the
//  audio thread under `@Sendable`/nonisolated constraints — avoided by design).
//
//  Voicing (D-046): the step tick is soft pitched percussion (a marimba/kalimba-like
//  "pock"), with the four move directions mapped to four pitches from a fixed
//  **pentatonic** set — up = higher, down = lower, left/right = the middle tones — so
//  any combination of simultaneous ticks stays consonant and each entity's path reads
//  as a little melodic phrase.
//
//  Session (D-047): `.ambient` + `.mixWithOthers` — ECHO mixes politely with the
//  user's own audio and is silenced by the hardware mute switch (a quiet puzzle game
//  should never play over music or sound through silent mode). The in-app sound
//  toggle (2.06) is the primary control; this phase exposes only its binding point.
//
//  `var isEnabled` gates all playback — the single Settings hook (no toggle UI, no
//  persistence; that is Phase 2.06). When `false`, every trigger is a no-op.
//

import Foundation
import AVFoundation

/// Owns the one `AVAudioEngine` and the synthesized sound bank, and plays the
/// game's sounds on demand. Created and `start()`-ed at app launch (`ContentView`)
/// and kept alive for the session so the first tick has no spin-up latency.
@MainActor
final class AudioManager {
    /// Gates **all** playback. Default `true`. This is the only Settings hook —
    /// Phase 2.06 binds a real, persisted toggle to it; nothing else changes here.
    /// Flipping it off makes every `play…` call a no-op (already-scheduled tails,
    /// at most ~half a second, finish naturally — there is nothing harsh to cut).
    var isEnabled: Bool = true

    // MARK: Engine + node pool

    private let engine = AVAudioEngine()

    /// The processing format every buffer is built in and every player node is
    /// connected with: 44.1 kHz mono float. The main mixer up-mixes mono → the
    /// hardware channel count and the engine resamples to the device rate, so the
    /// synthesis math stays in one fixed, device-independent format.
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    /// A small pool of player nodes. Each simultaneous voice (each tick in a chord,
    /// or an event sound) is scheduled on its own node, because one player node is a
    /// single voice — it cannot sound two overlapping buffers at once. 16 is far more
    /// than any room needs (max simultaneous ticks = the player + echoes that stepped,
    /// bounded by the room's small echo budget).
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private static let poolSize = 16

    /// A small scheduling lead so all voices of one turn share a single future host
    /// time and start sample-aligned (a chord, not a flam). ~15 ms is imperceptible
    /// and keeps the tick well under the 100 ms input-to-response budget.
    private static let scheduleLead: TimeInterval = 0.015

    /// Master headroom: with per-voice peaks kept low (~0.15) and the mixer trimmed,
    /// even a dense in-phase chord stays below full scale, so a busy turn never clips
    /// without needing a limiter unit.
    private static let masterVolume: Float = 0.75

    private var started = false

    // MARK: Synthesized sound bank (built once at init)

    /// One marimba-like tick buffer per move direction, pitched on a fixed pentatonic
    /// set (up highest, down lowest, left/right the middle tones).
    private var stepBuffers: [Direction: AVAudioPCMBuffer] = [:]
    /// The fold sound — a warm descending settle, weighty but restrained.
    private var foldBuffer: AVAudioPCMBuffer!
    /// The death sound — a calm muted low tone + soft filtered-noise puff.
    private var deathBuffer: AVAudioPCMBuffer!
    /// The solve flourish — a short gentle ascending pentatonic resolve.
    private var solveBuffer: AVAudioPCMBuffer!

    // MARK: Lifecycle

    /// Builds the sound bank and wires the node pool into the engine graph. Cheap and
    /// side-effect-free (no session, no engine start) so it is safe to construct in a
    /// SwiftUI `@State` initializer and in previews; `start()` does the rest.
    init() {
        buildSoundBank()
        attachPlayers()
    }

    /// Configure the audio session, pre-warm and start the engine, and ready the
    /// player pool — called once at app launch so the very first tick is instant.
    /// Idempotent; a no-op in SwiftUI previews (no live engine wanted there).
    func start() {
        guard !started else { return }
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }

        configureSession()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // A dead engine must never crash the game; it just plays nothing. The
            // toggle (2.06) and a relaunch are the recovery paths.
            return
        }
        // Master trim — set on the *live* mixer (after `start()`) so engine/format
        // setup can't reset it. Leaves headroom so a dense multi-tick chord never clips.
        engine.mainMixerNode.outputVolume = Self.masterVolume
        // Keep every node running (rendering silence) so a fire is a single
        // `scheduleBuffer(at:)` at a shared future host time — sample-accurate and
        // with no per-fire `play()` start jitter.
        for player in players { player.play() }
        started = true
    }

    /// `.ambient` + `.mixWithOthers` (D-047): mix politely under the user's own audio
    /// and honour the hardware silent switch. iOS-only API — guarded so the rest of
    /// this file still type-checks against the macOS SDK in the no-Xcode dev env.
    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    private func attachPlayers() {
        for _ in 0..<Self.poolSize {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
    }

    // MARK: Triggers (presentation-only; called from the view layer)

    /// Play one tick per moving entity this turn, all at the same audio time so they
    /// layer into a chord rather than a flam. `directions` is the player's move plus
    /// each stepping echo's move; an empty list (no mover) is a no-op. Fired at the
    /// instant of commit — the start of the 120 ms slide — so the tick is perceptually
    /// instantaneous.
    func playStep(directions: [Direction]) {
        guard isEnabled, started, !directions.isEmpty else { return }
        let when = futureTime(after: 0)
        for direction in directions {
            if let buffer = stepBuffers[direction] {
                schedule(buffer, at: when)
            }
        }
    }

    /// Play the fold sound the instant the fold fires — the §6c hit-pause *onset*
    /// (t = 0, when the board briefly freezes to let the moment land), not the later
    /// ripple. Immediate feedback (the prompt: "play the fold sound when the fold
    /// fires"); the warm, long-decaying tone then sustains over the ripple + peel.
    func playFold() {
        guard isEnabled, started else { return }
        schedule(foldBuffer, at: futureTime(after: 0))
    }

    /// Play the death sound aligned to the §6d particle fizz — i.e. after the fatal
    /// step's glide (`motion.step`) and the calm freeze (`motion.deathFreeze`), so the
    /// soft puff swells exactly as the player and echo dissolve. Reads its offset from
    /// the same `Motion.Span` tokens the visual uses, so audio and motion share one clock.
    func playDeath() {
        guard isEnabled, started else { return }
        let toFizz = Motion.Span.step + Motion.Span.deathFreeze
        schedule(deathBuffer, at: futureTime(after: toFizz))
    }

    /// Play the solve flourish as the player lands on the exit — a small delay of one
    /// step slide (`motion.step`) so the figure resolves on arrival, not before the
    /// winning move has visibly completed.
    func playSolve() {
        guard isEnabled, started else { return }
        schedule(solveBuffer, at: futureTime(after: Motion.Span.step))
    }

    // MARK: Scheduling

    /// The next round-robin player node renders `buffer` at host time `when` (or as
    /// soon as possible if `when` is `nil`, e.g. before the engine's first render).
    /// Passing a shared `when` across a turn's voices is what makes them simultaneous.
    private func schedule(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime?) {
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: when, options: [], completionHandler: nil)
        // Nodes are pre-started in `start()`, so this is normally already playing; the
        // guard is a defensive restart in case an audio-session interruption or route
        // change stopped a node out from under us.
        if !player.isPlaying { player.play() }
    }

    /// A host-clock time `seconds` (plus a small alignment lead) in the future, taken
    /// from the engine's most recent render. Returns `nil` if no valid render time is
    /// available yet (only the moment right after launch), in which case the caller
    /// schedules "as soon as possible". All player nodes read the same global host
    /// clock, so one shared time = sample-accurate simultaneity, no per-node timeline
    /// conversion, and graceful degradation (a slightly-past time just plays ASAP).
    private func futureTime(after seconds: TimeInterval) -> AVAudioTime? {
        guard let render = engine.outputNode.lastRenderTime, render.isHostTimeValid else {
            return nil
        }
        let host = render.hostTime + AVAudioTime.hostTime(forSeconds: max(0, seconds) + Self.scheduleLead)
        return AVAudioTime(hostTime: host)
    }

    // MARK: - Synthesis (D-045 / D-046)

    /// Build every buffer once. Synthesized in the engine's processing format so they
    /// play with no conversion. All deterministic — no randomness — so a given sound is
    /// byte-identical every run, matching the engine's no-randomness character.
    private func buildSoundBank() {
        buildStepTicks()
        buildWaitTick()
        buildFold()
        buildDeath()
        buildSolve()
    }

    /// The four direction ticks. A soft marimba/kalimba "pock": fast attack,
    /// exponential decay, a sine fundamental with a touch of harmonic plus a very
    /// short bright partial for the wooden knock. Pitches are a C-major-pentatonic
    /// subset so any chord of simultaneous ticks is consonant; up is the highest tone,
    /// down the lowest, left/right the middle two (D-046). Exact notes are tunable by
    /// ear on device.
    private func buildStepTicks() {
        let partials = [
            Partial(multiple: 1.0, amplitude: 1.00, tau: 0.16),   // fundamental
            Partial(multiple: 2.0, amplitude: 0.22, tau: 0.07),   // a touch of harmonic
            Partial(multiple: 5.4, amplitude: 0.30, tau: 0.012),  // bright "pock" knock
        ]
        let peak = 0.15
        let frequencies: [Direction: Double] = [
            .down:  261.63,   // C4 — lowest
            .left:  329.63,   // E4 — middle-low
            .right: 392.00,   // G4 — middle-high
            .up:    440.00,   // A4 — highest
        ]
        for (direction, frequency) in frequencies {
            let buffer = makeBuffer(seconds: 0.30)
            renderTone(into: buffer, baseFrequency: frequency, partials: partials, peak: peak)
            stepBuffers[direction] = buffer
        }
    }

    /// The wait tick (Phase 4.01 / D-067) — the voice of a `.stay`. A low, quiet, calm
    /// note that sits *under* the four-tone pentatonic step set: C3, a full octave below
    /// the lowest step tick (C4 / down), with a softer, duller voicing (a longer-decaying
    /// fundamental and only a faint second harmonic — no bright "pock" partial), so a held
    /// turn reads as a quiet breath in the rhythm rather than a step. Stored in the same
    /// `stepBuffers` map keyed on `.stay`, so a wait's turn layers with any stepping
    /// echoes' ticks as one chord through the existing `playStep(directions:)` path
    /// (an echo replaying a recorded wait voices this same calm note). Tunable by ear.
    private func buildWaitTick() {
        let calm = [
            Partial(multiple: 1.0, amplitude: 1.00, tau: 0.26),   // soft, longer-decaying fundamental
            Partial(multiple: 2.0, amplitude: 0.12, tau: 0.10),   // a faint harmonic for body
        ]
        let buffer = makeBuffer(seconds: 0.34)
        renderTone(into: buffer, baseFrequency: 130.81, partials: calm, peak: 0.10)   // C3 — quiet, under the set
        stepBuffers[.stay] = buffer
    }

    /// Fold: a warm, slightly lower two-note settle (G3 → a perfect fifth down to C3),
    /// longer and softer than a tick — weighty, matching the fold's hit-pause + ripple.
    private func buildFold() {
        let buffer = makeBuffer(seconds: 0.55)
        let warm = [
            Partial(multiple: 1.0, amplitude: 1.00, tau: 0.28),
            Partial(multiple: 2.0, amplitude: 0.18, tau: 0.16),
        ]
        renderTone(into: buffer, baseFrequency: 196.00, partials: warm, peak: 0.16)                       // G3
        renderTone(into: buffer, baseFrequency: 130.81, partials: warm, peak: 0.14, startSeconds: 0.075)  // C3 settle
        foldBuffer = buffer
    }

    /// Death: a calm, short, soft sound — a muted low tone plus a gently low-passed
    /// noise puff, matching the particle fizz. Quiet and never harsh (death in ECHO is
    /// legibly the player's fault, not a punishment).
    private func buildDeath() {
        let buffer = makeBuffer(seconds: 0.36)
        let low = [
            Partial(multiple: 1.0, amplitude: 1.00, tau: 0.16),
            Partial(multiple: 2.0, amplitude: 0.10, tau: 0.08),
        ]
        renderTone(into: buffer, baseFrequency: 110.00, partials: low, peak: 0.10)        // A2 muted thud
        renderNoise(into: buffer, peak: 0.09, tau: 0.10, lowpassAlpha: 0.06)              // soft filtered puff
        deathBuffer = buffer
    }

    /// Solve: the one small flourish — a short, gentle ascending figure (E4 → A4 → C5),
    /// three pentatonic notes that resolve upward. Quiet; the game's tone is calm, not
    /// celebratory.
    private func buildSolve() {
        let buffer = makeBuffer(seconds: 0.60)
        let bell = [
            Partial(multiple: 1.0, amplitude: 1.00, tau: 0.22),
            Partial(multiple: 2.0, amplitude: 0.20, tau: 0.10),
            Partial(multiple: 4.0, amplitude: 0.10, tau: 0.05),
        ]
        renderTone(into: buffer, baseFrequency: 329.63, partials: bell, peak: 0.13)                       // E4
        renderTone(into: buffer, baseFrequency: 440.00, partials: bell, peak: 0.13, startSeconds: 0.13)   // A4
        renderTone(into: buffer, baseFrequency: 523.25, partials: bell, peak: 0.13, startSeconds: 0.26)   // C5
        solveBuffer = buffer
    }

    // MARK: Synthesis primitives

    /// One additive partial of a tone: a frequency `multiple` of the base, a relative
    /// `amplitude`, and its own exponential-decay time constant `tau` (seconds) — so a
    /// fast-decaying bright partial can ride a slower fundamental for a percussive knock.
    private struct Partial {
        let multiple: Double
        let amplitude: Double
        let tau: Double
    }

    /// Allocate a silence-filled mono buffer of `seconds` at the processing rate.
    private func makeBuffer(seconds: Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { channel[i] = 0 }
        return buffer
    }

    /// Sum an additive, exponentially-decaying tone into `buffer` starting at
    /// `startSeconds` (so several notes can be layered into one buffer). Each partial
    /// is `amplitude · e^(−t/tau) · sin(2π · f · multiple · t)`; the partial sum is
    /// scaled so the onset peak is `peak`, and a ~2 ms linear attack ramp removes the
    /// start-click. Adds (`+=`) into whatever is already there.
    private func renderTone(into buffer: AVAudioPCMBuffer, baseFrequency: Double,
                            partials: [Partial], peak: Double, startSeconds: Double = 0) {
        let sampleRate = format.sampleRate
        let channel = buffer.floatChannelData![0]
        let total = Int(buffer.frameLength)
        let startSample = Int(startSeconds * sampleRate)
        guard startSample < total else { return }

        let amplitudeSum = partials.reduce(0) { $0 + $1.amplitude }
        let scale = amplitudeSum > 0 ? peak / amplitudeSum : 0
        let attackSamples = max(1, Int(0.002 * sampleRate))
        let count = total - startSample

        for i in 0..<count {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for partial in partials {
                sample += partial.amplitude
                    * exp(-t / partial.tau)
                    * sin(2 * .pi * baseFrequency * partial.multiple * t)
            }
            sample *= scale
            if i < attackSamples { sample *= Double(i) / Double(attackSamples) }
            channel[startSample + i] += Float(sample)
        }
    }

    /// Sum a soft, exponentially-decaying, one-pole-low-passed noise puff into
    /// `buffer` — the "breath" of the death sound. The noise is a deterministic LCG
    /// (no `Math.random`), so the puff is identical every time. `lowpassAlpha` is the
    /// one-pole coefficient (smaller = duller/softer); `peak` scales the result.
    private func renderNoise(into buffer: AVAudioPCMBuffer, peak: Double, tau: Double,
                             lowpassAlpha: Double) {
        let sampleRate = format.sampleRate
        let channel = buffer.floatChannelData![0]
        let total = Int(buffer.frameLength)

        var rng: UInt64 = 0x9E37_79B9_7F4A_7C15
        var lowpass = 0.0
        for i in 0..<total {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            // Top 53 bits → a fraction in [0, 1), then to white noise in [-1, 1).
            let white = Double(rng >> 11) * (1.0 / 9007199254740992.0) * 2 - 1
            lowpass += lowpassAlpha * (white - lowpass)
            let t = Double(i) / sampleRate
            channel[i] += Float(lowpass * exp(-t / tau) * peak)
        }
    }
}
