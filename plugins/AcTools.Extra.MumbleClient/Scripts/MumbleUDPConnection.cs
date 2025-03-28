using System;
using System.Net;
using System.Net.Sockets;
using System.Timers;
using UnityEngine;
using MumbleProto;
using System.Threading;

namespace Mumble {
    public class MumbleUdpConnection {
        private const int MaxUDPSize = 0x10000;
        private readonly byte[] _recvBuffer = new byte[MaxUDPSize];
        private readonly IPEndPoint _host;
        private readonly UdpClient _udpClient;
        private readonly MumbleClient _mumbleClient;
        private readonly AudioDecodeThread _audioDecodeThread;
        private readonly object _sendLock = new object();
        private MumbleTcpConnection _tcpConnection;
        private CryptState _cryptState;
        private System.Timers.Timer _udpTimer;
        private bool _isConnected;
        private bool _useTcp;

        // These are used for switching to TCP audio and back. Don't rely on them for anything else
        private bool _running; // This is to signal threads to shut down safely
        private bool _qos;
        private int _numPingsOutstanding;
        private Thread _receiveThread;

        internal MumbleUdpConnection(IPEndPoint host, AudioDecodeThread audioDecodeThread, MumbleClient mumbleClient) {
            _host = host;
            _udpClient = new UdpClient();
            if (Environment.GetEnvironmentVariable("ACCSP_PREFERRED_ADAPTER_IP") is string ip) {
                try {
                    _udpClient.Client.Bind(new IPEndPoint(IPAddress.Parse(ip), 0));
                } catch (Exception e) { 
                    Debug.LogError($"Failed to bind UDP socket to {ip}: {e.Message}");
                }
            }
            _audioDecodeThread = audioDecodeThread;
            _mumbleClient = mumbleClient;
        }

        public bool TcpOnly;

        public bool UseQos {
            get => _qos;
            set {
                if (_qos == value) return;
                _qos = value;
                if (_cryptState != null) {
                    SetQos();
                }
            }
        }

        internal void SetTcpConnection(MumbleTcpConnection tcpConnection) {
            _tcpConnection = tcpConnection;
        }

        internal void UpdateOcbServerNonce(byte[] serverNonce) {
            if (serverNonce != null) _cryptState.CryptSetup.ServerNonce = serverNonce;
        }

        private void SetQos() {
            try {
                _udpClient.Client.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.TypeOfService, _qos ? 46 : 0);
                Debug.Log("QOS set: " + (_qos ? 46 : 0));
            } catch (Exception e) {
                Debug.LogWarning("Failed to specify QOS: " + e);
            }
        }

        internal void Connect() {
            _cryptState = new CryptState { CryptSetup = _mumbleClient.CryptSetup };
            _udpClient.Connect(_host);

            // I believe that I need to enable DontFragment in order to make
            // sure that all packets received are received as discreet datagrams
            _udpClient.DontFragment = true;
            if (_qos) {
                SetQos();
            }

            _isConnected = true;

            _udpTimer = new System.Timers.Timer(MumbleConstants.PING_INTERVAL_MS);
            _udpTimer.Elapsed += RunPing;
            _udpTimer.Enabled = true;

            SendPing();

            // Before starting our thread, set running to true
            _running = true;
            _receiveThread = new Thread(ReceiveUDP) { IsBackground = true };
            _receiveThread.Start();
        }

        private void RunPing(object sender, ElapsedEventArgs elapsedEventArgs) {
            if (TcpOnly) return;
            SendPing();
        }

        private void ReceiveUDP() {
            var prevPacketSize = 0;
            var endPoint = (EndPoint)_host;
            while (_running) {
                try {
                    // This should only happen on exit
                    if (_udpClient == null) return;

                    // We receive the data into a pre-allocated buffer to avoid needless allocations
                    var readLen = _udpClient.Client.ReceiveFrom(_recvBuffer, ref endPoint);
                    if (!ProcessUdpMessage(_recvBuffer, readLen)) {
                        Debug.LogError("Failed decrypt of: " + readLen + " bytes. exclusive: "
                                + _udpClient.ExclusiveAddressUse
                                + " ttl:" + _udpClient.Ttl
                                + " avail: " + _udpClient.Available
                                + " prev pkt size:" + prevPacketSize);
                    }
                    prevPacketSize = readLen;
                } catch (Exception ex) {
                    switch (ex) {
                        case ObjectDisposedException _:
                        case ThreadAbortException _:
                            return;
                        default:
                            Debug.LogError("Unhandled UDP receive error: " + ex);
                            break;
                    }
                }
            }
        }

