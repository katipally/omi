import Combine
import Foundation
import QuartzCore

/// Dedicated monitor for audio levels that doesn't trigger global AppState re-renders.
/// Only views that explicitly observe this class will update when audio levels change.
/// Updates are throttled to ~5 Hz to avoid flooding SwiftUI with layout invalidations.
@MainActor
class AudioLevelMonitor: ObservableObject {
  static let shared = AudioLevelMonitor()

  /// Microphone audio level (0.0 - 1.0)
  @Published private(set) var microphoneLevel: Float = 0.0

  /// The same microphone level, published to nobody. Views that already redraw
  /// every frame (the notch orb's `Canvas`) read this instead: they need each
  /// update as it arrives, while the `@Published` mirror stays throttled so
  /// observing views aren't asked to re-lay out at capture rate.
  private(set) var instantMicrophoneLevel: Float = 0.0

  /// System audio level (0.0 - 1.0)
  @Published private(set) var systemLevel: Float = 0.0

  /// Voice-response (TTS) output level (0.0 - 1.0), fed from the streaming PCM
  /// player as Omi speaks. Drives the notch orb's speaking waveform. This is
  /// output, not capture: `systemLevel` barely moves during our own playback.
  @Published private(set) var playbackLevel: Float = 0.0

  // Throttle: only publish at ~5 Hz (every ~200ms)
  private let updateInterval: Double = 1.0 / 5.0
  private var lastMicUpdate: Double = 0.0
  private var lastSysUpdate: Double = 0.0
  private var lastPlaybackUpdate: Double = 0.0
  private var pendingMicLevel: Float = 0.0
  private var pendingSysLevel: Float = 0.0

  private init() {}

  /// Update microphone level - called from audio capture callback.
  /// Throttled to ~5 Hz to prevent excessive SwiftUI re-renders.
  func updateMicrophoneLevel(_ level: Float) {
    pendingMicLevel = level
    instantMicrophoneLevel = level
    let now = CACurrentMediaTime()
    if now - lastMicUpdate >= updateInterval {
      lastMicUpdate = now
      microphoneLevel = level
    }
  }

  /// Update system audio level - called from audio capture callback.
  /// Throttled to ~5 Hz to prevent excessive SwiftUI re-renders.
  func updateSystemLevel(_ level: Float) {
    pendingSysLevel = level
    let now = CACurrentMediaTime()
    if now - lastSysUpdate >= updateInterval {
      lastSysUpdate = now
      systemLevel = level
    }
  }

  /// Update voice-response (TTS) playback level - called from the streaming PCM
  /// player as chunks are enqueued. Throttled to ~5 Hz like the others, except
  /// for a zero: playback stopping must land immediately or the waveform freezes
  /// at whatever level the last chunk happened to have.
  func updatePlaybackLevel(_ level: Float) {
    let now = CACurrentMediaTime()
    guard level == 0 || now - lastPlaybackUpdate >= updateInterval else { return }
    lastPlaybackUpdate = now
    playbackLevel = level
  }

  /// Reset all levels to zero
  func reset() {
    microphoneLevel = 0.0
    instantMicrophoneLevel = 0.0
    systemLevel = 0.0
    playbackLevel = 0.0
    pendingMicLevel = 0.0
    pendingSysLevel = 0.0
  }
}
