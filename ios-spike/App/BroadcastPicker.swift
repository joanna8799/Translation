import SwiftUI
import ReplayKit

/// 系統的「開始廣播」按鈕。Apple 只允許使用者手動啟動螢幕擷取，不能由 app 自動開。
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = AppGroup.broadcastExtensionBundleID
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
