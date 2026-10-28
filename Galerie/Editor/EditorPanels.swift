import SwiftUI

enum EditorTab: String, CaseIterable, Identifiable {
    case trim, adjust, filters, crop, annotate, audio
    var id: String { rawValue }
    var title: String { switch self { case .trim: return "Découper"; case .adjust: return "Ajuster"; case .filters: return "Filtres"; case .crop: return "Recadrer"; case .annotate: return "Annoter"; case .audio: return "Audio" } }
    var icon: String { switch self { case .trim: return "scissors"; case .adjust: return "slider.horizontal.3"; case .filters: return "camera.filters"; case .crop: return "crop.rotate"; case .annotate: return "pencil.tip.crop.circle"; case .audio: return "speaker.wave.2" } }
}

func fitRect(_ content: CGSize, in bounds: CGSize) -> CGRect {
    guard content.width > 0, content.height > 0 else { return CGRect(origin: .zero, size: bounds) }
    let s = min(bounds.width / content.width, bounds.height / content.height)
    let w = content.width * s, h = content.height * s
    return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
}

// MARK: - Recadrage
enum CropMath {
    /// Rapport largeur/hauteur normalisé du recadrage pour un preset et une taille d’image.
    static func normalizedRatio(_ a: AspectPreset, imageSize: CGSize) -> CGFloat? {
        guard let r = a.ratio, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let pixel = r == 0 ? imageSize.width / imageSize.height : r
        return pixel * imageSize.height / imageSize.width
    }
    static func centered(_ nr: CGFloat) -> CGRect {
        var w: CGFloat = 1, h: CGFloat = 1 / nr
        if h > 1 { h = 1; w = nr }
        return CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }
    static func dragCorner(anchor: CGPoint, to p: CGPoint, nr: CGFloat?, minSize: CGFloat = 0.08) -> CGRect {
        let sx: CGFloat = p.x >= anchor.x ? 1 : -1, sy: CGFloat = p.y >= anchor.y ? 1 : -1
        var nw = abs(min(max(p.x, 0), 1) - anchor.x), nh = abs(min(max(p.y, 0), 1) - anchor.y)
        if let nr {
            if nh == 0 || nw / max(nh, 0.0001) > nr { nw = nh * nr } else { nh = nw / nr }
            let maxW = sx > 0 ? 1 - anchor.x : anchor.x, maxH = sy > 0 ? 1 - anchor.y : anchor.y
            if nw > maxW { nw = maxW; nh = nw / nr }
            if nh > maxH { nh = maxH; nw = nh * nr }
        }
        nw = max(nw, minSize); nh = max(nh, nr.map { minSize / max($0, 0.1) } ?? minSize)
        let x = sx > 0 ? anchor.x : anchor.x - nw, y = sy > 0 ? anchor.y : anchor.y - nh
        return CGRect(x: max(0, x), y: max(0, y), width: min(nw, 1), height: min(nh, 1))
    }
}

