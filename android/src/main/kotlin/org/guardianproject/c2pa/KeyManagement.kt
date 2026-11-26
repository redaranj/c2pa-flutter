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

import io.flutter.plugin.common.MethodCall
import org.contentauth.c2pa.CertificateManager
import org.contentauth.c2pa.KeyStoreSigner
import org.contentauth.c2pa.StrongBoxSigner
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyFactory
import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Base64

/** Android KeyStore / StrongBox key management behind the Dart key API. */
class KeyManagement(private val appContext: () -> android.content.Context?) {

    fun isHardwareSigningAvailable(): Boolean =
        try {
            appContext()?.let { StrongBoxSigner.isAvailable(it) } ?: false
        } catch (e: Exception) {
            false
        }

    fun createKey(call: MethodCall) {
        val keyAlias = call.req<String>("keyAlias")
        call.req<String>("algorithm")
        val useHardware = call.opt<Boolean>("useHardware") ?: false
        if (useHardware) {
            StrongBoxSigner.createKey(StrongBoxSigner.Config(keyTag = keyAlias))
        } else {
            CertificateManager.generateHardwareKey(keyAlias, requireStrongBox = false)
        }
    }

    fun deleteKey(call: MethodCall): Boolean {
        val keyAlias = call.req<String>("keyAlias")
        if (StrongBoxSigner.deleteKey(keyAlias)) return true
        return KeyStoreSigner.deleteKey(keyAlias)
    }

    fun keyExists(call: MethodCall): Boolean {
        val keyAlias = call.req<String>("keyAlias")
        return StrongBoxSigner.keyExists(keyAlias) || KeyStoreSigner.keyExists(keyAlias)
    }

    fun exportPublicKey(call: MethodCall): String {
        val keyAlias = call.req<String>("keyAlias")
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val cert = keyStore.getCertificate(keyAlias)
            ?: throw PluginError("KEY_NOT_FOUND", "Key not found: $keyAlias")
        val encoded = android.util.Base64.encodeToString(cert.publicKey.encoded, android.util.Base64.DEFAULT)
        return "-----BEGIN PUBLIC KEY-----\n$encoded-----END PUBLIC KEY-----"
    }

    fun importKey(call: MethodCall) {
        val keyAlias = call.req<String>("keyAlias")
        val privateKey = parsePemPrivateKey(call.req("privateKeyPem"))
        val chain = parsePemCertificateChain(call.req("certificateChainPem"))
        if (chain.isEmpty()) throw invalidArgument("No certificates found in certificate chain")
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        keyStore.setKeyEntry(keyAlias, privateKey, null, chain.toTypedArray())
    }

    fun createCSR(call: MethodCall): String {
        val config = CertificateManager.CertificateConfig(
            commonName = call.req("commonName"),
            organization = call.opt("organization"),
            organizationalUnit = call.opt("organizationalUnit"),
            country = call.opt("country"),
            state = call.opt("state"),
            locality = call.opt("locality"),
        )
        return CertificateManager.createCSR(call.req("keyAlias"), config)
    }

    fun enrollHardwareKey(call: MethodCall): Map<String, Any?> {
        val keyAlias = call.req<String>("keyAlias")
        val signingServerUrl = call.req<String>("signingServerUrl")
        val bearerToken = call.opt<String>("bearerToken")
        val commonName = call.opt<String>("commonName") ?: "C2PA Hardware Key"
        val organization = call.opt<String>("organization") ?: "C2PA App"
        val useStrongBox = call.opt<Boolean>("useStrongBox") ?: false

        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(keyAlias)) keyStore.deleteEntry(keyAlias)

        if (useStrongBox) {
            StrongBoxSigner.createKey(StrongBoxSigner.Config(keyTag = keyAlias, requireUserAuthentication = false))
        } else {
            CertificateManager.generateHardwareKey(keyAlias, requireStrongBox = false)
        }

        val csr = CertificateManager.createCSR(
            keyAlias,
            CertificateManager.CertificateConfig(commonName = commonName, organization = organization, country = "US"),
        )

        val connection = URL("$signingServerUrl/api/v1/certificates/sign").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.connectTimeout = 30000
            connection.readTimeout = 30000
            bearerToken?.let { connection.setRequestProperty("Authorization", "Bearer $it") }
            connection.outputStream.use { it.write(JSONObject().put("csr", csr).toString().toByteArray()) }

            if (connection.responseCode != 200) {
                val error = connection.errorStream?.bufferedReader()?.use { it.readText() }
                    ?: "HTTP ${connection.responseCode}"
                throw PluginError("ENROLLMENT_ERROR", "Certificate enrollment failed: $error")
            }
            val response = connection.inputStream.bufferedReader().use { it.readText() }
            return mapOf(
                "certificateChain" to JSONObject(response).getString("certificate_chain"),
                "keyAlias" to keyAlias,
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun parsePemPrivateKey(pem: String): PrivateKey {
        val base64 = pem
            .replace("-----BEGIN PRIVATE KEY-----", "")
            .replace("-----END PRIVATE KEY-----", "")
            .replace("-----BEGIN EC PRIVATE KEY-----", "")
            .replace("-----END EC PRIVATE KEY-----", "")
            .replace("\\s".toRegex(), "")
        val spec = PKCS8EncodedKeySpec(Base64.getDecoder().decode(base64))
        return try {
            KeyFactory.getInstance("EC").generatePrivate(spec)
        } catch (e: Exception) {
            KeyFactory.getInstance("RSA").generatePrivate(spec)
        }
    }

    private fun parsePemCertificateChain(pem: String): List<X509Certificate> {
        val factory = CertificateFactory.getInstance("X.509")
        return Regex("-----BEGIN CERTIFICATE-----([^-]+)-----END CERTIFICATE-----")
            .findAll(pem)
            .map { match ->
                val bytes = Base64.getDecoder().decode(match.groupValues[1].replace("\\s".toRegex(), ""))
                factory.generateCertificate(bytes.inputStream()) as X509Certificate
            }
            .toList()
    }
}
