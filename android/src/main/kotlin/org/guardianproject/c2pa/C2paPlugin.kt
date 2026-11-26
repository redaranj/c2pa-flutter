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

package org.guardianproject.c2pa

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import org.contentauth.c2pa.Action
import org.contentauth.c2pa.Builder
import org.contentauth.c2pa.ByteArrayStream
import org.contentauth.c2pa.C2PA
import org.contentauth.c2pa.C2PAContext
import org.contentauth.c2pa.C2PAContextBuilder
import org.contentauth.c2pa.C2PAError
import org.contentauth.c2pa.C2PASettings
import org.contentauth.c2pa.HttpResolver
import org.contentauth.c2pa.HttpResponse
import org.contentauth.c2pa.ProgressObserver
import org.contentauth.c2pa.Reader
import org.contentauth.c2pa.Stream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Flutter plugin bridging the Dart C2PA API to c2pa-android.
 *
 * Threading model: every call that touches a builder, reader, settings or
 * context runs on one serial worker thread, in the order Dart sent it. That
 * keeps the main thread free while signing (callback signers, progress and
 * HTTP resolvers call back into Dart on the main thread and block the worker
 * until Dart answers), and it means `builderDispose` can never free a builder
 * that an earlier call is still using. Key management runs on a separate pool
 * so a Dart signing callback can use it while the worker is blocked.
 * `contextCancel` runs immediately, since it must reach an operation that is
 * occupying the worker.
 */