struct CropOverlay: View {
    @Binding var crop: CGRect
    let aspect: AspectPreset
    let imageSize: CGSize
    var onEnd: () -> Void
    @State private var startCrop: CGRect?

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let r = CGRect(x: crop.minX * W, y: crop.minY * H, width: crop.width * W, height: crop.height * H)
            let nr = CropMath.normalizedRatio(aspect, imageSize: imageSize)
            ZStack {
                Path { p in p.addRect(CGRect(origin: .zero, size: g.size)); p.addRect(r) }.fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                Path { p in
                    for i in 1...2 {
                        let fx = r.minX + r.width * CGFloat(i) / 3, fy = r.minY + r.height * CGFloat(i) / 3
                        p.move(to: CGPoint(x: fx, y: r.minY)); p.addLine(to: CGPoint(x: fx, y: r.maxY))
                        p.move(to: CGPoint(x: r.minX, y: fy)); p.addLine(to: CGPoint(x: r.maxX, y: fy))
                    }
                }.stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                Rectangle().stroke(Color.white, lineWidth: 1.5).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                Color.clear.contentShape(Rectangle()).frame(width: max(r.width - 44, 10), height: max(r.height - 44, 10)).position(x: r.midX, y: r.midY)
                    .gesture(DragGesture().onChanged { v in
                        if startCrop == nil { startCrop = crop }
                        guard let s = startCrop else { return }
                        crop.origin.x = min(max(0, s.minX + v.translation.width / W), 1 - s.width)
                        crop.origin.y = min(max(0, s.minY + v.translation.height / H), 1 - s.height)
                    }.onEnded { _ in startCrop = nil; onEnd() })
                ForEach(0..<4, id: \.self) { i in
                    let cx = (i % 2 == 0) ? r.minX : r.maxX, cy = i < 2 ? r.minY : r.maxY
                    Circle().fill(Color.white).frame(width: 22, height: 22).shadow(radius: 2)
                        .frame(width: 44, height: 44).contentShape(Rectangle()).position(x: cx, y: cy)
                        .gesture(DragGesture(coordinateSpace: .named("crop")).onChanged { v in
                            let ax = (i % 2 == 0) ? crop.maxX : crop.minX, ay = i < 2 ? crop.maxY : crop.minY
                            crop = CropMath.dragCorner(anchor: CGPoint(x: ax, y: ay), to: CGPoint(x: v.location.x / W, y: v.location.y / H), nr: nr)
                        }.onEnded { _ in onEnd() })
                }
            }.coordinateSpace(name: "crop")
        }
    }
}

// MARK: - Annotations (réglages d’outil)
@MainActor
final class AnnotateSettings: ObservableObject {
    @Published var tool: Annotation.Kind = .pen
    @Published var colorHex = "FF3B30FF"
    @Published var width: CGFloat = 0.008
    @Published var redo: [Annotation] = []
}

// MARK: - Panneaux
struct AdjustPanel: View {
    @ObservedObject var session: EditorSession
    @State private var selected = AdjustDef.all[0]
    @Environment(\.pal) private var pal

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { session.state.auto.toggle(); session.commit(); Haptics.shared.medium() } label: {
                    Label("Auto", systemImage: "wand.and.stars").gFont(.caption).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(session.state.auto ? pal.accent : pal.card)).foregroundStyle(session.state.auto ? Color.white : pal.text)
                }
                Spacer()
                Text("\(selected.label) · \(Int(session.state[keyPath: selected.kp] * 100))").gFont(.caption)
                Spacer()
                Button("Réinitialiser") { session.resetAll() }.gFont(.caption)
            }
            Slider(value: Binding(get: { session.state[keyPath: selected.kp] }, set: { session.state[keyPath: selected.kp] = $0 }),
                   in: selected.range, onEditingChanged: { if !$0 { session.commit() } })
                .accessibilityLabel(selected.label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AdjustDef.all) { d in
                        let changed = session.state[keyPath: d.kp] != 0
                        Button { Haptics.shared.selection(); selected = d } label: {
                            VStack(spacing: 4) {
                                Image(systemName: d.icon).font(.system(size: 18)).frame(width: 46, height: 46)
                                    .background(Circle().fill(selected.id == d.id ? pal.accent.opacity(0.2) : pal.card))
                                    .overlay(Circle().stroke(changed ? pal.accent : pal.border, lineWidth: changed ? 2 : 0.5))
                                Text(d.label).font(.system(size: 9)).lineLimit(1).frame(width: 60)
                            }.foregroundStyle(selected.id == d.id ? pal.accent : pal.text)
                        }.simultaneousGesture(TapGesture(count: 2).onEnded { session.reset(d.kp) })
                    }
                }
            }
            Text("Double-touche une icône pour réinitialiser ce réglage.").gFont(.small).foregroundStyle(pal.textSecondary)
        }.padding(.horizontal, 14)
    }
}

