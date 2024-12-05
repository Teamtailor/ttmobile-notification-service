package com.teamtailor.modules.encryption

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class EncryptionModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("EncryptionModule")

        Function("getPublicKey") {
            CryptoUtils.getPublicKey()
        }

        Function("hybridDecrypt") { encryptedKey: String, cipherText: String, nonce: String, tag: String ->
            CryptoUtils.hybridDecrypt(encryptedKey, cipherText, nonce, tag)
        }

        Function("deleteKeyPair") {
            CryptoUtils.deleteKeyPair()
        }

        Function("testEncryption") { message: String ->
            CryptoUtils.testEncryption(message)
        }

        Function("rsaDecrypt") { encryptedBase64: String ->
            CryptoUtils.rsaDecrypt(encryptedBase64)
        }
    }
}