import { requireNativeModule } from 'expo-modules-core';

const EncryptionModule = requireNativeModule('EncryptionModule');

export interface EncryptionInterface {
  getPublicKey(): string;
  hybridDecrypt(
    encryptedKey: string,
    cipherText: string,
    nonce: string,
    tag: string
  ): string;
  deleteKeyPair(): void;
  testEncryption(message: string): boolean;
  rsaDecrypt(encryptedBase64: string): string;
}

export default EncryptionModule as EncryptionInterface;