struct FiltersPanel: View {
    @ObservedObject var session: EditorSession
    let thumbs: [String: UIImage]
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ImagePipeline.filters) { f in
                        Button { Haptics.shared.selection(); session.state.filterID = f.id; session.state.filterIntensity = 1; session.commit() } label: {
                            VStack(spacing: 4) {
                                Group { if let t = thumbs[f.id] { Image(uiImage: t).resizable().scaledToFill() } else { pal.card } }
                                    .frame(width: 68, height: 68).clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(session.state.filterID == f.id ? pal.accent : pal.border, lineWidth: session.state.filterID == f.id ? 3 : 0.5))
                                Text(f.name).font(.system(size: 10)).lineLimit(1).frame(width: 72)
                            }.foregroundStyle(pal.text)
                        }
                    }
                }.padding(.horizontal, 14)
            }
            if session.state.filterID != "original" {
                HStack { Text("Intensité").gFont(.caption)
                    Slider(value: $session.state.filterIntensity, in: 0...1, onEditingChanged: { if !$0 { session.commit() } })
                    Text("\(Int(session.state.filterIntensity * 100))").gFont(.caption).frame(width: 34) }.padding(.horizontal, 14)
            }
        }
    }
}

struct CropPanel: View {
    @ObservedObject var session: EditorSession
    let geometrySize: CGSize
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(AspectPreset.allCases) { a in Chip(title: a.label, selected: session.state.aspect == a) { setAspect(a) } } }.padding(.horizontal, 14)
            }
            HStack(spacing: 14) {
                tool("rotate.left", "Pivoter à gauche") { session.state.quarterTurns += 1; session.state.crop = CGRect(x: 0, y: 0, width: 1, height: 1); session.state.aspect = .free; session.commit() }
                tool("arrow.left.and.right.righttriangle.left.righttriangle.right", "Miroir horizontal") { session.state.flipH.toggle(); session.commit() }
                tool("arrow.up.and.down.righttriangle.up.righttriangle.down", "Miroir vertical") { session.state.flipV.toggle(); session.commit() }
                tool("arrow.counterclockwise", "Réinitialiser le cadrage") {
                    var s = session.state; s.quarterTurns = 0; s.flipH = false; s.flipV = false; s.straighten = 0; s.perspV = 0; s.perspH = 0; s.crop = CGRect(x: 0, y: 0, width: 1, height: 1); s.aspect = .free
                    session.state = s; session.commit(); Haptics.shared.warning()
                }
            }
            slider("Redresser", icon: "level", value: $session.state.straighten, range: -30...30, suffix: "°")
            slider("Perspective verticale", icon: "perspective", value: $session.state.perspV, range: -1...1, suffix: "")
            slider("Perspective horizontale", icon: "perspective", value: $session.state.perspH, range: -1...1, suffix: "")
        }
    }
    private func setAspect(_ a: AspectPreset) {
        session.state.aspect = a
        if let nr = CropMath.normalizedRatio(a, imageSize: geometrySize) { session.state.crop = CropMath.centered(nr) }
        else if a == .free { }
        session.commit()
    }
    private func tool(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.shared.light(); action() } label: { Image(systemName: icon).font(.system(size: 18)).frame(width: 46, height: 46).background(Circle().fill(pal.card)).overlay(Circle().stroke(pal.border, lineWidth: 0.5)) }.accessibilityLabel(label)
    }
    private func slider(_ title: String, icon: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack { Text(title).gFont(.small).frame(width: 110, alignment: .leading)
            Slider(value: value, in: range, onEditingChanged: { if !$0 { session.commit() } })
            Text(suffix == "°" ? "\(Int(value.wrappedValue))°" : "\(Int(value.wrappedValue * 100))").gFont(.small).frame(width: 36) }.padding(.horizontal, 14)
    }
}

