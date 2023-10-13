using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Net;
using System.Threading;
using AcTools.Extra.MumbleClient.Implementation;
using AcTools.Extra.MumbleClient.Implementation.Utils;
using MumbleProto;
using UnityEngine;

namespace Mumble {
    public delegate void UpdateOcbServerNonce(byte[] cryptSetup);

    public class MumbleClient {
        public bool ConnectionSetupFinished;
        public MumbleMicrophone Mic;

        public readonly MumbleTcpConnection TcpConnection;
        public readonly MumbleUdpConnection UdpConnection;
        public readonly AudioDecodeThread AudioDecodeThread;
        public readonly ManageAudioSendBuffer ManageSendBuffer;
        
        public event Action<uint, UserState, UserState> UserStateChange;
        public event Action ChannelStateChange;

        private string _pendingChannel;
        private bool? _pendingMute;
        private byte[] _pendingContext;
        private string _pendingPluginIdentity;
        private string _pendingComment;
        private byte[] _pendingTexture;

        private readonly List<UserState> _allUsersList = new List<UserState>(256);
        private readonly Dictionary<uint, UserState> _allUsersDict = new Dictionary<uint, UserState>();
        private readonly Dictionary<uint, Channel> _channels = new Dictionary<uint, Channel>();

        internal UserState OurUserState;
        internal CryptSetup CryptSetup;
        private ServerSync _serverSync;

        // The Mumble version of this integration
        public static string ReleaseName = "AcTools.Extra.MumbleClient";
        public const uint Major = 1;
        public const uint Minor = 4;
        public const uint Patch = 0;

        public MumbleClient(string hostName, int port) {
            hostName = string.Equals(hostName, "localhost", StringComparison.OrdinalIgnoreCase) ? "127.0.0.1" : hostName;
            var endpoint = new IPEndPoint(GetAddress(hostName), port);
            AudioDecodeThread = new AudioDecodeThread();
            Debug.Log($"Connecting to {endpoint} ({hostName})");
            UdpConnection = new MumbleUdpConnection(endpoint, AudioDecodeThread, this);
            TcpConnection = new MumbleTcpConnection(endpoint, hostName, UdpConnection.UpdateOcbServerNonce, UdpConnection, this);
            UdpConnection.SetTcpConnection(TcpConnection);
            ManageSendBuffer = new ManageAudioSendBuffer(UdpConnection);
            Mic = new MumbleMicrophone(ManageSendBuffer);
        }

        private static IPAddress GetAddress(string hostName) {
            try {
                return IPAddress.Parse(hostName);
            } catch (Exception e) {
                Debug.Log($"Couldn’t parse as a basic IP: {hostName}, {e}");
                var addresses = Dns.GetHostAddresses(hostName);
                if (addresses.Length == 0) {
                    Debug.LogError("Failed to get addresses!");
                    Environment.Exit(ExitCode.FailedToFindAddress);
                }
                return addresses[0];
            }
        }

        private class Comparer : IComparer<UserState> {
            public static readonly Comparer Instance = new Comparer();

            public UserState OwnState;

            public int Compare(UserState x, UserState y) {
                // ReSharper disable MergeConditionalExpression
                var cx = x == OwnState ? int.MinValue : x == null ? int.MaxValue : x.AcUserID;
                var cy = y == OwnState ? int.MinValue : y == null ? int.MaxValue : y.AcUserID;
                return cx < cy ? -1 : cx > cy ? 1 : 0;
                // ReSharper restore MergeConditionalExpression
            }
        }

