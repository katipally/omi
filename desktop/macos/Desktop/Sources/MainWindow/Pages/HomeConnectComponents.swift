import AppKit
import OmiTheme
import SwiftUI

/// The Home connect tray's tiles, cards and rows.
///
/// Split out of `DashboardPage` so that file stays under its line-count
/// baseline; every type here is a leaf view driven entirely by its inputs.

enum HomeRowStatus {
  case connect
  case connected
  case open
}

enum HomeDestinationProminence {
  case primary
  case quiet
}

struct HomeSourceIconTile: View {
  let title: String
  let brand: ConnectorBrand?
  let systemImage: String?
  let usesOmiDeviceImage: Bool
  let isConnected: Bool
  let isBrowse: Bool
  let action: () -> Void

  @State private var isHovering = false

  init(
    title: String,
    brand: ConnectorBrand,
    isConnected: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.brand = brand
    self.systemImage = nil
    self.usesOmiDeviceImage = false
    self.isConnected = isConnected
    self.isBrowse = false
    self.action = action
  }

  init(
    title: String,
    systemImage: String,
    isBrowse: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.brand = nil
    self.systemImage = systemImage
    self.usesOmiDeviceImage = false
    self.isConnected = false
    self.isBrowse = isBrowse
    self.action = action
  }

  init(
    title: String,
    usesOmiDeviceImage: Bool,
    isConnected: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.brand = nil
    self.systemImage = nil
    self.usesOmiDeviceImage = usesOmiDeviceImage
    self.isConnected = isConnected
    self.isBrowse = false
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      VStack(spacing: OmiSpacing.sm) {
        ZStack(alignment: .topTrailing) {
          icon

          if isConnected {
            Circle()
              .fill(HomePalette.green)
              .frame(width: 9, height: 9)
              .overlay(Circle().stroke(HomePalette.tile, lineWidth: 2))
              .offset(x: 2, y: -2)
          }
        }

        HStack(spacing: OmiSpacing.xxs) {
          Text(title)
            .scaledFont(size: OmiType.caption, weight: .semibold)
            .foregroundStyle(HomePalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.72)

          if isBrowse {
            Image(systemName: "chevron.right")
              .scaledFont(size: 8, weight: .bold)
              .foregroundStyle(HomePalette.faint)
          }
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 92)
      .background(
        RoundedRectangle(cornerRadius: 17, style: .continuous)
          .fill(isHovering ? HomePalette.tileHover : HomePalette.tile)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 17, style: .continuous)
          .stroke(isHovering ? HomePalette.glow.opacity(0.58) : HomePalette.hairline.opacity(0.9), lineWidth: 1)
      )
      .shadow(color: isHovering ? HomePalette.glow.opacity(0.16) : .clear, radius: 14)
      .contentShape(.rect(cornerRadius: 17))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel(title)
  }

  @ViewBuilder
  private var icon: some View {
    if usesOmiDeviceImage {
      HomeOmiDeviceIcon(size: 42, cornerRadius: OmiChrome.smallControlRadius)
    } else if let brand {
      ConnectorBrandIcon(brand: brand, size: 42, cornerRadius: OmiChrome.smallControlRadius)
    } else if let systemImage {
      ZStack {
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .fill(Color.white.opacity(0.05))
        Image(systemName: systemImage)
          .scaledFont(size: 19, weight: .semibold)
          .foregroundStyle(HomePalette.secondary)
      }
      .frame(width: 42, height: 42)
    }
  }
}

struct HomeOmiDeviceIcon: View {
  let size: CGFloat
  let cornerRadius: CGFloat

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color.white.opacity(0.05))
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )

      if let deviceImage = OmiDeviceImage.shared {
        Image(nsImage: deviceImage)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .padding(size * 0.16)
      } else {
        Image(systemName: "wave.3.right.circle.fill")
          .scaledFont(size: size * 0.45, weight: .semibold)
          .foregroundStyle(HomePalette.secondary)
      }
    }
    .frame(width: size, height: size)
  }
}

