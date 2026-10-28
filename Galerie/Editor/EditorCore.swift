import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - État d’édition (sérialisable : stocké comme données d’ajustement PhotoKit)
enum AspectPreset: String, Codable, CaseIterable, Identifiable {
    case free, original, square, r45, r34, r23, r32, r43, r169, r916
    var id: String { rawValue }
    var label: String {
        switch self { case .free: return "Libre"; case .original: return "Original"; case .square: return "1:1"; case .r45: return "4:5"; case .r34: return "3:4"
        case .r23: return "2:3"; case .r32: return "3:2"; case .r43: return "4:3"; case .r169: return "16:9"; case .r916: return "9:16" }
    }
    /// largeur / hauteur en pixels ; nil = libre ; 0 = ratio de l’image
    var ratio: CGFloat? {
        switch self { case .free: return nil; case .original: return 0; case .square: return 1; case .r45: return 0.8; case .r34: return 0.75; case .r23: return 2.0 / 3
        case .r32: return 1.5; case .r43: return 4.0 / 3; case .r169: return 16.0 / 9; case .r916: return 9.0 / 16 }
    }
}

struct Annotation: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case pen, highlighter, rect, oval, arrow, text }
    var id = UUID()
    var kind: Kind
    var points: [CGPoint]      // normalisés (origine en haut à gauche)
    var colorHex: String
    var width: CGFloat         // fraction du plus petit côté
    var text: String = ""
}

struct EditState: Codable, Equatable {
    var exposure = 0.0, brilliance = 0.0, highlights = 0.0, shadows = 0.0, contrast = 0.0, brightness = 0.0, blackPoint = 0.0
    var saturation = 0.0, vibrance = 0.0, temperature = 0.0, tint = 0.0, sharpness = 0.0, definition = 0.0, noise = 0.0, vignette = 0.0
    var filterID = "original"
    var filterIntensity = 1.0
    var auto = false
    var quarterTurns = 0
    var flipH = false, flipV = false
    var straighten = 0.0
    var perspV = 0.0, perspH = 0.0
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var aspect: AspectPreset = .free
    var annotations: [Annotation] = []

    var hasGeometry: Bool { quarterTurns % 4 != 0 || flipH || flipV || straighten != 0 || perspV != 0 || perspH != 0 || crop != CGRect(x: 0, y: 0, width: 1, height: 1) }
    var hasColorEdits: Bool { auto || filterID != "original" || [exposure, brilliance, highlights, shadows, contrast, brightness, blackPoint, saturation, vibrance, temperature, tint, sharpness, definition, noise, vignette].contains { $0 != 0 } }
    var hasVisualEdits: Bool { hasGeometry || hasColorEdits }
    var isDefault: Bool { self == EditState() }

    /// Taille de sortie (pixels) après géométrie + recadrage pour une source de taille donnée.
    func outputSize(for source: CGSize) -> CGSize {
        var w = source.width, h = source.height
        if quarterTurns % 2 != 0 { swap(&w, &h) }
        return CGSize(width: max(2, (w * crop.width / 2).rounded() * 2), height: max(2, (h * crop.height / 2).rounded() * 2))
    }
}

struct AdjustDef: Identifiable {
    let id: String, label: String, icon: String
    let kp: WritableKeyPath<EditState, Double>
    let range: ClosedRange<Double>
    static let all: [AdjustDef] = [
        .init(id: "exposure", label: "Exposition", icon: "plusminus.circle", kp: \.exposure, range: -1...1),
        .init(id: "brilliance", label: "Brillance", icon: "sparkles", kp: \.brilliance, range: -1...1),
        .init(id: "highlights", label: "Hautes lumières", icon: "circle.lefthalf.filled", kp: \.highlights, range: -1...1),
        .init(id: "shadows", label: "Ombres", icon: "circle.righthalf.filled", kp: \.shadows, range: -1...1),
        .init(id: "contrast", label: "Contraste", icon: "circle.lefthalf.striped.horizontal", kp: \.contrast, range: -1...1),
        .init(id: "brightness", label: "Luminosité", icon: "sun.max", kp: \.brightness, range: -1...1),
        .init(id: "blackPoint", label: "Point noir", icon: "circle.fill", kp: \.blackPoint, range: -1...1),
        .init(id: "saturation", label: "Saturation", icon: "drop.fill", kp: \.saturation, range: -1...1),
        .init(id: "vibrance", label: "Vibrance", icon: "waveform.path.ecg", kp: \.vibrance, range: -1...1),
        .init(id: "temperature", label: "Température", icon: "thermometer.medium", kp: \.temperature, range: -1...1),
        .init(id: "tint", label: "Teinte", icon: "eyedropper", kp: \.tint, range: -1...1),
        .init(id: "sharpness", label: "Netteté", icon: "triangle", kp: \.sharpness, range: 0...1),
        .init(id: "definition", label: "Définition", icon: "square.grid.3x3", kp: \.definition, range: 0...1),
        .init(id: "noise", label: "Réduction du bruit", icon: "aqi.medium", kp: \.noise, range: 0...1),
        .init(id: "vignette", label: "Vignettage", icon: "circle.dashed", kp: \.vignette, range: -1...1),
    ]
}

