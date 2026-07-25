import XCTest

@testable import Omi_Computer

/// The TTS playback level that drives the notch orb's speaking waveform.
final class VoicePlaybackLevelTests: XCTestCase {
  func testSilenceReadsAsZeroAndLoudSpeechSaturates() {
    XCTAssertEqual(StreamingPCMPlayer.visualizerLevel(rms: 0), 0)
    // Anything at or above ~0.29 RMS is already full-scale for the visualizer.
    XCTAssertEqual(StreamingPCMPlayer.visualizerLevel(rms: 0.9), 1.0)
  }

  func testTypicalSpeechRMSLandsMidRange() {
    // Conversational TTS sits well below full scale without the gain, which is
    // the whole reason the scale factor exists.
    let level = StreamingPCMPlayer.visualizerLevel(rms: 0.1)
    XCTAssertGreaterThan(level, 0.2)
    XCTAssertLessThan(level, 0.6)
  }

  func testNegativeRMSCannotDriveTheOrbBelowZero() {
    XCTAssertEqual(StreamingPCMPlayer.visualizerLevel(rms: -1), 0)
  }

  @MainActor
  func testResetClearsPlaybackLevel() {
    let monitor = AudioLevelMonitor.shared
    monitor.updatePlaybackLevel(0.8)
    XCTAssertGreaterThan(monitor.playbackLevel, 0)

    monitor.reset()
    XCTAssertEqual(monitor.playbackLevel, 0)
  }
}