        internal void AddOrUpdateUser(UserState newUserState) {
            var isOurUser = OurUserState != null && newUserState.Session == OurUserState.Session;
            if (!_allUsersDict.TryGetValue(newUserState.Session, out var userState)) {
                //Debug.Log("New audio buffer with session: " + newUserState.Session + " name: " + newUserState.Name);
                Comparer.Instance.OwnState = OurUserState;
                _allUsersDict[newUserState.Session] = newUserState;
                _allUsersList.AddSorted(newUserState, Comparer.Instance);
                userState = newUserState;
            } else {
                // Copy over the things that have changed
                if (newUserState.ShouldSerializeActor()) userState.Actor = newUserState.Actor;
                if (newUserState.ShouldSerializeName()) userState.Name = newUserState.Name;
                if (newUserState.ShouldSerializeMute()) userState.Mute = newUserState.Mute;
                if (newUserState.ShouldSerializeDeaf()) userState.Deaf = newUserState.Deaf;
                if (newUserState.ShouldSerializeSuppress()) userState.Suppress = newUserState.Suppress;
                if (newUserState.ShouldSerializeSelfMute()) userState.SelfMute = newUserState.SelfMute;
                if (newUserState.ShouldSerializeSelfDeaf()) userState.SelfDeaf = newUserState.SelfDeaf;
                if (newUserState.ShouldSerializeComment()) userState.Comment = newUserState.Comment;
                if (newUserState.ShouldSerializeChannelId()) userState.ChannelId = newUserState.ChannelId;
                if (newUserState.ShouldSerializeTexture()) userState.Texture = newUserState.Texture;
                if (newUserState.ShouldSerializePluginContext()) userState.PluginContext = newUserState.PluginContext;
                if (newUserState.ShouldSerializePluginIdentity()) userState.PluginIdentity = newUserState.PluginIdentity;

                // If this is us, and it's signaling that we've changed channels, notify the delegate on the main thread
                if (isOurUser && newUserState.ShouldSerializeChannelId()) {
                    Debug.Log("Our channel changed to #" + newUserState.ChannelId);
                    // Re-evaluate all users to see if they need decoding buffers
                    ReevaluateAllDecodingBuffers();
                }
            }

            if (OurUserState == null) {
                return;
            }

            // Create the audio player if the user is in the same room, and is not muted
            if (ShouldAddAudioPlayerForUser(userState)) {
                AddDecodingBuffer(userState);
            } else {
                // Otherwise remove the audio decoding buffer and audioPlayer if it exists
                TryRemoveDecodingBuffer(userState);
            }

            UserStateChange?.Invoke(newUserState.Session, newUserState, userState);
        }

        public int Bitrate {
            get => ManageSendBuffer.GetBitrate();
            set => ManageSendBuffer.SetBitrate(value);
        }

        private readonly ConcurrentDictionary<int, float> _configurations = new ConcurrentDictionary<int, float>();

        public void ConfigureUser(int userID, float volume) {
            if (volume == 1f) {
                _configurations.TryRemove(userID, out _);
            } else {
                _configurations[userID] = volume;
            }
            
            var user = GetByID(userID);
            if (user != null) {
                if (volume == 0f) {
                    TryRemoveDecodingBuffer(user);
                } else {
                    var audio = user.Audio;
                    if (audio != null) {
                        audio.volume = volume;
                    } else {
                        AddDecodingBuffer(user);
                    }
                }
            }
        }

        private bool ShouldAddAudioPlayerForUser(UserState other) {
            return (other.Session != OurUserState.Session || Mic.ServerLoopback)
                    && (other.ChannelId == OurUserState.ChannelId || _channels[OurUserState.ChannelId].DoesShareAudio(_channels[other.ChannelId]))
                    && !other.Mute && !other.SelfMute 
                    && (!_configurations.TryGetValue(other.AcUserID, out var volume) || volume > 0f);
        }

        private void AddDecodingBuffer(UserState userState) {
            if (userState.Audio == null) {
                var created = new AudioSource(userState);
                if (Interlocked.CompareExchange(ref userState.Audio, created, null) == null) {
                    AudioDecodeThread.StartDecoding(userState.Audio);
                    if (!_configurations.TryGetValue(userState.AcUserID, out userState.Audio.volume)) {
                        userState.Audio.volume = 1f;
                    }
                } else {
                    created.Dispose();
                }
            }
        }

        private void TryRemoveDecodingBuffer(UserState userState) {
            var audio = Interlocked.Exchange(ref userState.Audio, null);
            if (audio != null) {
                audio.Dispose();
                AudioDecodeThread.StopDecoding(userState.Session);
            }
        }

        public void ReevaluateAllDecodingBuffers() {
            for (var i = _allUsersList.Count - 1; i >= 0; i--) {
                var user = _allUsersList[i];
                if (ShouldAddAudioPlayerForUser(user)) {
                    AddDecodingBuffer(user);
                } else {
                    TryRemoveDecodingBuffer(user);
                }
            }
        }

        internal void SetServerSync(ServerSync sync) {
            _serverSync = sync;
            OurUserState = _allUsersDict[_serverSync.Session];

            Comparer.Instance.OwnState = OurUserState;
            _allUsersList.Sort(Comparer.Instance);

            // Now that we know who we are, we can determine which users need decoding buffers
            ReevaluateAllDecodingBuffers();
            ConnectionSetupFinished = true;

            // Do the stuff we were waiting to do
            if (_pendingChannel != null) {
                JoinChannel(_pendingChannel);
                _pendingChannel = null;
            }

            if (_pendingMute.HasValue) {
                SetSelfMute(_pendingMute.Value);
                _pendingMute = null;
            }

            if (_pendingContext != null) {
                SetPluginContext(_pendingContext);
                _pendingContext = null;
            }

            if (_pendingPluginIdentity != null) {
                SetPluginIdentity(_pendingPluginIdentity);
                _pendingPluginIdentity = null;
            }

            if (_pendingComment != null) {
                SetOurComment(_pendingComment);
                _pendingComment = null;
            }

            if (_pendingTexture != null) {
                SetOurTexture(_pendingTexture);
                _pendingTexture = null;
            }
        }

