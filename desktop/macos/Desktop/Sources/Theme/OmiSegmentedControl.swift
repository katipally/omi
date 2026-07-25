import SwiftUI

/// The app's one segmented control: a capsule track whose selected fill slides
/// between segments, with a soft hover wash on the unselected ones.
///
/// Surfaces that need more than a title per segment — an icon, a count badge, a
/// dropdown — compose `omiSegmentedTrack()` and `omiSegmentFill(...)` directly
/// rather than reaching for a wider API here. Both spellings share these two
/// modifiers, so the visuals are defined exactly once.
package struct OmiSegmentedControl: View {
  package let segments: [String]
  @Binding package var selection: Int

  @Namespace private var namespace

  package init(segments: [String], selection: Binding<Int>) {
    self.segments = segments
    self._selection = selection
  }

  package var body: some View {
    HStack(spacing: OmiSpacing.hairline) {
      ForEach(Array(segments.enumerated()), id: \.offset) { index, title in
        OmiSegment(
          title: title,
          isSelected: selection == index,
          namespace: namespace
        ) {
          OmiMotion.withGated(OmiSegmentedMetrics.selectionAnimation) {
            selection = index
          }
        }
      }
    }
    .omiSegmentedTrack()
  }
}

/// Shared geometry for the segmented language, so a hand-composed track (the
/// window's top nav) and `OmiSegmentedControl` cannot drift apart.
package enum OmiSegmentedMetrics {
  package static let trackPadding: CGFloat = 3
  /// Segments claim the track's full inner height. Sizing the segment rather
  /// than the track is what keeps the selected fill flush with the track edge:
  /// give the track a height instead and the pill floats inside it.
  package static let segmentHeight: CGFloat = OmiChrome.controlHeight - 2 * trackPadding
  package static let selectionAnimation: Animation = .spring(response: 0.32, dampingFraction: 0.82)
  package static let hoverAnimation: Animation = .easeOut(duration: 0.12)
}

extension View {
  /// The capsule track that segments sit inside. Its height comes from the
  /// segments (`omiSegmentContent`), which sum with `trackPadding` to
  /// `OmiChrome.controlHeight` — the same height as search fields and chips, so
  /// a header row of mixed controls sits on one line.
  package func omiSegmentedTrack() -> some View {
    self
      .padding(OmiSegmentedMetrics.trackPadding)
      .background(
        Capsule(style: .continuous)
          .fill(Color.white.opacity(0.05))
          .overlay(
            Capsule(style: .continuous)
              .stroke(Color.white.opacity(0.07), lineWidth: 1)
          )
      )
  }

  /// Padding and height for one segment's label, so every track — the plain
  /// string control and the window's hand-composed nav — sizes identically.
  package func omiSegmentContent() -> some View {
    self
      .padding(.horizontal, OmiSpacing.md)
      .frame(height: OmiSegmentedMetrics.segmentHeight)
  }

  /// The sliding selected fill (and hover wash) for one segment. `namespace`
  /// and `geometryID` must match across the segments of a single track.
  package func omiSegmentFill(
    isSelected: Bool,
    isHovering: Bool = false,
    namespace: Namespace.ID,
    geometryID: String
  ) -> some View {
    self
      .background {
        ZStack {
          if isSelected {
            Capsule(style: .continuous)
              .fill(Color.white.opacity(0.12))
              .matchedGeometryEffect(id: geometryID, in: namespace)
          } else if isHovering {
            Capsule(style: .continuous)
              .fill(Color.white.opacity(0.05))
          }
        }
      }
      .contentShape(Capsule(style: .continuous))
  }
}

private struct OmiSegment: View {
  let title: String
  let isSelected: Bool
  var namespace: Namespace.ID
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .scaledFont(size: OmiType.caption, weight: .semibold)
        .foregroundColor(isSelected ? OmiColors.textPrimary : OmiColors.textTertiary)
        .omiSegmentContent()
        .omiSegmentFill(
          isSelected: isSelected,
          isHovering: isHovering,
          namespace: namespace,
          geometryID: "omiSegmentedSelection"
        )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      OmiMotion.withGated(OmiSegmentedMetrics.hoverAnimation) { isHovering = hovering }
    }
  }
}
