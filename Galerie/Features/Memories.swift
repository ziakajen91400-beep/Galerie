import SwiftUI
import Photos
import CoreLocation

struct Memory: Identifiable {
    enum Kind: String { case onThisDay, trip, favorites, period }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let assets: [PHAsset]
    var cover: PHAsset? { assets.first }
}

enum MemoryMath {
    /// Date du même jour il y a `years` ans (nil pour un 29 février inexistant).
    static func sameDay(years: Int, from now: Date, cal: Calendar = .current) -> Date? {
        let c = cal.dateComponents([.month, .day], from: now)
        var t = DateComponents(); t.year = cal.component(.year, from: now) - years; t.month = c.month; t.day = c.day
        guard let d = cal.date(from: t), cal.component(.day, from: d) == c.day else { return nil }
        return d
    }
    static func distanceKm(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let r = 6371.0
        let dLat = (b.0 - a.0) * .pi / 180, dLon = (b.1 - a.1) * .pi / 180
        let x = sin(dLat / 2) * sin(dLat / 2) + cos(a.0 * .pi / 180) * cos(b.0 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(x), sqrt(1 - x))
    }
    /// Détecte les voyages : suites de médias éloignées du « domicile » (cellule la plus fréquente), séparées de moins de 2 jours.
    static func trips(points: [GeoPoint], minCount: Int = 8, awayKm: Double = 80) -> [[GeoPoint]] {
        guard !points.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for p in points { counts["\(Int(p.lat * 4))_\(Int(p.lon * 4))", default: 0] += 1 }
        guard let top = counts.max(by: { $0.value < $1.value }), let home = points.first(where: { "\(Int($0.lat * 4))_\(Int($0.lon * 4))" == top.key }) else { return [] }
        let away = points.filter { distanceKm((home.lat, home.lon), ($0.lat, $0.lon)) > awayKm }.sorted { $0.date < $1.date }
        var trips: [[GeoPoint]] = []; var cur: [GeoPoint] = []
        for p in away {
            if let l = cur.last, p.date.timeIntervalSince(l.date) > 2 * 86400 { if cur.count >= minCount { trips.append(cur) }; cur = [] }
            cur.append(p)
        }
        if cur.count >= minCount { trips.append(cur) }
        return trips
    }
}

@MainActor
final class MemoriesEngine: ObservableObject {
    @Published private(set) var memories: [Memory] = []
    @Published private(set) var loading = false
    private var dirty = true

    func invalidate() { dirty = true }

    func refresh(prefs: Prefs, geo: GeoIndex, force: Bool = false) async {
        guard prefs.memoriesEnabled else { memories = []; return }
        guard dirty || force else { return }
        dirty = false; loading = true
        let dismissed = Set(prefs.dismissedMemories)
        let pts = geo.points
        let p = prefs
        let out: [Memory] = await Task.detached(priority: .userInitiated) {
            var res: [Memory] = []
            let now = Date(), cal = Calendar.current
            if p.memOnThisDay {
                for y in 1...25 {
                    guard let d = MemoryMath.sameDay(years: y, from: now, cal: cal) else { continue }
                    let s = cal.startOfDay(for: d), e = cal.date(byAdding: .day, value: 1, to: s)!
                    let o = PHFetchOptions()
                    o.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", s as NSDate, e as NSDate)
                    o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                    let r = PHAsset.fetchAssets(with: o)
                    if r.count > 0 {
                        var a: [PHAsset] = []; r.enumerateObjects { x, _, _ in a.append(x) }
                        let f = a.filter { $0.isFavorite }; let ordered = f + a.filter { !$0.isFavorite }
                        res.append(Memory(id: "otd-\(y)-\(cal.component(.year, from: now))\(cal.ordinality(of: .day, in: .year, for: now) ?? 0)", kind: .onThisDay,
                                          title: y == 1 ? "Il y a un an" : "Il y a \(y) ans",
                                          subtitle: s.formatted(.dateTime.day().month(.wide).year()), assets: ordered))
                    }
                }
            }
            if p.memTrips {
                for t in MemoryMath.trips(points: pts).sorted(by: { $0.first!.date > $1.first!.date }).prefix(6) {
                    let ids = t.map(\.id)
                    let assets = AssetFetch.sorted(ids: ids, ascending: true)
                    guard let f = t.first?.date, let l = t.last?.date else { continue }
                    res.append(Memory(id: "trip-\(Int(f.timeIntervalSince1970))", kind: .trip, title: "Voyage", subtitle: Fmt.range(f, l), assets: assets))
                }
            }
            if p.memFavorites {
                let o = PHFetchOptions(); o.predicate = NSPredicate(format: "favorite == YES")
                o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let r = PHAsset.fetchAssets(with: o)
                if r.count >= 6 {
                    var a: [PHAsset] = []; r.enumerateObjects { x, _, _ in a.append(x) }
                    var g = SeededRNG(seed: UInt64(cal.ordinality(of: .day, in: .year, for: now) ?? 1))
                    let pick = Array(a.shuffled(using: &g).prefix(30))
                    res.append(Memory(id: "fav-\(cal.ordinality(of: .day, in: .year, for: now) ?? 0)", kind: .favorites, title: "Tes favoris", subtitle: "Sélection du jour", assets: pick))
                }
            }
            if p.memPeriods {
                let all = PHAsset.fetchAssets(with: nil)
                if all.count > 0 {
                    var buckets: [DateComponents: [PHAsset]] = [:]
                    all.enumerateObjects { a, _, _ in
                        if let d = a.creationDate { buckets[cal.dateComponents([.year, .month], from: d), default: []].append(a) }
                    }
                    for (k, v) in buckets.sorted(by: { $0.value.count > $1.value.count }).prefix(3) where v.count >= 20 {
                        guard let d = cal.date(from: k) else { continue }
                        res.append(Memory(id: "period-\(k.year ?? 0)-\(k.month ?? 0)", kind: .period, title: d.formatted(.dateTime.month(.wide).year()), subtitle: "\(v.count) médias · un de tes meilleurs mois",
                                          assets: v.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }))
                    }
                }
            }
            return res
        }.value
        memories = out.filter { !dismissed.contains($0.id) }
        loading = false
    }
}

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}

