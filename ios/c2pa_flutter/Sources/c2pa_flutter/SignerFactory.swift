/*
This file is licensed to you under the Apache License, Version 2.0
(http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
(http://opensource.org/licenses/MIT), at your option.

Unless required by applicable law or agreed to in writing, this software is
distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
files for the specific language governing permissions and limitations under
each license.
*/

import C2PA
import Flutter
import Foundation
import Security

/// Calls Dart handlers on the main thread from a background thread and waits
/// for the answer. Callback signers and HTTP resolvers run synchronously on
/// the thread performing a C2PA operation, so they use this to reach Dart.
final class DartBridge: @unchecked Sendable {
    /// Held strongly: nothing else owns the channel created in `register`,
    /// so a weak reference is released as soon as registration returns.
    var channel: FlutterMethodChannel?

    private final class Box: @unchecked Sendable {
        var value: Any?
        var error: Error?
    }

    func invokeBlocking(_ method: String, _ arguments: Any?) throws -> Any? {
        if Thread.isMainThread {
            throw C2PAError.api("\(method) must not be invoked on the main thread")
        }
        guard let channel = channel else {
            throw C2PAError.api("Method channel not available")
        }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            channel.invokeMethod(method, arguments: arguments) { response in
                if let error = response as? FlutterError {
                    box.error = C2PAError.api("\(method) failed in Dart: \(error.message ?? error.code)")
                } else if let marker = response as? NSObject, marker === FlutterMethodNotImplemented {
                    box.error = C2PAError.api("\(method) has no Dart handler")
                } else {
                    box.value = response
                }
                semaphore.signal()
            }
        }
        semaphore.wait()
        if let error = box.error { throw error }
        return box.value
    }

    /// Fire-and-forget notification to Dart.
    func notify(_ method: String, _ arguments: Any?) {
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod(method, arguments: arguments)
        }
    }
}

/// Builds c2pa-swift `Signer`s from the maps produced by `C2paSigner.toMap()`.
///
/// Call only from the plugin's worker queue: remote signers wait for a
/// network round trip and callback signers wait for Dart.
final class SignerFactory {
    private let bridge: DartBridge

    init(bridge: DartBridge) {
        self.bridge = bridge
    }

    func isSettingsSigner(_ map: [String: Any]) -> Bool {
        map["type"] as? String == "settings"
    }

    func create(_ map: [String: Any]) throws -> Signer {
        let args = Args(map: map)
        let type: String = args.opt("type") ?? "pem"
        switch type {
        case "pem":
            return try Signer(
                certsPEM: try args.req("certificatePem"),
                privateKeyPEM: try args.req("privateKeyPem"),
                algorithm: try parseAlgorithm(try args.req("algorithm")),
                tsa: tsaURL(args)
            )
        case "keystore":
            return try Signer(
                algorithm: try parseAlgorithm(try args.req("algorithm")),
                certificateChainPEM: try args.req("certificateChainPem"),
                tsa: tsaURL(args),
                keychainKeyTag: try args.req("keyAlias")
            )
        case "hardware":
            var accessControl: SecAccessControlCreateFlags = [.privateKeyUsage]
            if args.opt("requireUserAuthentication") ?? false {
                accessControl.insert(.biometryCurrentSet)
            }
            return try Signer(
                algorithm: .es256,
                certificateChainPEM: try args.req("certificateChainPem"),
                tsa: tsaURL(args),
                secureEnclaveConfig: SecureEnclaveSignerConfig(
                    keyTag: try args.req("keyAlias"),
                    accessControl: accessControl
                )
            )
        case "callback":
            return try createCallback(args)
        case "remote":
            return try createRemote(args)
        case "cawgIdentity":
            return try createCawgIdentity(args)
        case "settings":
            throw PluginError.invalidArgument(
                "A SettingsSigner is not a standalone signer. Put the signer in the settings of a " +
                    "C2paContext and sign without passing a signer, or use C2pa.signBytes/signFile."
            )
        default:
            throw PluginError.invalidArgument("Unknown signer type: \(type)")
        }
    }

    private func tsaURL(_ args: Args) -> URL? {
        (args.opt("tsaUrl") as String?).flatMap(URL.init(string:))
    }

    private func createCallback(_ args: Args) throws -> Signer {
        let callbackId: String = try args.req("callbackId")
        let bridge = self.bridge
        return try Signer(
            algorithm: try parseAlgorithm(try args.req("algorithm")),
            certificateChainPEM: try args.req("certificateChainPem"),
            tsa: tsaURL(args)
        ) { @Sendable dataToSign in
            let response = try bridge.invokeBlocking(
                "signCallback",
                ["callbackId": callbackId, "data": FlutterStandardTypedData(bytes: dataToSign)]
            )
            guard let signature = response as? FlutterStandardTypedData else {
                throw C2PAError.api("Signing callback returned no signature")
            }
            return signature.data
        }
    }

    private final class SignerBox: @unchecked Sendable {
        var result: Result<Signer, Error>?
    }

    private func createRemote(_ args: Args) throws -> Signer {
        let urlString: String = try args.req("configurationUrl")
        guard let endpoint = URL(string: urlString) else {
            throw PluginError.invalidArgument("Invalid configurationUrl: \(urlString)")
        }
        let headers = (args.opt("customHeaders") as [String: Any]?)?
            .mapValues { "\($0)" } ?? [:]
        let webServiceSigner = WebServiceSigner(
            configurationEndpoint: endpoint,
            bearerToken: args.opt("bearerToken"),
            headers: headers
        )
        let box = SignerBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                box.result = .success(try await webServiceSigner.createSigner())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard let result = box.result else {
            throw C2PAError.api("Remote signer creation failed")
        }
        return try result.get()
    }

    private func createCawgIdentity(_ args: Args) throws -> Signer {
        let claimMap: [String: Any] = try args.req("claimSigner")
        let identityMap: [String: Any] = try args.req("identitySigner")
        let claim = try create(claimMap)
        let identity = try create(identityMap)
        return try Signer.withCawgIdentity(
            claim,
            identity: identity,
            referencedAssertions: args.opt("referencedAssertions") ?? [],
            roles: args.opt("roles") ?? []
        )
    }
}