struct FilterDef: Identifiable {
    let id: String, name: String
    let apply: (CIImage) -> CIImage
}

// MARK: - Pipeline Core Image
enum ImagePipeline {
    static let context = CIContext(options: [.cacheIntermediates: false])

    static func f(_ name: String, _ img: CIImage, _ p: [String: Any] = [:]) -> CIImage {
        guard let fl = CIFilter(name: name) else { return img }
        fl.setValue(img, forKey: kCIInputImageKey)
        for (k, v) in p { fl.setValue(v, forKey: k) }
        return fl.outputImage ?? img
    }
    static func normalized(_ i: CIImage) -> CIImage { i.transformed(by: CGAffineTransform(translationX: -i.extent.origin.x, y: -i.extent.origin.y)) }
    static func cc(_ i: CIImage, sat: Double = 1, con: Double = 1, bri: Double = 0) -> CIImage {
        f("CIColorControls", i, ["inputSaturation": sat, "inputContrast": con, "inputBrightness": bri])
    }
    static func warm(_ i: CIImage, _ v: Double, tint: Double = 0) -> CIImage {
        f("CITemperatureAndTint", i, ["inputNeutral": CIVector(x: 6500 + v * 2500, y: tint * 100), "inputTargetNeutral": CIVector(x: 6500, y: 0)])
    }
    static func curve(_ i: CIImage, _ pts: [(CGFloat, CGFloat)]) -> CIImage {
        var p: [String: Any] = [:]
        for (n, pt) in pts.enumerated() { p["inputPoint\(n)"] = CIVector(x: pt.0, y: pt.1) }
        return f("CIToneCurve", i, p)
    }
    static func vignette(_ i: CIImage, _ v: Double) -> CIImage { f("CIVignette", i, ["inputIntensity": v, "inputRadius": 1.6]) }
    static func grain(_ i: CIImage, _ amount: Double) -> CIImage {
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage?.cropped(to: i.extent) else { return i }
        let m = CIFilter(name: "CIColorMatrix")!
        m.setValue(noise, forKey: kCIInputImageKey)
        let g = CGFloat(amount)
        m.setValue(CIVector(x: g, y: 0, z: 0, w: 0), forKey: "inputRVector"); m.setValue(CIVector(x: 0, y: g, z: 0, w: 0), forKey: "inputGVector")
        m.setValue(CIVector(x: 0, y: 0, z: g, w: 0), forKey: "inputBVector"); m.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputAVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputBiasVector")
        guard let n2 = m.outputImage else { return i }
        return f("CIAdditionCompositing", n2.cropped(to: i.extent), [kCIInputBackgroundImageKey: i]).cropped(to: i.extent)
    }

