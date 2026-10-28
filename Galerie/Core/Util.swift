import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 6 { s += "FF" }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 24) & 0xFF) / 255,
                  green: Double((v >> 16) & 0xFF) / 255,
                  blue: Double((v >> 8) & 0xFF) / 255,
                  opacity: Double(v & 0xFF) / 255)
    }
    var hexString: String {
        let u = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)), Int(round(a * 255)))
    }
    static func hsb(_ h: Double, _ s: Double, _ b: Double) -> String {
        Color(hue: h.truncatingRemainder(dividingBy: 1), saturation: min(max(s, 0), 1), brightness: min(max(b, 0), 1)).hexString
    }
}

enum Fmt {
    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
    static func range(_ a: Date, _ b: Date) -> String {
        if Calendar.current.isDate(a, inSameDayAs: b) {
            return a.formatted(.dateTime.day().month(.wide).year())
        }
        let f = DateIntervalFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: min(a, b), to: max(a, b))
    }
    static func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Aujourd’hui" }
        if cal.isDateInYesterday(d) { return "Hier" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
    static func shutter(_ t: Double) -> String {
        if t >= 1 { return String(format: "%.1f s", t) }
        return "1/\(Int((1 / t).rounded())) s"
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onDone: (() -> Void)? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let c = UIActivityViewController(activityItems: items, applicationActivities: nil)
        c.completionWithItemsHandler = { _, _, _, _ in onDone?() }
        return c
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

func appSupportURL(_ sub: String? = nil) -> URL {
    var u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    if let sub { u.appendPathComponent(sub, isDirectory: true) }
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}