class C2paPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var appContext: android.content.Context? = null
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private var worker: ExecutorService = newWorker()
    private val auxPool: ExecutorService = Executors.newCachedThreadPool { r -> Thread(r, "c2pa-flutter-aux") }

    private val builders = HandleRegistry<Builder>()
    private val settingsHandles = HandleRegistry<C2PASettings>()
    private val contexts = HandleRegistry<C2PAContext>()

    /** Settings applied by `loadSettings` to readers and builders created without a context. Worker thread only. */
    private var defaultSettings: C2PASettings? = null

    private val signers = SignerFactory(::invokeDartBlocking)
    private val keys = KeyManagement { appContext }

    private fun newWorker(): ExecutorService =
        Executors.newSingleThreadExecutor { r -> Thread(r, "c2pa-flutter-worker") }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "org.guardianproject.c2pa")
        channel.setMethodCallHandler(this)
        appContext = binding.applicationContext
        if (worker.isShutdown) worker = newWorker()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        appContext = null
        worker.execute {
            builders.drain().forEach { runCatching { it.close() } }
            settingsHandles.drain().forEach { runCatching { it.close() } }
            contexts.drain().forEach { runCatching { it.close() } }
            defaultSettings?.let { runCatching { it.close() } }
            defaultSettings = null
        }
        worker.shutdown()
    }

    // =========================================================================
    // Dispatch
    // =========================================================================

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "contextCancel" -> respond(result) { handleContextCancel(call) }
            in keyMethods -> auxPool.execute { respondOnMain(result) { handleKeyCall(call) } }
            else -> worker.execute { respondOnMain(result) { handleWorkerCall(call) } }
        }
    }

    private val keyMethods = setOf(
        "isHardwareSigningAvailable", "createKey", "deleteKey", "keyExists",
        "exportPublicKey", "importKey", "createCSR", "enrollHardwareKey",
        "createSelfSignedCertificateChain",
    )

    private fun handleKeyCall(call: MethodCall): Any? =
        when (call.method) {
            "isHardwareSigningAvailable" -> keys.isHardwareSigningAvailable()
            "createKey" -> keys.createKey(call)
            "deleteKey" -> keys.deleteKey(call)
            "keyExists" -> keys.keyExists(call)
            "exportPublicKey" -> keys.exportPublicKey(call)
            "importKey" -> keys.importKey(call)
            "createCSR" -> keys.createCSR(call)
            "enrollHardwareKey" -> keys.enrollHardwareKey(call)
            "createSelfSignedCertificateChain" -> throw PluginError(
                "NOT_IMPLEMENTED_ANDROID",
                "createSelfSignedCertificateChain is not available in c2pa-android",
            )
            else -> NotImplemented
        }

    private fun handleWorkerCall(call: MethodCall): Any? =
        when (call.method) {
            "getVersion" -> C2PA.version()

            // Reader
            "readFile" -> readFromPath(call, output = "json")
            "readBytes" -> readFromBytes(call, output = "json")
            "readFileDetailed", "readFileWithContext" ->
                readFromPath(call, output = if (call.opt<Boolean>("detailed") == true) "detailed" else "json")
            "readBytesDetailed" ->
                readFromBytes(call, output = if (call.opt<Boolean>("detailed") == true) "detailed" else "json")
            "readCrJson" ->
                if (call.opt<ByteArray>("data") != null) readFromBytes(call, "crJson") else readFromPath(call, "crJson")
            "readWithManifest" -> handleReadWithManifest(call)
            "readFragment" -> handleReadFragment(call)
            "extractResource" -> handleExtractResource(call)
            "getRemoteUrl" -> withPathReader(call) { it.remoteUrl() }
            "isManifestEmbedded" -> withPathReader(call) { it.isEmbedded() }
            "getSupportedReadMimeTypes" -> Reader.supportedMimeTypes()
            "getSupportedSignMimeTypes" -> Builder.supportedMimeTypes()

            // One-shot signing
            "signBytes" -> handleSignBytes(call)
            "signFile" -> handleSignFile(call)
            "getSignerReserveSize" -> signers.create(call.req("signer")).use { it.reserveSize() }
            "composeManifest" -> C2PAContext.create().use { ctx ->
                Builder.fromContext(ctx).use { it.composeManifest(call.req("mimeType"), call.req("manifestBytes")) }
            }

            // Builder lifecycle
            "createBuilder" -> builders.store(newBuilder(call.optInt("contextHandle"), call.req("manifestJson")))
            "createBuilderWithContext" -> builders.store(newBuilder(call.req("contextHandle"), call.req("manifestJson")))
            "createBuilderWithSettings" -> {
                val settings = settingsFor(call.req("settingsHandle"))
                builders.store(Builder.fromJson(call.req("manifestJson"), settings))
            }
            "createBuilderFromArchive" -> builders.store(newBuilderFromArchive(call))
            "builderDispose" -> {
                builders.remove(call.req("handle"))?.close()
                null
            }

            // Builder configuration
            "builderSetIntent" -> builder(call).setIntent(
                parseIntent(call.req("intent"), call.opt("digitalSourceType")),
            ).let { null }
            "builderSetNoEmbed" -> builder(call).setNoEmbed().let { null }
            "builderSetRemoteUrl" -> builder(call).setRemoteURL(call.req("url")).let { null }
            "builderSetBasePath" -> builder(call).setBasePath(call.req("path")).let { null }
            "builderAddResource" -> ByteArrayStream(call.req("data")).use {
                builder(call).addResource(call.req("uri"), it)
                null
            }
            "builderAddIngredient" -> ByteArrayStream(call.req("data")).use {
                builder(call).addIngredient(call.opt("ingredientJson") ?: "{}", call.req("mimeType"), it)
                null
            }
            "builderAddIngredientFromFile" -> {
                val path = call.req<String>("path")
                openForRead(path).use {
                    builder(call).addIngredient(
                        call.opt("ingredientJson") ?: "{}",
                        call.opt("mimeType") ?: mimeTypeForPath(path),
                        it,
                    )
                }
                null
            }
            "builderAddIngredientFromArchive" -> ByteArrayStream(call.req("archiveData")).use {
                builder(call).addIngredientFromArchive(it)
                null
            }
            "builderWriteIngredientArchive" -> ByteArrayStream().use {
                builder(call).writeIngredientArchive(call.req("ingredientId"), it)
                it.getData()
            }
            "builderAddAction" -> builder(call).addAction(parseAction(call.req("actionJson"))).let { null }
            "builderToArchive" -> ByteArrayStream().use {
                builder(call).toArchive(it)
                it.getData()
            }

            // Builder signing
            "builderSign" -> handleBuilderSign(call)
            "builderSignFile" -> handleBuilderSignFile(call)

            // Embeddable / data-hash / BMFF flows
            "builderNeedsPlaceholder" -> builder(call).needsPlaceholder(call.req("mimeType"))
            "builderPlaceholder" -> builder(call).placeholder(call.req("mimeType"))
            "builderSetDataHashExclusions" -> {
                val raw = call.req<List<List<Number>>>("exclusions")
                builder(call).setDataHashExclusions(raw.map { it[0].toLong() to it[1].toLong() })
                null
            }
            "builderUpdateHashFromBytes" -> ByteArrayStream(call.req("data")).use {
                builder(call).updateHashFromStream(call.req("mimeType"), it)
                null
            }
            "builderUpdateHashFromFile" -> {
                val path = call.req<String>("path")
                openForRead(path).use {
                    builder(call).updateHashFromStream(call.opt("mimeType") ?: mimeTypeForPath(path), it)
                }
                null
            }
            "builderSignEmbeddable" -> builder(call).signEmbeddable(call.req("mimeType"))
            "builderHashType" -> hashTypeName(builder(call).hashType(call.req("mimeType")))
            "builderSetFixedSizeMerkle" -> builder(call).setFixedSizeMerkle(call.reqLong("fixedSizeKb")).let { null }
            "builderHashMdatBytes" -> builder(call).hashMdatBytes(
                call.reqLong("mdatId"),
                call.req("data"),
                call.opt<Boolean>("largeSize") ?: false,
            ).let { null }

            // Settings
            "loadSettings" -> handleLoadSettings(call)
            "createSettings" -> settingsHandles.store(C2PASettings.create())
            "settingsUpdateFromString" ->
                settingsFor(call.req("handle")).updateFromString(call.req("settings"), call.req("format")).let { null }
            "settingsSetValue" ->
                settingsFor(call.req("handle")).setValue(call.req("path"), call.req("value")).let { null }
            "settingsDispose" -> {
                settingsHandles.remove(call.req("handle"))?.close()
                null
            }

            // Contexts
            "createContext" -> handleCreateContext(call)
            "createContextFromSettings" -> handleCreateContext(call)
            "contextDispose" -> {
                contexts.remove(call.req("handle"))?.close()
                null
            }

            else -> NotImplemented
        }

    // =========================================================================
    // Result plumbing
    // =========================================================================

    private object NotImplemented

    private fun respond(result: Result, block: () -> Any?) {
        try {
            when (val value = block()) {
                NotImplemented -> result.notImplemented()
                is Unit -> result.success(null)
                else -> result.success(value)
            }
        } catch (e: PluginError) {
            result.error(e.code, e.message, null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message ?: e.toString(), null)
        } catch (e: Exception) {
            result.error("ERROR", e.message ?: e.toString(), null)
        }
    }

    /** Runs [block] on the calling (background) thread and delivers its outcome on the main thread. */
    private fun respondOnMain(result: Result, block: () -> Any?) {
        var value: Any? = null
        var errorCode: String? = null
        var errorMessage: String? = null
        try {
            value = block()
        } catch (e: PluginError) {
            errorCode = e.code
            errorMessage = e.message
        } catch (e: C2PAError) {
            errorCode = "C2PA_ERROR"
            errorMessage = e.message ?: e.toString()
        } catch (e: Exception) {
            errorCode = "ERROR"
            errorMessage = e.message ?: e.toString()
        }
        mainHandler.post {
            when {
                errorCode != null -> result.error(errorCode, errorMessage, null)
                value === NotImplemented -> result.notImplemented()
                value is Unit -> result.success(null)
                else -> result.success(value)
            }
        }
    }

    /**
     * Invokes a Dart handler on the main thread and blocks the calling thread
     * until it answers. Must never be called on the main thread.
     */
    private fun invokeDartBlocking(method: String, arguments: Any?): Any? {
        check(Looper.myLooper() != Looper.getMainLooper()) { "$method must not be invoked on the main thread" }
        val latch = CountDownLatch(1)
        var value: Any? = null
        var failure: Exception? = null
        mainHandler.post {
            try {
                channel.invokeMethod(method, arguments, object : Result {
                    override fun success(result: Any?) {
                        value = result
                        latch.countDown()
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        failure = C2PAError.Api("$method failed in Dart: ${errorMessage ?: errorCode}")
                        latch.countDown()
                    }

                    override fun notImplemented() {
                        failure = C2PAError.Api("$method has no Dart handler")
                        latch.countDown()
                    }
                })
            } catch (e: Exception) {
                failure = e
                latch.countDown()
            }
        }
        latch.await()
        failure?.let { throw it }
        return value
    }

    // =========================================================================
    // Handle lookup and factories
    // =========================================================================

    private fun builder(call: MethodCall): Builder =
        builders.get(call.req("handle")) ?: throw invalidHandle("builder")

    private fun settingsFor(handle: Int): C2PASettings =
        settingsHandles.get(handle) ?: throw invalidHandle("settings")

    private fun contextFor(handle: Int): C2PAContext =
        contexts.get(handle) ?: throw invalidHandle("context")

    /** Runs [block] with a context for [contextHandle], or a short-lived one built from the default settings. */
    private fun <R> withContext(contextHandle: Int?, block: (C2PAContext?) -> R): R {
        if (contextHandle != null) return block(contextFor(contextHandle))
        val defaults = defaultSettings ?: return block(null)
        // A context without callbacks may be closed once readers/builders exist.
        return C2PAContext.fromSettings(defaults).use { block(it) }
    }

    private fun newReader(contextHandle: Int?, mimeType: String, stream: Stream): Reader =
        withContext(contextHandle) { ctx ->
            if (ctx == null) Reader.fromStream(mimeType, stream) else Reader.fromContext(ctx).withStream(mimeType, stream)
        }

    private fun newBuilder(contextHandle: Int?, manifestJson: String): Builder {
        if (contextHandle != null) return Builder.fromContext(contextFor(contextHandle)).withDefinition(manifestJson)
        val defaults = defaultSettings ?: return Builder.fromJson(manifestJson)
        return Builder.fromJson(manifestJson, defaults)
    }

    private fun newBuilderFromArchive(call: MethodCall): Builder {
        val stream = ByteArrayStream(call.req("archiveData"))
        return withContext(call.optInt("contextHandle")) { ctx ->
            if (ctx == null) Builder.fromArchive(stream) else Builder.fromContext(ctx).withArchive(stream)
        }
    }

    /** Settings for a one-shot SettingsSigner, seeded the way Builder.fromJson(json) seeds its own. */
    private fun settingsFromSignerMap(map: Map<String, Any?>): C2PASettings {
        val settings = C2PASettings.create()
        try {
            settings.updateFromString(defaultLabelsJson(), "json")
            settings.updateFromString(
                map["settings"] as? String ?: throw invalidArgument("SettingsSigner settings are required"),
                (map["format"] as? String ?: "json").lowercase(),
            )
        } catch (e: Exception) {
            settings.close()
            throw e
        }
        return settings
    }

    private fun defaultLabelsJson(): String {
        val labels = Builder.DEFAULT_CREATED_ASSERTION_LABELS.joinToString(",") { "\"$it\"" }
        return """{"version":1,"builder":{"created_assertion_labels":[$labels]}}"""
    }

    private fun parseAction(actionJson: String): Action {
        val obj = Json.parseToJsonElement(actionJson).jsonObject
        val name = obj["action"]?.jsonPrimitive?.contentOrNull ?: throw invalidArgument("action is required")
        val digitalSourceType = obj["digitalSourceType"]?.jsonPrimitive?.contentOrNull
        val softwareAgent = obj["softwareAgent"]?.takeUnless { it is JsonNull }
        val parameters = obj["parameters"]?.takeUnless { it is JsonNull }?.jsonObject?.toMap()
        return Action(name, digitalSourceType, softwareAgent, parameters)
    }

    // =========================================================================
    // Reader
    // =========================================================================

    private fun readerOutput(reader: Reader, output: String): String =
        when (output) {
            "detailed" -> reader.detailedJson()
            "crJson" -> reader.crJSON()
            else -> reader.json()
        }

    private fun readFromPath(call: MethodCall, output: String): String {
        val path = call.req<String>("path")
        return openForRead(path).use { stream ->
            newReader(call.optInt("contextHandle"), call.opt("mimeType") ?: mimeTypeForPath(path), stream)
                .use { readerOutput(it, output) }
        }
    }

    private fun readFromBytes(call: MethodCall, output: String): String =
        ByteArrayStream(call.req("data")).use { stream ->
            newReader(call.optInt("contextHandle"), call.req("mimeType"), stream).use { readerOutput(it, output) }
        }

    private fun <R> withPathReader(call: MethodCall, block: (Reader) -> R): R {
        val path = call.req<String>("path")
        return openForRead(path).use { stream ->
            newReader(call.optInt("contextHandle"), call.opt("mimeType") ?: mimeTypeForPath(path), stream).use(block)
        }
    }

    private fun handleReadWithManifest(call: MethodCall): String {
        // c2pa-android has no context-aware form of this reader; contextHandle is ignored.
        val manifest = call.req<ByteArray>("manifestData")
        val output = if (call.opt<Boolean>("detailed") == true) "detailed" else "json"
        val data = call.opt<ByteArray>("data")
        val mimeType = call.opt<String>("mimeType")
            ?: if (data == null) mimeTypeForPath(call.req("path")) else throw invalidArgument("mimeType is required")
        val stream: Stream = if (data != null) ByteArrayStream(data) else openForRead(call.req("path"))
        return stream.use { s -> Reader.fromManifestAndStream(mimeType, s, manifest).use { readerOutput(it, output) } }
    }

    private fun handleReadFragment(call: MethodCall): String {
        val initPath = call.req<String>("initPath")
        val output = if (call.opt<Boolean>("detailed") == true) "detailed" else "json"
        val mimeType = call.opt<String>("mimeType") ?: mimeTypeForPath(initPath)
        return openForRead(initPath).use { initStream ->
            openForRead(call.req("fragmentPath")).use { fragment ->
                withContext(call.optInt("contextHandle")) { ctx ->
                    val owned = if (ctx == null) C2PAContext.create() else null
                    try {
                        Reader.fromContext(ctx ?: owned!!).withFragment(mimeType, initStream, fragment)
                            .use { readerOutput(it, output) }
                    } finally {
                        owned?.close()
                    }
                }
            }
        }
    }

    private fun handleExtractResource(call: MethodCall): ByteArray =
        ByteArrayStream(call.req("data")).use { stream ->
            newReader(call.optInt("contextHandle"), call.req("mimeType"), stream).use { reader ->
                ByteArrayStream().use { out ->
                    reader.resource(call.req("uri"), out)
                    out.getData()
                }
            }
        }

    // =========================================================================
    // Signing
    // =========================================================================

    private fun signResultMap(result: Builder.SignResult, signedData: ByteArray?): Map<String, Any?> =
        mapOf(
            "signedData" to signedData,
            "manifestBytes" to result.manifestBytes,
            "manifestSize" to (result.manifestBytes?.size ?: result.size.toInt()),
        )

    /**
     * Signs with an explicit signer map, or with the builder's context signer
     * when [signerMap] is null.
     */
    private fun signWith(
        builder: Builder,
        signerMap: Map<String, Any?>?,
        mimeType: String,
        source: Stream,
        dest: Stream,
    ): Builder.SignResult {
        if (signerMap == null) return builder.signWithContext(mimeType, source, dest)
        return signers.create(signerMap).use { builder.sign(mimeType, source, dest, it) }
    }

    private fun handleSignBytes(call: MethodCall): Map<String, Any?> {
        val signerMap = call.req<Map<String, Any?>>("signer")
        val mimeType = call.req<String>("mimeType")
        val manifestJson = call.req<String>("manifestJson")
        return ByteArrayStream(call.req("sourceData")).use { source ->
            ByteArrayStream().use { dest ->
                val result = if (signers.isSettingsSigner(signerMap)) {
                    settingsFromSignerMap(signerMap).use { s ->
                        Builder.fromJson(manifestJson, s).use { it.signWithContext(mimeType, source, dest) }
                    }
                } else {
                    newBuilder(null, manifestJson).use { signWith(it, signerMap, mimeType, source, dest) }
                }
                signResultMap(result, dest.getData())
            }
        }
    }

    private fun handleSignFile(call: MethodCall): Any? {
        val signerMap = call.req<Map<String, Any?>>("signer")
        val sourcePath = call.req<String>("sourcePath")
        val mimeType = call.opt<String>("mimeType") ?: mimeTypeForPath(sourcePath)
        val manifestJson = call.req<String>("manifestJson")
        openForRead(sourcePath).use { source ->
            openForWrite(call.req("destPath")).use { dest ->
                if (signers.isSettingsSigner(signerMap)) {
                    settingsFromSignerMap(signerMap).use { s ->
                        Builder.fromJson(manifestJson, s).use { it.signWithContext(mimeType, source, dest) }
                    }
                } else {
                    newBuilder(null, manifestJson).use { signWith(it, signerMap, mimeType, source, dest) }
                }
            }
        }
        return null
    }

    private fun handleBuilderSign(call: MethodCall): Map<String, Any?> {
        val builder = builder(call)
        return ByteArrayStream(call.req("sourceData")).use { source ->
            ByteArrayStream().use { dest ->
                val result = signWith(builder, call.opt("signer"), call.req("mimeType"), source, dest)
                signResultMap(result, dest.getData())
            }
        }
    }

    private fun handleBuilderSignFile(call: MethodCall): Map<String, Any?> {
        val builder = builder(call)
        val sourcePath = call.req<String>("sourcePath")
        val mimeType = call.opt<String>("mimeType") ?: mimeTypeForPath(sourcePath)
        val result = openForRead(sourcePath).use { source ->
            openForWrite(call.req("destPath")).use { dest ->
                signWith(builder, call.opt("signer"), mimeType, source, dest)
            }
        }
        return signResultMap(result, null)
    }

    // =========================================================================
    // Settings and contexts
    // =========================================================================

    private fun handleLoadSettings(call: MethodCall): Any? {
        val settings = defaultSettings ?: C2PASettings.create().also {
            it.updateFromString(defaultLabelsJson(), "json")
            defaultSettings = it
        }
        settings.updateFromString(call.req("settings"), call.req<String>("format").lowercase())
        return null
    }

    private fun handleCreateContext(call: MethodCall): Int {
        val settings = call.optInt("settingsHandle")?.let { settingsFor(it) }
        val signerMap = call.opt<Map<String, Any?>>("signer")
        val wantsProgress = call.opt<Boolean>("progress") ?: false
        val resolverMode = call.opt<String>("httpResolver")

        val handle = contexts.reserve()
        val context = if (signerMap == null && !wantsProgress && resolverMode == null) {
            settings?.let { C2PAContext.fromSettings(it) } ?: C2PAContext.create()
        } else {
            val builder = C2PAContextBuilder.create()
            try {
                settings?.let { builder.setSettings(it) }
                signerMap?.let { builder.setSigner(signers.create(it)) }
                if (wantsProgress) {
                    builder.setProgressCallback(ProgressObserver { update -> postProgress(handle, update) })
                }
                when (resolverMode) {
                    null -> Unit
                    "native" -> builder.setHttpResolver(OkHttpClient())
                    "callback" -> builder.setHttpResolver(HttpResolver { request ->
                        @Suppress("UNCHECKED_CAST")
                        val response = invokeDartBlocking(
                            "httpResolve",
                            mapOf(
                                "contextHandle" to handle,
                                "url" to request.url,
                                "method" to request.method,
                                "headers" to request.headers,
                                "body" to request.body,
                            ),
                        ) as? Map<String, Any?> ?: throw C2PAError.Api("HTTP resolver returned no response")
                        HttpResponse((response["status"] as Number).toInt(), response["body"] as ByteArray?)
                    })
                    else -> throw invalidArgument("Unknown httpResolver mode: $resolverMode")
                }
                builder.build()
            } catch (e: Exception) {
                builder.close()
                throw e
            }
        }
        contexts.put(handle, context)
        return handle
    }

    private fun postProgress(handle: Int, update: org.contentauth.c2pa.ProgressUpdate) {
        val args = mapOf(
            "contextHandle" to handle,
            "phase" to progressPhaseName(update.phase),
            "step" to update.step,
            "total" to update.total,
        )
        mainHandler.post { channel.invokeMethod("contextProgress", args) }
    }

    private fun handleContextCancel(call: MethodCall): Any? {
        contexts.get(call.req("handle"))?.cancel() ?: throw invalidHandle("context")
        return null
    }
}