    static let filters: [FilterDef] = {
        func vivid(_ i: CIImage) -> CIImage { f("CIVibrance", cc(i, sat: 1.22, con: 1.06), ["inputAmount": 0.35]) }
        func dramatic(_ i: CIImage) -> CIImage { vignette(f("CIUnsharpMask", f("CIHighlightShadowAdjust", cc(i, sat: 0.82, con: 1.32), ["inputShadowAmount": -0.25, "inputHighlightAmount": 0.8]), ["inputRadius": 12, "inputIntensity": 0.6]), 0.5) }
        return [
            .init(id: "original", name: "Original") { $0 },
            .init(id: "vivid", name: "Vif", apply: vivid),
            .init(id: "vividWarm", name: "Vif chaud") { warm(vivid($0), 0.3) },
            .init(id: "vividCool", name: "Vif froid") { warm(vivid($0), -0.3) },
            .init(id: "dramatic", name: "Dramatique", apply: dramatic),
            .init(id: "dramaticWarm", name: "Dramatique chaud") { warm(dramatic($0), 0.3) },
            .init(id: "dramaticCool", name: "Dramatique froid") { warm(dramatic($0), -0.3) },
            .init(id: "mono", name: "Mono") { f("CIPhotoEffectMono", $0) },
            .init(id: "silver", name: "Argentique") { grain(f("CIPhotoEffectTonal", $0), 0.07) },
            .init(id: "bw", name: "Noir et blanc") { cc($0, sat: 0, con: 1.1) },
            .init(id: "noir", name: "Noir") { f("CIPhotoEffectNoir", $0) },
            .init(id: "natural", name: "Naturel") { f("CIVibrance", cc($0, sat: 1.04, con: 1.03), ["inputAmount": 0.2]) },
            .init(id: "cinema", name: "Cinéma") { vignette(f("CIColorPolynomial", cc($0, sat: 0.9, con: 1.15), [
                "inputRedCoefficients": CIVector(x: 0.02, y: 0.98, z: 0.12, w: -0.08), "inputGreenCoefficients": CIVector(x: 0.01, y: 0.98, z: 0.02, w: 0),
                "inputBlueCoefficients": CIVector(x: 0.05, y: 0.9, z: -0.05, w: 0.08), "inputAlphaCoefficients": CIVector(x: 0, y: 1, z: 0, w: 0)]), 0.35) },
            .init(id: "soft", name: "Doux") { f("CIBloom", cc($0, sat: 0.95, con: 0.9, bri: 0.03), ["inputRadius": 8, "inputIntensity": 0.35]).cropped(to: $0.extent) },
            .init(id: "contrast", name: "Contrasté") { cc($0, sat: 1.1, con: 1.3) },
            .init(id: "vintage", name: "Vintage") { vignette(f("CISepiaTone", f("CIPhotoEffectFade", $0), ["inputIntensity": 0.45]), 0.5) },
            .init(id: "chrome", name: "Chrome") { f("CIPhotoEffectChrome", $0) },
            .init(id: "fade", name: "Fané") { f("CIPhotoEffectFade", $0) },
            .init(id: "process", name: "Process") { f("CIPhotoEffectProcess", $0) },
            .init(id: "transfer", name: "Transfert") { f("CIPhotoEffectTransfer", $0) },
            .init(id: "instant", name: "Instantané") { f("CIPhotoEffectInstant", $0) },
        ]
    }()

    // MARK: Géométrie
    static func geometry(_ input: CIImage, _ s: EditState) -> CIImage {
        var img = normalized(input)
        let ext0 = img.extent
        // Perspective (trapèze vertical / horizontal)
        if s.perspV != 0 || s.perspH != 0 {
            let w = ext0.width, h = ext0.height
            let dv = CGFloat(s.perspV) * 0.12 * w     // > 0 : pince le haut ; < 0 : pince le bas
            let dh = CGFloat(s.perspH) * 0.12 * h     // > 0 : pince la gauche ; < 0 : pince la droite
            let f = CIFilter(name: "CIPerspectiveTransform")!
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(CIVector(cgPoint: CGPoint(x: max(0, dv), y: h - max(0, dh))), forKey: "inputTopLeft")
            f.setValue(CIVector(cgPoint: CGPoint(x: w - max(0, dv), y: h - max(0, -dh))), forKey: "inputTopRight")
            f.setValue(CIVector(cgPoint: CGPoint(x: w - max(0, -dv), y: max(0, -dh))), forKey: "inputBottomRight")
            f.setValue(CIVector(cgPoint: CGPoint(x: max(0, -dv), y: max(0, dh))), forKey: "inputBottomLeft")
            if let o = f.outputImage {
                let cover = 1 + 0.14 * (abs(s.perspV) + abs(s.perspH))
                img = scaleAbout(o, center: CGPoint(x: w / 2, y: h / 2), scale: cover).cropped(to: ext0)
                img = normalized(img)
            }
        }
        // Quarts de tour (sens antihoraire) et miroirs
        let turns = ((s.quarterTurns % 4) + 4) % 4
        if turns != 0 {
            img = img.transformed(by: CGAffineTransform(rotationAngle: CGFloat(turns) * .pi / 2))
            img = normalized(img)
        }
        if s.flipH { img = normalized(img.transformed(by: CGAffineTransform(scaleX: -1, y: 1))) }
        if s.flipV { img = normalized(img.transformed(by: CGAffineTransform(scaleX: 1, y: -1))) }
        // Redressement : rotation + zoom pour éviter les coins vides
        if s.straighten != 0 {
            let e = img.extent
            let th = CGFloat(s.straighten) * .pi / 180
            let c = CGPoint(x: e.midX, y: e.midY)
            let ratio = max(e.width / e.height, e.height / e.width)
            let cover = abs(cos(th)) + abs(sin(th)) * ratio
            var t = CGAffineTransform(translationX: -c.x, y: -c.y)
            t = t.concatenating(CGAffineTransform(rotationAngle: th)).concatenating(CGAffineTransform(scaleX: cover, y: cover)).concatenating(CGAffineTransform(translationX: c.x, y: c.y))
            img = normalized(img.transformed(by: t).cropped(to: e))
        }
        return img
    }
    static func scaleAbout(_ i: CIImage, center: CGPoint, scale: CGFloat) -> CIImage {
        var t = CGAffineTransform(translationX: -center.x, y: -center.y)
        t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        return i.transformed(by: t)
    }
    static func applyCrop(_ i: CIImage, _ s: EditState) -> CIImage {
        let e = i.extent, c = s.crop
        if c == CGRect(x: 0, y: 0, width: 1, height: 1) { return i }
        let r = CGRect(x: e.minX + c.minX * e.width, y: e.minY + (1 - c.maxY) * e.height, width: c.width * e.width, height: c.height * e.height).integral
        return normalized(i.cropped(to: r))
    }

