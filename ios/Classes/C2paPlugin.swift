import Flutter
import UIKit
import C2PAC

public class C2paPlugin: NSObject, FlutterPlugin {
    // Builder handle management
    private var builders: [Int: UnsafeMutablePointer<C2paBuilder>] = [:]
    private var nextBuilderHandle: Int = 1
    private let builderLock = NSLock()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "org.guardianproject.c2pa", binaryMessenger: registrar.messenger())
        let instance = C2paPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "getVersion":
            handleGetVersion(result: result)
        case "readFile":
            handleReadFile(call: call, result: result)
        case "readBytes":
            handleReadBytes(call: call, result: result)
        case "readFileDetailed":
            handleReadFileDetailed(call: call, result: result)
        case "readBytesDetailed":
            handleReadBytesDetailed(call: call, result: result)
        case "extractResource":
            handleExtractResource(call: call, result: result)
        case "readIngredientFile":
            handleReadIngredientFile(call: call, result: result)
        case "getSupportedReadMimeTypes":
            handleGetSupportedReadMimeTypes(result: result)
        case "getSupportedSignMimeTypes":
            handleGetSupportedSignMimeTypes(result: result)
        case "signBytes":
            handleSignBytes(call: call, result: result)
        case "signFile":
            handleSignFile(call: call, result: result)
        case "createBuilder":
            handleCreateBuilder(call: call, result: result)
        case "createBuilderFromArchive":
            handleCreateBuilderFromArchive(call: call, result: result)
        case "builderSetIntent":
            handleBuilderSetIntent(call: call, result: result)
        case "builderSetNoEmbed":
            handleBuilderSetNoEmbed(call: call, result: result)
        case "builderSetRemoteUrl":
            handleBuilderSetRemoteUrl(call: call, result: result)
        case "builderAddResource":
            handleBuilderAddResource(call: call, result: result)
        case "builderAddIngredient":
            handleBuilderAddIngredient(call: call, result: result)
        case "builderAddIngredientFromFile":
            handleBuilderAddIngredientFromFile(call: call, result: result)
        case "builderAddAction":
            handleBuilderAddAction(call: call, result: result)
        case "builderToArchive":
            handleBuilderToArchive(call: call, result: result)
        case "builderSign":
            handleBuilderSign(call: call, result: result)
        case "builderSignFile":
            handleBuilderSignFile(call: call, result: result)
        case "builderDispose":
            handleBuilderDispose(call: call, result: result)
        case "createHashedPlaceholder":
            handleCreateHashedPlaceholder(call: call, result: result)
        case "signHashedEmbeddable":
            handleSignHashedEmbeddable(call: call, result: result)
        case "formatEmbeddable":
            handleFormatEmbeddable(call: call, result: result)
        case "getSignerReserveSize":
            handleGetSignerReserveSize(call: call, result: result)
        case "loadSettings":
            handleLoadSettings(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Version and Info

    private func handleGetVersion(result: @escaping FlutterResult) {
        if let versionPtr = c2pa_version() {
            let version = String(cString: versionPtr)
            c2pa_release_string(versionPtr)
            result(version)
        } else {
            result("unknown")
        }
    }

    // MARK: - Reader API - Basic

    private func handleReadFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Path is required", details: nil))
            return
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            result(FlutterError(code: "FILE_NOT_FOUND", message: "File not found: \(path)", details: nil))
            return
        }

        let jsonPtr = c2pa_read_file(path, nil)
        if let jsonPtr = jsonPtr {
            let json = String(cString: jsonPtr)
            c2pa_release_string(jsonPtr)
            result(json)
        } else {
            let errorPtr = c2pa_error()
            if let errorPtr = errorPtr {
                let error = String(cString: errorPtr)
                c2pa_release_string(errorPtr)
                result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func handleReadBytes(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? FlutterStandardTypedData,
              let mimeType = args["mimeType"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Data and mimeType are required", details: nil))
            return
        }

        readBytesInternal(data: data.data, mimeType: mimeType, detailed: false, result: result)
    }

    // MARK: - Reader API - Enhanced

    private func handleReadFileDetailed(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Path is required", details: nil))
            return
        }

        let detailed = args["detailed"] as? Bool ?? false
        let dataDir = args["dataDir"] as? String

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            result(FlutterError(code: "FILE_NOT_FOUND", message: "File not found: \(path)", details: nil))
            return
        }

        let jsonPtr = c2pa_read_file(path, dataDir)
        if let jsonPtr = jsonPtr {
            let json = String(cString: jsonPtr)
            c2pa_release_string(jsonPtr)
            result(json)
        } else {
            let errorPtr = c2pa_error()
            if let errorPtr = errorPtr {
                let error = String(cString: errorPtr)
                c2pa_release_string(errorPtr)
                result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func handleReadBytesDetailed(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? FlutterStandardTypedData,
              let mimeType = args["mimeType"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Data and mimeType are required", details: nil))
            return
        }

        let detailed = args["detailed"] as? Bool ?? false
        readBytesInternal(data: data.data, mimeType: mimeType, detailed: detailed, result: result)
    }

    private func readBytesInternal(data: Data, mimeType: String, detailed: Bool, result: @escaping FlutterResult) {
        var streamData = StreamData(data: data, position: 0)

        let stream = withUnsafeMutablePointer(to: &streamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, streamRead, streamSeek, nil, nil)
        }

        guard let stream = stream else {
            result(FlutterError(code: "ERROR", message: "Failed to create stream", details: nil))
            return
        }

        defer { c2pa_release_stream(stream) }

        let reader = c2pa_reader_from_stream(mimeType, stream)
        if let reader = reader {
            let jsonPtr = detailed ? c2pa_reader_detailed_json(reader) : c2pa_reader_json(reader)
            c2pa_reader_free(reader)

            if let jsonPtr = jsonPtr {
                let json = String(cString: jsonPtr)
                c2pa_string_free(jsonPtr)
                result(json)
            } else {
                result(nil)
            }
        } else {
            let errorPtr = c2pa_error()
            if let errorPtr = errorPtr {
                let error = String(cString: errorPtr)
                c2pa_string_free(errorPtr)
                result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func handleExtractResource(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? FlutterStandardTypedData,
              let mimeType = args["mimeType"] as? String,
              let uri = args["uri"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Data, mimeType, and uri are required", details: nil))
            return
        }

        var streamData = StreamData(data: data.data, position: 0)

        let stream = withUnsafeMutablePointer(to: &streamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, streamRead, streamSeek, nil, nil)
        }

        guard let stream = stream else {
            result(FlutterError(code: "ERROR", message: "Failed to create stream", details: nil))
            return
        }

        defer { c2pa_release_stream(stream) }

        let reader = c2pa_reader_from_stream(mimeType, stream)
        guard let reader = reader else {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to create reader"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }
        defer { c2pa_reader_free(reader) }

        var resourceData = Data()
        var resourceStreamData = WriteStreamData(data: &resourceData, position: 0)

        let resourceStream = withUnsafeMutablePointer(to: &resourceStreamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, writeStreamRead, writeStreamSeek, writeStreamWrite, writeStreamFlush)
        }

        guard let resourceStream = resourceStream else {
            result(FlutterError(code: "ERROR", message: "Failed to create resource stream", details: nil))
            return
        }
        defer { c2pa_release_stream(resourceStream) }

        let size = c2pa_reader_resource_to_stream(reader, uri, resourceStream)
        if size < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to extract resource"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        result(FlutterStandardTypedData(bytes: resourceData))
    }

    private func handleReadIngredientFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Path is required", details: nil))
            return
        }

        let dataDir = args["dataDir"] as? String

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            result(FlutterError(code: "FILE_NOT_FOUND", message: "File not found: \(path)", details: nil))
            return
        }

        let jsonPtr = c2pa_read_ingredient_file(path, dataDir)
        if let jsonPtr = jsonPtr {
            let json = String(cString: jsonPtr)
            c2pa_release_string(jsonPtr)
            result(json)
        } else {
            let errorPtr = c2pa_error()
            if let errorPtr = errorPtr {
                let error = String(cString: errorPtr)
                c2pa_release_string(errorPtr)
                result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func handleGetSupportedReadMimeTypes(result: @escaping FlutterResult) {
        var count: UInt = 0
        let typesPtr = c2pa_reader_supported_mime_types(&count)

        guard let typesPtr = typesPtr else {
            result([String]())
            return
        }

        var types: [String] = []
        for i in 0..<Int(count) {
            if let typePtr = typesPtr[i] {
                types.append(String(cString: typePtr))
            }
        }

        c2pa_free_string_array(typesPtr, count)
        result(types)
    }

    private func handleGetSupportedSignMimeTypes(result: @escaping FlutterResult) {
        var count: UInt = 0
        let typesPtr = c2pa_builder_supported_mime_types(&count)

        guard let typesPtr = typesPtr else {
            result([String]())
            return
        }

        var types: [String] = []
        for i in 0..<Int(count) {
            if let typePtr = typesPtr[i] {
                types.append(String(cString: typePtr))
            }
        }

        c2pa_free_string_array(typesPtr, count)
        result(types)
    }

    // MARK: - Signer API - Basic

    private func handleSignBytes(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let sourceData = args["sourceData"] as? FlutterStandardTypedData,
              let mimeType = args["mimeType"] as? String,
              let manifestJson = args["manifestJson"] as? String,
              let signerInfoMap = args["signerInfo"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "sourceData, mimeType, manifestJson, and signerInfo are required", details: nil))
            return
        }

        signBytesInternal(sourceData: sourceData.data, mimeType: mimeType, manifestJson: manifestJson, signerInfoMap: signerInfoMap, result: result)
    }

    private func signBytesInternal(sourceData: Data, mimeType: String, manifestJson: String, signerInfoMap: [String: Any], result: @escaping FlutterResult) {
        guard let algorithmStr = signerInfoMap["algorithm"] as? String,
              let certificatePem = signerInfoMap["certificatePem"] as? String,
              let privateKeyPem = signerInfoMap["privateKeyPem"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid signerInfo", details: nil))
            return
        }

        let tsaUrl = signerInfoMap["tsaUrl"] as? String
        let algorithm = mapAlgorithm(algorithmStr)

        var signerInfo = C2paSignerInfo(
            alg: algorithm,
            sign_cert: certificatePem,
            private_key: privateKeyPem,
            ta_url: tsaUrl
        )

        let signer = c2pa_signer_from_info(&signerInfo)
        guard let signer = signer else {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to create signer"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }
        defer { c2pa_signer_free(signer) }

        let builderPtr = c2pa_builder_from_json(manifestJson)
        guard let builderPtr = builderPtr else {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to create builder"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }
        let builder = UnsafeMutableRawPointer(builderPtr).assumingMemoryBound(to: C2paBuilder.self)
        defer { c2pa_builder_free(builder) }

        var sourceStreamData = StreamData(data: sourceData, position: 0)
        var destData = Data()
        var destStreamData = WriteStreamData(data: &destData, position: 0)

        let sourceStream = withUnsafeMutablePointer(to: &sourceStreamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, streamRead, streamSeek, nil, nil)
        }

        guard let sourceStream = sourceStream else {
            result(FlutterError(code: "ERROR", message: "Failed to create source stream", details: nil))
            return
        }
        defer { c2pa_release_stream(sourceStream) }

        let destStream = withUnsafeMutablePointer(to: &destStreamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, writeStreamRead, writeStreamSeek, writeStreamWrite, writeStreamFlush)
        }

        guard let destStream = destStream else {
            result(FlutterError(code: "ERROR", message: "Failed to create dest stream", details: nil))
            return
        }
        defer { c2pa_release_stream(destStream) }

        var manifestBytesPtr: UnsafePointer<UInt8>? = nil
        let signResult = c2pa_builder_sign(builder, mimeType, sourceStream, destStream, signer, &manifestBytesPtr)

        if signResult < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Sign operation failed"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        var manifestBytes: FlutterStandardTypedData? = nil
        if let manifestBytesPtr = manifestBytesPtr, signResult > 0 {
            let manifestData = Data(bytes: manifestBytesPtr, count: Int(signResult))
            manifestBytes = FlutterStandardTypedData(bytes: manifestData)
            c2pa_manifest_bytes_free(manifestBytesPtr)
        }

        let resultMap: [String: Any?] = [
            "signedData": FlutterStandardTypedData(bytes: destData),
            "manifestBytes": manifestBytes
        ]

        result(resultMap)
    }

    private func handleSignFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let sourcePath = args["sourcePath"] as? String,
              let destPath = args["destPath"] as? String,
              let manifestJson = args["manifestJson"] as? String,
              let signerInfoMap = args["signerInfo"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "sourcePath, destPath, manifestJson, and signerInfo are required", details: nil))
            return
        }

        guard let algorithmStr = signerInfoMap["algorithm"] as? String,
              let certificatePem = signerInfoMap["certificatePem"] as? String,
              let privateKeyPem = signerInfoMap["privateKeyPem"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid signerInfo", details: nil))
            return
        }

        let tsaUrl = signerInfoMap["tsaUrl"] as? String
        let algorithm = mapAlgorithm(algorithmStr)

        var signerInfo = C2paSignerInfo(
            alg: algorithm,
            sign_cert: certificatePem,
            private_key: privateKeyPem,
            ta_url: tsaUrl
        )

        let signResult = c2pa_sign_file(sourcePath, destPath, manifestJson, &signerInfo, nil)

        if signResult == nil {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Sign operation failed"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        c2pa_release_string(signResult)
        result(nil)
    }

    // MARK: - Builder API

    private func handleCreateBuilder(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let manifestJson = args["manifestJson"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "manifestJson is required", details: nil))
            return
        }

        let builderPtr = c2pa_builder_from_json(manifestJson)
        guard let builderPtr = builderPtr else {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to create builder"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }
        let builder = UnsafeMutableRawPointer(builderPtr).assumingMemoryBound(to: C2paBuilder.self)

        let handle = storeBuilder(builder)
        result(handle)
    }

    private func handleCreateBuilderFromArchive(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let archiveData = args["archiveData"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "archiveData is required", details: nil))
            return
        }

        var streamData = StreamData(data: archiveData.data, position: 0)

        let stream = withUnsafeMutablePointer(to: &streamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, streamRead, streamSeek, nil, nil)
        }

        guard let stream = stream else {
            result(FlutterError(code: "ERROR", message: "Failed to create stream", details: nil))
            return
        }
        defer { c2pa_release_stream(stream) }

        let builderPtr = c2pa_builder_from_archive(stream)
        guard let builderPtr = builderPtr else {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to create builder from archive"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }
        let builder = UnsafeMutableRawPointer(builderPtr).assumingMemoryBound(to: C2paBuilder.self)

        let handle = storeBuilder(builder)
        result(handle)
    }

    private func handleBuilderSetIntent(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let intentStr = args["intent"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle and intent are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        let intent = mapIntent(intentStr)
        let digitalSourceType = mapDigitalSourceType(args["digitalSourceType"] as? String)

        let setResult = c2pa_builder_set_intent(builder, intent, digitalSourceType)
        if setResult < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to set intent"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        result(nil)
    }

    private func handleBuilderSetNoEmbed(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle is required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        c2pa_builder_set_no_embed(builder)
        result(nil)
    }

    private func handleBuilderSetRemoteUrl(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let url = args["url"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle and url are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        let setResult = c2pa_builder_set_remote_url(builder, url)
        if setResult < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to set remote url"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        result(nil)
    }

    private func handleBuilderAddResource(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let uri = args["uri"] as? String,
              let data = args["data"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle, uri, and data are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        var streamData = StreamData(data: data.data, position: 0)

        let stream = withUnsafeMutablePointer(to: &streamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, streamRead, streamSeek, nil, nil)
        }

        guard let stream = stream else {
            result(FlutterError(code: "ERROR", message: "Failed to create stream", details: nil))
            return
        }
        defer { c2pa_release_stream(stream) }

        let addResult = c2pa_builder_add_resource(builder, uri, stream)
        if addResult < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to add resource"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        result(nil)
    }

    private func handleBuilderAddIngredient(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let data = args["data"] as? FlutterStandardTypedData,
              let mimeType = args["mimeType"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle, data, and mimeType are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        let ingredientJson = args["ingredientJson"] as? String ?? "{}"

        var streamData = StreamData(data: data.data, position: 0)

        let stream = withUnsafeMutablePointer(to: &streamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, streamRead, streamSeek, nil, nil)
        }

        guard let stream = stream else {
            result(FlutterError(code: "ERROR", message: "Failed to create stream", details: nil))
            return
        }
        defer { c2pa_release_stream(stream) }

        let addResult = c2pa_builder_add_ingredient_from_stream(builder, ingredientJson, mimeType, stream)
        if addResult < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to add ingredient"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        result(nil)
    }

    private func handleBuilderAddIngredientFromFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle and path are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            result(FlutterError(code: "FILE_NOT_FOUND", message: "File not found: \(path)", details: nil))
            return
        }

        guard let data = fileManager.contents(atPath: path) else {
            result(FlutterError(code: "ERROR", message: "Failed to read file", details: nil))
            return
        }

        let ingredientJson = args["ingredientJson"] as? String ?? "{}"

        // Determine mime type from extension
        let ext = (path as NSString).pathExtension.lowercased()
        let mimeType = mimeTypeForExtension(ext)

        var streamData = StreamData(data: data, position: 0)

        let stream = withUnsafeMutablePointer(to: &streamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, streamRead, streamSeek, nil, nil)
        }

        guard let stream = stream else {
            result(FlutterError(code: "ERROR", message: "Failed to create stream", details: nil))
            return
        }
        defer { c2pa_release_stream(stream) }

        let addResult = c2pa_builder_add_ingredient_from_stream(builder, ingredientJson, mimeType, stream)
        if addResult < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to add ingredient"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        result(nil)
    }

    private func handleBuilderAddAction(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let actionJson = args["actionJson"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle and actionJson are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        let addResult = c2pa_builder_add_action(builder, actionJson)
        if addResult < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to add action"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        result(nil)
    }

    private func handleBuilderToArchive(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle is required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        var archiveData = Data()
        var archiveStreamData = WriteStreamData(data: &archiveData, position: 0)

        let archiveStream = withUnsafeMutablePointer(to: &archiveStreamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, writeStreamRead, writeStreamSeek, writeStreamWrite, writeStreamFlush)
        }

        guard let archiveStream = archiveStream else {
            result(FlutterError(code: "ERROR", message: "Failed to create archive stream", details: nil))
            return
        }
        defer { c2pa_release_stream(archiveStream) }

        let archiveResult = c2pa_builder_to_archive(builder, archiveStream)
        if archiveResult < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to create archive"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        result(FlutterStandardTypedData(bytes: archiveData))
    }

    private func handleBuilderSign(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let sourceData = args["sourceData"] as? FlutterStandardTypedData,
              let mimeType = args["mimeType"] as? String,
              let signerInfoMap = args["signerInfo"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle, sourceData, mimeType, and signerInfo are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        guard let algorithmStr = signerInfoMap["algorithm"] as? String,
              let certificatePem = signerInfoMap["certificatePem"] as? String,
              let privateKeyPem = signerInfoMap["privateKeyPem"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid signerInfo", details: nil))
            return
        }

        let tsaUrl = signerInfoMap["tsaUrl"] as? String
        let algorithm = mapAlgorithm(algorithmStr)

        var signerInfo = C2paSignerInfo(
            alg: algorithm,
            sign_cert: certificatePem,
            private_key: privateKeyPem,
            ta_url: tsaUrl
        )

        let signer = c2pa_signer_from_info(&signerInfo)
        guard let signer = signer else {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to create signer"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }
        defer { c2pa_signer_free(signer) }

        var sourceStreamData = StreamData(data: sourceData.data, position: 0)
        var destData = Data()
        var destStreamData = WriteStreamData(data: &destData, position: 0)

        let sourceStream = withUnsafeMutablePointer(to: &sourceStreamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, streamRead, streamSeek, nil, nil)
        }

        guard let sourceStream = sourceStream else {
            result(FlutterError(code: "ERROR", message: "Failed to create source stream", details: nil))
            return
        }
        defer { c2pa_release_stream(sourceStream) }

        let destStream = withUnsafeMutablePointer(to: &destStreamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, writeStreamRead, writeStreamSeek, writeStreamWrite, writeStreamFlush)
        }

        guard let destStream = destStream else {
            result(FlutterError(code: "ERROR", message: "Failed to create dest stream", details: nil))
            return
        }
        defer { c2pa_release_stream(destStream) }

        var manifestBytesPtr: UnsafePointer<UInt8>? = nil
        let signResult = c2pa_builder_sign(builder, mimeType, sourceStream, destStream, signer, &manifestBytesPtr)

        if signResult < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Sign operation failed"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        var manifestBytes: FlutterStandardTypedData? = nil
        if let manifestBytesPtr = manifestBytesPtr, signResult > 0 {
            let manifestData = Data(bytes: manifestBytesPtr, count: Int(signResult))
            manifestBytes = FlutterStandardTypedData(bytes: manifestData)
            c2pa_manifest_bytes_free(manifestBytesPtr)
        }

        let resultMap: [String: Any?] = [
            "signedData": FlutterStandardTypedData(bytes: destData),
            "manifestBytes": manifestBytes,
            "manifestSize": Int(signResult)
        ]

        result(resultMap)
    }

    private func handleBuilderSignFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let sourcePath = args["sourcePath"] as? String,
              let destPath = args["destPath"] as? String,
              let signerInfoMap = args["signerInfo"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle, sourcePath, destPath, and signerInfo are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        guard let algorithmStr = signerInfoMap["algorithm"] as? String,
              let certificatePem = signerInfoMap["certificatePem"] as? String,
              let privateKeyPem = signerInfoMap["privateKeyPem"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid signerInfo", details: nil))
            return
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourcePath) else {
            result(FlutterError(code: "FILE_NOT_FOUND", message: "Source file not found: \(sourcePath)", details: nil))
            return
        }

        guard let sourceData = fileManager.contents(atPath: sourcePath) else {
            result(FlutterError(code: "ERROR", message: "Failed to read source file", details: nil))
            return
        }

        let ext = (sourcePath as NSString).pathExtension.lowercased()
        let mimeType = mimeTypeForExtension(ext)

        let tsaUrl = signerInfoMap["tsaUrl"] as? String
        let algorithm = mapAlgorithm(algorithmStr)

        var signerInfo = C2paSignerInfo(
            alg: algorithm,
            sign_cert: certificatePem,
            private_key: privateKeyPem,
            ta_url: tsaUrl
        )

        let signer = c2pa_signer_from_info(&signerInfo)
        guard let signer = signer else {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to create signer"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }
        defer { c2pa_signer_free(signer) }

        var sourceStreamData = StreamData(data: sourceData, position: 0)
        var destData = Data()
        var destStreamData = WriteStreamData(data: &destData, position: 0)

        let sourceStream = withUnsafeMutablePointer(to: &sourceStreamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, streamRead, streamSeek, nil, nil)
        }

        guard let sourceStream = sourceStream else {
            result(FlutterError(code: "ERROR", message: "Failed to create source stream", details: nil))
            return
        }
        defer { c2pa_release_stream(sourceStream) }

        let destStream = withUnsafeMutablePointer(to: &destStreamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(opaquePtr, writeStreamRead, writeStreamSeek, writeStreamWrite, writeStreamFlush)
        }

        guard let destStream = destStream else {
            result(FlutterError(code: "ERROR", message: "Failed to create dest stream", details: nil))
            return
        }
        defer { c2pa_release_stream(destStream) }

        var manifestBytesPtr: UnsafePointer<UInt8>? = nil
        let signResult = c2pa_builder_sign(builder, mimeType, sourceStream, destStream, signer, &manifestBytesPtr)

        if signResult < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Sign operation failed"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        if manifestBytesPtr != nil {
            c2pa_manifest_bytes_free(manifestBytesPtr)
        }

        // Write to destination file
        do {
            try destData.write(to: URL(fileURLWithPath: destPath))
            result(nil)
        } catch {
            result(FlutterError(code: "ERROR", message: "Failed to write destination file: \(error.localizedDescription)", details: nil))
        }
    }

    private func handleBuilderDispose(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle is required", details: nil))
            return
        }

        removeBuilder(handle)
        result(nil)
    }

    // MARK: - Advanced Signing API

    private func handleCreateHashedPlaceholder(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let reservedSize = args["reservedSize"] as? Int,
              let mimeType = args["mimeType"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle, reservedSize, and mimeType are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        var manifestBytesPtr: UnsafePointer<UInt8>? = nil
        let placeholderSize = c2pa_builder_data_hashed_placeholder(builder, UInt(reservedSize), mimeType, &manifestBytesPtr)

        if placeholderSize < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to create hashed placeholder"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        guard let manifestBytesPtr = manifestBytesPtr else {
            result(FlutterError(code: "ERROR", message: "No placeholder data returned", details: nil))
            return
        }

        let placeholderData = Data(bytes: manifestBytesPtr, count: Int(placeholderSize))
        c2pa_manifest_bytes_free(manifestBytesPtr)

        result(FlutterStandardTypedData(bytes: placeholderData))
    }

    private func handleSignHashedEmbeddable(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let signerInfoMap = args["signerInfo"] as? [String: Any],
              let dataHash = args["dataHash"] as? String,
              let mimeType = args["mimeType"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle, signerInfo, dataHash, and mimeType are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        guard let algorithmStr = signerInfoMap["algorithm"] as? String,
              let certificatePem = signerInfoMap["certificatePem"] as? String,
              let privateKeyPem = signerInfoMap["privateKeyPem"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid signerInfo", details: nil))
            return
        }

        let tsaUrl = signerInfoMap["tsaUrl"] as? String
        let algorithm = mapAlgorithm(algorithmStr)

        var signerInfo = C2paSignerInfo(
            alg: algorithm,
            sign_cert: certificatePem,
            private_key: privateKeyPem,
            ta_url: tsaUrl
        )

        let signer = c2pa_signer_from_info(&signerInfo)
        guard let signer = signer else {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to create signer"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }
        defer { c2pa_signer_free(signer) }

        let assetData = args["assetData"] as? FlutterStandardTypedData
        var assetStream: UnsafeMutablePointer<C2paStream>? = nil
        var assetStreamData: StreamData? = nil

        if let assetData = assetData {
            assetStreamData = StreamData(data: assetData.data, position: 0)
            assetStream = withUnsafeMutablePointer(to: &assetStreamData!) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
                let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
                return c2pa_create_stream(opaquePtr, streamRead, streamSeek, nil, nil)
            }
        }

        defer {
            if let assetStream = assetStream {
                c2pa_release_stream(assetStream)
            }
        }

        var manifestBytesPtr: UnsafePointer<UInt8>? = nil
        let signSize = c2pa_builder_sign_data_hashed_embeddable(builder, signer, dataHash, mimeType, assetStream, &manifestBytesPtr)

        if signSize < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to sign hashed embeddable"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        guard let manifestBytesPtr = manifestBytesPtr else {
            result(FlutterError(code: "ERROR", message: "No manifest data returned", details: nil))
            return
        }

        let manifestData = Data(bytes: manifestBytesPtr, count: Int(signSize))
        c2pa_manifest_bytes_free(manifestBytesPtr)

        result(FlutterStandardTypedData(bytes: manifestData))
    }

    private func handleFormatEmbeddable(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let mimeType = args["mimeType"] as? String,
              let manifestBytes = args["manifestBytes"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "mimeType and manifestBytes are required", details: nil))
            return
        }

        var resultBytesPtr: UnsafePointer<UInt8>? = nil

        let formatSize = manifestBytes.data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Int64 in
            return c2pa_format_embeddable(
                mimeType,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                UInt(manifestBytes.data.count),
                &resultBytesPtr
            )
        }

        if formatSize < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to format embeddable"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        guard let resultBytesPtr = resultBytesPtr else {
            result(FlutterError(code: "ERROR", message: "No embeddable data returned", details: nil))
            return
        }

        let embeddableData = Data(bytes: resultBytesPtr, count: Int(formatSize))
        c2pa_manifest_bytes_free(resultBytesPtr)

        result(FlutterStandardTypedData(bytes: embeddableData))
    }

    private func handleGetSignerReserveSize(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let signerInfoMap = args["signerInfo"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "signerInfo is required", details: nil))
            return
        }

        guard let algorithmStr = signerInfoMap["algorithm"] as? String,
              let certificatePem = signerInfoMap["certificatePem"] as? String,
              let privateKeyPem = signerInfoMap["privateKeyPem"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid signerInfo", details: nil))
            return
        }

        let tsaUrl = signerInfoMap["tsaUrl"] as? String
        let algorithm = mapAlgorithm(algorithmStr)

        var signerInfo = C2paSignerInfo(
            alg: algorithm,
            sign_cert: certificatePem,
            private_key: privateKeyPem,
            ta_url: tsaUrl
        )

        let signer = c2pa_signer_from_info(&signerInfo)
        guard let signer = signer else {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to create signer"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }
        defer { c2pa_signer_free(signer) }

        let reserveSize = c2pa_signer_reserve_size(signer)
        if reserveSize < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to get reserve size"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        result(Int(reserveSize))
    }

    // MARK: - Settings API

    private func handleLoadSettings(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let settings = args["settings"] as? String,
              let format = args["format"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "settings and format are required", details: nil))
            return
        }

        let loadResult = c2pa_load_settings(settings, format)
        if loadResult < 0 {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to load settings"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }

        result(nil)
    }

    // MARK: - Helper Functions

    private func mapAlgorithm(_ str: String) -> UnsafePointer<CChar> {
        switch str {
        case "es256": return ("es256" as NSString).utf8String!
        case "es384": return ("es384" as NSString).utf8String!
        case "es512": return ("es512" as NSString).utf8String!
        case "ps256": return ("ps256" as NSString).utf8String!
        case "ps384": return ("ps384" as NSString).utf8String!
        case "ps512": return ("ps512" as NSString).utf8String!
        case "ed25519": return ("ed25519" as NSString).utf8String!
        default: return ("es256" as NSString).utf8String!
        }
    }

    private func mapIntent(_ str: String) -> C2paBuilderIntent {
        switch str {
        case "create": return C2paBuilderIntent(rawValue: 0)
        case "edit": return C2paBuilderIntent(rawValue: 1)
        case "update": return C2paBuilderIntent(rawValue: 2)
        default: return C2paBuilderIntent(rawValue: 0)
        }
    }

    private func mapDigitalSourceType(_ str: String?) -> C2paDigitalSourceType {
        guard let str = str else { return C2paDigitalSourceType(rawValue: 0) }
        switch str {
        case "empty": return C2paDigitalSourceType(rawValue: 0)
        case "trainedAlgorithmicData": return C2paDigitalSourceType(rawValue: 1)
        case "digitalCapture": return C2paDigitalSourceType(rawValue: 2)
        case "computationalCapture": return C2paDigitalSourceType(rawValue: 3)
        case "negativeFilm": return C2paDigitalSourceType(rawValue: 4)
        case "positiveFilm": return C2paDigitalSourceType(rawValue: 5)
        case "print": return C2paDigitalSourceType(rawValue: 6)
        case "humanEdits": return C2paDigitalSourceType(rawValue: 7)
        case "compositeWithTrainedAlgorithmicMedia": return C2paDigitalSourceType(rawValue: 8)
        case "algorithmicallyEnhanced": return C2paDigitalSourceType(rawValue: 9)
        case "digitalCreation": return C2paDigitalSourceType(rawValue: 10)
        case "dataDrivenMedia": return C2paDigitalSourceType(rawValue: 11)
        case "trainedAlgorithmicMedia": return C2paDigitalSourceType(rawValue: 12)
        case "algorithmicMedia": return C2paDigitalSourceType(rawValue: 13)
        case "screenCapture": return C2paDigitalSourceType(rawValue: 14)
        case "virtualRecording": return C2paDigitalSourceType(rawValue: 15)
        case "composite": return C2paDigitalSourceType(rawValue: 16)
        case "compositeCapture": return C2paDigitalSourceType(rawValue: 17)
        case "compositeSynthetic": return C2paDigitalSourceType(rawValue: 18)
        default: return C2paDigitalSourceType(rawValue: 0)
        }
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "gif": return "image/gif"
        case "tiff", "tif": return "image/tiff"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Builder Handle Management

    private func storeBuilder(_ builder: UnsafeMutablePointer<C2paBuilder>) -> Int {
        builderLock.lock()
        defer { builderLock.unlock() }

        let handle = nextBuilderHandle
        nextBuilderHandle += 1
        builders[handle] = builder
        return handle
    }

    private func getBuilder(_ handle: Int) -> UnsafeMutablePointer<C2paBuilder>? {
        builderLock.lock()
        defer { builderLock.unlock() }

        return builders[handle]
    }

    private func removeBuilder(_ handle: Int) {
        builderLock.lock()
        defer { builderLock.unlock() }

        if let builder = builders.removeValue(forKey: handle) {
            c2pa_builder_free(builder)
        }
    }
}

