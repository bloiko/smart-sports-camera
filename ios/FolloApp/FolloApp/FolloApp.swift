import SwiftUI

@main
struct FolloApp: App {
    @State var onboarded = UserDefaults.standard.bool(forKey: "onboarding.done")
    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded { MyMatchesView() } else { OnboardingView { onboarded = true } }
            }.preferredColorScheme(.dark)
        }
    }
}
