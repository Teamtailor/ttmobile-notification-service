export interface EncryptionInterface {
    getPublicKey(): string;
    hybridDecrypt(encryptedKey: string, cipherText: string, nonce: string, tag: string): string;
    deleteKeyPair(): void;
    testEncryption(message: string): boolean;
    rsaDecrypt(encryptedBase64: string): string;
}
declare const _default: EncryptionInterface;
export default _default;
//# sourceMappingURL=index.d.ts.map