// MARK: - Stream Helpers

private struct StreamData {
    var data: Data
    var position: Int
}

private class WriteStreamData {
    var dataPtr: UnsafeMutablePointer<Data>
    var position: Int

    init(data: UnsafeMutablePointer<Data>, position: Int) {
        self.dataPtr = data
        self.position = position
    }
}

private func streamRead(context: UnsafeMutablePointer<StreamContext>?, buffer: UnsafeMutablePointer<UInt8>?, length: Int) -> Int {
    guard let context = context, let buffer = buffer else { return -1 }

    let streamDataPtr = UnsafeMutableRawPointer(context).assumingMemoryBound(to: StreamData.self)
    let data = streamDataPtr.pointee.data
    let position = streamDataPtr.pointee.position

    let remainingBytes = data.count - position
    let bytesToRead = min(length, remainingBytes)

    if bytesToRead <= 0 { return 0 }

    data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
        let source = bytes.baseAddress!.advanced(by: position)
        buffer.initialize(from: source.assumingMemoryBound(to: UInt8.self), count: bytesToRead)
    }

    streamDataPtr.pointee.position = position + bytesToRead
    return bytesToRead
}

private func streamSeek(context: UnsafeMutablePointer<StreamContext>?, offset: Int, mode: C2paSeekMode) -> Int {
    guard let context = context else { return -1 }

    let streamDataPtr = UnsafeMutableRawPointer(context).assumingMemoryBound(to: StreamData.self)
    let dataSize = streamDataPtr.pointee.data.count
    var newPosition: Int

    switch mode.rawValue {
    case 0: newPosition = offset
    case 1: newPosition = streamDataPtr.pointee.position + offset
    case 2: newPosition = dataSize + offset
    default: return -1
    }

    if newPosition < 0 || newPosition > dataSize { return -1 }

    streamDataPtr.pointee.position = newPosition
    return newPosition
}

