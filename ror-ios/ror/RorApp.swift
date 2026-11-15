import SwiftUI

@main
struct RorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm = RorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        vm.syncFromPC()
                    }
                }
        }
    }
}
