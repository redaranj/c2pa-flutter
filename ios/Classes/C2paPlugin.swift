import Flutter
import UIKit
import C2PAC

public class C2paPlugin: NSObject, FlutterPlugin {
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
            if let versionPtr = c2pa_version() {
                let version = String(cString: versionPtr)
                c2pa_release_string(versionPtr)
                result(version)
            } else {
                result("unknown")
            }
        case "readFile":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Path is required", details: nil))
                return
            }
            readFile(path: path, result: result)
        case "readBytes":
            guard let args = call.arguments as? [String: Any],
                  let data = args["data"] as? FlutterStandardTypedData,
                  let mimeType = args["mimeType"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Data and mimeType are required", details: nil))
                return
            }
            readBytes(data: data.data, mimeType: mimeType, result: result)
        case "signBytes":
            guard let args = call.arguments as? [String: Any],
                  let sourceData = args["sourceData"] as? FlutterStandardTypedData,
                  let mimeType = args["mimeType"] as? String,
                  let manifestJson = args["manifestJson"] as? String,
                  let signerInfoMap = args["signerInfo"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "sourceData, mimeType, manifestJson, and signerInfo are required", details: nil))
                return
            }
            signBytes(sourceData: sourceData.data, mimeType: mimeType, manifestJson: manifestJson, signerInfoMap: signerInfoMap, result: result)
        case "signFile":
            guard let args = call.arguments as? [String: Any],
                  let sourcePath = args["sourcePath"] as? String,
                  let destPath = args["destPath"] as? String,
                  let manifestJson = args["manifestJson"] as? String,
                  let signerInfoMap = args["signerInfo"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "sourcePath, destPath, manifestJson, and signerInfo are required", details: nil))
                return
            }
            signFile(sourcePath: sourcePath, destPath: destPath, manifestJson: manifestJson, signerInfoMap: signerInfoMap, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func readFile(path: String, result: @escaping FlutterResult) {
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

    private func readBytes(data: Data, mimeType: String, result: @escaping FlutterResult) {
        var streamData = StreamData(data: data, position: 0)
        
        let stream = withUnsafeMutablePointer(to: &streamData) { contextPtr -> UnsafeMutablePointer<C2paStream>? in
            let opaquePtr = UnsafeMutableRawPointer(contextPtr).assumingMemoryBound(to: StreamContext.self)
            return c2pa_create_stream(
                opaquePtr,
                streamRead,
                streamSeek,
                nil,
                nil
            )
        }

        guard let stream = stream else {
            result(FlutterError(code: "ERROR", message: "Failed to create stream", details: nil))
            return
        }

        defer { c2pa_release_stream(stream) }

        let reader = c2pa_reader_from_stream(mimeType, stream)
        if let reader = reader {
            let jsonPtr = c2pa_reader_json(reader)
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

    private func signBytes(sourceData: Data, mimeType: String, manifestJson: String, signerInfoMap: [String: Any], result: @escaping FlutterResult) {
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
        
        let builder = c2pa_builder_from_json(manifestJson)
        guard let builder = builder else {
            let errorPtr = c2pa_error()
            let error = errorPtr != nil ? String(cString: errorPtr!) : "Failed to create builder"
            if errorPtr != nil { c2pa_string_free(errorPtr) }
            result(FlutterError(code: "C2PA_ERROR", message: error, details: nil))
            return
        }
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

    private func signFile(sourcePath: String, destPath: String, manifestJson: String, signerInfoMap: [String: Any], result: @escaping FlutterResult) {
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
}

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