        internal void RemoveUser(uint removedUserSession) {
            if (_allUsersDict.TryGetValue(removedUserSession, out var removedUserState)) {
                _allUsersDict.Remove(removedUserSession);
                _allUsersList.Remove(removedUserState);
                UserStateChange?.Invoke(removedUserSession, null, removedUserState);
                TryRemoveDecodingBuffer(removedUserState);
            }
        }

        public void Connect(string username, string password) {
            TcpConnection.StartClient(username, password);
        }

        internal void ConnectUdp() {
            UdpConnection.Connect();
        }

        public void Close() {
            Debug.Log("Closing mumble");
            ManageSendBuffer?.Dispose();
            TcpConnection?.Close();
            UdpConnection?.Close();
            AudioDecodeThread?.Dispose();
        }

        public void SendTextMessage(string textMessage) {
            if (OurUserState == null) return;
            TcpConnection.SendMessage(MessageType.TextMessage, new TextMessage {
                Message = textMessage,
                ChannelIds = new[] { OurUserState.ChannelId },
                Actor = _serverSync.Session
            });
        }

        public bool IsChannelAvailable(string channelName) {
            return TryGetChannelByName(channelName, out _);
        }

        public bool CreateChannel(string channelName, bool temporary, uint parent, string description, uint maxusers) {
            if (OurUserState == null || !ConnectionSetupFinished) return false;
            TcpConnection.SendMessage(MessageType.ChannelState, new ChannelState {
                Name = channelName,
                Temporary = temporary,
                Parent = parent,
                Description = description,
                MaxUsers = maxusers,
                Position = -1
            });
            return true;
        }

        public void DestroyChannel(string channelName) {
            if (!TryGetChannelByName(channelName, out var channel)) {
                Debug.LogError("channel :" + channelName + " to remove not found!");
                return;
            }
            TcpConnection.SendMessage(MessageType.ChannelRemove, new ChannelRemove { ChannelId = channel.ChannelId });
        }

        public bool JoinChannel(string channelToJoin) {
            if (OurUserState == null || !ConnectionSetupFinished) {
                _pendingChannel = channelToJoin;
                return false;
            }

            _pendingChannel = null;
            if (!TryGetChannelByName(channelToJoin, out var channel)) {
                Debug.LogResponse($"channel {channelToJoin} not found");
                return false;
            }
            if (!channel.CanEnter) {
                Debug.LogResponse($"can’t join {channelToJoin}");
                return false;
            }
            var state = new UserState {
                ChannelId = channel.ChannelId,
                Actor = OurUserState.Session,
                Session = OurUserState.Session,
                SelfMute = _pendingMute ?? OurUserState.SelfMute,
                PluginContext = _pendingContext ?? OurUserState.PluginContext,
                PluginIdentity = _pendingPluginIdentity ?? OurUserState.PluginIdentity,
            };
            _pendingMute = null;
            _pendingContext = null;
            _pendingPluginIdentity = null;

            Debug.Log("Attempting to join channel Id: " + state.ChannelId);
            TcpConnection.SendMessage(MessageType.UserState, state);
            return true;
        }

        public void SetMute(UserState state, bool mute) {
            var newState = new UserState {
                Actor = state.Session,
                Session = state.Session,
                Mute = mute
            };
            Debug.Log("Attempting to mute user Id: " + state.Session);
            TcpConnection.SendMessage(MessageType.UserState, newState);
        }

        public List<UserState> GetAllUsersList() {
            return _allUsersList;
        }

        public Dictionary<uint, Channel> GetAllChannels() {
            return _channels;
        }

        public UserState GetByID(int userID) {
            // TODO: Binary search?
            for (var i = _allUsersList.Count - 1; i >= 0; i--) {
                var x = _allUsersList[i];
                if (x.AcUserID == userID) return x;
            }
            return null;
        }

        public void SetSelfMute(bool mute) {
            if (OurUserState != null && ConnectionSetupFinished) {
                _pendingMute = null;
                var state = new UserState { SelfMute = mute };
                OurUserState.SelfMute = mute;
                TcpConnection.SendMessage(MessageType.UserState, state);
            } else {
                _pendingMute = mute;
            }
        }

        public void SetPluginContext(byte[] context) {
            if (OurUserState == null || !ConnectionSetupFinished) {
                _pendingContext = context;
                return;
            }
            _pendingContext = null;

            var state = new UserState {
                PluginContext = context
            };
            OurUserState.PluginContext = context;
            Debug.Log("Will set our plugin context to: " + context.Length);
            TcpConnection.SendMessage(MessageType.UserState, state);
        }

