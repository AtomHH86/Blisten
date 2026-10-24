import Flutter
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var nativeChannels: BlistenNativeChannels?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        guard let registrar = registrar(forPlugin: "BlistenNativeChannels") else {
            return false
        }
        nativeChannels = BlistenNativeChannels(messenger: registrar.messenger())
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}

private final class BlistenNativeChannels {
    private let credentials: FlutterMethodChannel
    private let browser: FlutterMethodChannel
    private let nativeTLS: FlutterMethodChannel
    private let audioFocus: BlistenAudioFocusBridge

    init(messenger: FlutterBinaryMessenger) {
        credentials = FlutterMethodChannel(name: "abts/credentials", binaryMessenger: messenger)
        browser = FlutterMethodChannel(name: "abts/browser", binaryMessenger: messenger)
        nativeTLS = FlutterMethodChannel(name: "blisten/native_tls", binaryMessenger: messenger)
        audioFocus = BlistenAudioFocusBridge(messenger: messenger)

        credentials.setMethodCallHandler { call, result in
            do {
                switch call.method {
                case "read":
                    result(try BlistenKeychain.read())
                case "write":
                    if call.arguments == nil || call.arguments is NSNull {
                        try BlistenKeychain.write(nil)
                    } else if let cookie = call.arguments as? String {
                        try BlistenKeychain.write(cookie)
                    } else {
                        result(FlutterError(code: "invalid_arguments", message: "Expected a string or null", details: nil))
                        return
                    }
                    result(true)
                default:
                    result(FlutterMethodNotImplemented)
                }
            } catch {
                // Never expose the cookie, Keychain contents or a system diagnostic string.
                result(FlutterError(code: "credential_storage", message: "Credential storage unavailable", details: nil))
            }
        }

        browser.setMethodCallHandler { call, result in
            guard call.method == "open" else {
                result(FlutterMethodNotImplemented)
                return
            }
            guard let arguments = call.arguments as? [String: Any],
                  let rawURL = arguments["url"] as? String,
                  let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = url.host, !host.isEmpty else {
                result(false)
                return
            }
            UIApplication.shared.open(url, options: [:]) { opened in
                result(opened)
            }
        }

        nativeTLS.setMethodCallHandler { call, result in
            guard call.method == "trustedCaFile" else {
                result(FlutterMethodNotImplemented)
                return
            }
            // An iOS trust policy for this libmpv build has not been validated.
            // Do not return a made-up CA path, empty success or disable TLS verification.
            result(FlutterError(
                code: "ios_tls_not_configured",
                message: "iOS native audio certificate verification is not configured",
                details: nil
            ))
        }
    }
}

private enum BlistenKeychain {
    private struct Failure: Error {
        let status: OSStatus
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "abts.credentials",
            kSecAttrAccount as String: "bili_cookie",
            // No iCloud synchronization or Keychain access group is requested.
            kSecAttrSynchronizable as String: false,
        ]
    }

    static func read() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard let data = value as? Data, let cookie = String(data: data, encoding: .utf8) else {
            throw Failure(status: errSecDecode)
        }
        return cookie
    }

    static func write(_ cookie: String?) throws {
        guard let cookie else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw Failure(status: status)
            }
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(cookie.utf8),
            // Background playback can read after the first unlock; the item cannot
            // migrate to another device. This does not imply deletion on uninstall.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw Failure(status: updateStatus) }
        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Failure(status: addStatus) }
    }
}