struct HomeDataSourceCard: View {
  let title: String
  let subtitle: String
  let brand: ConnectorBrand?
  let systemImage: String?
  let actionTitle: String
  let isConnected: Bool
  let action: () -> Void

  @State private var isHovering = false

  init(
    title: String,
    subtitle: String,
    brand: ConnectorBrand,
    actionTitle: String,
    isConnected: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.subtitle = subtitle
    self.brand = brand
    self.systemImage = nil
    self.actionTitle = actionTitle
    self.isConnected = isConnected
    self.action = action
  }

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    actionTitle: String,
    isConnected: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.subtitle = subtitle
    self.brand = nil
    self.systemImage = systemImage
    self.actionTitle = actionTitle
    self.isConnected = isConnected
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.md) {
        icon

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(title)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundStyle(HomePalette.ink)
            .lineLimit(1)

          Text(subtitle)
            .scaledFont(size: OmiType.caption, weight: .medium)
            .foregroundStyle(HomePalette.muted)
            .lineLimit(1)
        }

        Spacer(minLength: 10)

        HStack(spacing: OmiSpacing.xxs) {
          if isConnected {
            Circle()
              .fill(HomePalette.green)
              .frame(width: 5, height: 5)
          }

          Text(actionTitle)
            .scaledFont(size: OmiType.caption, weight: .semibold)
            .foregroundStyle(isConnected ? HomePalette.green : HomePalette.secondary)
            .lineLimit(1)

          if !isConnected && actionTitle == "Browse" {
            Image(systemName: "chevron.right")
              .scaledFont(size: OmiType.micro, weight: .bold)
              .foregroundStyle(HomePalette.faint)
          }
        }
        .fixedSize(horizontal: true, vertical: false)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.md)
      .frame(height: 64)
      .frame(maxWidth: .infinity)
      .background(
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .fill(isHovering ? HomePalette.tileHover : HomePalette.tile)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .stroke(isHovering ? HomePalette.glow.opacity(0.5) : HomePalette.hairline.opacity(0.9), lineWidth: 1)
      )
      .shadow(color: isHovering ? HomePalette.glow.opacity(0.12) : .clear, radius: 12)
      .contentShape(.rect(cornerRadius: 15))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel("\(title), \(subtitle), \(actionTitle)")
  }

  @ViewBuilder
  private var icon: some View {
    if let brand {
      ConnectorBrandIcon(brand: brand, size: 36, cornerRadius: OmiChrome.smallControlRadius)
    } else if let systemImage {
      ZStack {
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
          .fill(Color.white.opacity(0.04))
        Image(systemName: systemImage)
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundStyle(HomePalette.secondary)
      }
      .frame(width: 36, height: 36)
    }
  }
}

struct HomeAIChoiceButton: View {
  let title: String
  let brand: ConnectorBrand?
  let systemImage: String?
  let usesOmiMark: Bool
  let isPrimary: Bool
  let isConnected: Bool
  let action: () -> Void

  @State private var isHovering = false

  init(
    title: String, brand: ConnectorBrand, isPrimary: Bool = false, isConnected: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.brand = brand
    self.systemImage = nil
    self.usesOmiMark = false
    self.isPrimary = isPrimary
    self.isConnected = isConnected
    self.action = action
  }

  init(
    title: String, systemImage: String, isPrimary: Bool = false, isConnected: Bool = false, action: @escaping () -> Void
  ) {
    self.title = title
    self.brand = nil
    self.systemImage = systemImage
    self.usesOmiMark = false
    self.isPrimary = isPrimary
    self.isConnected = isConnected
    self.action = action
  }