struct MemoryCard: View {
    let memory: Memory
    @Environment(\.pal) private var pal
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let c = memory.cover { AssetThumb(asset: c, size: CGSize(width: 220, height: 280)) } else { pal.card }
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.title).gFont(.headline).foregroundStyle(.white)
                Text(memory.subtitle).gFont(.small).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
            }.padding(12)
        }
        .frame(width: 220, height: 280).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(pal.border, lineWidth: 0.5))
    }
}

struct MemoryDetailView: View {
    let memory: Memory
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    @State private var slideshow = false
    @State private var showDuel = false
    var body: some View {
        MediaGridView(list: AssetList(memory.assets), token: memory.id, prefix: "mem", emptyTitle: "Souvenir vide")
            .themedScreen()
            .navigationTitle(memory.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { slideshow = true } label: { Image(systemName: "play.fill") }.accessibilityLabel("Diaporama")
                }
                ToolbarItem(placement: .topBarLeading) {
                    if memory.assets.filter({ !$0.isVideo }).count >= 2 { Button { showDuel = true } label: { Image(systemName: "rectangle.split.2x1") }.accessibilityLabel("Ceci ou cela") }
                }
            }
            .fullScreenCover(isPresented: $slideshow) { SlideshowView(list: AssetList(memory.assets), start: 0) }
            .sheet(isPresented: $showDuel) { ThisOrThatView(assets: memory.assets.filter { !$0.isVideo }) }
    }
}

/// « Ceci ou cela » : deux photos du souvenir, la gagnante est ajoutée aux favoris.
struct ThisOrThatView: View {
    let assets: [PHAsset]
    @State private var pair: (PHAsset, PHAsset)?
    @State private var rounds = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(spacing: 14) {
            Text("Laquelle préfères-tu ?").gFont(.title)
            if let (a, b) = pair {
                GeometryReader { g in
                    VStack(spacing: 10) { choice(a, g.size); choice(b, g.size) }
                }
            } else { EmptyState(icon: "photo", title: "Pas assez de photos", message: "Il faut au moins deux photos.") }
            Text("Choisir une photo l’ajoute à tes favoris. \(rounds) choix").gFont(.small).foregroundStyle(pal.textSecondary)
            Button("Terminer") { dismiss() }
        }.padding().background(pal.bg).onAppear(perform: next)
    }
    private func choice(_ a: PHAsset, _ s: CGSize) -> some View {
        Button {
            Task { _ = await MediaActions.setFavorite([a], true); rounds += 1; next() }
        } label: {
            AssetThumb(asset: a, size: CGSize(width: s.width, height: (s.height - 10) / 2), fill: true)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(PressableStyle())
    }
    private func next() {
        guard assets.count >= 2 else { return }
        var i = Int.random(in: 0..<assets.count), j = Int.random(in: 0..<assets.count)
        while j == i { j = Int.random(in: 0..<assets.count) }
        pair = (assets[i], assets[j])
    }
}
