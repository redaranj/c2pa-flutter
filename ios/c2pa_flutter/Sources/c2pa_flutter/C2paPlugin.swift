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
// Foundation also declares `Stream` (NSStream); prefer the C2PA type.
import class C2PA.Stream
import Flutter
import UIKit

/// Flutter plugin bridging the Dart C2PA API to c2pa-swift.
///
/// Threading model: every call that touches a builder, reader, settings or
/// context runs on one serial worker queue, in the order Dart sent it. That
/// keeps the main thread free while signing (callback signers, progress and
/// HTTP resolvers call back into Dart on the main thread while the worker
/// waits), and it means `builderDispose` can never free a builder that an
/// earlier call is still using. Key management runs on a separate queue so a
/// Dart signing callback can use it while the worker waits. `contextCancel`
/// runs immediately, since it must reach an operation occupying the worker.
public class C2paPlugin: NSObject, FlutterPlugin {
    private let worker = DispatchQueue(label: "org.guardianproject.c2pa.worker", qos: .userInitiated)
    private let aux = DispatchQueue(label: "org.guardianproject.c2pa.aux", qos: .userInitiated, attributes: .concurrent)

    private let builders = HandleRegistry<Builder>()
    private let settingsHandles = HandleRegistry<C2PASettings>()
    private let contexts = HandleRegistry<C2PAContext>()

    /// Settings applied by `loadSettings` to readers and builders created
    /// without a context. Worker queue only.
    private var defaultSettings: C2PASettings?