  init(
    title: String, usesOmiMark: Bool, isPrimary: Bool = false, isConnected: Bool = false, action: @escaping () -> Void
  ) {
    self.title = title
    self.brand = nil
    self.systemImage = nil
    self.usesOmiMark = usesOmiMark
    self.isPrimary = isPrimary
    self.isConnected = isConnected
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.sm) {
        icon

        Text(title)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundStyle(HomePalette.ink)
          .lineLimit(1)

        Spacer(minLength: 8)

        if isConnected {
          Text("Connected")
            .scaledFont(size: OmiType.caption, weight: .medium)
            .foregroundStyle(HomePalette.faint)
        }

        Image(systemName: "chevron.right")
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundStyle(HomePalette.faint)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.md)
      .frame(height: 48)
      .frame(maxWidth: .infinity)
      .background(buttonBackground)
      .overlay(buttonStroke)
      .contentShape(.rect(cornerRadius: 15))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel(title)
  }

  @ViewBuilder
  private var icon: some View {
    if usesOmiMark {
      HomeOmiMarkIcon(size: 24, cornerRadius: 7)
    } else if let brand {
      ConnectorBrandIcon(brand: brand, size: 24, cornerRadius: 7)
    } else if let systemImage {
      Image(systemName: systemImage)
        .scaledFont(size: OmiType.body, weight: .bold)
        .foregroundStyle(HomePalette.ink)
        .frame(width: 24, height: 24)
    }
  }

  private var buttonBackground: some View {
    RoundedRectangle(cornerRadius: 15, style: .continuous)
      .fill(isHovering ? HomePalette.tileHover : HomePalette.tile)
  }

  private var buttonStroke: some View {
    RoundedRectangle(cornerRadius: 15, style: .continuous)
      .stroke(
        HomePalette.hairline.opacity(isHovering ? 1 : 0.9),
        lineWidth: 1
      )
  }
}

struct HomeOmiMarkIcon: View {
  let size: CGFloat
  let cornerRadius: CGFloat

  private static let markImage: NSImage? = {
    guard let url = Bundle.resourceBundle.url(forResource: "herologo", withExtension: "png") else {
      return nil
    }
    return NSImage(contentsOf: url)
  }()

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color.white.opacity(0.08))
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )

      if let image = Self.markImage {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .padding(size * 0.18)
      } else {
        OmiDotRing()
          .frame(width: size * 0.58, height: size * 0.58)
      }
    }
    .frame(width: size, height: size)
  }
}

struct OmiDotRing: View {
  var body: some View {
    ZStack {
      ForEach(0..<8, id: \.self) { index in
        Circle()
          .fill(HomePalette.ink)
          .frame(width: 3.5, height: 3.5)
          .offset(y: -6)
          .rotationEffect(.degrees(Double(index) * 45))
      }
    }
  }
}

struct HomeOrbitButton: View {
  let title: String
  let brand: ConnectorBrand
  let badge: String?
  let action: () -> Void

  @State private var isHovering = false

  init(title: String, brand: ConnectorBrand, badge: String? = nil, action: @escaping () -> Void) {
    self.title = title
    self.brand = brand
    self.badge = badge
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      VStack(spacing: OmiSpacing.xs) {
        ZStack(alignment: .topTrailing) {
          ConnectorBrandIcon(brand: brand, size: 44, cornerRadius: 13)
            .shadow(color: .black.opacity(isHovering ? 0.16 : 0.08), radius: 9, y: 4)

          if let badge {
            Text(badge)
              .scaledFont(size: 8, weight: .bold)
              .foregroundStyle(.white)
              .padding(.horizontal, OmiSpacing.xxs)
              .padding(.vertical, OmiSpacing.hairline)
              .background(Capsule(style: .continuous).fill(HomePalette.green))
              .offset(x: 8, y: -6)
          }
        }

        Text(title)
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .foregroundStyle(HomePalette.secondary)
          .lineLimit(1)
      }
      .padding(OmiSpacing.sm)
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.controlRadius, style: .continuous)
          .fill(isHovering ? HomePalette.panel : Color.clear)
      )
      .contentShape(.rect(cornerRadius: OmiChrome.controlRadius))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel(title)
  }
}

