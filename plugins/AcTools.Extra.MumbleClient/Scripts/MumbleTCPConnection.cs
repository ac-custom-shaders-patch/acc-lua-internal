using System;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography.X509Certificates;
using MumbleProto;
using UnityEngine;
using ProtoBuf;
using System.Timers;
using System.Threading;
using AcTools.Extra.MumbleClient.Implementation;
using Version = MumbleProto.Version;

namespace Mumble {
    public class MumbleTcpConnection {
        private readonly UpdateOcbServerNonce _updateOcbServerNonce;
        private readonly IPEndPoint _host;
        private readonly string _hostname;
        private readonly MumbleClient _mumbleClient;
        private readonly TcpClient _tcpClient;
        private readonly MumbleUdpConnection _udpConnection;
        private BinaryReader _reader;
        private SslStream _ssl;
        private bool _validConnection;
        private BinaryWriter _writer;
        private bool _running; // Used to signal threads to shut down safely
        private System.Timers.Timer _tcpTimer;
        private Thread _processThread;
        private string _username;
        private string _password;

        internal MumbleTcpConnection(IPEndPoint host, string hostname, UpdateOcbServerNonce updateOcbServerNonce,
                MumbleUdpConnection udpConnection, MumbleClient mumbleClient) {
            _host = host;
            _hostname = hostname;
            _mumbleClient = mumbleClient;
            _udpConnection = udpConnection;
            _tcpClient = new TcpClient();
            _updateOcbServerNonce = updateOcbServerNonce;

            // Set thread as running before starting
            _running = true;
            _processThread = new Thread(ProcessTcpData) { IsBackground = true };
        }

        internal void StartClient(string username, string password) {
            _username = username;
            _password = password;
            _tcpClient.BeginConnect(_host.Address, _host.Port, OnTcpConnected, null);
        }

        private void OnTcpConnected(IAsyncResult connectionResult) {
            if (!_tcpClient.Connected) {
                Debug.LogError("Connection failed! Please confirm that you have internet access, and that the hostname is correct");
                Environment.Exit(ExitCode.FailedToConnect);
            }

            try {
                var networkStream = _tcpClient.GetStream();
                _ssl = new SslStream(networkStream, false, ValidateCertificate);
                _ssl.AuthenticateAsClient(_hostname);
                _reader = new BinaryReader(_ssl);
                _writer = new BinaryWriter(_ssl);

                var startWait = DateTime.Now;
                while (!_ssl.IsAuthenticated) {
                    if (DateTime.Now - startWait > TimeSpan.FromSeconds(2)) {
                        Debug.LogError("Time out waiting for SSL authentication");
                        Environment.Exit(ExitCode.FailedToConnect);
                    }
                }
                SendVersion();
                StartPingTimer();
            } catch (Exception e) {
                Debug.LogError($"Connection failed: {e}");
                if (e.InnerException is SocketException socketException) {
                    if (socketException.NativeErrorCode == 10053) {
                        Environment.Exit(ExitCode.HostRejected);
                    }
                }
                
                Environment.Exit(ExitCode.FailedToConnect);
            }
        }

        private void SendVersion() {
            SendMessage(MessageType.Version, new Version {
                Release = MumbleClient.ReleaseName,
                version = (MumbleClient.Major << 16) | (MumbleClient.Minor << 8) | (MumbleClient.Patch),
                Os = Environment.OSVersion.ToString(),
                OsVersion = Environment.OSVersion.VersionString,
            });
        }

        private void StartPingTimer() {
            // If the Mumble server doesn't get a message for 30 seconds it will close the connection
            _tcpTimer = new System.Timers.Timer(MumbleConstants.PING_INTERVAL_MS);
            _tcpTimer.Elapsed += SendPing;
            _tcpTimer.Enabled = true;
            _processThread.Start();
        }

