package com.teamtailor.modules.encryption

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

object CryptoUtils {
    private const val KEY_ALIAS = "com.teamtailor.modules.encryption.cryptoutils2"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val GCM_TAG_LENGTH = 128

    private fun getOrCreateKeyPair(): KeyStore.PrivateKeyEntry {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)

        if (!keyStore.containsAlias(KEY_ALIAS)) {
            val spec = KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setDigests(KeyProperties.DIGEST_SHA1)  // Changed to SHA1 to match Ruby/iOS
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
                .setKeySize(2048)  // Explicitly set key size to match other implementations
                .build()

            val generator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_RSA,
                ANDROID_KEYSTORE
            )
            generator.initialize(spec)
            generator.generateKeyPair()
        }

        return keyStore.getEntry(KEY_ALIAS, null) as KeyStore.PrivateKeyEntry
    }

    fun getPublicKey(): String {
        val entry = getOrCreateKeyPair()
        return Base64.encodeToString(entry.certificate.publicKey.encoded, Base64.NO_WRAP)
    }

    fun hybridDecrypt(encryptedKey: String, cipherText: String, nonce: String, tag: String): String {
        val aesKey = rsaDecrypt(encryptedKey)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        
        val nonceBytes = Base64.decode(nonce, Base64.NO_WRAP)
        val cipherBytes = Base64.decode(cipherText, Base64.NO_WRAP)
        val tagBytes = Base64.decode(tag, Base64.NO_WRAP)
        
        val spec = GCMParameterSpec(GCM_TAG_LENGTH, nonceBytes)
        val secretKey = SecretKeySpec(aesKey, "AES")  // AES-256 key from RSA decryption
        
        cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)
        val decryptedBytes = cipher.doFinal(cipherBytes + tagBytes)
        
        return String(decryptedBytes, Charsets.UTF_8)
    }

    fun rsaDecrypt(encryptedBase64: String): ByteArray {
        val entry = getOrCreateKeyPair()
        // Use RSA/ECB/OAEPWithSHA-1AndMGF1Padding to match Ruby's OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING
        val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-1AndMGF1Padding")
        cipher.init(Cipher.DECRYPT_MODE, entry.privateKey)
        
        val encryptedBytes = Base64.decode(encryptedBase64, Base64.NO_WRAP)
        return cipher.doFinal(encryptedBytes)
    }

    fun deleteKeyPair() {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)
        keyStore.deleteEntry(KEY_ALIAS)
    }

    fun testEncryption(message: String): Boolean {
        val entry = getOrCreateKeyPair()
        val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-1AndMGF1Padding")
        
        // Encrypt
        cipher.init(Cipher.ENCRYPT_MODE, entry.certificate.publicKey)
        val encrypted = cipher.doFinal(message.toByteArray())
        
        // Decrypt
        cipher.init(Cipher.DECRYPT_MODE, entry.privateKey)
        val decrypted = cipher.doFinal(encrypted)
        
        return message == String(decrypted)
    }
}