import SwiftUI

@main
struct GalerieApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var themes = ThemeStore()
    @StateObject private var fonts = FontStore()
    @StateObject private var library = PhotoLibraryModel()
    @StateObject private var appState = AppState()
    @StateObject private var profile = ProfileStore()
    @StateObject private var intelligence = IntelligenceIndex()
    @StateObject private var memories = MemoriesEngine()
    @StateObject private var geo = GeoIndex()
    @StateObject private var backdrops = BackdropStore()
    @StateObject private var lock = AppLock()
    @StateObject private var privateStore = PrivateStore()

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environmentObject(settings)
                .environmentObject(themes)
                .environmentObject(fonts)
                .environmentObject(library)
                .environmentObject(appState)
                .environmentObject(profile)
                .environmentObject(intelligence)
                .environmentObject(memories)
                .environmentObject(geo)
                .environmentObject(backdrops)
                .environmentObject(lock)
                .environmentObject(privateStore)
        }
    }
}