        internal void SendMessage<T>(MessageType mt, T message) {
            lock (_ssl) {
                var messageType = (short)mt;

                // UDP Tunnels have their own way in which they handle serialization
                if (mt == MessageType.UDPTunnel) {
                    if (message is UDPTunnel udpTunnel) {
                        var messageSize = udpTunnel.Packet.Length;
                        _writer.Write(IPAddress.HostToNetworkOrder(messageType));
                        _writer.Write(IPAddress.HostToNetworkOrder(messageSize));
                        _writer.Write(udpTunnel.Packet);
                    }
                } else {
                    using (var messageStream = new MemoryStream(64)) {
                        Serializer.NonGeneric.Serialize(messageStream, message);
                        var messageSize = (int)messageStream.Length;
                        _writer.Write(IPAddress.HostToNetworkOrder(messageType));
                        _writer.Write(IPAddress.HostToNetworkOrder(messageSize));
                        _writer.Write(messageStream.GetBuffer(), 0, (int)messageStream.Position);
                    }
                }

                _writer.Flush();
            }
        }

        private bool ValidateCertificate(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors errors) {
            // TODO: Implement actual certificate validation
            return true;
        }

        private void ProcessTcpData() {
            while (_running) {
                try {
                    var messageType = (MessageType)IPAddress.NetworkToHostOrder(_reader.ReadInt16());
                    switch (messageType) {
                        case MessageType.Version:
                            Serializer.DeserializeWithLengthPrefix<Version>(_ssl, PrefixStyle.Fixed32BigEndian);
                            SendMessage(MessageType.Authenticate, new Authenticate {
                                Username = _username,
                                Password = _password,
                                Opus = true
                            });
                            break;
                        case MessageType.CryptSetup:
                            ProcessCryptSetup(Serializer.DeserializeWithLengthPrefix<CryptSetup>(_ssl,
                                    PrefixStyle.Fixed32BigEndian));
                            break;
                        case MessageType.CodecVersion:
                            Serializer.DeserializeWithLengthPrefix<CodecVersion>(_ssl,
                                    PrefixStyle.Fixed32BigEndian);
                            break;
                        case MessageType.ChannelState:
                            _mumbleClient.AddChannel(Serializer.DeserializeWithLengthPrefix<ChannelState>(_ssl, PrefixStyle.Fixed32BigEndian));
                            break;
                        case MessageType.PermissionQuery:
                            Serializer.DeserializeWithLengthPrefix<PermissionQuery>(_ssl, PrefixStyle.Fixed32BigEndian);
                            break;
                        case MessageType.UserState:
                            // This is called for every user in the room, including us
                            _mumbleClient.AddOrUpdateUser(Serializer.DeserializeWithLengthPrefix<UserState>(_ssl, PrefixStyle.Fixed32BigEndian));
                            break;
                        case MessageType.ServerSync:
                            // This is where we get our session Id
                            _mumbleClient.SetServerSync(Serializer.DeserializeWithLengthPrefix<ServerSync>(_ssl, PrefixStyle.Fixed32BigEndian));
                            break;
                        case MessageType.ServerConfig:
                            Debug.Log("Mumble is connected");
                            Serializer.DeserializeWithLengthPrefix<ServerConfig>(_ssl, PrefixStyle.Fixed32BigEndian);
                            _validConnection = true;
                            break;
                        case MessageType.SuggestConfig:
                            // Contains suggested configuratio options from the server like whether to send positional data, client version, etc.
                            Serializer.DeserializeWithLengthPrefix<SuggestConfig>(_ssl, PrefixStyle.Fixed32BigEndian);
                            break;
                        case MessageType.TextMessage:
                            var textMessage = Serializer.DeserializeWithLengthPrefix<TextMessage>(_ssl, PrefixStyle.Fixed32BigEndian);
                            Debug.Log("Text message = " + textMessage.Message);
                            Debug.Log("Text actor = " + textMessage.Actor);
                            break;
                        case MessageType.UDPTunnel:
                            var length = IPAddress.NetworkToHostOrder(_reader.ReadInt32());
                            var data = _reader.ReadBytes(length);
                            // At this point the message is already decrypted
                            _udpConnection.UnpackOpusVoicePacket(data, data.Length, false);
                            break;
                        case MessageType.Ping:
                            Serializer.DeserializeWithLengthPrefix<Ping>(_ssl, PrefixStyle.Fixed32BigEndian);
                            break;
                        case MessageType.Reject:
                            // This is called, for example, when the max number of users has been hit
                            var reject = Serializer.DeserializeWithLengthPrefix<Reject>(_ssl, PrefixStyle.Fixed32BigEndian);
                            _validConnection = false;
                            _mumbleClient.OnConnectionDisconnect(reject.Reason);
                            return;
                        case MessageType.UserRemove:
                            var removal = Serializer.DeserializeWithLengthPrefix<UserRemove>(_ssl, PrefixStyle.Fixed32BigEndian);
                            Debug.Log("Removing " + removal.Session);
                            _mumbleClient.RemoveUser(removal.Session);
                            break;
                        case MessageType.ChannelRemove:
                            var removedChan = Serializer.DeserializeWithLengthPrefix<ChannelRemove>(_ssl, PrefixStyle.Fixed32BigEndian);
                            _mumbleClient.RemoveChannel(removedChan.ChannelId);
                            Debug.Log("Removing channel " + removedChan.ChannelId);
                            break;
                        case MessageType.PermissionDenied:
                            var denial = Serializer.DeserializeWithLengthPrefix<PermissionDenied>(_ssl, PrefixStyle.Fixed32BigEndian);
                            if (denial.Type == PermissionDenied.DenyType.ChannelFull) {
                                Debug.LogResponse("channel is full");
                            } else {
                                var ret = $"permission denied: {denial.Type}";
                                if (!string.IsNullOrWhiteSpace(denial.Name)) ret += $", name: {denial.Name}";
                                if (!string.IsNullOrWhiteSpace(denial.Reason)) ret += $", name: {denial.Reason}";
                                Debug.LogResponse(ret);
                            }
                            break;
                        default:
                            Debug.LogError("Message type " + messageType + " not implemented");
                            break;
                    }
                } catch (Exception ex) {
                    switch (ex) {
                        // This happens when we connect again with the same username
                        case EndOfStreamException _:
                            _mumbleClient.OnConnectionDisconnect(ex.ToString());
                            break;
                        case IOException _:
                            _mumbleClient.OnConnectionDisconnect(ex.ToString());
                            break;
                        // These just means the app stopped, it's ok
                        case ObjectDisposedException _:
                        case ThreadAbortException _:
                            break;
                        default:
                            Debug.LogError("Unhandled error: " + ex);
                            break;
                    }
                    return;
                }
            }
        }