struct HomeDestinationCapsule: View {
  let title: String
  let subtitle: String
  let brand: ConnectorBrand
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.sm) {
        ConnectorBrandIcon(brand: brand, size: 34, cornerRadius: 9)

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(title)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundStyle(HomePalette.ink)
            .lineLimit(1)

          Text(subtitle)
            .scaledFont(size: OmiType.caption, weight: .medium)
            .foregroundStyle(HomePalette.muted)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        Image(systemName: "arrow.up.right")
          .scaledFont(size: OmiType.caption, weight: .bold)
          .foregroundStyle(isHovering ? HomePalette.green : HomePalette.faint)
      }
      .padding(OmiSpacing.md)
      .background(
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .fill(isHovering ? HomePalette.tileHover : HomePalette.tile.opacity(0.82))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .stroke(isHovering ? HomePalette.green.opacity(0.32) : HomePalette.hairline.opacity(0.45), lineWidth: 1)
      )
      .contentShape(.rect(cornerRadius: 15))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel("\(title), \(subtitle)")
  }
}

struct HomeCommandCard: View {
  let onChatGPT: () -> Void
  let onClaude: () -> Void
  let onAskOmi: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: OmiSpacing.md) {
        Text("Connect Omi to ChatGPT, Claude, or ask Omi directly...")
          .scaledFont(size: OmiType.subheading, weight: .regular)
          .foregroundStyle(HomePalette.faint)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, OmiSpacing.hairline)

        Button(action: onAskOmi) {
          Image(systemName: "arrow.up.circle")
            .scaledFont(size: 24, weight: .regular)
            .foregroundStyle(HomePalette.faint)
        }
        .buttonStyle(.plain)
        .help("Ask Omi")
      }
      .padding(.horizontal, OmiSpacing.lg)
      .padding(.top, OmiSpacing.lg)
      .padding(.bottom, OmiSpacing.xxl)

      HStack(spacing: OmiSpacing.sm) {
        Button(action: onChatGPT) {
          HStack(spacing: OmiSpacing.sm) {
            ConnectorBrandIcon(brand: .chatgpt, size: 22, cornerRadius: OmiChrome.badgeRadius)
            Text("Connect ChatGPT")
              .scaledFont(size: OmiType.body, weight: .semibold)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, OmiSpacing.sm)
          .foregroundStyle(.white)
          .background(
            RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
              .fill(HomePalette.green)
          )
        }
        .buttonStyle(.plain)

        Button(action: onClaude) {
          HStack(spacing: OmiSpacing.sm) {
            ConnectorBrandIcon(brand: .claude, size: 22, cornerRadius: OmiChrome.badgeRadius)
            Text("Claude")
              .scaledFont(size: OmiType.body, weight: .semibold)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, OmiSpacing.sm)
          .foregroundStyle(HomePalette.secondary)
          .background(
            RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
              .fill(HomePalette.tile)
          )
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.bottom, OmiSpacing.md)
    }
    .background(
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .fill(HomePalette.panel)
        .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .stroke(HomePalette.hairline.opacity(0.72), lineWidth: 1)
    )
    .frame(maxWidth: 720)
  }
}

struct HomeSourceTile: View {
  let title: String
  let subtitle: String
  let brand: ConnectorBrand?
  let systemImage: String?
  let status: HomeRowStatus
  let action: () -> Void

  @State private var isHovering = false

