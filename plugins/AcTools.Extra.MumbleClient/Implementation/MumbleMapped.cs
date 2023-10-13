using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO.MemoryMappedFiles;
using System.Linq;
using System.Runtime.InteropServices;
using AcTools.Extra.MumbleClient.Implementation.Utils;
using Mumble;
using Tiny;
using UnityEngine;
using Debug = UnityEngine.Debug;

namespace AcTools.Extra.MumbleClient.Implementation {
    /// <summary>
    /// Version of Mumble client meant to be controlled with memory-mapped file.
    /// </summary>
    public class MumbleMapped : IDisposable {
        private const int MaxDevicesCount = 64;
        private const int MaxDeviceNameLength = 256;
        private const int MaxDeviceIconPathLength = 128;
        private const int MaxCommandsCount = 64;
        private const int MaxConnectedCount = 256;
        private const int SizeConnectedState = 8;
        private const int SizeDeviceItem = MaxDeviceNameLength + MaxDeviceIconPathLength + 4;
        private const int ChannelsDataLength = 32768;
        
        private const int OffsetStatic = 0;
        private const int OffsetStaticBitrate = 0;
        private const int OffsetCommands = 16 + SizeDeviceItem * MaxDevicesCount * 2;
        private const int OffsetNumCommands = OffsetCommands + MaxCommandsCount * CommandProcessor.MaxCommandLength;
        private const int OffsetFrameIndex = OffsetNumCommands + 4;
        private const int OffsetListenerPos = OffsetFrameIndex + 4;
        private const int OffsetListenerDir = OffsetListenerPos + 12;
        private const int OffsetListenerUp = OffsetListenerDir + 12;
        private const int OffsetAudioSourcePos = OffsetListenerUp + 12;
        private const int OffsetPushToTalk = OffsetAudioSourcePos + 12;
        private const int OffsetRequireMicPeak = OffsetPushToTalk + 1;
        private const int OffsetServerLoopback = OffsetRequireMicPeak + 1;
        private const int OffsetNumCurrentlyConnected = OffsetPushToTalk + 4;
        private const int OffsetCurrentlyConnected = OffsetNumCurrentlyConnected + 4;
        private const int OffsetChannelsPhase = OffsetCurrentlyConnected + MaxConnectedCount * SizeConnectedState;
        private const int OffsetChannelsData = OffsetChannelsPhase + 4;
        private const int OffsetMicPeak = OffsetChannelsData + ChannelsDataLength;
        private const int OffsetMark = OffsetMicPeak + 4;
        private const int SizeTotal = OffsetMark + 4;

        private const int ExpectedMarkValue = 12345678;

        [Flags]
        public enum MumbleDeviceFlags : uint {
            None = 0,
            Default = 1,
            Active = 2,
            Selected = 4,
        }

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        public struct MumbleDeviceInfo {
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = MaxDeviceNameLength, ArraySubType = UnmanagedType.U1)]
            public byte[] DeviceName;

            [MarshalAs(UnmanagedType.ByValArray, SizeConst = MaxDeviceIconPathLength, ArraySubType = UnmanagedType.U1)]
            public byte[] IconPath;

            public MumbleDeviceFlags Flags;