    // MARK: Réglages couleur
    static func adjust(_ input: CIImage, _ s: EditState) -> CIImage {
        var i = input
        let ext = input.extent
        if s.auto {
            for fl in input.autoAdjustmentFilters(options: [.redEye: false]) { fl.setValue(i, forKey: kCIInputImageKey); i = fl.outputImage ?? i }
        }
        if s.exposure != 0 { i = f("CIExposureAdjust", i, ["inputEV": s.exposure * 2]) }
        if s.brilliance != 0 {
            i = f("CIHighlightShadowAdjust", i, ["inputShadowAmount": s.brilliance * 0.5, "inputHighlightAmount": 1 - max(0, s.brilliance) * 0.25])
            i = cc(i, con: 1 + s.brilliance * 0.08)
        }
        if s.highlights != 0 || s.shadows != 0 {
            i = f("CIHighlightShadowAdjust", i, ["inputHighlightAmount": s.highlights < 0 ? 1 + s.highlights : 1, "inputShadowAmount": s.shadows])
            if s.highlights > 0 { let h = CGFloat(s.highlights) * 0.1; i = curve(i, [(0, 0), (0.25, 0.25), (0.5, 0.5), (0.75, 0.75 + h), (1, 1)]) }
        }
        if s.blackPoint != 0 {
            let b = CGFloat(s.blackPoint)
            i = curve(i, [(0, max(0, -b) * 0.08), (0.25, 0.25 - b * 0.06), (0.5, 0.5), (0.75, 0.75), (1, 1)])
        }
        if s.contrast != 0 || s.brightness != 0 || s.saturation != 0 {
            i = cc(i, sat: 1 + s.saturation, con: 1 + s.contrast * 0.6, bri: s.brightness * 0.25)
        }
        if s.vibrance != 0 { i = f("CIVibrance", i, ["inputAmount": s.vibrance]) }
        if s.temperature != 0 || s.tint != 0 { i = warm(i, s.temperature, tint: s.tint) }
        if s.noise > 0 { i = f("CINoiseReduction", i, ["inputNoiseLevel": s.noise * 0.05, "inputSharpness": 0.4]) }
        if s.sharpness > 0 { i = f("CISharpenLuminance", i, ["inputSharpness": s.sharpness * 1.5, "inputRadius": 1.2]) }
        if s.definition > 0 { i = f("CIUnsharpMask", i, ["inputRadius": 10, "inputIntensity": s.definition * 0.9]) }
        if s.vignette != 0 { i = vignette(i, s.vignette * 1.5) }
        return i.cropped(to: ext)
    }

    static func applyFilter(_ i: CIImage, _ s: EditState) -> CIImage {
        guard s.filterID != "original", let def = filters.first(where: { $0.id == s.filterID }) else { return i }
        let out = def.apply(i).cropped(to: i.extent)
        if s.filterIntensity >= 0.999 { return out }
        guard let d = CIFilter(name: "CIDissolveTransition") else { return out }
        d.setValue(i, forKey: kCIInputImageKey); d.setValue(out, forKey: kCIInputTargetImageKey); d.setValue(s.filterIntensity, forKey: kCIInputTimeKey)
        return d.outputImage?.cropped(to: i.extent) ?? out
    }

    /// Géométrie → (recadrage) → réglages → filtre.
    static func render(_ input: CIImage, _ s: EditState, includeCrop: Bool = true) -> CIImage {
        var i = geometry(input, s)
        if includeCrop { i = applyCrop(i, s) }
        i = adjust(i, s)
        i = applyFilter(i, s)
        return i
    }

