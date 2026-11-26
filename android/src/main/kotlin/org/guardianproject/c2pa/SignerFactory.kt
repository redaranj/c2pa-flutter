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

import org.contentauth.c2pa.C2PAError
import org.contentauth.c2pa.KeyStoreSigner
import org.contentauth.c2pa.Signer
import org.contentauth.c2pa.SignerInfo
import org.contentauth.c2pa.SigningAlgorithm
import org.contentauth.c2pa.StrongBoxSigner
import org.contentauth.c2pa.WebServiceSigner
import kotlinx.coroutines.runBlocking

/**
 * Builds SDK [Signer]s from the maps produced by `C2paSigner.toMap()` in Dart.
 *
 * Every method here must run off the main thread: callback signers block the
 * calling thread while Dart computes the signature on the main thread.
 */
class SignerFactory(private val invokeDart: (String, Any?) -> Any?) {

    /** True when the map describes a signer that lives in settings, not a Signer object. */
    fun isSettingsSigner(map: Map<String, Any?>): Boolean = map["type"] == "settings"

    fun create(map: Map<String, Any?>): Signer =
        when (val type = map["type"] as? String ?: "pem") {
            "pem" -> createPem(map)
            "callback" -> createCallback(map)
            "keystore" -> createKeystore(map)
            "hardware" -> createHardware(map)
            "remote" -> createRemote(map)
            "cawgIdentity" -> createCawgIdentity(map)
            "settings" -> throw invalidArgument(
                "A SettingsSigner is not a standalone signer. Put the signer in the settings of a " +
                    "C2paContext and sign without passing a signer, or use C2pa.signBytes/signFile.",
            )
            else -> throw invalidArgument("Unknown signer type: $type")
        }

    private fun string(map: Map<String, Any?>, key: String): String =
        map[key] as? String ?: throw invalidArgument("Signer field '$key' is required")

    private fun createPem(map: Map<String, Any?>): Signer {
        val info = SignerInfo(
            parseAlgorithm(string(map, "algorithm")),
            string(map, "certificatePem"),
            string(map, "privateKeyPem"),
            map["tsaUrl"] as String?,
        )
        return Signer.fromInfo(info)
    }

    private fun createCallback(map: Map<String, Any?>): Signer {
        val callbackId = string(map, "callbackId")
        return Signer.withCallback(
            parseAlgorithm(string(map, "algorithm")),
            string(map, "certificateChainPem"),
            map["tsaUrl"] as String?,
        ) { data ->
            val response = invokeDart("signCallback", mapOf("callbackId" to callbackId, "data" to data))
            response as? ByteArray ?: throw C2PAError.Api("Signing callback returned no signature")
        }
    }

    private fun createKeystore(map: Map<String, Any?>): Signer =
        KeyStoreSigner.createSigner(
            parseAlgorithm(string(map, "algorithm")),
            string(map, "certificateChainPem"),
            string(map, "keyAlias"),
            map["tsaUrl"] as String?,
        )

    private fun createHardware(map: Map<String, Any?>): Signer {
        val config = StrongBoxSigner.Config(
            keyTag = string(map, "keyAlias"),
            requireUserAuthentication = map["requireUserAuthentication"] as? Boolean ?: false,
        )
        // StrongBox only supports ES256.
        return StrongBoxSigner.createSigner(
            SigningAlgorithm.ES256,
            string(map, "certificateChainPem"),
            config,
            map["tsaUrl"] as String?,
        )
    }

    private fun createRemote(map: Map<String, Any?>): Signer {
        val rawHeaders = map["customHeaders"]
        val headers = if (rawHeaders is Map<*, *>) {
            rawHeaders.entries.associate { (k, v) -> k.toString() to v.toString() }
        } else {
            emptyMap()
        }
        val webServiceSigner = WebServiceSigner(
            string(map, "configurationUrl"),
            map["bearerToken"] as String?,
            headers,
        )
        return runBlocking { webServiceSigner.createSigner() }
    }

    @Suppress("UNCHECKED_CAST")
    private fun createCawgIdentity(map: Map<String, Any?>): Signer {
        val claimMap = map["claimSigner"] as? Map<String, Any?>
            ?: throw invalidArgument("claimSigner is required")
        val identityMap = map["identitySigner"] as? Map<String, Any?>
            ?: throw invalidArgument("identitySigner is required")
        val referenced = (map["referencedAssertions"] as? List<String>) ?: emptyList()
        val roles = (map["roles"] as? List<String>) ?: emptyList()

        val claim = create(claimMap)
        val identity = try {
            create(identityMap)
        } catch (e: Exception) {
            claim.close()
            throw e
        }
        // withCawgIdentity consumes both inputs once it reaches native code, but
        // leaves them untouched when it rejects its arguments up front.
        return try {
            Signer.withCawgIdentity(claim, identity, referenced, roles)
        } catch (e: Exception) {
            claim.close()
            identity.close()
            throw e
        }
    }
}