        public void SetPluginIdentity(string identity) {
            if (OurUserState == null || !ConnectionSetupFinished) {
                _pendingPluginIdentity = identity;
                return;
            }
            _pendingPluginIdentity = null;

            var state = new UserState {
                PluginIdentity = identity
            };
            OurUserState.PluginIdentity = identity;
            Debug.Log("Will set our plugin identity to: " + identity);
            TcpConnection.SendMessage(MessageType.UserState, state);
        }

        public bool IsSelfMuted() {
            return _pendingMute ?? (OurUserState != null && OurUserState.ShouldSerializeSelfMute() && OurUserState.SelfMute);
        }

        public bool SetOurComment(string newComment) {
            if (OurUserState == null) {
                _pendingComment = newComment;
                return false;
            }

            _pendingComment = null;
            var state = new UserState { Comment = newComment };
            OurUserState.Comment = newComment;
            TcpConnection.SendMessage(MessageType.UserState, state);
            return true;
        }

        public bool SetOurTexture(byte[] texture) {
            if (OurUserState == null) {
                _pendingTexture = texture;
                return false;
            }

            _pendingTexture = null;
            var state = new UserState { Texture = texture };
            OurUserState.Texture = texture;
            TcpConnection.SendMessage(MessageType.UserState, state);
            return true;
        }

        private bool TryGetChannelByName(string channelName, out Channel channelState) {
            foreach (var key in _channels.Keys) {
                if (_channels[key].Name == channelName) {
                    channelState = _channels[key];
                    return true;
                }
                //Debug.Log("Not " + Channels[key].name + " == " + channelName);
            }
            channelState = null;
            return false;
        }

        public string GetCurrentChannel() {
            if (_channels == null || OurUserState == null) return null;
            if (_channels.TryGetValue(OurUserState.ChannelId, out var ourChannel)) return ourChannel.Name;
            Debug.LogError("Could not get current channel");
            return null;
        }

        internal void AddChannel(ChannelState channelToAdd) {
            // If the channel already exists, just copy over the non-null data
            var isExistingChannel = _channels.TryGetValue(channelToAdd.ChannelId, out var channel);
            if (isExistingChannel) {
                channel.UpdateFromState(channelToAdd);
            } else {
                channel = new Channel(channelToAdd);
                lock (_channels) {
                    _channels[channelToAdd.ChannelId] = channel;
                }
            }

            // Update all the channel audio sharing settings
            // We can probably do this less, but we're cautious
            foreach (var kvp in _channels) {
                kvp.Value.UpdateSharedAudioChannels(_channels);
            }
            ChannelStateChange?.Invoke();
        }

        internal void RemoveChannel(uint channelIdToRemove) {
            if (channelIdToRemove == OurUserState.ChannelId) Debug.LogWarning("Removed current channel");
            if (_channels.TryGetValue(channelIdToRemove, out _)) {
                lock (_channels) {
                    _channels.Remove(channelIdToRemove);
                }
            }

            // Update all the channel audio sharing settings
            // We can probably do this less, but we're cautious
            foreach (var kvp in _channels) {
                kvp.Value.UpdateSharedAudioChannels(_channels);
            }
            ChannelStateChange?.Invoke();
        }

        public byte[] GetLatestClientNonce() {
            return UdpConnection?.GetLatestClientNonce();
        }

        internal void OnConnectionDisconnect(string reason) {
            Debug.LogError("Mumble connection disconnected: " + reason);
            Environment.Exit(reason == "Username already in use" ? ExitCode.UserNameTaken 
                    : reason == "Invalid server password" ? ExitCode.InvalidPassword
                    : ExitCode.Disconnected);
        }

        public static int GetNearestSupportedSampleRate(int listedRate) {
            var currentBest = -1;
            var currentDifference = int.MaxValue;
            for (var i = 0; i < MumbleConstants.SUPPORTED_SAMPLE_RATES.Length; i++) {
                if (Math.Abs(listedRate - MumbleConstants.SUPPORTED_SAMPLE_RATES[i]) < currentDifference) {
                    currentBest = MumbleConstants.SUPPORTED_SAMPLE_RATES[i];
                    currentDifference = Math.Abs(listedRate - MumbleConstants.SUPPORTED_SAMPLE_RATES[i]);
                }
            }
            return currentBest;
        }

        public void Update() {
            if (OurUserState == null || !ConnectionSetupFinished) return;
            Mic.Update(OurUserState.IsToBeHeard && AudioClip.MicVolume > 0f);
        }
    }
}