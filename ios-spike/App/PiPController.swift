import AVKit
import AVFoundation
import SwiftUI
import UIKit

/// 子母畫面：用 AVSampleBufferDisplayLayer 當內容來源，影格由 FrameRenderer 產生。
final class PiPController: NSObject, ObservableObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    let displayLayer = AVSampleBufferDisplayLayer()
    let renderer = FrameRenderer(width: 720, height: 360)

    @Published var isActive = false
    @Published var isPossible = false
    @Published var lastError: String?
    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()

    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?

    /// 在 displayLayer 已經加進畫面上的 view 之後呼叫。
    func attach() {
        guard controller == nil else { return }
        displayLayer.videoGravity = .resizeAspect
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            DispatchQueue.main.async { self?.isPossible = controller.isPictureInPicturePossible }
        }
        render(lines: ["等待字幕…"], note: "PiP 已就緒")
    }

    func start() {
        Metrics.app.log("pip.start.requested", ["possible": isPossible ? 1 : 0])
        controller?.startPictureInPicture()
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    func render(lines: [String], note: String) {
        guard let sampleBuffer = renderer.makeSampleBuffer(lines: lines, note: note) else {
            Metrics.app.log("pip.render.failed")
            return
        }
        let videoRenderer = displayLayer.sampleBufferRenderer
        if videoRenderer.status == .failed {
            Metrics.app.log("pip.renderer.failed", [:], ["error": String(describing: videoRenderer.error)])
            videoRenderer.flush()
        }
        videoRenderer.enqueue(sampleBuffer)
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isActive = true
        Metrics.app.log("pip.started")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        isActive = false
        Metrics.app.log("pip.stopped")
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        lastError = String(describing: error)
        Metrics.app.log("pip.failed", [:], ["error": String(describing: error)])
    }

    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

    func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        Metrics.app.log("pip.setPlaying", ["playing": playing ? 1 : 0])
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        // 沒有時間軸的即時內容
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        Metrics.app.log("pip.renderSize", ["w": Double(newRenderSize.width), "h": Double(newRenderSize.height)])
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

/// 承載 displayLayer 的小預覽。PiP 啟動時 layer 必須在畫面上的視圖階層裡。
struct PiPHostView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    let onAttached: () -> Void

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.backgroundColor = .black
        view.layer.addSublayer(layer)
        view.hostedLayer = layer
        DispatchQueue.main.async { onAttached() }
        return view
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {}

    final class LayerHostView: UIView {
        var hostedLayer: CALayer?
        override func layoutSubviews() {
            super.layoutSubviews()
            hostedLayer?.frame = bounds
        }
    }
}
