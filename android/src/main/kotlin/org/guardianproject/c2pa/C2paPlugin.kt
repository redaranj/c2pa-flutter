package org.guardianproject.c2pa

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.contentauth.c2pa.C2PA
import org.contentauth.c2pa.Reader
import org.contentauth.c2pa.Builder
import org.contentauth.c2pa.Signer
import org.contentauth.c2pa.SignerInfo
import org.contentauth.c2pa.SigningAlgorithm
import org.contentauth.c2pa.ByteArrayStream
import org.contentauth.c2pa.C2PAError
import org.contentauth.c2pa.BuilderIntent
import org.contentauth.c2pa.DigitalSourceType
import org.contentauth.c2pa.Action
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.locks.ReentrantLock

class C2paPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    // Builder handle management
    private val builders = HashMap<Int, Builder>()
    private var nextBuilderHandle = 1
    private val builderLock = ReentrantLock()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "org.guardianproject.c2pa")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            // Version and Platform Info
            "getPlatformVersion" -> handleGetPlatformVersion(result)
            "getVersion" -> handleGetVersion(result)

            // Reader API - Basic
            "readFile" -> handleReadFile(call, result)
            "readBytes" -> handleReadBytes(call, result)

            // Reader API - Enhanced
            "readFileDetailed" -> handleReadFileDetailed(call, result)
            "readBytesDetailed" -> handleReadBytesDetailed(call, result)
            "extractResource" -> handleExtractResource(call, result)
            "readIngredientFile" -> handleReadIngredientFile(call, result)
            "getSupportedReadMimeTypes" -> handleGetSupportedReadMimeTypes(result)
            "getSupportedSignMimeTypes" -> handleGetSupportedSignMimeTypes(result)

            // Signer API - Basic
            "signBytes" -> handleSignBytes(call, result)
            "signFile" -> handleSignFile(call, result)

            // Builder API
            "createBuilder" -> handleCreateBuilder(call, result)
            "createBuilderFromArchive" -> handleCreateBuilderFromArchive(call, result)
            "builderSetIntent" -> handleBuilderSetIntent(call, result)
            "builderSetNoEmbed" -> handleBuilderSetNoEmbed(call, result)
            "builderSetRemoteUrl" -> handleBuilderSetRemoteUrl(call, result)
            "builderAddResource" -> handleBuilderAddResource(call, result)
            "builderAddIngredient" -> handleBuilderAddIngredient(call, result)
            "builderAddIngredientFromFile" -> handleBuilderAddIngredientFromFile(call, result)
            "builderAddAction" -> handleBuilderAddAction(call, result)
            "builderToArchive" -> handleBuilderToArchive(call, result)
            "builderSign" -> handleBuilderSign(call, result)
            "builderSignFile" -> handleBuilderSignFile(call, result)
            "builderDispose" -> handleBuilderDispose(call, result)

            // Advanced Signing API
            "createHashedPlaceholder" -> handleCreateHashedPlaceholder(call, result)
            "signHashedEmbeddable" -> handleSignHashedEmbeddable(call, result)
            "formatEmbeddable" -> handleFormatEmbeddable(call, result)
            "getSignerReserveSize" -> handleGetSignerReserveSize(call, result)

            // Settings API
            "loadSettings" -> handleLoadSettings(call, result)

            else -> result.notImplemented()
        }
    }

    // ===========================================================================
    // Version and Platform Info
    // ===========================================================================

    private fun handleGetPlatformVersion(result: Result) {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
    }

    private fun handleGetVersion(result: Result) {
        try {
            val version = C2PA.version()
            result.success(version)
        } catch (e: Exception) {
            result.success("unknown")
        }
    }

    // ===========================================================================
    // Reader API - Basic
    // ===========================================================================

    private fun handleReadFile(call: MethodCall, result: Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("INVALID_ARGUMENT", "Path is required", null)
            return
        }
        try {
            val json = C2PA.readFile(path, null)
            result.success(json)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleReadBytes(call: MethodCall, result: Result) {
        val data = call.argument<ByteArray>("data")
        val mimeType = call.argument<String>("mimeType")
        if (data == null || mimeType == null) {
            result.error("INVALID_ARGUMENT", "Data and mimeType are required", null)
            return
        }
        try {
            val stream = ByteArrayStream(data)
            val reader = Reader.fromStream(mimeType, stream)
            val json = reader.json()
            reader.close()
            result.success(json)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ===========================================================================
    // Reader API - Enhanced
    // ===========================================================================

    private fun handleReadFileDetailed(call: MethodCall, result: Result) {
        val path = call.argument<String>("path")
        val detailed = call.argument<Boolean>("detailed") ?: false
        val dataDir = call.argument<String>("dataDir")

        if (path == null) {
            result.error("INVALID_ARGUMENT", "Path is required", null)
            return
        }

        try {
            // Read the file using the static API with dataDir for resource extraction
            val json = C2PA.readFile(path, dataDir)
            result.success(json)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleReadBytesDetailed(call: MethodCall, result: Result) {
        val data = call.argument<ByteArray>("data")
        val mimeType = call.argument<String>("mimeType")
        val detailed = call.argument<Boolean>("detailed") ?: false

        if (data == null || mimeType == null) {
            result.error("INVALID_ARGUMENT", "Data and mimeType are required", null)
            return
        }

        try {
            val stream = ByteArrayStream(data)
            val reader = Reader.fromStream(mimeType, stream)
            val json = reader.json()
            reader.close()
            result.success(json)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleExtractResource(call: MethodCall, result: Result) {
        val data = call.argument<ByteArray>("data")
        val mimeType = call.argument<String>("mimeType")
        val uri = call.argument<String>("uri")

        if (data == null || mimeType == null || uri == null) {
            result.error("INVALID_ARGUMENT", "Data, mimeType, and uri are required", null)
            return
        }

        try {
            val stream = ByteArrayStream(data)
            val reader = Reader.fromStream(mimeType, stream)
            val resourceStream = ByteArrayStream()
            reader.resource(uri, resourceStream)
            val resourceData = resourceStream.getData()
            reader.close()
            result.success(resourceData)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleReadIngredientFile(call: MethodCall, result: Result) {
        val path = call.argument<String>("path")
        val dataDir = call.argument<String>("dataDir")

        if (path == null) {
            result.error("INVALID_ARGUMENT", "Path is required", null)
            return
        }

        try {
            val json = C2PA.readIngredientFile(path, dataDir)
            result.success(json)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleGetSupportedReadMimeTypes(result: Result) {
        // Return common supported MIME types - the C2PA library supports these formats
        val mimeTypes = listOf(
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/gif",
            "image/tiff",
            "image/heic",
            "image/heif",
            "image/avif",
            "video/mp4",
            "video/quicktime",
            "audio/mp4",
            "application/mp4",
            "audio/mpeg",
            "application/pdf",
            "image/svg+xml"
        )
        result.success(mimeTypes)
    }

    private fun handleGetSupportedSignMimeTypes(result: Result) {
        // Return common supported MIME types for signing
        val mimeTypes = listOf(
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/gif",
            "image/tiff",
            "image/heic",
            "image/heif",
            "image/avif",
            "video/mp4",
            "video/quicktime",
            "audio/mp4",
            "application/mp4",
            "audio/mpeg",
            "application/pdf",
            "image/svg+xml"
        )
        result.success(mimeTypes)
    }

    // ===========================================================================
    // Signer API - Basic
    // ===========================================================================

    private fun handleSignBytes(call: MethodCall, result: Result) {
        val sourceData = call.argument<ByteArray>("sourceData")
        val mimeType = call.argument<String>("mimeType")
        val manifestJson = call.argument<String>("manifestJson")
        val signerInfoMap = call.argument<Map<String, Any?>>("signerInfo")

        if (sourceData == null || mimeType == null || manifestJson == null || signerInfoMap == null) {
            result.error("INVALID_ARGUMENT", "sourceData, mimeType, manifestJson, and signerInfo are required", null)
            return
        }

        try {
            val signerInfo = parseSignerInfo(signerInfoMap)
            val signer = Signer.fromInfo(signerInfo)

            val builder = Builder.fromJson(manifestJson)
            val sourceStream = ByteArrayStream(sourceData)
            val destStream = ByteArrayStream()

            val signResult = builder.sign(mimeType, sourceStream, destStream, signer)

            val signedData = destStream.getData()

            builder.close()
            signer.close()

            val resultMap = HashMap<String, Any?>()
            resultMap["signedData"] = signedData
            resultMap["manifestBytes"] = signResult.manifestBytes

            result.success(resultMap)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleSignFile(call: MethodCall, result: Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val destPath = call.argument<String>("destPath")
        val manifestJson = call.argument<String>("manifestJson")
        val signerInfoMap = call.argument<Map<String, Any?>>("signerInfo")

        if (sourcePath == null || destPath == null || manifestJson == null || signerInfoMap == null) {
            result.error("INVALID_ARGUMENT", "sourcePath, destPath, manifestJson, and signerInfo are required", null)
            return
        }

        try {
            val signerInfo = parseSignerInfo(signerInfoMap)
            C2PA.signFile(sourcePath, destPath, manifestJson, signerInfo, null)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ===========================================================================
    // Builder API
    // ===========================================================================

    private fun handleCreateBuilder(call: MethodCall, result: Result) {
        val manifestJson = call.argument<String>("manifestJson")

        if (manifestJson == null) {
            result.error("INVALID_ARGUMENT", "manifestJson is required", null)
            return
        }

        try {
            val builder = Builder.fromJson(manifestJson)
            val handle = storeBuilder(builder)
            result.success(handle)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleCreateBuilderFromArchive(call: MethodCall, result: Result) {
        val archiveData = call.argument<ByteArray>("archiveData")

        if (archiveData == null) {
            result.error("INVALID_ARGUMENT", "archiveData is required", null)
            return
        }

        try {
            val stream = ByteArrayStream(archiveData)
            val builder = Builder.fromArchive(stream)
            val handle = storeBuilder(builder)
            result.success(handle)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderSetIntent(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val intentStr = call.argument<String>("intent")
        val digitalSourceTypeStr = call.argument<String>("digitalSourceType")

        if (handle == null || intentStr == null) {
            result.error("INVALID_ARGUMENT", "handle and intent are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            // Map the digital source type if provided, otherwise use default
            val digitalSourceType = if (digitalSourceTypeStr != null) {
                mapDigitalSourceType(digitalSourceTypeStr)
            } else {
                DigitalSourceType.DIGITAL_CAPTURE
            }

            val intent = mapIntent(intentStr, digitalSourceType)
            builder.setIntent(intent)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderSetNoEmbed(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")

        if (handle == null) {
            result.error("INVALID_ARGUMENT", "handle is required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            builder.setNoEmbed()
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderSetRemoteUrl(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val url = call.argument<String>("url")

        if (handle == null || url == null) {
            result.error("INVALID_ARGUMENT", "handle and url are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            builder.setRemoteURL(url)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderAddResource(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val uri = call.argument<String>("uri")
        val data = call.argument<ByteArray>("data")

        if (handle == null || uri == null || data == null) {
            result.error("INVALID_ARGUMENT", "handle, uri, and data are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            val stream = ByteArrayStream(data)
            builder.addResource(uri, stream)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderAddIngredient(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val data = call.argument<ByteArray>("data")
        val mimeType = call.argument<String>("mimeType")
        val ingredientJson = call.argument<String>("ingredientJson")

        if (handle == null || data == null || mimeType == null) {
            result.error("INVALID_ARGUMENT", "handle, data, and mimeType are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            val stream = ByteArrayStream(data)
            // API signature: addIngredient(ingredientJson, mimeType, stream)
            // Use empty JSON object if ingredientJson is null
            builder.addIngredient(ingredientJson ?: "{}", mimeType, stream)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderAddIngredientFromFile(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val path = call.argument<String>("path")
        val ingredientJson = call.argument<String>("ingredientJson")

        if (handle == null || path == null) {
            result.error("INVALID_ARGUMENT", "handle and path are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            // Builder doesn't have addIngredientFile - read file and use addIngredient
            val file = File(path)
            val data = file.readBytes()
            val mimeType = getMimeTypeFromPath(path)
            val stream = ByteArrayStream(data)

            builder.addIngredient(ingredientJson ?: "{}", mimeType, stream)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderAddAction(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val actionJson = call.argument<String>("actionJson")

        if (handle == null || actionJson == null) {
            result.error("INVALID_ARGUMENT", "handle and actionJson are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            // Parse JSON and create Action object
            val json = JSONObject(actionJson)
            val actionName = json.optString("action", "c2pa.unknown")
            val softwareAgent = json.optString("softwareAgent", null)
            val digitalSourceType = json.optString("digitalSourceType", null)

            // Parse parameters if present
            val parameters = mutableMapOf<String, String>()
            if (json.has("parameters")) {
                val paramsJson = json.getJSONObject("parameters")
                val keys = paramsJson.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    parameters[key] = paramsJson.optString(key, "")
                }
            }

            val action = Action(
                actionName,
                digitalSourceType,
                softwareAgent,
                if (parameters.isEmpty()) null else parameters
            )

            builder.addAction(action)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderToArchive(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")

        if (handle == null) {
            result.error("INVALID_ARGUMENT", "handle is required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            val stream = ByteArrayStream()
            builder.toArchive(stream)
            val archiveData = stream.getData()
            result.success(archiveData)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderSign(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val sourceData = call.argument<ByteArray>("sourceData")
        val mimeType = call.argument<String>("mimeType")
        val signerInfoMap = call.argument<Map<String, Any?>>("signerInfo")

        if (handle == null || sourceData == null || mimeType == null || signerInfoMap == null) {
            result.error("INVALID_ARGUMENT", "handle, sourceData, mimeType, and signerInfo are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            val signerInfo = parseSignerInfo(signerInfoMap)
            val signer = Signer.fromInfo(signerInfo)

            val sourceStream = ByteArrayStream(sourceData)
            val destStream = ByteArrayStream()

            val signResult = builder.sign(mimeType, sourceStream, destStream, signer)
            val signedData = destStream.getData()

            signer.close()

            val resultMap = HashMap<String, Any?>()
            resultMap["signedData"] = signedData
            resultMap["manifestBytes"] = signResult.manifestBytes
            resultMap["manifestSize"] = signResult.manifestBytes?.size ?: 0

            result.success(resultMap)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderSignFile(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val sourcePath = call.argument<String>("sourcePath")
        val destPath = call.argument<String>("destPath")
        val signerInfoMap = call.argument<Map<String, Any?>>("signerInfo")

        if (handle == null || sourcePath == null || destPath == null || signerInfoMap == null) {
            result.error("INVALID_ARGUMENT", "handle, sourcePath, destPath, and signerInfo are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            val signerInfo = parseSignerInfo(signerInfoMap)
            val signer = Signer.fromInfo(signerInfo)

            // Note: The native C2PA library doesn't have a signFile method, so we read the
            // entire file into memory. For large files (especially videos), this may cause
            // out-of-memory errors. Consider using sign() with streamed data instead.
            val sourceFile = File(sourcePath)
            val sourceData = sourceFile.readBytes()

            // Determine MIME type from extension
            val mimeType = getMimeTypeFromPath(sourcePath)

            val sourceStream = ByteArrayStream(sourceData)
            val destStream = ByteArrayStream()

            builder.sign(mimeType, sourceStream, destStream, signer)

            // Write output to destination file
            val destFile = File(destPath)
            destFile.writeBytes(destStream.getData())

            signer.close()

            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun getMimeTypeFromPath(path: String): String {
        val extension = path.substringAfterLast('.', "").lowercase()
        return when (extension) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "tiff", "tif" -> "image/tiff"
            "heic" -> "image/heic"
            "heif" -> "image/heif"
            "avif" -> "image/avif"
            "mp4", "m4v" -> "video/mp4"
            "mov" -> "video/quicktime"
            "m4a" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "pdf" -> "application/pdf"
            "svg" -> "image/svg+xml"
            else -> "application/octet-stream"
        }
    }

    private fun handleBuilderDispose(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")

        if (handle == null) {
            result.error("INVALID_ARGUMENT", "handle is required", null)
            return
        }

        try {
            val builder = removeBuilder(handle)
            builder?.close()
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ===========================================================================
    // Advanced Signing API
    // ===========================================================================

    private fun handleCreateHashedPlaceholder(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val reservedSize = call.argument<Int>("reservedSize")
        val mimeType = call.argument<String>("mimeType")

        if (handle == null || reservedSize == null || mimeType == null) {
            result.error("INVALID_ARGUMENT", "handle, reservedSize, and mimeType are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            val placeholderData = builder.dataHashedPlaceholder(reservedSize.toLong(), mimeType)
            result.success(placeholderData)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleSignHashedEmbeddable(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val signerInfoMap = call.argument<Map<String, Any?>>("signerInfo")
        val dataHash = call.argument<String>("dataHash")
        val mimeType = call.argument<String>("mimeType")
        val assetData = call.argument<ByteArray>("assetData")

        if (handle == null || signerInfoMap == null || dataHash == null || mimeType == null) {
            result.error("INVALID_ARGUMENT", "handle, signerInfo, dataHash, and mimeType are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            val signerInfo = parseSignerInfo(signerInfoMap)
            val signer = Signer.fromInfo(signerInfo)

            val assetStream = if (assetData != null) ByteArrayStream(assetData) else null
            val embeddableData = builder.signDataHashedEmbeddable(signer, dataHash, mimeType, assetStream)

            signer.close()
            result.success(embeddableData)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleFormatEmbeddable(call: MethodCall, result: Result) {
        val mimeType = call.argument<String>("mimeType")
        val manifestBytes = call.argument<ByteArray>("manifestBytes")

        if (mimeType == null || manifestBytes == null) {
            result.error("INVALID_ARGUMENT", "mimeType and manifestBytes are required", null)
            return
        }

        // formatEmbeddable is not available in the Android C2PA library.
        // The manifest bytes from signDataHashedEmbeddable are already in the correct format.
        // Return the manifest bytes unchanged.
        Log.w("C2paPlugin", "formatEmbeddable: Not supported on Android, returning input unchanged")
        result.success(manifestBytes)
    }

    private fun handleGetSignerReserveSize(call: MethodCall, result: Result) {
        val signerInfoMap = call.argument<Map<String, Any?>>("signerInfo")

        if (signerInfoMap == null) {
            result.error("INVALID_ARGUMENT", "signerInfo is required", null)
            return
        }

        try {
            val signerInfo = parseSignerInfo(signerInfoMap)
            val signer = Signer.fromInfo(signerInfo)
            val reserveSize = signer.reserveSize()
            signer.close()
            result.success(reserveSize)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ===========================================================================
    // Settings API
    // ===========================================================================

    private fun handleLoadSettings(call: MethodCall, result: Result) {
        val settings = call.argument<String>("settings")
        val format = call.argument<String>("format")

        if (settings == null || format == null) {
            result.error("INVALID_ARGUMENT", "settings and format are required", null)
            return
        }

        try {
            C2PA.loadSettings(settings, format)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ===========================================================================
    // Helper Functions
    // ===========================================================================

    private fun parseSignerInfo(map: Map<String, Any?>): SignerInfo {
        val algorithmStr = map["algorithm"] as String
        val certificatePem = map["certificatePem"] as String
        val privateKeyPem = map["privateKeyPem"] as String
        val tsaUrl = map["tsaUrl"] as String?

        val algorithm = when (algorithmStr) {
            "es256" -> SigningAlgorithm.ES256
            "es384" -> SigningAlgorithm.ES384
            "es512" -> SigningAlgorithm.ES512
            "ps256" -> SigningAlgorithm.PS256
            "ps384" -> SigningAlgorithm.PS384
            "ps512" -> SigningAlgorithm.PS512
            "ed25519" -> SigningAlgorithm.ED25519
            else -> SigningAlgorithm.ES256
        }

        return SignerInfo(algorithm, certificatePem, privateKeyPem, tsaUrl)
    }

    private fun mapIntent(intent: String, digitalSourceType: DigitalSourceType = DigitalSourceType.DIGITAL_CAPTURE): BuilderIntent {
        return when (intent) {
            "create" -> BuilderIntent.Create(digitalSourceType)
            "edit" -> BuilderIntent.Edit
            "update" -> BuilderIntent.Update
            else -> BuilderIntent.Create(digitalSourceType)
        }
    }

    private fun mapDigitalSourceType(type: String): DigitalSourceType {
        return when (type) {
            "empty" -> DigitalSourceType.EMPTY
            "trainedAlgorithmicMedia" -> DigitalSourceType.TRAINED_ALGORITHMIC_MEDIA
            "compositeWithTrainedAlgorithmicMedia" -> DigitalSourceType.COMPOSITE_WITH_TRAINED_ALGORITHMIC_MEDIA
            "algorithmicMedia" -> DigitalSourceType.ALGORITHMIC_MEDIA
            "compositeCapture" -> DigitalSourceType.COMPOSITE_CAPTURE
            "compositeSynthetic" -> DigitalSourceType.COMPOSITE_SYNTHETIC
            "dataDrivenMedia" -> DigitalSourceType.DATA_DRIVEN_MEDIA
            "digitalCapture" -> DigitalSourceType.DIGITAL_CAPTURE
            "virtualRecording" -> DigitalSourceType.VIRTUAL_RECORDING
            "humanEdits" -> DigitalSourceType.HUMAN_EDITS
            "computationalCapture" -> DigitalSourceType.COMPUTATIONAL_CAPTURE
            "digitalCreation" -> DigitalSourceType.DIGITAL_CREATION
            "trainedAlgorithmicData" -> DigitalSourceType.TRAINED_ALGORITHMIC_DATA
            "screenCapture" -> DigitalSourceType.SCREEN_CAPTURE
            "composite" -> DigitalSourceType.COMPOSITE
            "algorithmicallyEnhanced" -> DigitalSourceType.ALGORITHMICALLY_ENHANCED
            "negativeFilm" -> DigitalSourceType.NEGATIVE_FILM
            "positiveFilm" -> DigitalSourceType.POSITIVE_FILM
            "print" -> DigitalSourceType.PRINT
            else -> DigitalSourceType.DIGITAL_CAPTURE
        }
    }

    // ===========================================================================
    // Builder Handle Management
    // ===========================================================================

    private fun storeBuilder(builder: Builder): Int {
        builderLock.lock()
        try {
            val handle = nextBuilderHandle++
            builders[handle] = builder
            return handle
        } finally {
            builderLock.unlock()
        }
    }

    private fun getBuilder(handle: Int): Builder? {
        builderLock.lock()
        try {
            return builders[handle]
        } finally {
            builderLock.unlock()
        }
    }

    private fun removeBuilder(handle: Int): Builder? {
        builderLock.lock()
        try {
            return builders.remove(handle)
        } finally {
            builderLock.unlock()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)

        // Clean up any remaining builders
        builderLock.lock()
        try {
            for (builder in builders.values) {
                try {
                    builder.close()
                } catch (e: Exception) {
                    // Ignore cleanup errors
                }
            }
            builders.clear()
        } finally {
            builderLock.unlock()
        }
    }
}
