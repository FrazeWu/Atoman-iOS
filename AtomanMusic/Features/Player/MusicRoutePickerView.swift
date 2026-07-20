import SwiftUI

#if os(iOS)
import AVKit

struct MusicRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.activeTintColor = UIColor(Color.musicAccent)
        picker.tintColor = .label
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else
struct MusicRoutePickerView: View {
    var body: some View {
        EmptyView()
    }
}
#endif