private func writeStreamRead(context: UnsafeMutablePointer<StreamContext>?, buffer: UnsafeMutablePointer<UInt8>?, length: Int) -> Int {
    guard let context = context, let buffer = buffer else { return -1 }

    let streamDataPtr = UnsafeMutableRawPointer(context).assumingMemoryBound(to: WriteStreamData.self)
    let data = streamDataPtr.pointee.dataPtr.pointee
    let position = streamDataPtr.pointee.position

    let remainingBytes = data.count - position
    let bytesToRead = min(length, remainingBytes)

    if bytesToRead <= 0 { return 0 }

    data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
        let source = bytes.baseAddress!.advanced(by: position)
        buffer.initialize(from: source.assumingMemoryBound(to: UInt8.self), count: bytesToRead)
    }

    streamDataPtr.pointee.position = position + bytesToRead
    return bytesToRead
}

private func writeStreamSeek(context: UnsafeMutablePointer<StreamContext>?, offset: Int, mode: C2paSeekMode) -> Int {
    guard let context = context else { return -1 }

    let streamDataPtr = UnsafeMutableRawPointer(context).assumingMemoryBound(to: WriteStreamData.self)
    let dataSize = streamDataPtr.pointee.dataPtr.pointee.count
    var newPosition: Int

    switch mode.rawValue {
    case 0: newPosition = offset
    case 1: newPosition = streamDataPtr.pointee.position + offset
    case 2: newPosition = dataSize + offset
    default: return -1
    }

    if newPosition < 0 { return -1 }

    streamDataPtr.pointee.position = newPosition
    return newPosition
}

private func writeStreamWrite(context: UnsafeMutablePointer<StreamContext>?, buffer: UnsafePointer<UInt8>?, length: Int) -> Int {
    guard let context = context, let buffer = buffer, length > 0 else { return -1 }

    let streamDataPtr = UnsafeMutableRawPointer(context).assumingMemoryBound(to: WriteStreamData.self)
    let position = streamDataPtr.pointee.position

    let newData = Data(bytes: buffer, count: length)

    if position >= streamDataPtr.pointee.dataPtr.pointee.count {
        streamDataPtr.pointee.dataPtr.pointee.append(newData)
    } else {
        let endPosition = position + length
        if endPosition > streamDataPtr.pointee.dataPtr.pointee.count {
            streamDataPtr.pointee.dataPtr.pointee.count = endPosition
        }
        streamDataPtr.pointee.dataPtr.pointee.replaceSubrange(position..<endPosition, with: newData)
    }

    streamDataPtr.pointee.position = position + length
    return length
}

private func writeStreamFlush(context: UnsafeMutablePointer<StreamContext>?) -> Int {
    return 0
}