  init(
    title: String,
    subtitle: String,
    brand: ConnectorBrand,
    status: HomeRowStatus = .connect,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.subtitle = subtitle
    self.brand = brand
    self.systemImage = nil
    self.status = status
    self.action = action
  }

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    status: HomeRowStatus = .connect,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.subtitle = subtitle
    self.brand = nil
    self.systemImage = systemImage
    self.status = status
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: OmiSpacing.sm) {
        HStack(alignment: .top) {
          iconView
          Spacer()
          statusView
        }

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(title)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundStyle(HomePalette.ink)
            .lineLimit(1)

          Text(subtitle)
            .scaledFont(size: OmiType.caption)
            .foregroundStyle(HomePalette.muted)
            .lineLimit(1)
        }
      }
      .padding(OmiSpacing.sm)
      .frame(minHeight: 78, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(isHovering ? HomePalette.tileHover : HomePalette.tile)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .stroke(isHovering ? HomePalette.green.opacity(0.4) : HomePalette.hairline.opacity(0.3), lineWidth: 1)
      )
      .contentShape(.rect(cornerRadius: 9))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel("\(title), \(subtitle)")
  }

  @ViewBuilder
  private var iconView: some View {
    if let brand {
      ConnectorBrandIcon(brand: brand, size: 28, cornerRadius: 7)
    } else if let systemImage {
      ZStack {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(HomePalette.panel)
        Image(systemName: systemImage)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundStyle(HomePalette.secondary)
      }
      .frame(width: 28, height: 28)
    }
  }

  @ViewBuilder
  private var statusView: some View {
    switch status {
    case .connect:
      Image(systemName: "plus")
        .scaledFont(size: OmiType.caption, weight: .bold)
        .foregroundStyle(HomePalette.secondary)
    case .connected:
      Image(systemName: "checkmark")
        .scaledFont(size: OmiType.caption, weight: .bold)
        .foregroundStyle(HomePalette.green)
    case .open:
      Image(systemName: "chevron.right")
        .scaledFont(size: OmiType.caption, weight: .bold)
        .foregroundStyle(HomePalette.secondary)
    }
  }
}

struct HomeMemoryMetricCard: View {
  let title: String
  let value: String
  let systemImage: String
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.md) {
        ZStack {
          RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius, style: .continuous)
            .fill(Color.white.opacity(0.055))

          Image(systemName: systemImage)
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundStyle(HomePalette.ink)
        }
        .frame(width: 42, height: 42)

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(value)
            .font(.system(size: 21, weight: .medium, design: .serif))
            .foregroundStyle(HomePalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.72)

          Text(title)
            .scaledFont(size: OmiType.caption, weight: .medium)
            .foregroundStyle(HomePalette.muted)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        Image(systemName: "arrow.up.right")
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundStyle(isHovering ? HomePalette.glow : HomePalette.faint)
      }
      .padding(.horizontal, OmiSpacing.md)
      .frame(height: 76)
      .frame(maxWidth: .infinity)
      .background(
        RoundedRectangle(cornerRadius: 17, style: .continuous)
          .fill(isHovering ? HomePalette.tileHover : HomePalette.tile)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 17, style: .continuous)
          .stroke(isHovering ? HomePalette.glow.opacity(0.56) : HomePalette.hairline.opacity(0.86), lineWidth: 1)
      )
      .contentShape(.rect(cornerRadius: 17))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel("\(title), \(value)")
  }
}

struct HomeMetricPill: View {
  let title: String
  let value: String
  let systemImage: String
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.xs) {
        Image(systemName: systemImage)
          .scaledFont(size: OmiType.caption, weight: .semibold)
          .foregroundStyle(HomePalette.secondary)

        Text(value)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundStyle(HomePalette.ink)

        Text(title)
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundStyle(HomePalette.muted)
          .lineLimit(1)
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .frame(maxWidth: .infinity)
      .background(
        Capsule(style: .continuous)
          .fill(isHovering ? HomePalette.tileHover : HomePalette.panel)
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(isHovering ? HomePalette.green.opacity(0.34) : HomePalette.hairline.opacity(0.64), lineWidth: 1)
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel("\(title), \(value)")
  }
}

