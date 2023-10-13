using System;
using System.Security.Cryptography;
using AcTools.Extra.MumbleClient.Implementation.Utils;
using MumbleProto;
using UnityEngine;

namespace Mumble {
    public class CryptState {
        const int AesBlockSize = 16;
        private readonly byte[] _decryptHistory = new byte[256];

        private CryptSetup _cryptSetup;
        private ICryptoTransform _decryptor;
        private ICryptoTransform _encryptor;

        /// <summary>
        /// In principal, I don't believe a lock is really
        /// needed here, presuming that decryption / encryption
        /// are handled in their own threads.
        /// However, interacting with this script from multiple
        /// threads seems to cause decode issues, specifically
        /// Crypt 4 errors. My current belief is that under the
        /// hood, Mono has special restrictions on AesManaged
        /// for security, that end up causing issues with
        /// threading. It may make sense to re-evaluate the
        /// need for this lock with later versions of Unity.
        /// This was last validated with Unity 2017.4.1
        /// </summary>
        private static readonly object CryptLock = new object();

        // Used by Encrypt
        private readonly byte[] _encTag = new byte[AesBlockSize];

        // Used by OCB Encrypt
        private readonly byte[] _encChecksum = new byte[AesBlockSize];
        private readonly byte[] _encTmp = new byte[AesBlockSize];
        private readonly byte[] _encDelta = new byte[AesBlockSize];
        private readonly byte[] _encPad = new byte[AesBlockSize];

        // Used by Decrypt
        private readonly byte[] _decSaveiv = new byte[AesBlockSize];
        private readonly byte[] _decTag = new byte[AesBlockSize];
        
        // Used by OCB Decrypt
        private readonly byte[] _decChecksum = new byte[AesBlockSize];
        private readonly byte[] _decTmp = new byte[AesBlockSize];
        private readonly byte[] _decDelta = new byte[AesBlockSize];
        private readonly byte[] _decPad = new byte[AesBlockSize];

        public CryptSetup CryptSetup {
            get => _cryptSetup;
            set {
                lock (CryptLock) {
                    _cryptSetup = value;
                    var aesAlg = new AesManaged {
                        BlockSize = AesBlockSize * 8,
                        Key = _cryptSetup.Key,
                        Mode = CipherMode.ECB,
                        Padding = PaddingMode.None
                    };
                    _encryptor = aesAlg.CreateEncryptor();
                    _decryptor = aesAlg.CreateDecryptor();
                }
            }
        }

        private void S2(byte[] block) {
            int carry = (block[0] >>  7) & 0x1;
            for (int i = 0; i < AesBlockSize - 1; i++) {
                block[i] = (byte)((block[i] << 1) | ((block[i + 1] >>  7) & 0x1));
            }
            block[AesBlockSize - 1] = (byte)((block[AesBlockSize - 1] << 1) ^ (carry * 0x87));
        }

        private void S3(byte[] block) {
            int carry = (block[0] >>  7) & 0x1;
            for (int i = 0; i < AesBlockSize - 1; i++) {
                block[i] ^= (byte)((block[i] << 1) | ((block[i + 1] >>  7) & 0x1));
            }
            block[AesBlockSize - 1] ^= (byte)((block[AesBlockSize - 1] << 1) ^ (carry * 0x87));
        }

        private void Xor(byte[] dst, byte[] a, byte[] b) {
            for (int i = 0; i < AesBlockSize; i++) {
                dst[i] = (byte)(a[i] ^ b[i]);
            }
        }

        private void Xor(byte[] dst, byte[] a, byte[] b, int dstOffset, int aOffset, int bOffset) {
            for (int i = 0; i < AesBlockSize; i++) {
                dst[dstOffset + i] = (byte)(a[aOffset + i] ^ b[bOffset + i]);
            }
        }

        private static void ZeroMemory(byte[] block) {
            Array.Clear(block, 0, block.Length);
        }