    static func cgImage(_ i: CIImage, colorSpace: CGColorSpace? = nil) -> CGImage? {
        context.createCGImage(i, from: i.extent, format: .RGBA8, colorSpace: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB))
    }
    static func scaled(_ i: CIImage, maxSide: CGFloat) -> CIImage {
        let m = max(i.extent.width, i.extent.height)
        guard m > maxSide else { return i }
        let s = maxSide / m
        return normalized(i.transformed(by: CGAffineTransform(scaleX: s, y: s)))
    }
}

// MARK: - Annotations
enum AnnotationRenderer {
    static func image(size: CGSize, annotations: [Annotation]) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in draw(ctx.cgContext, size: size, annotations: annotations) }
    }
    static func compose(_ base: CGImage, annotations: [Annotation]) -> CGImage {
        guard !annotations.isEmpty else { return base }
        let size = CGSize(width: base.width, height: base.height)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIImage(cgImage: base).draw(in: CGRect(origin: .zero, size: size))
            draw(ctx.cgContext, size: size, annotations: annotations)
        }
        return img.cgImage ?? base
    }
    static func draw(_ c: CGContext, size: CGSize, annotations: [Annotation]) {
        let m = min(size.width, size.height)
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        for a in annotations {
            let color = UIColor(Color(hex: a.colorHex))
            c.saveGState()
            c.setLineCap(.round); c.setLineJoin(.round)
            switch a.kind {
            case .pen, .highlighter:
                guard let f = a.points.first else { break }
                c.setStrokeColor(color.withAlphaComponent(a.kind == .highlighter ? 0.35 : 1).cgColor)
                c.setLineWidth(a.width * m * (a.kind == .highlighter ? 3 : 1))
                if a.kind == .highlighter { c.setLineCap(.square) }
                c.move(to: pt(f)); for p in a.points.dropFirst() { c.addLine(to: pt(p)) }
                if a.points.count == 1 { c.addLine(to: pt(f)) }
                c.strokePath()
            case .rect, .oval:
                guard a.points.count >= 2 else { break }
                let p0 = pt(a.points[0]), p1 = pt(a.points[a.points.count - 1])
                let r = CGRect(x: min(p0.x, p1.x), y: min(p0.y, p1.y), width: abs(p1.x - p0.x), height: abs(p1.y - p0.y))
                c.setStrokeColor(color.cgColor); c.setLineWidth(a.width * m)
                if a.kind == .rect { c.stroke(r) } else { c.strokeEllipse(in: r) }
            case .arrow:
                guard a.points.count >= 2 else { break }
                let p0 = pt(a.points[0]), p1 = pt(a.points[a.points.count - 1])
                c.setStrokeColor(color.cgColor); c.setLineWidth(a.width * m)
                c.move(to: p0); c.addLine(to: p1)
                let ang = atan2(p1.y - p0.y, p1.x - p0.x), head = max(a.width * m * 4, 12)
                for d in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                    c.move(to: p1); c.addLine(to: CGPoint(x: p1.x + head * cos(ang + d), y: p1.y + head * sin(ang + d)))
                }
                c.strokePath()
            case .text:
                guard let p = a.points.first, !a.text.isEmpty else { break }
                let font = UIFont.systemFont(ofSize: max(14, a.width * m * 6), weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color,
                    .shadow: { let s = NSShadow(); s.shadowColor = UIColor.black.withAlphaComponent(0.5); s.shadowBlurRadius = 3; s.shadowOffset = .zero; return s }()]
                (a.text as NSString).draw(at: pt(p), withAttributes: attrs)
            }
            c.restoreGState()
        }
    }
}

// MARK: - Session (historique annuler / rétablir)
@MainActor
final class EditorSession: ObservableObject {
    @Published var state = EditState() { didSet { onChange?() } }
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var showOriginal = false
    var onChange: (() -> Void)?
    private var history: [EditState] = [EditState()]
    private var index = 0

    func commit() {
        guard state != history[index] else { return }
        history = Array(history[0...index]); history.append(state); index = history.count - 1; refresh()
    }
    func undo() { guard index > 0 else { return }; index -= 1; state = history[index]; refresh(); Haptics.shared.light() }
    func redo() { guard index < history.count - 1 else { return }; index += 1; state = history[index]; refresh(); Haptics.shared.light() }
    func resetAll() { state = EditState(); commit(); Haptics.shared.warning() }
    func reset(_ kp: WritableKeyPath<EditState, Double>) { state[keyPath: kp] = 0; commit() }
    private func refresh() { canUndo = index > 0; canRedo = index < history.count - 1 }
}
