import SwiftUI

public struct RootAppView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            Text("Atoman Blog Studio")
                .navigationTitle("Blog Studio")
        }
    }
}