        // Buffer + amount of useful bytes in buffer
        public byte[] Encrypt(byte[] inBytes, int length) {
            var dst = new byte[length + 4];

            lock (CryptLock) {
                for (int i = 0; i < AesBlockSize; i++) {
                    if (++_cryptSetup.ClientNonce[i] != 0)
                        break;
                }

                OcbEncrypt(inBytes, length, dst, _cryptSetup.ClientNonce, _encTag, 4);
                dst[0] = _cryptSetup.ClientNonce[0];
                dst[1] = _encTag[0];
                dst[2] = _encTag[1];
                dst[3] = _encTag[2];
            }

            return dst;
        }

        private void OcbEncrypt(byte[] plain, int plainLength, byte[] encrypted, byte[] nonce, byte[] tag, int encryptedOffset) {
            ZeroMemory(_encChecksum);
            _encryptor.TransformBlock(nonce, 0, AesBlockSize, _encDelta, 0);

            int offset = 0;
            int len = plainLength;
            while (len > AesBlockSize) {
                S2(_encDelta);
                Xor(_encChecksum, _encChecksum, plain, 0, 0, offset);
                Xor(_encTmp, _encDelta, plain, 0, 0, offset);

                _encryptor.TransformBlock(_encTmp, 0, AesBlockSize, _encTmp, 0);

                Xor(encrypted, _encDelta, _encTmp, offset + encryptedOffset, 0, 0);
                offset += AesBlockSize;
                len -= AesBlockSize;
            }

            S2(_encDelta);
            ZeroMemory(_encTmp);
            long num = len * 8;
            _encTmp[AesBlockSize - 2] = (byte)((num >>  8) & 0xFF);
            _encTmp[AesBlockSize - 1] = (byte)(num & 0xFF);
            Xor(_encTmp, _encTmp, _encDelta);

            _encryptor.TransformBlock(_encTmp, 0, AesBlockSize, _encPad, 0);

            Array.Copy(plain, offset, _encTmp, 0, len);
            Array.Copy(_encPad, len, _encTmp, len, AesBlockSize - len);

            Xor(_encChecksum, _encChecksum, _encTmp);
            Xor(_encTmp, _encPad, _encTmp);
            Array.Copy(_encTmp, 0, encrypted, offset + encryptedOffset, len);

            S3(_encDelta);
            Xor(_encTmp, _encDelta, _encChecksum);

            _encryptor.TransformBlock(_encTmp, 0, AesBlockSize, tag, 0);
        }

        private static readonly MemoryPool<byte> DecryptedData = new MemoryPool<byte>("Decrypted Data", 512, true);

        public static void ReleaseDecryptedData(byte[] data) {
            DecryptedData.Release(ref data);
        }
        
