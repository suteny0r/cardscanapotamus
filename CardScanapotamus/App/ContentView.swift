import SwiftUI

struct ContentView: View {
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            CardListView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showScanner = true
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                        }
                    }
                }
                .sheet(isPresented: $showScanner) {
                    CameraScannerView()
                }
        }
    }
}
