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
import CryptoKit
import Foundation
import Security

/// Keychain / Secure Enclave key management behind the Dart key API.
final class KeyManagement {
    func isHardwareSigningAvailable() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    func createKey(_ args: Args) throws {
        let keyAlias: String = try args.req("keyAlias")
        if args.opt("useHardware") ?? false {
            #if targetEnvironment(simulator)
            throw PluginError(code: "NOT_AVAILABLE", message: "Secure Enclave not available in Simulator")
            #else
            let config = SecureEnclaveSignerConfig(keyTag: keyAlias, accessControl: [.privateKeyUsage])
            _ = try Signer.createSecureEnclaveKey(config: config)
            #endif
        } else {
            try createKeychainKey(keyAlias)
        }
    }

    private func createKeychainKey(_ keyAlias: String) throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Data(keyAlias.utf8),
            ],
        ]
        var error: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil else {
            let message = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw PluginError(code: "ERROR", message: "Failed to create key: \(message)")
        }
    }

    func deleteKey(_ args: Args) throws -> Bool {
        let keyAlias: String = try args.req("keyAlias")
        if Signer.deleteSecureEnclaveKey(keyTag: keyAlias) { return true }
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(keyAlias.utf8),
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    func keyExists(_ args: Args) throws -> Bool {
        let keyAlias: String = try args.req("keyAlias")
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(keyAlias.utf8),
            kSecReturnRef as String: false,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func exportPublicKey(_ args: Args) throws -> String {
        try Signer.exportPublicKeyPEM(fromKeychainTag: try args.req("keyAlias"))
    }

    /// Imports an EC private key (PEM, PKCS#8 or SEC1) into the keychain under
    /// [keyAlias]. The certificate chain is not stored: keychain signers take
    /// it as a separate argument. RSA keys are not supported by the keychain
    /// signer path, so they are rejected.
    func importKey(_ args: Args) throws {
        let keyAlias: String = try args.req("keyAlias")
        let pem: String = try args.req("privateKeyPem")
        let _: String = try args.req("certificateChainPem")

        let (x963, bits) = try ecPrivateKeyX963(pem)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: bits,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(x963 as CFData, attributes as CFDictionary, &error) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw PluginError(code: "ERROR", message: "Failed to import key: \(message)")
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(keyAlias.utf8),
        ]
        _ = SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: key,
            kSecAttrApplicationTag as String: Data(keyAlias.utf8),
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PluginError(code: "ERROR", message: "Failed to store imported key: \(status)")
        }
    }

    private func ecPrivateKeyX963(_ pem: String) throws -> (Data, Int) {
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) {
            return (key.x963Representation, 256)
        }
        if let key = try? P384.Signing.PrivateKey(pemRepresentation: pem) {
            return (key.x963Representation, 384)
        }
        if let key = try? P521.Signing.PrivateKey(pemRepresentation: pem) {
            return (key.x963Representation, 521)
        }
        throw PluginError.notImplemented(
            "importKey on iOS supports EC P-256, P-384 and P-521 private keys only"
        )
    }

    func createCSR(_ args: Args) throws -> String {
        let config = CertificateManager.CertificateConfig(
            commonName: try args.req("commonName"),
            organization: args.opt("organization") ?? "",
            organizationalUnit: args.opt("organizationalUnit") ?? "",
            country: args.opt("country") ?? "",
            state: args.opt("state") ?? "",
            locality: args.opt("locality") ?? ""
        )
        return try CertificateManager.createCSR(keyTag: try args.req("keyAlias"), config: config)
    }

    /// Creates a fresh key (Secure Enclave on device, keychain in the
    /// simulator or when `useStrongBox` is false and the enclave is
    /// unavailable), creates a CSR for it and submits it to
    /// `<signingServerUrl>/api/v1/certificates/sign`, the same protocol the
    /// Android implementation uses.
    func enrollHardwareKey(_ args: Args) throws -> [String: Any] {
        let keyAlias: String = try args.req("keyAlias")
        let serverURL: String = try args.req("signingServerUrl")
        let bearerToken: String? = args.opt("bearerToken")
        let commonName: String = args.opt("commonName") ?? "C2PA Hardware Key"
        let organization: String = args.opt("organization") ?? "C2PA App"

        _ = Signer.deleteSecureEnclaveKey(keyTag: keyAlias)
        if isHardwareSigningAvailable() {
            let config = SecureEnclaveSignerConfig(keyTag: keyAlias, accessControl: [.privateKeyUsage])
            _ = try Signer.createSecureEnclaveKey(config: config)
        } else {
            try createKeychainKey(keyAlias)
        }

        let csr = try CertificateManager.createCSR(
            keyTag: keyAlias,
            config: CertificateManager.CertificateConfig(
                commonName: commonName,
                organization: organization,
                organizationalUnit: "",
                country: "US",
                state: "",
                locality: ""
            )
        )

        guard let url = URL(string: "\(serverURL)/api/v1/certificates/sign") else {
            throw PluginError.invalidArgument("Invalid signingServerUrl: \(serverURL)")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["csr": csr])

        let (data, response) = try performBlocking(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw PluginError(code: "ENROLLMENT_ERROR", message: "Certificate enrollment failed: \(body)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chain = json["certificate_chain"] as? String else {
            throw PluginError(code: "ENROLLMENT_ERROR", message: "Enrollment response has no certificate_chain")
        }
        return ["certificateChain": chain, "keyAlias": keyAlias]
    }

    private func performBlocking(_ request: URLRequest) throws -> (Data, URLResponse?) {
        final class Box: @unchecked Sendable {
            var data = Data()
            var response: URLResponse?
            var error: Error?
        }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data ?? Data()
            box.response = response
            box.error = error
            semaphore.signal()
        }.resume()
        semaphore.wait()
        if let error = box.error { throw error }
        return (box.data, box.response)
    }

    func createSelfSignedCertificateChain(_ args: Args) throws -> String {
        let keyAlias: String = try args.req("keyAlias")
        let configMap: [String: Any] = args.opt("config") ?? [:]
        let config = CertificateManager.CertificateConfig(
            commonName: configMap["commonName"] as? String ?? "C2PA Signer",
            organization: configMap["organization"] as? String ?? "Unknown",
            organizationalUnit: configMap["organizationalUnit"] as? String ?? "",
            country: configMap["country"] as? String ?? "US",
            state: configMap["state"] as? String ?? "",
            locality: configMap["locality"] as? String ?? "",
            emailAddress: configMap["emailAddress"] as? String,
            validityDays: configMap["validityDays"] as? Int ?? 365
        )

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyAlias,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let found = item else {
            throw PluginError(code: "ERROR", message: "Failed to find key '\(keyAlias)' in keychain: \(status)")
        }
        // swiftlint:disable:next force_cast
        let privateKey = found as! SecKey
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw PluginError(code: "ERROR", message: "Failed to extract public key from private key")
        }
        return try CertificateManager.createSelfSignedCertificateChain(for: publicKey, config: config)
    }
}
