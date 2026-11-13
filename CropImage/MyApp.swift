import SwiftUI

@main
struct MyApp: App {
    @StateObject private var cropModel = CropImageViewModel()
    @State private var croppedImage: CroppedImage?

    var body: some Scene {
        WindowGroup {
            NavigationView {
                if let image = UIImage(named: "test") {
                    CropImageScreen(vm: cropModel, inputImage: image) {
                        croppedImage = CroppedImage(image: $0)
                    }
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .navigationViewStyle(.stack)
            .sheet(item: $croppedImage) { result in
                Image(uiImage: result.image)
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}
