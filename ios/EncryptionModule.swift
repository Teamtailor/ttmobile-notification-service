import ExpoModulesCore

final public class EncryptionModule: Module {
    private func mapError(_ error: Error) -> Error {
        guard let cryptoError = error as? CryptoUtils.CryptoError else {
            return error
        }
        
        switch cryptoError {
        case .keyGenerationFailed(let message):
            return NSError(domain: "EncryptionModule", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "Key generation failed: \(message)"
            ])
        case .keychainAccessFailed(let message):
            return NSError(domain: "EncryptionModule", code: 1002, userInfo: [
                NSLocalizedDescriptionKey: "Keychain access failed: \(message)"
            ])
        case .publicKeyExtractionFailed:
            return NSError(domain: "EncryptionModule", code: 1003, userInfo: [
                NSLocalizedDescriptionKey: "Failed to extract public key"
            ])
        case .privateKeyNotFound:
            return NSError(domain: "EncryptionModule", code: 1004, userInfo: [
                NSLocalizedDescriptionKey: "Private key not found"
            ])
        case .invalidBase64Input:
            return NSError(domain: "EncryptionModule", code: 1005, userInfo: [
                NSLocalizedDescriptionKey: "Invalid base64 input"
            ])
        case .rsaDecryptionFailed:
            return NSError(domain: "EncryptionModule", code: 1006, userInfo: [
                NSLocalizedDescriptionKey: "RSA decryption failed"
            ])
        case .invalidAESKey:
            return NSError(domain: "EncryptionModule", code: 1008, userInfo: [
                NSLocalizedDescriptionKey: "Invalid AES key"
            ])
        case .aesDecryptionFailed:
            return NSError(domain: "EncryptionModule", code: 1009, userInfo: [
                NSLocalizedDescriptionKey: "AES decryption failed"
            ])
        case .rsaEncryptionFailed:
            return NSError(domain: "EncryptionModule", code: 1010, userInfo: [
                NSLocalizedDescriptionKey: "RSA encryption failed"
            ])
        }
    }
    
    public func definition() -> ModuleDefinition {
        Name("EncryptionModule")
        
        Function("getPublicKey") { () throws -> String in
            do {
                let result = try CryptoUtils.getPublicKey()
                return result
            } catch {
                NSLog("EncryptionModule: Function failed with error: \(error)")
                throw mapError(error)
            }
        }
        
        Function("hybridDecrypt") { (
            encryptedKey: String,
            cipherText: String,
            nonce: String,
            tag: String
        ) throws -> String in
            do {
                let result = try CryptoUtils.hybridDecrypt(
                    encryptedKey: encryptedKey,
                    cipherText: cipherText,
                    nonce: nonce,
                    tag: tag
                )
                return result
            } catch {
                NSLog("EncryptionModule: Function failed with error: \(error)")
                throw mapError(error)
            }
        }
        
        Function("deleteKeyPair") {
            CryptoUtils.deleteKeyPair()
        }
        
        Function("testEncryption") { (message: String) throws -> Bool in
            do {
                let result = try CryptoUtils.testEncryption(message: message)
                return result
            } catch {
                NSLog("EncryptionModule: Function failed with error: \(error)")
                throw mapError(error)
            }
        }
        
        Function("rsaDecrypt") { (encryptedBase64: String) throws -> String in
            do {
                let decryptedData = try CryptoUtils.rsaDecrypt(encryptedBase64: encryptedBase64)
                guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
                    throw CryptoUtils.CryptoError.rsaDecryptionFailed
                }
                return decryptedString
            } catch {
                NSLog("EncryptionModule: Function failed with error: \(error)")
                throw mapError(error)
            }
        }
    }
}