        private bool ProcessUdpMessage(byte[] encrypted, int len) {
            // TODO: Sometimes this fails and I have no idea why
            var message = _cryptState.Decrypt(encrypted, len, out var dataLength);
            if (message == null) return false;

            // Figure out type of message
            var type = (message[0] >>  5) & 0x7;

            // If we get an OPUS audio packet, de-encode it
            switch ((UDPType)type) {
                case UDPType.Opus:
                    UnpackOpusVoicePacket(message, dataLength, false);
                    break;
                case UDPType.Ping:
                    OnPing();
                    break;
                default:
                    Debug.LogError("Not implemented: " + ((UDPType)type) + " #" + type);
                    CryptState.ReleaseDecryptedData(message);
                    return false;
            }
            CryptState.ReleaseDecryptedData(message);
            return true;
        }

        private void OnPing() {
            _numPingsOutstanding = 0;
            /*if (_useTcp) {
                Debug.Log("Switching back to UDP");
                _useTcp = false;
            }*/
        }

        private static readonly byte[] EmptyArray = new byte[0];

        internal void UnpackOpusVoicePacket(byte[] data, int dataLength, bool isLoopback) {
            var pos = 1;
            var session = isLoopback ? _mumbleClient.OurUserState.Session : (uint)UdpPacketReader.ReadVarInt64(data, ref pos);
            var sequence = UdpPacketReader.ReadVarInt64(data, ref pos);

            // We assume we mean OPUS
            var size = (int)UdpPacketReader.ReadVarInt64(data, ref pos);
            var isLast = (size & 8192) == 8192;
            if (isLast) {
                Debug.Log("Found last byte in seq");
            }

            // Apply a bitmask to remove the bit that marks if this is the last packet
            size &= 0x1fff;

            if (pos + size > dataLength) {
                Debug.LogWarning($"Data is damaged: expected {pos + size} bytes, got {dataLength} bytes");
                return;
            }

            _audioDecodeThread.AddCompressedAudio(session, size != 0 ? UdpPacketReader.GetOpusVoiceData(data, ref pos, size) : EmptyArray,
                    size, UdpPacketReader.ReadVec3(data, dataLength, ref pos), sequence, isLast);
        }

        private readonly byte[] _sendPingBuffer = new byte[9];

        public static readonly long DateTimeBase = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).Ticks;

        private unsafe void SendPing() {
            if (!_isConnected) {
                Debug.LogError("Not yet connected");
                return;
            }

            if (!_useTcp && _numPingsOutstanding >= MumbleConstants.MAX_CONSECUTIVE_MISSED_UDP_PINGS) {
                Debug.LogWarning("Error establishing UDP connection, will switch to TCP");
                _useTcp = true;
                return;
            }

            var unixTimeStamp = (ulong)(DateTime.UtcNow.Ticks - DateTimeBase);
            fixed (byte* data = _sendPingBuffer) {
                *(ulong*)&data[1] = unixTimeStamp;
            }
            _sendPingBuffer[0] = 1 << 5;
            var encryptedData = _cryptState.Encrypt(_sendPingBuffer, 9);
            
            _numPingsOutstanding++;
            lock (_sendLock) {
                _udpClient.Send(encryptedData, encryptedData.Length);
            }
        }

        internal void Close() {
            // Signal thread that it’s time to shut down
            _running = false;
            _receiveThread?.Interrupt();
            _udpTimer?.Close();
            _udpClient.Close();
        }

        internal void SendVoicePacket(byte[] voicePacket, int size) {
            if (!_isConnected) {
                Debug.LogError("Not yet connected");
                return;
            }
            try {
                if (_useTcp || TcpOnly) {
                    if (size != voicePacket.Length) {
                        var slicedVicePacket = new byte[size];
                        Array.Copy(voicePacket, 0, slicedVicePacket, 0, size);
                        voicePacket = slicedVicePacket;
                    }
                    _tcpConnection.SendMessage(MessageType.UDPTunnel, new UDPTunnel { Packet = voicePacket });
                } else {
                    var encrypted = _cryptState.Encrypt(voicePacket, size);
                    lock (_sendLock) {
                        _udpClient.Send(encrypted, encrypted.Length);
                    }
                }
            } catch (Exception e) {
                Debug.LogError("Error sending packet: " + e);
            }
        }

        internal byte[] GetLatestClientNonce() {
            return _cryptState.CryptSetup.ClientNonce;
        }
    }
}