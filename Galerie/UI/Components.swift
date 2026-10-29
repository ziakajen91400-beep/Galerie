import SwiftUI

// MARK: - Liquid Glass (iOS 26+) avec repli matériau translucide
struct GlassModifier<S: Shape>: ViewModifier {
    @Environment(\.pal) private var pal
    @EnvironmentObject private var settings: AppSettings
    let shape: S
    var tint: Color?
    var interactive = false

    private var level: GlassLevel { settings.prefs.glassLevel }
    /// Opacité de la teinte : réduite par rapport à l’ancienne version (trop teintée) et réglable.
    /// Une teinte demandée explicitement (bouton sélectionné) reste lisible.
    private var tintOpacity: Double { pal.glassOpacity * (tint == nil ? level.tintFactor : max(level.tintFactor, 0.5)) }

    /// Contour lumineux fin + reflet supérieur : donnent de la profondeur sans bordure marquée ni fond opaque.
    /// Ces calques ne captent jamais les touches.
    private func sheen(_ content: some View) -> some View {
        content
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.55 * level.highlight), .white.opacity(0.03), .white.opacity(0.22 * level.highlight)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.6).allowsHitTesting(false))
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.10 * level.highlight), .clear], startPoint: .top, endPoint: .center)).allowsHitTesting(false))
    }

    @ViewBuilder func body(content: Content) -> some View {
        if settings.prefs.panelStyle == .solid {
            content.background(shape.fill(pal.surface)).overlay(shape.stroke(pal.border, lineWidth: 0.6))
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                let t = (tint ?? pal.glassTint).opacity(tintOpacity)
                let base: Glass = (level == .low) ? .clear : .regular
                let g: Glass = base.tint(t)
                if interactive { sheen(content.glassEffect(g.interactive(), in: shape)) }
                else { sheen(content.glassEffect(g, in: shape)) }
            } else { legacy(content) }
            #else
            legacy(content)
            #endif
        }
    }

    private func legacy(_ content: Content) -> some View {
        let mat: Material = level == .high ? .thinMaterial : .ultraThinMaterial
        return sheen(
            content
                .background(mat, in: shape)
                .background(shape.fill((tint ?? pal.glassTint).opacity(tintOpacity * 0.8)))
        )
        .shadow(color: pal.shadow.opacity(level == .low ? 0.08 : 0.16), radius: 12, y: 5)
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
                .contentShape(Circle())
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
    @Environment(\.backdrop) private var backdrop
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    pal.bg
                    if let b = backdrop { BackdropView(spec: b, pal: pal, dark: b.dark) }
                }.ignoresSafeArea()
            }
            .toolbarBackground(pal.nav, for: .navigationBar)
    }
}