        public byte[] Decrypt(byte[] source, int length, out int dataLength) {
            if (length < 4) {
                Debug.LogError("Length less than 4, decryption failed");
                dataLength = 0;
                return null;
            }
            
            byte[] dst;
            lock (CryptLock) {
                var ivbyte = source[0];
                var restore = false;
                Array.Copy(_cryptSetup.ServerNonce, 0, _decSaveiv, 0, AesBlockSize);

                if (((_cryptSetup.ServerNonce[0] + 1) & 0xFF) == ivbyte) {
                    // In order as expected.
                    if (ivbyte > _cryptSetup.ServerNonce[0]) {
                        _cryptSetup.ServerNonce[0] = ivbyte;
                    } else if (ivbyte < _cryptSetup.ServerNonce[0]) {
                        _cryptSetup.ServerNonce[0] = ivbyte;
                        for (int i = 1; i < AesBlockSize; i++) {
                            if (++_cryptSetup.ServerNonce[i] != 0)
                                break;
                        }
                    } else {
                        Debug.LogError("Crypt: 1");
                        dataLength = 0;
                        return null;
                    }
                } else {
                    // This is either out of order or a repeat.
                    int diff = ivbyte - _cryptSetup.ServerNonce[0];
                    if (diff > 128) {
                        diff -= 256;
                    } else if (diff < -128) {
                        diff += 256;
                    }

                    if (ivbyte < _cryptSetup.ServerNonce[0] && diff > -30 && diff < 0) {
                        // Late packet, but no wraparound.
                        _cryptSetup.ServerNonce[0] = ivbyte;
                        restore = true;
                    } else if (ivbyte > _cryptSetup.ServerNonce[0] && diff > -30 &&
                            diff < 0) {
                        // Last was 0x02, here comes 0xff from last round
                        _cryptSetup.ServerNonce[0] = ivbyte;
                        for (int i = 1; i < AesBlockSize; i++) {
                            if (_cryptSetup.ServerNonce[i]-- != 0)
                                break;
                        }
                        restore = true;
                    } else if (ivbyte > _cryptSetup.ServerNonce[0] && diff > 0) {
                        // Lost a few packets, but beyond that we're good.
                        _cryptSetup.ServerNonce[0] = ivbyte;
                    } else if (ivbyte < _cryptSetup.ServerNonce[0] && diff > 0) {
                        // Lost a few packets, and wrapped around
                        _cryptSetup.ServerNonce[0] = ivbyte;
                        for (int i = 1; i < AesBlockSize; i++) {
                            if (++_cryptSetup.ServerNonce[i] != 0)
                                break;
                        }
                    } else {
                        // Happens if the packets arrive out of order
                        Debug.LogError("Crypt: 2");
                        dataLength = 0;
                        return null;
                    }

                    if (_decryptHistory[_cryptSetup.ServerNonce[0]] == _cryptSetup.ClientNonce[1]) {
                        Array.Copy(_decSaveiv, 0, _cryptSetup.ServerNonce, 0, AesBlockSize);
                        Debug.LogError("Crypt: 3");
                        dataLength = 0;
                        return null;
                    }
                }

                var plainLength = length - 4;
                dst = DecryptedData.GetOrAllocate(plainLength);
                dataLength = plainLength;
                OcbDecrypt(source, plainLength, dst, _cryptSetup.ServerNonce, _decTag, 4);

                if (_decTag[0] != source[1]
                        || _decTag[1] != source[2]
                        || _decTag[2] != source[3]) {
                    Array.Copy(_decSaveiv, 0, _cryptSetup.ServerNonce, 0, AesBlockSize);
                    Debug.LogError("Crypt: 4");
                    //Debug.LogError("Crypt: 4 good:" + _good + " lost: " + _lost + " late: " + _late);
                    DecryptedData.Release(ref dst);
                    dataLength = 0;
                    return null;
                }
                _decryptHistory[_cryptSetup.ServerNonce[0]] = _cryptSetup.ServerNonce[1];

                if (restore) {
                    //Debug.Log("Restoring");
                    Array.Copy(_decSaveiv, 0, _cryptSetup.ServerNonce, 0, AesBlockSize);
                }
            }

            return dst;
        }

        private void OcbDecrypt(byte[] encrypted, int len, byte[] plain, byte[] nonce, byte[] tag, int encryptedOffset) {
            ZeroMemory(_decChecksum);
            _encryptor.TransformBlock(nonce, 0, AesBlockSize, _decDelta, 0);

            var offset = 0;
            while (len > AesBlockSize) {
                S2(_decDelta);
                Xor(_decTmp, _decDelta, encrypted, 0, 0, offset + encryptedOffset);
                _decryptor.TransformBlock(_decTmp, 0, AesBlockSize, _decTmp, 0);

                Xor(plain, _decDelta, _decTmp, offset, 0, 0);
                Xor(_decChecksum, _decChecksum, plain, 0, 0, offset);

                len -= AesBlockSize;
                offset += AesBlockSize;
            }

            S2(_decDelta);
            ZeroMemory(_decTmp);

            long num = len * 8;
            _decTmp[AesBlockSize - 2] = (byte)((num >>  8) & 0xFF);
            _decTmp[AesBlockSize - 1] = (byte)(num & 0xFF);
            Xor(_decTmp, _decTmp, _decDelta);

            _encryptor.TransformBlock(_decTmp, 0, AesBlockSize, _decPad, 0);

            ZeroMemory(_decTmp);
            Array.Copy(encrypted, offset + encryptedOffset, _decTmp, 0, len);

            Xor(_decTmp, _decTmp, _decPad);
            Xor(_decChecksum, _decChecksum, _decTmp);

            Array.Copy(_decTmp, 0, plain, offset, len);

            S3(_decDelta);
            Xor(_decTmp, _decDelta, _decChecksum);
            _encryptor.TransformBlock(_decTmp, 0, AesBlockSize, tag, 0);
        }
    }
}