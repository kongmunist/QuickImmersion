import SwiftUI

struct ContentView: View {
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissWindow) var dismissWindow
    @Binding var isEnabled:Bool
    @Binding var buttonText:String


    

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                // image
                Image(.graph1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 300)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                Spacer()
                // Text instructions for how to get out of the menu
                Text("To exit the immersive space, tap your left wrist with your index & middle fingers.")
                    .font(.title)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 50)
                // huge button
               Button { 
                   Task {
                       await self.openImmersiveSpace(id: "immersiveSpace")
                       // self.dismissWindow()
                       // disable start button
                       isEnabled = false
                       // self.setTitle("Immersive space started...")
                   }
               } label: {
                   Text(buttonText)
                       .font(.largeTitle)
                       .padding(.vertical, 12)
                       .padding(.horizontal, 4)
                       .frame(width: 400, height: 225)
               }.disabled(!isEnabled)
                Spacer()
                
            }
            .navigationTitle("VisionOS: Quick Immersion Switch")
        }
        .frame(width: 750, height: 600
        )
    }

//    var buttnon:UIButton = body.subviews[2].subviews[1] as! UIButton
}
