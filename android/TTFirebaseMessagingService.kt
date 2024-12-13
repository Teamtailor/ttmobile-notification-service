package com.teamtailor.app

import com.google.firebase.messaging.RemoteMessage
import expo.modules.notifications.service.ExpoFirebaseMessagingService
import android.util.Log
import org.json.JSONObject
import com.teamtailor.modules.encryption.CryptoUtils

class TTFirebaseMessagingService : ExpoFirebaseMessagingService() {
    companion object {
        private const val TAG = "TTFirebaseMessagingService"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val originalData = remoteMessage.getData()
        Log.d(TAG, "Received message with data: ${originalData}")

        if (originalData["encrypted_data"]?.let { encryptedDataString ->
            try {
                val encryptedData = parseJsonToMap(encryptedDataString)
                val decryptedDataString = CryptoUtils.hybridDecrypt(
                    encryptedData["encrypted_key"]!!,
                    encryptedData["cipher_text"]!!,
                    encryptedData["nonce"]!!,
                    encryptedData["tag"]!!
                )
                
                val decryptedData = parseJsonToMap(decryptedDataString)
                val modifiedData = originalData.toMutableMap().apply {
                    remove("encrypted_data")
                    putAll(decryptedData)
                }

                val newMessage = RemoteMessage.Builder("/topics/default").apply {
                    remoteMessage.getMessageId()?.let { setMessageId(it) }
                    setData(modifiedData)
                    setTtl(remoteMessage.getTtl())
                    setCollapseKey(remoteMessage.getCollapseKey())
                }.build()

                super.onMessageReceived(newMessage)
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to decrypt or parse encrypted data", e)
                false
            }
        } == true) {
            Log.d(TAG, "Successfully handled encrypted data")
        } else {
            Log.d(TAG, "No encrypted data found or decryption failed, passing original message")
            super.onMessageReceived(remoteMessage)
        }
    }

    private fun parseJsonToMap(jsonString: String): Map<String, String> =
        JSONObject(jsonString).let { json ->
            json.keys().asSequence().associateWith { key ->
                json.getString(key)
            }
        }
}