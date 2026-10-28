import SwiftUI

// MARK: - Liquid Glass (iOS 26+) avec repli matériau translucide
struct GlassModifier<S: Shape>: ViewModifier {
    @Environment(\.pal) private var pal
    @EnvironmentObject private var settings: AppSettings
    let shape: S
    var tint: Color?
    var interactive = false

    @ViewBuilder func body(content: Content) -> some View {
        if settings.prefs.panelStyle == .solid {
            content.background(shape.fill(pal.surface)).overlay(shape.stroke(pal.border, lineWidth: 0.6))
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                let t = (tint ?? pal.glassTint).opacity(pal.glassOpacity)
                if interactive { content.glassEffect(.regular.tint(t).interactive(), in: shape) }
                else { content.glassEffect(.regular.tint(t), in: shape) }
            } else { legacy(content) }
            #else
            legacy(content)
            #endif
        }
    }

    private func legacy(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background(shape.fill((tint ?? pal.glassTint).opacity(pal.glassOpacity * 0.6)))
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05), .white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
            .shadow(color: pal.shadow.opacity(0.18), radius: 14, y: 6)
    }
}
extension View {
    func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
}

// MARK: - Styles
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GlassIconButton: View {
    let system: String
    var label: String
    var size: CGFloat = 44
    var selected = false
    let action: () -> Void
    @Environment(\.pal) private var pal
    var body: some View {
        Button { Haptics.shared.light(); action() } label: {
            Image(systemName: system)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(selected ? pal.accent : pal.icon)
                .frame(width: size, height: size)
                .glass(Circle(), tint: selected ? pal.accent : nil, interactive: true)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

struct GCard<Content: View>: View {
    @Environment(\.pal) private var pal
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(pal.border, lineWidth: 0.5))
    }
}

struct SectionTitle: View {
    let text: String
    @Environment(\.pal) private var pal
    var body: some View {
        Text(text.uppercased()).gFont(.small).foregroundStyle(pal.textSecondary)
            .padding(.horizontal, 6).padding(.top, 6).accessibilityAddTraits(.isHeader)
    }
}

struct EmptyState: View {
    let icon: String, title: String, message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 44, weight: .light)).foregroundStyle(pal.accent)
            Text(title).gFont(.title).multilineTextAlignment(.center)
            Text(message).gFont(.body).foregroundStyle(pal.textSecondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button { Haptics.shared.medium(); action() } label: {
                    Text(actionTitle).gFont(.headline).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Capsule().fill(pal.accent))
                }.buttonStyle(PressableStyle())
            }
        }
        .padding(28).frame(maxWidth: 420).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    @Environment(\.pal) private var pal
    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { isOn = $0; Haptics.shared.selection() })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).gFont(.body)
                if let subtitle { Text(subtitle).gFont(.caption).foregroundStyle(pal.textSecondary) }
            }
        }.tint(pal.accent)
    }
}

struct InfoRow: View {
    let title: String, value: String
    @Environment(\.pal) private var pal
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).gFont(.body)
            Spacer(minLength: 12)
            Text(value).gFont(.body).foregroundStyle(pal.textSecondary).multilineTextAlignment(.trailing)
        }
    }
}

struct Divider2: View {
    @Environment(\.pal) private var pal
    var body: some View { Rectangle().fill(pal.separator).frame(height: 0.5) }
}

struct Chip: View {
    let title: String
    var icon: String? = nil
    var selected: Bool
    let action: () -> Void
    @Environment(\.pal) private var pal
    var body: some View {
        Button { Haptics.shared.selection(); action() } label: {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title).gFont(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : pal.text)
            .background(Capsule().fill(selected ? pal.accent : pal.card))
            .overlay(Capsule().stroke(pal.border, lineWidth: selected ? 0 : 0.5))
        }.buttonStyle(PressableStyle())
    }
}

extension View {
    func themedScreen() -> some View { modifier(ThemedScreen()) }
}
struct ThemedScreen: ViewModifier {
    @Environment(\.pal) private var pal
    func body(content: Content) -> some View {
        content
            .background(pal.bg.ignoresSafeArea())
            .toolbarBackground(pal.nav, for: .navigationBar)
    }
}
