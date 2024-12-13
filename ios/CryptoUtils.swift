import Foundation
import Security
import CryptoKit

public final class CryptoUtils {
    private static let keyTag = "com.teamtailor.app.cryptoutils.rsa"
    private static let keychainGroup = "group.com.teamtailor.keys"
    
    public enum CryptoError: Error {
        case keyGenerationFailed(String)
        case keychainAccessFailed(String)
        case publicKeyExtractionFailed
        case privateKeyNotFound
        case invalidBase64Input
        case rsaDecryptionFailed
        case invalidAESKey
        case aesDecryptionFailed
        case rsaEncryptionFailed
    }
    
    private static func generateKeyPair(tag: Data) throws -> SecKey {
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, // This means that the key is only accessible after the device has been unlocked once. So if we get notifications before that, then we will show fallback gdpr compliant message. Any other option are more restrictive. 
            [],
            nil
        ) else {
            throw CryptoError.keyGenerationFailed("Failed to create access control")
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessGroup as String: keychainGroup,
                kSecAttrAccessControl as String: access
            ]
        ]
        
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else {
            throw CryptoError.keyGenerationFailed("Failed to generate key pair")
        }
        
        return privateKey
    }

    private static func getPrivateKey() throws -> SecKey {
        let tag = keyTag.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrApplicationTag as String: tag,
            kSecReturnRef as String: true,
            kSecAttrAccessGroup as String: keychainGroup
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess {
            return item as! SecKey
        }

        if status == errSecItemNotFound {
            return try generateKeyPair(tag: tag)
        }

        let error = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
        NSLog("CryptoUtils: Keychain access failed with error: \(error)")
        throw CryptoError.keychainAccessFailed(error)
    }

    public static func getPublicKey() throws -> String {
        let privateKey = try getPrivateKey()
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CryptoError.publicKeyExtractionFailed
        }
        
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw CryptoError.publicKeyExtractionFailed
        }
        
        return publicKeyData.base64EncodedString()
    }
    
    public static func rsaDecrypt(encryptedBase64: String) throws -> Data {
        guard let cipherData = Data(base64Encoded: encryptedBase64) else {
            throw CryptoError.invalidBase64Input
        }
        
        let privateKey = try getPrivateKey()
        
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(privateKey,
                                                          .rsaEncryptionOAEPSHA1,
                                                          cipherData as CFData,
                                                          &error) as Data? else {
            if let error = error?.takeRetainedValue() {
                NSLog("RSA Decrypt: Failed with error: \(error)")
            }
            throw CryptoError.rsaDecryptionFailed
        }
        
        return decryptedData
    }
    
    public static func rsaEncrypt(data: Data) throws -> String {
        let privateKey = try getPrivateKey()
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CryptoError.privateKeyNotFound
        }
        
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA1,
            data as CFData,
            &error
        ) as Data? else {
            if let error = error?.takeRetainedValue() {
                NSLog("RSA Encrypt: Failed with error: \(error)")
            }
            throw CryptoError.rsaEncryptionFailed
        }
        
        return encryptedData.base64EncodedString()
    }
    
    public static func hybridDecrypt(
        encryptedKey: String,
        cipherText: String,
        nonce: String,
        tag: String
    ) throws -> String {
        let aesKeyData = try rsaDecrypt(encryptedBase64: encryptedKey)

        guard let cipherData = Data(base64Encoded: cipherText),
              let nonceData = Data(base64Encoded: nonce),
              let tagData = Data(base64Encoded: tag) else {
            throw CryptoError.invalidBase64Input
        }
        
        guard let aeadNonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw CryptoError.invalidBase64Input
        }
        
        let symmetricKey = SymmetricKey(data: aesKeyData)
        do {
            let sealedBox = try AES.GCM.SealedBox(
                nonce: aeadNonce,
                ciphertext: cipherData,
                tag: tagData
            )
            
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
            
            guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
                throw CryptoError.aesDecryptionFailed
            }
            
            return decryptedString
            
        } catch {
            NSLog("AES Decryption failed: \(error)")
            throw CryptoError.aesDecryptionFailed
        }
    }
    
    public static func deleteKeyPair() {
        let tag = keyTag.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrAccessGroup as String: keychainGroup
        ]
        SecItemDelete(query as CFDictionary)
    }

    public static func testEncryption(message: String) throws -> Bool {
        guard let messageData = message.data(using: .utf8) else {
            throw CryptoError.invalidBase64Input
        }
        
        let encrypted = try rsaEncrypt(data: messageData)
        let decryptedData = try rsaDecrypt(encryptedBase64: encrypted)
        
        guard let decryptedMessage = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoError.rsaDecryptionFailed
        }
        
        return message == decryptedMessage
    }
}