struct AnnotatePanel: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var tool: AnnotateSettings
    @Environment(\.pal) private var pal
    private let palette = ["FF3B30FF", "FF9500FF", "FFCC00FF", "34C759FF", "0A84FFFF", "AF52DEFF", "FFFFFFFF", "000000FF"]
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach([(Annotation.Kind.pen, "pencil.tip"), (.highlighter, "highlighter"), (.arrow, "arrow.up.right"), (.rect, "rectangle"), (.oval, "circle"), (.text, "textformat")], id: \.0) { k, icon in
                    Button { Haptics.shared.selection(); tool.tool = k } label: {
                        Image(systemName: icon).frame(width: 44, height: 44).background(Circle().fill(tool.tool == k ? pal.accent.opacity(0.22) : pal.card))
                            .overlay(Circle().stroke(tool.tool == k ? pal.accent : pal.border, lineWidth: tool.tool == k ? 2 : 0.5))
                    }
                }
                Spacer()
                Button { if let l = session.state.annotations.popLast() { tool.redo.append(l); session.commit(); Haptics.shared.light() } } label: { Image(systemName: "arrow.uturn.backward") }.disabled(session.state.annotations.isEmpty).accessibilityLabel("Annuler le tracé")
                Button { if let r = tool.redo.popLast() { session.state.annotations.append(r); session.commit(); Haptics.shared.light() } } label: { Image(systemName: "arrow.uturn.forward") }.disabled(tool.redo.isEmpty).accessibilityLabel("Rétablir le tracé")
            }.padding(.horizontal, 14)
            HStack(spacing: 8) {
                ForEach(palette, id: \.self) { c in
                    Circle().fill(Color(hex: c)).frame(width: 28, height: 28).overlay(Circle().stroke(tool.colorHex == c ? pal.accent : pal.border, lineWidth: tool.colorHex == c ? 3 : 1))
                        .onTapGesture { Haptics.shared.selection(); tool.colorHex = c }
                }
                ColorPicker("", selection: Binding(get: { Color(hex: tool.colorHex) }, set: { tool.colorHex = $0.hexString }), supportsOpacity: false).labelsHidden()
            }.padding(.horizontal, 14)
            HStack { Image(systemName: "lineweight"); Slider(value: $tool.width, in: 0.003...0.03); Text(tool.tool == .text ? "Taille" : "Épaisseur").gFont(.small) }.padding(.horizontal, 14)
            Text(tool.tool == .text ? "Touche l’image pour ajouter du texte." : "Dessine directement sur l’image.").gFont(.small).foregroundStyle(pal.textSecondary)
        }
    }
}

// MARK: - Canvas
struct EditorCanvas: View {
    let image: UIImage?
    @ObservedObject var session: EditorSession
    @ObservedObject var tool: AnnotateSettings
    let tab: EditorTab
    let geometrySize: CGSize
    var onTapText: (CGPoint) -> Void
    @State private var current: Annotation?

    var body: some View {
        GeometryReader { g in
            if let image {
                let fit = fitRect(image.size, in: g.size)
                ZStack {
                    Image(uiImage: image).resizable().frame(width: fit.width, height: fit.height)
                    if tab != .crop {
                        let anns = session.state.annotations + (current.map { [$0] } ?? [])
                        if !anns.isEmpty && !session.showOriginal {
                            Image(uiImage: AnnotationRenderer.image(size: fit.size, annotations: anns)).resizable().frame(width: fit.width, height: fit.height).allowsHitTesting(false)
                        }
                    }
                    if tab == .crop {
                        CropOverlay(crop: $session.state.crop, aspect: session.state.aspect, imageSize: geometrySize) { session.commit() }
                            .frame(width: fit.width, height: fit.height)
                    }
                    if tab == .annotate {
                        Color.clear.contentShape(Rectangle()).frame(width: fit.width, height: fit.height)
                            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                                let p = CGPoint(x: min(max(v.location.x / fit.width, 0), 1), y: min(max(v.location.y / fit.height, 0), 1))
                                if tool.tool == .text { return }
                                if current == nil { current = Annotation(kind: tool.tool, points: [p], colorHex: tool.colorHex, width: tool.width) }
                                else if tool.tool == .pen || tool.tool == .highlighter { current?.points.append(p) }
                                else { if current!.points.count < 2 { current?.points.append(p) } else { current?.points[1] = p } }
                            }.onEnded { v in
                                let p = CGPoint(x: min(max(v.location.x / fit.width, 0), 1), y: min(max(v.location.y / fit.height, 0), 1))
                                if tool.tool == .text { onTapText(p); return }
                                if let c = current { session.state.annotations.append(c); tool.redo = []; session.commit(); Haptics.shared.light() }
                                current = nil
                            })
                    }
                }.frame(width: g.size.width, height: g.size.height)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).tint(.white) }
        }
    }
}
