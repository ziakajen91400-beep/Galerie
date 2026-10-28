import XCTest
import SwiftUI
import MapKit
@testable import Galerie

final class GalerieTests: XCTestCase {
    // MARK: Thèmes
    func testPresetThemes() {
        let t = Theme.presets
        XCTAssertGreaterThanOrEqual(t.count, 20)
        XCTAssertEqual(Set(t.map(\.id)).count, t.count, "identifiants uniques")
        for th in t { XCTAssertNotEqual(th.light.background, th.dark.background, th.name) }
        XCTAssertTrue(t.contains { $0.id == "rose" })
    }
    func testThemeCodableRoundTrip() throws {
        let t = Theme.generated(id: "x", name: "X", hue: 0.9, tint: 0.8)
        let d = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(Theme.self, from: d), t)
    }
    func testHexColorRoundTrip() {
        XCTAssertEqual(Color(hex: "FF8800FF").hexString, "FF8800FF")
        XCTAssertEqual(Color(hex: "0A84FF").hexString, "0A84FFFF")
    }
    func testRoseLightLighterThanDark() {
        let r = Theme.presets.first { $0.id == "rose" }!
        func lum(_ h: String) -> CGFloat { var w: CGFloat = 0; UIColor(Color(hex: h)).getWhite(&w, alpha: nil); return w }
        XCTAssertGreaterThan(lum(r.light.background), lum(r.dark.background))
    }

    // MARK: Préférences
    func testPrefsRoundTrip() throws {
        var p = Prefs(); p.hapticsEnabled = false; p.gridColumns = 6; p.themeID = "violet"
        let d = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(Prefs.self, from: d), p)
    }
    func testDefaultHapticsEnabled() { XCTAssertTrue(Prefs().hapticsEnabled) }

    // MARK: Sections chronologiques
    func testSectionsByMonth() {
        let c = Calendar(identifier: .gregorian)
        func d(_ y: Int, _ m: Int, _ day: Int) -> Date { c.date(from: DateComponents(year: y, month: m, day: day))! }
        let dates = [d(2026, 10, 27), d(2026, 10, 19), d(2026, 9, 30), d(2025, 10, 2)]
        let s = MediaSection.compute(dates: dates, mode: .month, calendar: c)
        XCTAssertEqual(s.map(\.count), [2, 1, 1])
        XCTAssertEqual(s[0].minDate, d(2026, 10, 19)); XCTAssertEqual(s[0].maxDate, d(2026, 10, 27))
        XCTAssertEqual(MediaSection.compute(dates: dates, mode: .year, calendar: c).map(\.count), [3, 1])
        XCTAssertEqual(MediaSection.compute(dates: dates, mode: .day, calendar: c).count, 4)
    }

    // MARK: Souvenirs
    func testOnThisDay() {
        let c = Calendar(identifier: .gregorian)
        let now = c.date(from: DateComponents(year: 2026, month: 9, day: 17))!
        let d = MemoryMath.sameDay(years: 1, from: now, cal: c)!
        XCTAssertEqual(c.dateComponents([.year, .month, .day], from: d), DateComponents(year: 2025, month: 9, day: 17))
        let leap = c.date(from: DateComponents(year: 2024, month: 2, day: 29))!
        XCTAssertNil(MemoryMath.sameDay(years: 1, from: leap, cal: c))
        XCTAssertNotNil(MemoryMath.sameDay(years: 4, from: leap, cal: c))
    }
    func testTripDetection() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var pts: [GeoPoint] = (0..<40).map { GeoPoint(id: "h\($0)", lat: 48.85, lon: 2.35, date: base.addingTimeInterval(Double($0) * 86400 * 3), kind: 0) }
        pts += (0..<12).map { GeoPoint(id: "t\($0)", lat: 41.9, lon: 12.5, date: base.addingTimeInterval(86400 * 200 + Double($0) * 3600), kind: 0) }
        let trips = MemoryMath.trips(points: pts)
        XCTAssertEqual(trips.count, 1); XCTAssertEqual(trips[0].count, 12)
    }

    // MARK: Carte
    func testClustering() {
        let now = Date()
        var pts = (0..<50).map { GeoPoint(id: "p\($0)", lat: 48.85 + Double($0) * 0.00001, lon: 2.35, date: now.addingTimeInterval(Double($0)), kind: 0) }
        pts.append(GeoPoint(id: "far", lat: 43.3, lon: 5.4, date: now, kind: 0))
        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 46, longitude: 3), span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12))
        let r = Clusterer.cluster(points: pts, region: region)
        XCTAssertEqual(r.visible.count, 51)
        XCTAssertEqual(r.clusters.count, 2)
        XCTAssertEqual(r.clusters.first?.count, 50)
        XCTAssertEqual(r.clusters.first?.repID, "p49")
        let zoomed = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35), span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001))
        XCTAssertEqual(Clusterer.cluster(points: pts, region: zoomed).visible.count, 50)
    }
    func testBounds() {
        let b = Clusterer.bounds(of: [GeoPoint(id: "a", lat: 10, lon: 10, date: Date(), kind: 0), GeoPoint(id: "b", lat: 20, lon: 30, date: Date(), kind: 0)])!
        XCTAssertEqual(b.center.latitude, 15, accuracy: 0.001); XCTAssertEqual(b.center.longitude, 20, accuracy: 0.001)
        XCTAssertNil(Clusterer.bounds(of: []))
    }

    // MARK: Recherche
    func testSearchParser() {
        let s = SearchParser.parse("vidéos 2024 chat", into: SearchSpec())
        XCTAssertEqual(s.kind, .videos); XCTAssertEqual(s.text, "chat")
        let c = Calendar.current
        XCTAssertEqual(c.component(.year, from: s.from!), 2024); XCTAssertEqual(c.component(.year, from: s.to!), 2025)
        let m = SearchParser.parse("août 2023", into: SearchSpec())
        XCTAssertEqual(c.component(.month, from: m.from!), 8); XCTAssertEqual(c.component(.month, from: m.to!), 9)
        XCTAssertTrue(SearchParser.parse("favoris", into: SearchSpec()).favoritesOnly)
    }

    // MARK: Édition
    func testEditState() {
        var s = EditState(); XCTAssertTrue(s.isDefault); XCTAssertFalse(s.hasVisualEdits)
        s.exposure = 0.3; XCTAssertTrue(s.hasColorEdits)
        s = EditState(); s.quarterTurns = 1; s.crop = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        XCTAssertEqual(s.outputSize(for: CGSize(width: 4000, height: 3000)), CGSize(width: 1500, height: 4000))
    }
    func testCropMath() {
        let nr = CropMath.normalizedRatio(.square, imageSize: CGSize(width: 4000, height: 2000))!
        XCTAssertEqual(nr, 0.5, accuracy: 0.001)
        let c = CropMath.centered(nr)
        XCTAssertEqual(c.width * 4000, c.height * 2000, accuracy: 0.5)
        XCTAssertNil(CropMath.normalizedRatio(.free, imageSize: CGSize(width: 10, height: 10)))
    }
    func testPipelineRenders() {
        let base = CIImage(color: CIColor(red: 0.4, green: 0.5, blue: 0.6)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
        var s = EditState(); s.exposure = 0.4; s.saturation = 0.3; s.vignette = 0.5; s.quarterTurns = 1; s.filterID = "vivid"
        let out = ImagePipeline.render(base, s)
        XCTAssertEqual(out.extent.width, 100, accuracy: 1); XCTAssertEqual(out.extent.height, 200, accuracy: 1)
        for f in ImagePipeline.filters {
            var fs = EditState(); fs.filterID = f.id
            XCTAssertNotNil(ImagePipeline.cgImage(ImagePipeline.render(base, fs)), f.name)
        }
        var g = EditState(); g.straighten = 5; g.perspV = 0.4; g.flipH = true
        XCTAssertNotNil(ImagePipeline.cgImage(ImagePipeline.render(base, g)))
    }
    @MainActor func testSessionUndoRedo() {
        let s = EditorSession()
        s.state.exposure = 0.5; s.commit(); s.state.contrast = 0.2; s.commit()
        XCTAssertTrue(s.canUndo); s.undo(); XCTAssertEqual(s.state.contrast, 0); XCTAssertEqual(s.state.exposure, 0.5)
        s.redo(); XCTAssertEqual(s.state.contrast, 0.2)
    }

    // MARK: Divers
    func testFormats() {
        XCTAssertEqual(Fmt.duration(65), "1:05"); XCTAssertEqual(Fmt.duration(3661), "1:01:01")
        XCTAssertEqual(Fmt.shutter(1.0 / 120), "1/120 s")
    }
    @MainActor
    func testIconResources() {
        for o in AppIconOption.all { XCTAssertNotNil(UIImage(named: o.preview), "aperçu manquant : \(o.preview)") }
        let alts = AppIconManager.configuredAlternates()
        for o in AppIconOption.all where !o.id.isEmpty { XCTAssertTrue(alts.contains(o.id), "icône non configurée : \(o.id)") }
    }
}
