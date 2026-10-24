// All state and Flutter channel delivery use the main queue.
import AVFoundation
import Flutter

final class BlistenAudioFocusBridge: NSObject, FlutterStreamHandler {
    private struct InterruptedRequest {
        let id: Int64
        let wasActive: Bool
    }

    private let session = AVAudioSession.sharedInstance()
    private let methods: FlutterMethodChannel
    private let events: FlutterEventChannel
    private var sink: FlutterEventSink?
    private var observers: [NSObjectProtocol] = []
    private var requestID: Int64?
    private var isActive = false
    private var interruption: InterruptedRequest?
    private var lossRevision = 0

    init(messenger: FlutterBinaryMessenger) {
        methods = FlutterMethodChannel(name: "abts/audio_focus", binaryMessenger: messenger)
        events = FlutterEventChannel(name: "abts/audio_focus_events", binaryMessenger: messenger)
        super.init()
        methods.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(FlutterError(code: "audio_focus_unavailable", message: "Audio session unavailable", details: nil))
                return
            }
            let arguments = call.arguments as? [String: Any]
            let id = (arguments?["requestId"] as? NSNumber)?.int64Value
            switch call.method {
            case "request":
                guard let id, id > 0 else {
                    result("failed")
                    return
                }
                result(self.request(id: id, speech: arguments?["speech"] as? Bool == true))
            case "abandon":
                // A late cancellation must not release a newer request.
                guard let id, id == self.requestID else {
                    result(true)
                    return
                }
                do {
                    try self.abandon()
                    result(true)
                } catch {
                    result(FlutterError(code: "audio_focus_release", message: "Audio session deactivation failed", details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        events.setStreamHandler(self)
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
        ) { [weak self] _ in
            guard let self, let id = self.requestID else { return }
            self.loseFocus(id: id)
        })
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    private func emit(_ event: String, id: Int64) {
        guard requestID == id else { return }
        sink?(["event": event, "requestId": id])
    }

    private func request(id: Int64, speech: Bool) -> String {
        requestID = id
        interruption = nil
        isActive = false
        let revision = lossRevision
        do {
            // Exclusive playback: do not mix with or duck other applications.
            try session.setCategory(.playback, mode: speech ? .spokenAudio : .default, options: [])
            try session.setActive(true)
            guard requestID == id, revision == lossRevision else { return "failed" }
            isActive = true
            return "granted"
        } catch {
            if requestID == id {
                requestID = nil
                interruption = nil
                isActive = false
            }
            // iOS provides no Android-style delayed focus grant here.
            return "failed"
        }
    }

    private func abandon() throws {
        // Invalidate before the native call, even if deactivation throws.
        requestID = nil
        interruption = nil
        isActive = false
        lossRevision += 1
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            guard let id = requestID else { return }
            // Duplicate begin notifications must not replace the original resume state.
            if interruption == nil {
                interruption = InterruptedRequest(id: id, wasActive: isActive)
            }
            isActive = false
            lossRevision += 1
            emit("interrupted", id: id)
        case .ended:
            guard let interrupted = interruption else { return }
            interruption = nil
            guard requestID == interrupted.id else { return }
            let rawOptions = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            guard interrupted.wasActive, options.contains(.shouldResume) else {
                loseFocus(id: interrupted.id)
                return
            }
            let revision = lossRevision
            do {
                try session.setActive(true)
                guard requestID == interrupted.id, revision == lossRevision else { return }
                isActive = true
                emit("gained", id: interrupted.id)
            } catch {
                loseFocus(id: interrupted.id)
            }
        @unknown default:
            if let id = requestID { loseFocus(id: id) }
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let rawReason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue,
              AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable,
              let id = requestID else { return }
        // Do not auto-resume after headphones/Bluetooth output disconnects.
        interruption = nil
        emit("noisy", id: id)
        // Dart's onNoisy pauses the player and sends abandon for this request.
    }

    private func loseFocus(id: Int64) {
        guard requestID == id else { return }
        isActive = false
        interruption = nil
        lossRevision += 1
        emit("lost", id: id)
        requestID = nil
    }

    // Call before detaching the owning Flutter engine. This bridge is retained by
    // AppDelegate for the main engine's entire application lifetime.
    func dispose() {
        try? abandon()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        methods.setMethodCallHandler(nil)
        events.setStreamHandler(nil)
        sink = nil
    }
}
