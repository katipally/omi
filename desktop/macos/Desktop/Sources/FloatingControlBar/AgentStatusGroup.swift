import SwiftUI

/// Collapses `AgentPill.Status` into the handful of buckets the notch tints by.
/// The notch shows agent activity ambiently — the Omi mark's dots take this
/// color — so the vocabulary here is deliberately coarser than the pill's own
/// status: the user needs "something needs me" / "something is happening", not
/// a state machine readout.
enum AgentStatusGroup: String, Identifiable {
  case running
  case queued
  case failed
  case stopped
  case done

  var id: String { rawValue }

  init(status: AgentPill.Status) {
    switch status {
    case .starting, .running: self = .running
    case .queued: self = .queued
    case .failed: self = .failed
    case .stopped: self = .stopped
    case .done: self = .done
    }
  }

  var color: Color {
    switch self {
    case .running: return Color(red: 1.0, green: 0.80, blue: 0.40)
    case .queued: return Color(red: 0.20, green: 0.86, blue: 1.0)
    case .failed: return Color(red: 1.0, green: 0.42, blue: 0.42)
    case .stopped: return Color(red: 0.64, green: 0.66, blue: 0.70)
    case .done: return Color(red: 0.27, green: 0.92, blue: 0.46)
    }
  }

  var accessibilityLabel: String {
    switch self {
    case .running: return "Agents running"
    case .queued: return "Agents queued"
    case .failed: return "An agent failed"
    case .stopped: return "An agent stopped"
    case .done: return "Agents finished"
    }
  }

  /// Highest-priority aggregate across all pills, for the notch mark's tint:
  /// failure needs the user, activity is ambient. Finished agents the user has
  /// already viewed go quiet — done work should stop tugging at the eye.
  @MainActor
  static func aggregate(for pills: [AgentPill]) -> AgentStatusGroup? {
    let groups =
      pills
      .filter { !($0.status.isFinished && $0.viewedAt != nil) }
      .map { AgentStatusGroup(status: $0.status) }
    for candidate: AgentStatusGroup in [.failed, .running, .queued, .done, .stopped]
    where groups.contains(candidate) {
      return candidate
    }
    return groups.first
  }
}
