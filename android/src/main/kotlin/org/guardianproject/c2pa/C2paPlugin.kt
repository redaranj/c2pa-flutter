package org.guardianproject.c2pa

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
import java.io.File

class C2paPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "org.guardianproject.c2pa")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "getVersion" -> {
                try {
                    val version = C2PA.version()
                    result.success(version)
                } catch (e: Exception) {
                    result.success("unknown")
                }
            }
            "readFile" -> {
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
            "readBytes" -> {
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
            "signBytes" -> {
                handleSignBytes(call, result)
            }
            "signFile" -> {
                handleSignFile(call, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

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

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