            public void Fill(DevicesHolder.DeviceInfo info, bool isSelected) {
                MarshalMatters.CopyString(ref DeviceName, MaxDeviceNameLength, info.FullName);
                MarshalMatters.CopyString(ref IconPath, MaxDeviceIconPathLength, info.IconPath);
                Flags = (info.IsActive ? MumbleDeviceFlags.Active : MumbleDeviceFlags.None)
                        | (info.IsDefault ? MumbleDeviceFlags.Default : MumbleDeviceFlags.None)
                        | (isSelected ? MumbleDeviceFlags.Selected : MumbleDeviceFlags.None);
            }
        }

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        public struct MumbleStaticState {
            public int Bitrate;
            public int StreamConnectPointSize;
            public int NumInputDevices;
            public int NumOutputDevices;

            [MarshalAs(UnmanagedType.ByValArray, SizeConst = MaxDevicesCount)]
            public MumbleDeviceInfo[] InputDevices;

            [MarshalAs(UnmanagedType.ByValArray, SizeConst = MaxDevicesCount)]
            public MumbleDeviceInfo[] OutputDevices;
        }

        [Flags]
        public enum MumbleConnectedFlags : ushort {
            None = 0,
            Talking = 1,
            Muted = 2,
            SelfMuted = 4,
            Supressed = 8,
            Deaf = 16,
            SelfDeaf = 32,
            ActiveStream = 64,
            ImmediateTalking = 128
        }

        private readonly MonoBehaviour.IMonoRunner _runner;
        private readonly CommandProcessor _commands;
        private readonly Mumble.MumbleClient _client;
        private readonly UserTransformState[] _ownTransform = { new UserTransformState(), new UserTransformState() };
        private int _ownTransformIndex;

        private readonly bool _debugRun;
        private readonly bool _sendPosition;
        private readonly Stopwatch _frameTimeout = Stopwatch.StartNew();
        private readonly MemoryMappedFile _mmf;
        private readonly MemoryMappedViewAccessor _accessor;
        private readonly IntPtr _sharedPtr;

        private int _lastFrameIndex;
        private bool _staticStateDirty = true;
        private bool _channelsStateDirty = true;

        private MumbleStaticState _staticState = new MumbleStaticState {
            InputDevices = new MumbleDeviceInfo[MaxDevicesCount],
            OutputDevices = new MumbleDeviceInfo[MaxDevicesCount]
        };

        private unsafe byte* GetPtr() {
            return (byte*)_sharedPtr;
        }

        private unsafe byte* GetPtr(int offset) {
            // ReSharper disable once PossibleNullReferenceException
            return &((byte*)_sharedPtr)[offset];
        }

        private static MicType ParseMicType(string micType) {
            switch (micType) {
                case "alwaysSend":
                    return MicType.AlwaysSend;
                case "amplitude":
                    return MicType.Amplitude;
                case "pushToTalk":
                    return MicType.PushToTalk;
                case "voiceActivity":
                    return MicType.VoiceActivity;
                default:
                    Debug.LogWarning("Unknown audio input mode: " + micType);
                    return MicType.None;
            }
        }

        public unsafe MumbleMapped(string configData, bool debugRun) {
            var config = new ConfigProcessor(configData);
            _debugRun = debugRun;
            _runner = MonoBehaviour.CreateRunner(Update);
            _mmf = MemoryMappedFile.CreateOrOpen(
                    config.String("system.connectPoint") ?? throw new Exception("Parameter “system.connectPoint” is missing"),
                    SizeTotal, MemoryMappedFileAccess.ReadWrite);
            _accessor = _mmf.CreateViewAccessor();
            var value = (byte*)IntPtr.Zero;
            _accessor.SafeMemoryMappedViewHandle.AcquirePointer(ref value);
            _sharedPtr = (IntPtr)value;
            *(int*)&value[OffsetChannelsPhase] = 0;

            Mumble.MumbleClient.ReleaseName = config.String("server.userAgent") ?? "AcTools.Extra.MumbleClient";
            _sendPosition = config.Bool("data.sendPosition") ?? false;
            _client = new Mumble.MumbleClient(
                    config.String("server.host") ?? throw new Exception("Parameter “server.host” is missing"),
                    config.Int("server.port") ?? throw new Exception("Parameter “server.port” is missing")) {
                        Mic = {
                            VoiceSendingType = ParseMicType(config.String("audio.inputMode") ?? "pushToTalk"),
                            MicName = config.String("audio.inputDevice")
                        },
                        Bitrate = config.Int("audio.inputBitrate") ?? 24000
                    };
            _client.ChannelStateChange += () => _channelsStateDirty = true;

            var connectAsAdmin = config.Bool("server.admin") ?? false;
            _client.Connect(
                    connectAsAdmin ? "SuperUser" : config.Int("server.userID")?.ToString(CultureInfo.InvariantCulture)
                            ?? throw new Exception("Parameter “server.userID” is missing"),
                    config.String("server.password") ?? string.Empty);

            if (connectAsAdmin) {
                _client.SetOurComment(config.Int("server.userID")?.ToString(CultureInfo.InvariantCulture));
            }

            // Basic commands, can be set in both initial config and called with MMF
            _commands = new CommandProcessor {
                ["system.forceTCP"] = p => _client.UdpConnection.TcpOnly = p.Bool(),
                ["system.setQOS"] = p => _client.UdpConnection.UseQos = p.Bool(),
                ["action.sendMessage"] = p => _client.SendTextMessage(p.String()),
                ["action.configureUser"] = p => _client.ConfigureUser(p.At(0).Int(), p.At(1).Float()),
                ["user.channel"] = p => _client.JoinChannel(p.String()),
                ["user.comment"] = p => _client.SetOurComment(p.String()),
                ["user.pluginContext"] = p => _client.SetPluginContext(p.Bytes()),
                ["user.pluginIdentity"] = p => _client.SetPluginIdentity(p.String()),
                ["user.selfMute"] = p => _client.SetSelfMute(p.Bool()),
                ["user.texture"] = p => _client.SetOurTexture(p.Bytes()),
                ["audio.inputMode.amplitude.minValue"] = p => _client.Mic.MinAmplitude = p.Float(),
                ["audio.outputDevice.volume"] = p => AudioSource.OutputVolume = p.Float(),
                ["audio.inputDevice.volume"] = p => AudioClip.MicVolume = p.Float(),
            };

            _commands.Process(config);
            SharedSettings.Processor.Process(config);
            AudioFilterWrapper.FilterConfig.Extend(config);

            // Extra commands that can’t be called with initial config (possibly set earlier manually)
            _commands.Link(new CommandProcessor {
                ["action.updateDevices"] = p => DevicesHolder.Rescan(),
                ["audio.inputBitrate"] = p => {
                    _client.Bitrate = p.Int();
                    *(int*)GetPtr(OffsetStaticBitrate) = _client.Bitrate;
                },
                ["audio.inputDevice"] = p => {
                    _client.Mic.MicName = p.String();
                    _staticStateDirty = true;
                },
                ["audio.inputMode"] = p => _client.Mic.VoiceSendingType = ParseMicType(p.String()),
                ["system.forceTCP"] = p => _client.UdpConnection.TcpOnly = p.Bool(),
                ["system.setQOS"] = p => _client.UdpConnection.UseQos = p.Bool(),
            });
            _commands.Link(SharedSettings.Processor);
            _commands.Link(AudioFilterWrapper.FilterConfig);

            DevicesHolder.DevicesUpdated += (sender, args) => _staticStateDirty = true;
            SharedSettings.DeviceSettingChange += (sender, args) => {
                if (args.Key == nameof(SharedSettings.OutputDeviceName)) {
                    _staticStateDirty = true;
                }
                if (args.Key == nameof(SharedSettings.InputBufferMilliseconds)) {
                    _client.Mic.Restart();
                }
            };
        }

        private string SerializeChannelData() {
            var channels = _client.GetAllChannels();
            lock (channels) {
                var rootKey = channels.Values.FirstOrDefault(x => x.State.Parent == x.ChannelId)?.ChannelId ?? 0U;
                var ret = channels
                        .OrderBy(x => x.Value.State.Position)
                        .ThenBy(x => x.Value.Name).ToDictionary(x => x.Key, x => new {
                            id = x.Key,
                            name = x.Value.Name,
                            description = string.IsNullOrEmpty(x.Value.State.Description) ? null : x.Value.State.Description,
                            isEnterRestricted = x.Value.State.IsEnterRestricted,
                            canEnter = x.Value.State.CanEnter,
                            maxUsers = x.Value.State.MaxUsers,
                            children = new List<object>()
                        });
                foreach (var data in ret.Where(data => data.Key != rootKey)) {
                    ret[channels[data.Key].State.Parent].children.Add(data.Value);
                }
                return ret.TryGetValue(rootKey, out var root) ? root.Encode() : null;
            }
        }

        public void Run() {
            _runner.Start();
        }

        private unsafe void Update() {
            _client.Update();

            var ptr = GetPtr();

            // Sync static state if necessary
            if (_staticStateDirty) {
                _staticStateDirty = false;
                
                var selectedInput = DevicesHolder.GetIn(_client.Mic.MicName);
                MarshalMatters.Fill(out _staticState.NumInputDevices, _staticState.InputDevices, DevicesHolder.GetIns(),
                        (DevicesHolder.DeviceInfo src, ref MumbleDeviceInfo dst) => dst.Fill(src, ReferenceEquals(src, selectedInput)));
                var selectedOutput = DevicesHolder.GetOut(SharedSettings.OutputDeviceName);
                MarshalMatters.Fill(out _staticState.NumOutputDevices, _staticState.OutputDevices, DevicesHolder.GetOuts(),
                        (DevicesHolder.DeviceInfo src, ref MumbleDeviceInfo dst) => dst.Fill(src, ReferenceEquals(src, selectedOutput)));
                
                _staticState.Bitrate = _client.Bitrate;
                _staticState.StreamConnectPointSize = AudioSource._mmfSize;
                _staticState.ToBytes(&ptr[OffsetStatic]);
            }

            if (_channelsStateDirty && _client.GetAllChannels().Count > 0) {
                var ready = SerializeChannelData();
                if (ready != null) {
                    _channelsStateDirty = false;
                    ++*(int*)&ptr[OffsetChannelsPhase];
                    MarshalMatters.StringToBytes(SerializeChannelData(), &ptr[OffsetChannelsData], ChannelsDataLength);
                }
            }

            // Read game state
            var own = _ownTransform[_ownTransformIndex = 1 - _ownTransformIndex];
            own.Pos = *(MuVec3*)&ptr[OffsetListenerPos];
            own.Dir = *(MuVec3*)&ptr[OffsetListenerDir];
            own.Up = *(MuVec3*)&ptr[OffsetListenerUp];
            GainEstimator.Own = own;

            if (_sendPosition) {
                _client.Mic.SourcePos = *(MuVec3*)&ptr[OffsetAudioSourcePos];
            }
            _client.Mic.PushToTalkFlag = ptr[OffsetPushToTalk] != 0;
            _client.Mic.RequireMicPeak = ptr[OffsetRequireMicPeak] != 0;
            if (ptr[OffsetServerLoopback] != 0 != _client.Mic.ServerLoopback) {
                _client.Mic.ServerLoopback = !_client.Mic.ServerLoopback;
                _client.ReevaluateAllDecodingBuffers();
            }

            var numCommands = *(int*)&ptr[OffsetNumCommands];
            if (numCommands > 0) {
                for (var i = 0; i < numCommands; ++i) {
                    MarshalMatters.BytesToStringPair(&ptr[OffsetCommands + CommandProcessor.MaxCommandLength * i],
                            CommandProcessor.MaxCommandLength, out var key, out var value);
                    _commands.ProcessKeyValue(key, value, true);
                }
                *(int*)&ptr[OffsetNumCommands] = 0;
            }

            var frameIndex = *(int*)&ptr[OffsetFrameIndex];
            if (_lastFrameIndex != frameIndex) {
                _lastFrameIndex = frameIndex;
                _frameTimeout.Restart();
            } else if (!_debugRun && _frameTimeout.Elapsed.TotalSeconds > 5d) {
                Debug.LogError("Host seems to be dead, exiting");
                Environment.Exit(ExitCode.Mismatch);
            }

            var list = _client.GetAllUsersList();
            var connected = 0;
            var lastAcID = -1;
            for (var i = 0; i < list.Count; i++) {
                var user = list[i];
                if (user.AcUserID < 0 || user.AcUserID == lastAcID || i > 0 && user.AcUserID == list[0].AcUserID) continue;
                lastAcID = user.AcUserID;

                ++connected;
                var ownUser = user == _client.OurUserState;
                var flags = (user.Mute ? MumbleConnectedFlags.Muted : MumbleConnectedFlags.None)
                        | (user.Suppress ? MumbleConnectedFlags.Supressed : MumbleConnectedFlags.None)
                        | (user.Deaf ? MumbleConnectedFlags.Deaf : MumbleConnectedFlags.None)
                        | (user.SelfDeaf ? MumbleConnectedFlags.SelfDeaf : MumbleConnectedFlags.None);
                var peak = 0f;
                if (ownUser && !_client.Mic.ServerLoopback) {
                    if (_client.IsSelfMuted()) {
                        flags |= MumbleConnectedFlags.SelfMuted;
                    } else if (_client.Mic.IsAudioSending) {
                        flags |= MumbleConnectedFlags.Talking;
                        peak = AudioClip.PeakVolume;
                    }
                } else if (user.SelfMute) {
                    flags |= MumbleConnectedFlags.SelfMuted;
                } else {
                    var player = user.Audio;
                    if (player != null) {
                        if (player._isActuallyPlaying) {
                            if (player.PeakValue > AudioSource.ActiveThreshold) {
                                player.ActiveFor = AudioSource.ActivePeriod;
                            }
                            if (player.ActiveFor > 0f) {
                                peak = player.PeakValue;
                                flags |= MumbleConnectedFlags.Talking;
                                player.ActiveFor -= Time.deltaTime;
                            }
                        } else {
                            player.ActiveFor = 0f;
                        }
                        if (player._mmfOpened) {
                            flags |= MumbleConnectedFlags.ActiveStream;
                        }
                    }
                }
                
                if (ownUser && _client.Mic.RequireMicPeak && _client.Mic.ImmediateSendTrigger()) {
                    flags |= MumbleConnectedFlags.ImmediateTalking;
                }

                var dst = &ptr[OffsetCurrentlyConnected + i * SizeConnectedState];
                dst[0] = (byte)user.AcUserID;
                dst[1] = (byte)(peak * 255f);
                *(ushort*)&dst[2] = (ushort)flags;
                *(uint*)&dst[4] = user.ChannelId;
            }
            *(int*)&ptr[OffsetNumCurrentlyConnected] = connected;
            *(float*)&ptr[OffsetMicPeak] = AudioClip.PeakVolume;

            if (!_debugRun && *(int*)&ptr[OffsetMark] != ExpectedMarkValue) {
                Debug.LogError("Host seems to be mismatched, exiting");
                Environment.Exit(ExitCode.Mismatch);
            }
        }

        public void Dispose() {
            _runner?.Dispose();
            _accessor?.Dispose();
            _mmf?.Dispose();
        }
    }
}