        private void ProcessCryptSetup(CryptSetup cryptSetup) {
            if (cryptSetup.Key != null && cryptSetup.ClientNonce != null && cryptSetup.ServerNonce != null) {
                // Apply the key and client/server nonce values provided
                _mumbleClient.CryptSetup = cryptSetup;
                _mumbleClient.ConnectUdp();
            } else if (cryptSetup.ServerNonce != null) {
                Debug.Log("Updating server nonce");
                _updateOcbServerNonce(cryptSetup.ServerNonce);
            } else {
                // This generally means that the server is requesting our nonce
                SendMessage(MessageType.CryptSetup, new CryptSetup { ClientNonce = _mumbleClient.GetLatestClientNonce() });
            }
        }

        internal void Close() {
            // Signal thread that it's time to shut down
            _running = false;

            _ssl?.Close();
            _ssl = null;
            _tcpTimer?.Close();
            _tcpTimer = null;
            _processThread?.Interrupt();
            _processThread = null;
            _reader?.Close();
            _reader = null;
            _writer?.Close();
            _writer = null;
            _tcpClient?.Close();
        }

        private void SendPing(object sender, ElapsedEventArgs elapsedEventArgs) {
            if (_validConnection) {
                SendMessage(MessageType.Ping, new Ping {
                    Timestamp = (ulong)(DateTime.UtcNow.Ticks - MumbleUdpConnection.DateTimeBase)
                });
            }
        }
    }
}