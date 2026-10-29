import SwiftUI

extension AppSettings {
    /// Onglets du dock, nettoyés : identifiants valides et uniques, Photothèque et Réglages toujours présents, 8 au maximum.
    var dock: [AppTab] { Self.sanitizeDock(prefs.dockTabs) }

    static func sanitizeDock(_ ids: [String]) -> [AppTab] {
        var out: [AppTab] = []
        for id in ids { if let t = AppTab(rawValue: id), !out.contains(t) { out.append(t) } }
        for t in [AppTab.library, .settings] where !out.contains(t) { out.append(t) }
        if out.count > 8 {
            // on retire les derniers onglets non essentiels
            while out.count > 8, let i = out.lastIndex(where: { !$0.isEssential }) { out.remove(at: i) }
        }
        return out
    }
}

/// Style d’un bouton du dock : retour visuel immédiat, sans délai.
struct DockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Barre de navigation inférieure.
///
/// Fiabilité tactile :
/// - chaque bouton occupe toute sa cellule (`contentShape`) : plus besoin de viser l’icône ;
/// - tout le bloc (marges comprises) est un support tactile opaque aux touches : rien de ce qui est
///   affiché derrière (photo de la carte, miniature…) ne peut recevoir un appui destiné au dock ;
/// - l’indicateur et les reflets ne captent jamais les touches (`allowsHitTesting(false)`).
///
/// Navigation gestuelle : en glissant le doigt à l’horizontale sur le dock, l’indicateur suit le doigt
/// et la section sous le doigt s’ouvre au relâchement. Le geste ne démarre qu’après 14 pt de mouvement
/// horizontal : un simple appui reste un appui. Au-delà de 5 onglets, le dock défile horizontalement.
struct GalerieTabBar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings
    @Environment(\.pal) private var pal
    @State private var scrub: Int?
    @State private var width: CGFloat = 0

    private let rowHeight: CGFloat = 56
    private let scrollItemWidth: CGFloat = 70

    private var tabs: [AppTab] { settings.dock }
    private var scrolls: Bool { tabs.count > 5 }
    private var selectedIndex: Int { tabs.firstIndex(of: app.tab) ?? -1 }

    var body: some View {
        Group {
            if scrolls {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) { row(itemWidth: scrollItemWidth) }
                        .onAppear { proxy.scrollTo(app.tab, anchor: .center) }
                        .onChange(of: app.tab) { _, t in withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(t, anchor: .center) } }
                }
            } else {
                row(itemWidth: width > 0 ? width / CGFloat(max(tabs.count, 1)) : 64)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
                    .simultaneousGesture(settings.prefs.dockSwipe ? scrubGesture : nil)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .glass(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 4)
        // Support tactile opaque aux touches sur toute l’emprise du dock : bloque les éléments situés derrière.
        .background(Color.black.opacity(0.001))
        .accessibilityElement(children: .contain)
    }

    private func row(itemWidth: CGFloat) -> some View {
        let highlighted = scrub ?? selectedIndex
        return ZStack(alignment: .leading) {
            if highlighted >= 0 && highlighted < tabs.count {
                Capsule().fill(pal.accent.opacity(0.16))
                    .overlay(Capsule().stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 0.6))
                    .frame(width: max(itemWidth - 6, 10), height: rowHeight - 4)
                    .offset(x: CGFloat(highlighted) * itemWidth + 3)
                    .animation(settings.spring, value: highlighted)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 0) {
                ForEach(tabs) { t in
                    Button { tap(t) } label: { label(t) }
                        .buttonStyle(DockButtonStyle())
                        .frame(width: itemWidth, height: rowHeight)
                        .contentShape(Rectangle())
                        .id(t)
                        .accessibilityLabel(t.title)
                        .accessibilityAddTraits(app.tab == t ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
        .frame(height: rowHeight)
    }

    private func tap(_ t: AppTab) {
        Haptics.shared.dock()
        app.select(t)
    }

    @ViewBuilder private func label(_ t: AppTab) -> some View {
        let sel = app.tab == t || scrub.map({ tabs.indices.contains($0) && tabs[$0] == t }) == true
        VStack(spacing: 2) {
            if t == .library { centerIcon(selected: sel) }
            else {
                Image(systemName: t.icon).font(.system(size: 20, weight: .semibold))
                    .frame(height: 30)
            }
            Text(t.title).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(sel ? pal.accent : pal.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    /// Bouton central : entièrement contenu dans la hauteur du dock (aucun débordement), avec un dégradé,
    /// un reflet supérieur et une ombre douce.
    private func centerIcon(selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [pal.accent.opacity(0.95), pal.accent.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    Circle().fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0)], startPoint: .top, endPoint: .center))
                        .padding(1.5)
                )
                .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
                .shadow(color: pal.accent.opacity(selected ? 0.40 : 0.22), radius: selected ? 6 : 3, y: 2)
            Image(systemName: "photo.fill.on.rectangle.fill")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
        .frame(height: 30)
        .allowsHitTesting(false)
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onChanged { v in
                guard width > 0, abs(v.translation.width) > abs(v.translation.height) || scrub != nil else { return }
                let cell = width / CGFloat(max(tabs.count, 1))
                let i = min(max(Int(v.location.x / cell), 0), tabs.count - 1)
                if scrub != i { scrub = i; Haptics.shared.selection() }
            }
            .onEnded { _ in
                if let i = scrub, tabs.indices.contains(i) { app.select(tabs[i]) }
                scrub = nil
            }
    }
}
