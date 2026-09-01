import SwiftUI

struct RootView: View {
    static let welcomeKey = "com.jawatlas.seenWelcome"

    @State private var environment = AppEnvironment()
    @State private var path: [String] = []
    @State private var showsWelcome = !UserDefaults.standard.bool(forKey: RootView.welcomeKey)
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            CaseLibraryView(path: $path)
        }
        .environment(environment)
        .overlay {
            if environment.appLock.isLocked {
                LockScreen(lock: environment.appLock)
            }
        }
        .task {
            await environment.bootstrap()
        }
        .onOpenURL { url in
            environment.receiveIncoming(url: url)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                environment.appLock.lockIfNeeded()
            }
        }
        .sheet(isPresented: $showsWelcome) {
            WelcomeView {
                UserDefaults.standard.set(true, forKey: RootView.welcomeKey)
                showsWelcome = false
            }
        }
    }
}
