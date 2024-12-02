package com.teamtailor.app;

import com.google.firebase.messaging.RemoteMessage;
import expo.modules.notifications.service.ExpoFirebaseMessagingService;

import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.KeyStore.Entry;
import java.security.KeyStore.PrivateKeyEntry;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.cert.CertificateException;

import javax.crypto.Cipher;

import java.util.Iterator;
import java.util.Map;
import java.util.HashMap;

import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

public class TTFirebaseMessagingService extends ExpoFirebaseMessagingService {

    private static final String TAG = "TTFirebaseMessagingService";

    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {
        Map<String, String> originalData = remoteMessage.getData();

        // Check if 'encrypted_data' exists in the original data
        if (originalData.containsKey("encrypted_data")) {
            // String encryptedData = originalData.get("encrypted_data");
            String decryptedDataString = originalData.get("encrypted_data");

            try {
                // Parse the decrypted JSON string into a Map
                Map<String, String> decryptedData = parseJsonToMap(decryptedDataString);

                // Create a new data map for the modified message
                Map<String, String> modifiedData = new HashMap<>(originalData);

                // Remove 'encrypted_data' if desired
                modifiedData.remove("encrypted_data");

                // Add the decrypted data to the modified data map
                modifiedData.putAll(decryptedData);

                // Build a new RemoteMessage with the modified data
                RemoteMessage.Builder builder = new RemoteMessage.Builder(remoteMessage.getFrom())
                        .setMessageId(remoteMessage.getMessageId())
                        .setData(modifiedData)
                        .setTtl(remoteMessage.getTtl());

                if (remoteMessage.getCollapseKey() != null) {
                    builder.setCollapseKey(remoteMessage.getCollapseKey());
                }

                RemoteMessage newMessage = builder.build();

                // Pass the new message to Expo's handler
                super.onMessageReceived(newMessage);

            } catch (Exception e) {
                // Handle exceptions during decryption or JSON parsing
                Log.e(TAG, "Failed to decrypt or parse encrypted data", e);

                // You can choose to pass the original message or handle it differently
                super.onMessageReceived(remoteMessage);
            }
        } else {
            // If 'encrypted_data' is not present, pass the original message
            super.onMessageReceived(remoteMessage);
        }
    }

    // Method to parse the decrypted JSON string into a Map<String, String>
    private Map<String, String> parseJsonToMap(String jsonString) throws JSONException {
        Map<String, String> dataMap = new HashMap<>();
        JSONObject jsonObject = new JSONObject(jsonString);

        Iterator<String> keys = jsonObject.keys();

        while (keys.hasNext()) {
            String key = keys.next();
            String value = jsonObject.getString(key);
            dataMap.put(key, value);
        }

        return dataMap;
    }
}