struct HomeGlassPanel<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(OmiSpacing.lg)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: 29, style: .continuous)
          .fill(HomePalette.panel)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 29, style: .continuous)
          .stroke(HomePalette.hairline.opacity(0.8), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
  }
}

struct HomeStageHeader: View {
  let eyebrow: String
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
      Text(eyebrow.uppercased())
        .scaledFont(size: OmiType.micro, weight: .bold)
        .foregroundStyle(HomePalette.green)

      Text(title)
        .scaledFont(size: OmiType.heading, weight: .semibold)
        .foregroundStyle(HomePalette.ink)
        .lineLimit(1)

      Text(subtitle)
        .scaledFont(size: OmiType.caption)
        .foregroundStyle(HomePalette.muted)
        .fixedSize(horizontal: false, vertical: true)
        .lineLimit(2)
    }
  }
}

struct HomeBridgeChevron: View {
  var body: some View {
    VStack(spacing: OmiSpacing.sm) {
      Rectangle()
        .fill(
          LinearGradient(
            colors: [.clear, OmiColors.border.opacity(0.65), .clear],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .frame(width: 1, height: 150)

      Image(systemName: "chevron.right")
        .scaledFont(size: OmiType.subheading, weight: .bold)
        .foregroundStyle(OmiColors.textTertiary)
    }
    .frame(width: 22)
    .accessibilityHidden(true)
  }
}

struct HomeSourceRow: View {
  let title: String
  let subtitle: String
  let brand: ConnectorBrand?
  let systemImage: String?
  let status: HomeRowStatus
  let action: () -> Void

  @State private var isHovering = false

  init(
    title: String,
    subtitle: String,
    brand: ConnectorBrand,
    status: HomeRowStatus = .connect,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.subtitle = subtitle
    self.brand = brand
    self.systemImage = nil
    self.status = status
    self.action = action
  }

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    status: HomeRowStatus = .connect,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.subtitle = subtitle
    self.brand = nil
    self.systemImage = systemImage
    self.status = status
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.sm) {
        rowIcon

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(title)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundStyle(OmiColors.textPrimary)
            .lineLimit(1)

          Text(subtitle)
            .scaledFont(size: OmiType.caption)
            .foregroundStyle(OmiColors.textTertiary)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        statusView
      }
      .padding(.horizontal, OmiSpacing.sm)
      .padding(.vertical, OmiSpacing.sm)
      .background(
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .fill(isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.035))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .stroke(isHovering ? OmiColors.success.opacity(0.28) : Color.white.opacity(0.06), lineWidth: 1)
      )
      .contentShape(.rect(cornerRadius: 13))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel("\(title), \(subtitle)")
  }

  @ViewBuilder
  private var rowIcon: some View {
    if let brand {
      ConnectorBrandIcon(brand: brand, size: 32, cornerRadius: OmiChrome.elementRadius)
    } else if let systemImage {
      ZStack {
        RoundedRectangle(cornerRadius: OmiChrome.elementRadius, style: .continuous)
          .fill(OmiColors.backgroundPrimary.opacity(0.78))
        Image(systemName: systemImage)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundStyle(OmiColors.textSecondary)
      }
      .frame(width: 32, height: 32)
    }
  }

  @ViewBuilder
  private var statusView: some View {
    switch status {
    case .connect:
      Image(systemName: "plus")
        .scaledFont(size: OmiType.caption, weight: .bold)
        .foregroundStyle(OmiColors.success)
    case .connected:
      Image(systemName: "checkmark")
        .scaledFont(size: OmiType.caption, weight: .bold)
        .foregroundStyle(OmiColors.success)
    case .open:
      Image(systemName: "chevron.right")
        .scaledFont(size: OmiType.caption, weight: .bold)
        .foregroundStyle(OmiColors.success)
    }
  }
}

struct HomeDestinationRow: View {
  let title: String
  let subtitle: String
  let brand: ConnectorBrand?
  let systemImage: String?
  let prominence: HomeDestinationProminence
  let action: () -> Void

