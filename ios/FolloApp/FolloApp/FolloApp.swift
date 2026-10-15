import SwiftUI

@main
struct FolloApp: App {
    @State var onboarded = UserDefaults.standard.bool(forKey: "onboarding.done") || CommandLine.arguments.contains("--autostart")
    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded { MyMatchesView() } else { OnboardingView { onboarded = true } }
            }.preferredColorScheme(.dark)
        }
    }
}
