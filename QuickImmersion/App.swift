import SwiftUI

@main
struct HeadHandsDemo: App {
    @State var isEnabled: Bool = true
    @State var buttonText: String = "Start"
    
    var body: some Scene {
        WindowGroup {
            ContentView(isEnabled:$isEnabled, buttonText: $buttonText)
        }
        .windowResizability(.contentSize)
        
        ImmersiveSpace(id: "immersiveSpace") {
            🌐RealityView(isEnabled: $isEnabled, buttonText: $buttonText)
//            Cube()
        }
    }
    
    init() {
        🧑HeadTrackingComponent.registerComponent()
        🧑HeadTrackingSystem.registerSystem()
    }
}