    private let bridge = DartBridge()
    private lazy var signers = SignerFactory(bridge: bridge)
    private let keys = KeyManagement()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "org.guardianproject.c2pa", binaryMessenger: registrar.messenger())
        let instance = C2paPlugin()
        instance.bridge.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private static let keyMethods: Set<String> = [
        "isHardwareSigningAvailable", "createKey", "deleteKey", "keyExists",
        "exportPublicKey", "importKey", "createCSR", "enrollHardwareKey",
        "createSelfSignedCertificateChain",
    ]

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "contextCancel":
            respond(result, onMain: false) { try self.handleContextCancel(Args(call)) }
        case let method where Self.keyMethods.contains(method):
            aux.async { self.respond(result) { try self.handleKeyCall(call) } }
        default:
            worker.async { self.respond(result) { try self.handleWorkerCall(call) } }
        }
    }

    // MARK: - Result plumbing

    private func respond(_ result: @escaping FlutterResult, onMain: Bool = true, _ block: () throws -> Any?) {
        let outcome: Any?
        do {
            let value = try block()
            if value is NotImplementedMarker {
                outcome = FlutterMethodNotImplemented
            } else if let data = value as? Data {
                outcome = FlutterStandardTypedData(bytes: data)
            } else {
                outcome = value
            }
        } catch let error as PluginError {
            outcome = FlutterError(code: error.code, message: error.message, details: nil)
        } catch let error as C2PAError {
            outcome = FlutterError(code: "C2PA_ERROR", message: error.errorDescription ?? "\(error)", details: nil)
        } catch {
            outcome = FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)
        }
        if onMain {
            DispatchQueue.main.async { result(outcome) }
        } else {
            result(outcome)
        }
    }

    // MARK: - Dispatch

    private func handleKeyCall(_ call: FlutterMethodCall) throws -> Any? {
        let args = Args(call)
        switch call.method {
        case "isHardwareSigningAvailable": return keys.isHardwareSigningAvailable()
        case "createKey": try keys.createKey(args); return nil
        case "deleteKey": return try keys.deleteKey(args)
        case "keyExists": return try keys.keyExists(args)
        case "exportPublicKey": return try keys.exportPublicKey(args)
        case "importKey": try keys.importKey(args); return nil
        case "createCSR": return try keys.createCSR(args)
        case "enrollHardwareKey": return try keys.enrollHardwareKey(args)
        case "createSelfSignedCertificateChain": return try keys.createSelfSignedCertificateChain(args)
        default: return NotImplementedMarker()
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func handleWorkerCall(_ call: FlutterMethodCall) throws -> Any? {
        let args = Args(call)
        switch call.method {
        case "getVersion":
            return C2PA.version

        // Reader
        case "readFile":
            return try readFromPath(args, output: "json")
        case "readBytes":
            return try readFromBytes(args, output: "json")
        case "readFileDetailed", "readFileWithContext":
            return try readFromPath(args, output: (args.opt("detailed") ?? false) ? "detailed" : "json")
        case "readBytesDetailed":
            return try readFromBytes(args, output: (args.opt("detailed") ?? false) ? "detailed" : "json")
        case "readCrJson":
            return args.optData("data") != nil
                ? try readFromBytes(args, output: "crJson")
                : try readFromPath(args, output: "crJson")
        case "readWithManifest":
            return try handleReadWithManifest(args)
        case "readFragment":
            throw PluginError.notImplemented("Fragmented BMFF reading is not available in c2pa-swift")
        case "extractResource":
            return try handleExtractResource(args)
        case "getRemoteUrl":
            return try withPathReader(args) { $0.remote()?.absoluteString }
        case "isManifestEmbedded":
            return try withPathReader(args) { $0.isEmbedded() }
        case "getSupportedReadMimeTypes":
            return Reader.supportedMimeTypes
        case "getSupportedSignMimeTypes":
            return Builder.supportedMimeTypes

        // One-shot signing
        case "signBytes":
            return try handleSignBytes(args)
        case "signFile":
            try handleSignFile(args)
            return nil
        case "getSignerReserveSize":
            return try signers.create(try args.req("signer")).reserveSize()
        case "composeManifest":
            return try Builder.composeManifest(try args.reqData("manifestBytes"), format: try args.req("mimeType"))

        // Builder lifecycle
        case "createBuilder":
            return builders.store(try newBuilder(args.optInt("contextHandle"), try args.req("manifestJson")))
        case "createBuilderWithContext":
            return builders.store(try newBuilder(try args.reqInt("contextHandle"), try args.req("manifestJson")))
        case "createBuilderWithSettings":
            let context = try C2PAContext(settings: try settingsFor(try args.reqInt("settingsHandle")))
            return builders.store(try Builder(context: context, manifestJSON: try args.req("manifestJson")))
        case "createBuilderFromArchive":
            let stream = try Stream(data: try args.reqData("archiveData"))
            if let context = try contextFor(args.optInt("contextHandle")) {
                return builders.store(try Builder(context: context, archiveStream: stream))
            }
            return builders.store(try Builder(archiveStream: stream))
        case "builderDispose":
            builders.remove(try args.reqInt("handle"))
            return nil

        // Builder configuration
        case "builderSetIntent":
            try handleSetIntent(args)
            return nil
        case "builderSetNoEmbed":
            try builder(args).setNoEmbed()
            return nil
        case "builderSetRemoteUrl":
            let urlString: String = try args.req("url")
            guard let url = URL(string: urlString) else {
                throw PluginError.invalidArgument("Invalid url: \(urlString)")
            }
            try builder(args).setRemote(url: url)
            return nil
        case "builderSetBasePath":
            try builder(args).setBasePath(fileURL(try args.req("path")))
            return nil
        case "builderAddResource":
            try builder(args).addResource(uri: try args.req("uri"), stream: try Stream(data: try args.reqData("data")))
            return nil
        case "builderAddIngredient":
            try builder(args).addIngredient(
                json: args.opt("ingredientJson") ?? "{}",
                format: try args.req("mimeType"),
                from: try Stream(data: try args.reqData("data"))
            )
            return nil
        case "builderAddIngredientFromFile":
            let path: String = try args.req("path")
            try builder(args).addIngredient(
                json: args.opt("ingredientJson") ?? "{}",
                format: args.opt("mimeType") ?? mimeType(forPath: path),
                from: try openForRead(path)
            )
            return nil
        case "builderAddIngredientFromArchive":
            try builder(args).addIngredient(fromArchive: try Stream(data: try args.reqData("archiveData")))
            return nil
        case "builderWriteIngredientArchive":
            let sink = DataSink()
            try builder(args).writeIngredientArchive(id: try args.req("ingredientId"), to: try sink.stream())
            return sink.data
        case "builderAddAction":
            try builder(args).addAction(try parseAction(try args.req("actionJson")))
            return nil
        case "builderToArchive":
            let sink = DataSink()
            try builder(args).writeArchive(to: try sink.stream())
            return sink.data

        // Builder signing
        case "builderSign":
            return try handleBuilderSign(args)
        case "builderSignFile":
            return try handleBuilderSignFile(args)

        // Embeddable / data-hash / BMFF flows
        case "builderNeedsPlaceholder":
            return try builder(args).needsPlaceholder(format: try args.req("mimeType"))
        case "builderPlaceholder":
            return try builder(args).placeholder(format: try args.req("mimeType"))
        case "builderSetDataHashExclusions":
            let raw: [[NSNumber]] = try args.req("exclusions")
            let exclusions = try raw.map { pair -> (start: UInt64, length: UInt64) in
                guard pair.count == 2 else {
                    throw PluginError.invalidArgument("Each exclusion must be [start, length]")
                }
                return (start: pair[0].uint64Value, length: pair[1].uint64Value)
            }
            try builder(args).setDataHashExclusions(exclusions)
            return nil
        case "builderUpdateHashFromBytes":
            try builder(args).updateHashFromStream(
                format: try args.req("mimeType"),
                stream: try Stream(data: try args.reqData("data"))
            )
            return nil
        case "builderUpdateHashFromFile":
            let path: String = try args.req("path")
            try builder(args).updateHashFromStream(
                format: args.opt("mimeType") ?? mimeType(forPath: path),
                stream: try openForRead(path)
            )
            return nil
        case "builderSignEmbeddable":
            return try builder(args).signEmbeddable(format: try args.req("mimeType"))
        case "builderHashType":
            return hashTypeName(try builder(args).hashType(format: try args.req("mimeType")))
        case "builderSetFixedSizeMerkle":
            try builder(args).setFixedSizeMerkle(try args.reqInt("fixedSizeKb"))
            return nil
        case "builderHashMdatBytes":
            try builder(args).hashMdatBytes(
                mdatId: try args.reqInt("mdatId"),
                data: try args.reqData("data"),
                largeSize: args.opt("largeSize") ?? false
            )
            return nil

        // Settings
        case "loadSettings":
            try handleLoadSettings(args)
            return nil
        case "createSettings":
            return settingsHandles.store(try C2PASettings(json: "{\"version\":1}"))
        case "settingsUpdateFromString":
            try load(
                into: try settingsFor(try args.reqInt("handle")),
                try args.req("settings"),
                format: try args.req("format")
            )
            return nil
        case "settingsSetValue":
            let value: String = try args.req("value")
            try settingsFor(try args.reqInt("handle")).setValue(jsonValue(value), forPath: try args.req("path"))
            return nil
        case "settingsDispose":
            settingsHandles.remove(try args.reqInt("handle"))
            return nil

        // Contexts
        case "createContext", "createContextFromSettings":
            return try handleCreateContext(args)
        case "contextDispose":
            contexts.remove(try args.reqInt("handle"))
            return nil

        default:
            return NotImplementedMarker()
        }
    }

    // MARK: - Handle lookup and factories

    private func builder(_ args: Args) throws -> Builder {
        guard let builder = builders.get(try args.reqInt("handle")) else {
            throw PluginError.invalidHandle("builder")
        }
        return builder
    }

    private func settingsFor(_ handle: Int) throws -> C2PASettings {
        guard let settings = settingsHandles.get(handle) else {
            throw PluginError.invalidHandle("settings")
        }
        return settings
    }

    /// The context for [handle], a fresh one built from the default settings,
    /// or nil to let the SDK use its own default context.
    private func contextFor(_ handle: Int?) throws -> C2PAContext? {
        if let handle = handle {
            guard let context = contexts.get(handle) else {
                throw PluginError.invalidHandle("context")
            }
            return context
        }
        if let defaults = defaultSettings {
            return try C2PAContext(settings: defaults)
        }
        return nil
    }

    private func newReader(_ contextHandle: Int?, format: String, stream: Stream) throws -> Reader {
        if let context = try contextFor(contextHandle) {
            return try Reader(context: context, format: format, stream: stream)
        }
        return try Reader(format: format, stream: stream)
    }

    private func newBuilder(_ contextHandle: Int?, _ manifestJson: String) throws -> Builder {
        if let context = try contextFor(contextHandle) {
            return try Builder(context: context, manifestJSON: manifestJson)
        }
        return try Builder(manifestJSON: manifestJson)
    }

    private func load(into settings: C2PASettings, _ text: String, format: String) throws {
        switch format.lowercased() {
        case "json": try settings.load(json: text)
        case "toml": try settings.load(toml: text)
        default: throw PluginError.invalidArgument("format must be 'json' or 'toml'")
        }
    }

    private func newSettings(_ text: String, format: String) throws -> C2PASettings {
        switch format.lowercased() {
        case "json": return try C2PASettings(json: text)
        case "toml": return try C2PASettings(toml: text)
        default: throw PluginError.invalidArgument("format must be 'json' or 'toml'")
        }
    }

    /// Interprets a Dart setting value: JSON literals (true, 42, null, "x",
    /// arrays, objects) keep their type; anything else is a plain string.
    private func jsonValue(_ value: String) -> Any {
        if let data = value.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return parsed
        }
        return value
    }

    private func parseAction(_ json: String) throws -> Action {
        guard let data = json.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = dict["action"] as? String else {
            throw PluginError.invalidArgument("actionJson must be an object with an 'action' string")
        }
        let parameters = (dict["parameters"] as? [String: Any])?.mapValues { AnyCodable($0) }
        let softwareAgent: AnyCodable? = dict["softwareAgent"].flatMap { $0 is NSNull ? nil : AnyCodable($0) }
        return Action(
            action: name,
            digitalSourceType: dict["digitalSourceType"] as? String,
            softwareAgent: softwareAgent,
            parameters: parameters,
            when: dict["when"] as? String
        )
    }

    private func handleSetIntent(_ args: Args) throws {
        let builder = try builder(args)
        let intent: String = try args.req("intent")
        let sourceName: String? = args.opt("digitalSourceType")
        switch intent {
        case "create":
            if let name = sourceName, parseDigitalSourceType(name) == nil {
                // c2pa-swift's DigitalSourceType lacks this IPTC type, so
                // declare the created action directly instead of via intent.
                try builder.addAction(Action(
                    action: "c2pa.created",
                    digitalSourceType: digitalSourceTypeURL(name)
                ))
            } else {
                try builder.setIntent(.create(sourceName.flatMap(parseDigitalSourceType) ?? .digitalCapture))
            }
        case "edit":
            try builder.setIntent(.edit)
        case "update":
            try builder.setIntent(.update)
        default:
            throw PluginError.invalidArgument("Unknown intent: \(intent)")
        }
    }

    // MARK: - Reader

    private func output(_ reader: Reader, _ kind: String) throws -> String {
        switch kind {
        case "detailed": return try reader.detailedJSON()
        case "crJson": return try reader.crJSON()
        default: return try reader.json()
        }
    }

    private func readFromPath(_ args: Args, output kind: String) throws -> String {
        let path: String = try args.req("path")
        let reader = try newReader(
            args.optInt("contextHandle"),
            format: args.opt("mimeType") ?? mimeType(forPath: path),
            stream: try openForRead(path)
        )
        return try output(reader, kind)
    }

    private func readFromBytes(_ args: Args, output kind: String) throws -> String {
        let reader = try newReader(
            args.optInt("contextHandle"),
            format: try args.req("mimeType"),
            stream: try Stream(data: try args.reqData("data"))
        )
        return try output(reader, kind)
    }

    private func withPathReader<R>(_ args: Args, _ body: (Reader) throws -> R) throws -> R {
        let path: String = try args.req("path")
        let reader = try newReader(
            args.optInt("contextHandle"),
            format: args.opt("mimeType") ?? mimeType(forPath: path),
            stream: try openForRead(path)
        )
        return try body(reader)
    }

    private func handleReadWithManifest(_ args: Args) throws -> String {
        let manifest = try args.reqData("manifestData")
        let stream: Stream
        let format: String
        if let data = args.optData("data") {
            stream = try Stream(data: data)
            format = try args.req("mimeType")
        } else {
            let path: String = try args.req("path")
            stream = try openForRead(path)
            format = args.opt("mimeType") ?? mimeType(forPath: path)
        }
        let reader: Reader
        if let context = try contextFor(args.optInt("contextHandle")) {
            reader = try Reader(context: context, format: format, stream: stream, manifest: manifest)
        } else {
            reader = try Reader(format: format, stream: stream, manifest: manifest)
        }
        return try output(reader, (args.opt("detailed") ?? false) ? "detailed" : "json")
    }

    private func handleExtractResource(_ args: Args) throws -> Data {
        let reader = try newReader(
            args.optInt("contextHandle"),
            format: try args.req("mimeType"),
            stream: try Stream(data: try args.reqData("data"))
        )
        let sink = DataSink()
        try reader.resource(uri: try args.req("uri"), to: try sink.stream())
        return sink.data
    }

    // MARK: - Signing

    private func signResultMap(manifest: Data, signedData: Data?) -> [String: Any] {
        [
            "signedData": typed(signedData),
            "manifestBytes": FlutterStandardTypedData(bytes: manifest),
            "manifestSize": manifest.count,
        ]
    }

    /// Signs with an explicit signer map, or the builder's context signer when nil.
    private func sign(
        _ builder: Builder,
        signerMap: [String: Any]?,
        format: String,
        source: Stream,
        destination: Stream
    ) throws -> Data {
        guard let signerMap = signerMap else {
            return try builder.sign(format: format, source: source, destination: destination)
        }
        let signer = try signers.create(signerMap)
        return try builder.sign(format: format, source: source, destination: destination, signer: signer)
    }

    /// A builder whose context carries the signer described by a SettingsSigner map.
    private func settingsSignerBuilder(_ signerMap: [String: Any], manifestJson: String) throws -> Builder {
        let settingsArgs = Args(map: signerMap)
        let settings = try newSettings(try settingsArgs.req("settings"), format: settingsArgs.opt("format") ?? "json")
        return try Builder(context: try C2PAContext(settings: settings), manifestJSON: manifestJson)
    }

    private func handleSignBytes(_ args: Args) throws -> [String: Any] {
        let signerMap: [String: Any] = try args.req("signer")
        let format: String = try args.req("mimeType")
        let manifestJson: String = try args.req("manifestJson")
        let source = try Stream(data: try args.reqData("sourceData"))
        let dest = TempFile()
        let destination = try Stream(writeTo: dest.url)

        let manifest: Data
        if signers.isSettingsSigner(signerMap) {
            manifest = try settingsSignerBuilder(signerMap, manifestJson: manifestJson)
                .sign(format: format, source: source, destination: destination)
        } else {
            manifest = try sign(
                try newBuilder(nil, manifestJson),
                signerMap: signerMap,
                format: format,
                source: source,
                destination: destination
            )
        }
        return signResultMap(manifest: manifest, signedData: try dest.contents())
    }

    private func handleSignFile(_ args: Args) throws {
        let signerMap: [String: Any] = try args.req("signer")
        let sourcePath: String = try args.req("sourcePath")
        let format: String = args.opt("mimeType") ?? mimeType(forPath: sourcePath)
        let manifestJson: String = try args.req("manifestJson")
        let source = try openForRead(sourcePath)
        let destination = try openForWrite(try args.req("destPath"))

        if signers.isSettingsSigner(signerMap) {
            _ = try settingsSignerBuilder(signerMap, manifestJson: manifestJson)
                .sign(format: format, source: source, destination: destination)
        } else {
            _ = try sign(
                try newBuilder(nil, manifestJson),
                signerMap: signerMap,
                format: format,
                source: source,
                destination: destination
            )
        }
    }

    private func handleBuilderSign(_ args: Args) throws -> [String: Any] {
        let builder = try builder(args)
        let dest = TempFile()
        let manifest = try sign(
            builder,
            signerMap: args.opt("signer"),
            format: try args.req("mimeType"),
            source: try Stream(data: try args.reqData("sourceData")),
            destination: try Stream(writeTo: dest.url)
        )
        return signResultMap(manifest: manifest, signedData: try dest.contents())
    }

    private func handleBuilderSignFile(_ args: Args) throws -> [String: Any] {
        let builder = try builder(args)
        let sourcePath: String = try args.req("sourcePath")
        let manifest = try sign(
            builder,
            signerMap: args.opt("signer"),
            format: args.opt("mimeType") ?? mimeType(forPath: sourcePath),
            source: try openForRead(sourcePath),
            destination: try openForWrite(try args.req("destPath"))
        )
        return signResultMap(manifest: manifest, signedData: nil)
    }

    // MARK: - Settings and contexts

    private func handleLoadSettings(_ args: Args) throws {
        let text: String = try args.req("settings")
        let format: String = try args.req("format")
        if let defaults = defaultSettings {
            try load(into: defaults, text, format: format)
        } else {
            defaultSettings = try newSettings(text, format: format)
        }
    }

    private func handleCreateContext(_ args: Args) throws -> Int {
        let settings = try args.optInt("settingsHandle").map { try settingsFor($0) }
        let signerMap: [String: Any]? = args.opt("signer")
        let wantsProgress: Bool = args.opt("progress") ?? false
        let resolverMode: String? = args.opt("httpResolver")

        let handle = contexts.reserve()
        let bridge = self.bridge
        let signer = try signerMap.map { try signers.create($0) }

        let onProgress: (@Sendable (ProgressUpdate) -> ProgressDisposition)? = wantsProgress
            ? { update in
                bridge.notify("contextProgress", [
                    "contextHandle": handle,
                    "phase": progressPhaseName(update.phase),
                    "step": Int(update.step),
                    "total": Int(update.total),
                ])
                return .continue
            }
            : nil

        let context: C2PAContext
        switch resolverMode {
        case nil:
            context = try C2PAContext(settings: settings, signer: signer, onProgress: onProgress, httpResolver: nil)
        case "native":
            context = try C2PAContext(
                settings: settings,
                signer: signer,
                onProgress: onProgress,
                urlSession: URLSession(configuration: .default)
            )
        case "callback":
            context = try C2PAContext(settings: settings, signer: signer, onProgress: onProgress) { request in
                let response = try bridge.invokeBlocking("httpResolve", [
                    "contextHandle": handle,
                    "url": request.url.absoluteString,
                    "method": request.method,
                    "headers": request.headers,
                    "body": typed(request.body),
                ])
                guard let map = response as? [String: Any], let status = (map["status"] as? NSNumber)?.intValue else {
                    throw C2PAError.api("HTTP resolver returned no response")
                }
                let body = (map["body"] as? FlutterStandardTypedData)?.data ?? Data()
                return HTTPResponse(status: status, body: body)
            }
        default:
            throw PluginError.invalidArgument("Unknown httpResolver mode: \(resolverMode ?? "")")
        }
        contexts.put(handle, context)
        return handle
    }

    private func handleContextCancel(_ args: Args) throws -> Any? {
        guard let context = contexts.get(try args.reqInt("handle")) else {
            throw PluginError.invalidHandle("context")
        }
        try context.cancel()
        return nil
    }
}