  @State private var isHovering = false

  init(
    title: String,
    subtitle: String,
    brand: ConnectorBrand,
    prominence: HomeDestinationProminence = .primary,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.subtitle = subtitle
    self.brand = brand
    self.systemImage = nil
    self.prominence = prominence
    self.action = action
  }

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    prominence: HomeDestinationProminence = .primary,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.subtitle = subtitle
    self.brand = nil
    self.systemImage = systemImage
    self.prominence = prominence
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.sm) {
        rowIcon

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(title)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundStyle(prominence == .primary ? HomePalette.ink : HomePalette.secondary)
            .lineLimit(1)

          Text(subtitle)
            .scaledFont(size: OmiType.caption)
            .foregroundStyle(HomePalette.muted)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        Image(systemName: "arrow.up.right")
          .scaledFont(size: OmiType.caption, weight: .bold)
          .foregroundStyle(isHovering ? HomePalette.green : HomePalette.faint)
      }
      .padding(.horizontal, OmiSpacing.sm)
      .padding(.vertical, OmiSpacing.sm)
      .background(rowBackground)
      .overlay(rowStroke)
      .contentShape(.rect(cornerRadius: OmiChrome.chipRadius))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel("\(title), \(subtitle)")
  }

  @ViewBuilder
  private var rowIcon: some View {
    if let brand {
      ConnectorBrandIcon(brand: brand, size: 34, cornerRadius: 9)
    } else if let systemImage {
      ZStack {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(HomePalette.tile)
        Image(systemName: systemImage)
          .scaledFont(size: OmiType.body, weight: .semibold)
          .foregroundStyle(HomePalette.secondary)
      }
      .frame(width: 34, height: 34)
    }
  }

  private var rowBackground: some View {
    RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
      .fill(
        prominence == .primary
          ? HomePalette.green.opacity(isHovering ? 0.20 : 0.12)
          : (isHovering ? HomePalette.tileHover : HomePalette.tile)
      )
  }

  private var rowStroke: some View {
    RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
      .stroke(
        prominence == .primary
          ? HomePalette.green.opacity(isHovering ? 0.42 : 0.24)
          : HomePalette.hairline.opacity(isHovering ? 0.7 : 0.4),
        lineWidth: 1
      )
  }
}

struct HomeMetricTile: View {
  let title: String
  let value: String
  let systemImage: String
  let accent: Color
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: OmiSpacing.xs) {
        HStack {
          Image(systemName: systemImage)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundStyle(accent)

          Spacer()

          Image(systemName: "arrow.up.right")
            .scaledFont(size: OmiType.micro, weight: .bold)
            .foregroundStyle(isHovering ? accent : OmiColors.textQuaternary)
        }

        Text(value)
          .scaledFont(size: OmiType.heading, weight: .semibold)
          .foregroundStyle(OmiColors.textPrimary)
          .lineLimit(1)

        Text(title)
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundStyle(OmiColors.textTertiary)
          .lineLimit(1)
      }
      .padding(OmiSpacing.md)
      .frame(minHeight: 86, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.controlRadius, style: .continuous)
          .fill(Color.white.opacity(isHovering ? 0.08 : 0.04))
      )
      .overlay(
        RoundedRectangle(cornerRadius: OmiChrome.controlRadius, style: .continuous)
          .stroke(isHovering ? accent.opacity(0.34) : Color.white.opacity(0.07), lineWidth: 1)
      )
      .contentShape(.rect(cornerRadius: OmiChrome.controlRadius))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel("\(title), \(value)")
  }
}

struct HomeSectionHeader: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
      Text(title)
        .scaledFont(size: OmiType.heading, weight: .semibold)
        .foregroundStyle(OmiColors.textPrimary)

      Text(subtitle)
        .scaledFont(size: OmiType.caption)
        .foregroundStyle(OmiColors.textTertiary)
    }
  }
}
