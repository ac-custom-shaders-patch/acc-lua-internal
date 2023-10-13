using System;
using UnityEngine;
using AcTools.Extra.MumbleClient.Implementation.Utils;

namespace Mumble {
    public class MumbleMicrophone {
        public MicType VoiceSendingType = MicType.AlwaysSend;
        public bool RequireMicPeak;
        public bool ServerLoopback;
        public bool PushToTalkFlag;
        public bool IsMicRecording;
        public bool IsAudioSending;

        public MuVec3 SourcePos {
            get => _currentPos[_currentPosIndex];
            set {
                var nextIndex = 1 - _currentPosIndex;
                _currentPos[nextIndex] = value;
                _currentPosIndex = nextIndex;
            }
        }

        private readonly MuVec3[] _currentPos = {MuVec3.Invalid, MuVec3.Invalid};
        private int _currentPosIndex;

        private const int NumRecordingSeconds = 1;
        private const float MaxSecondsWithoutMicData = 1f;

        public float MinAmplitude = 0.007f;

        private int _numSamplesPerOutgoingPacket;
        private AudioClip _sendAudioClip;
        private ManageAudioSendBuffer _sendBuffer;
        private int _totalNumSamplesSent;
        private float _secondsWithoutMicSamples;
        private bool _requiresFinalization;
        private bool _stopMicNext;
        private bool _finalizeNext;
        private DateTime _holdUntil;
        private int _lastPosition;
        private int _micSampleRate;
        private string _expectedMicName;
        private string _readyMicName;

        public MumbleMicrophone(ManageAudioSendBuffer sendBuffer) {
            _sendBuffer = sendBuffer;
            DevicesHolder.DevicesUpdated += (sender, args) => {
                _readyMicName = null;
            };
        }

        public string MicName {
            get => _readyMicName ?? _expectedMicName;
            set {
                if (_expectedMicName == value) return;
                _expectedMicName = value;
                _readyMicName = null;
            }
        }

        private bool EnsureMicIsReady() {
            if (_readyMicName != null) {
                if (!string.IsNullOrEmpty(_expectedMicName) && _expectedMicName != _readyMicName) {
                    DevicesHolder.Rescan();
                }
                return true;
            }

            _holdUntil = default;
            var device = DevicesHolder.GetIn(_expectedMicName);
            if (device == null) {
                DevicesHolder.Rescan();
                return false;
            }

            _readyMicName = device.FullName;
            if (IsMicRecording) {
                StopRecordingAudio();
            }
            FinalizeSentRecord();

            _micSampleRate = MumbleClient.GetNearestSupportedSampleRate(device.MaxFrequency);
            _numSamplesPerOutgoingPacket = MumbleConstants.NUM_FRAMES_PER_OUTGOING_PACKET * _micSampleRate / 100;

            Debug.Log($"Device {device.FullName} has frequency from {device.MinFrequency} to {device.MaxFrequency}, setting to: {_micSampleRate}");
            if (_micSampleRate != 48000) {
                Debug.LogWarning($"Using a possibly unsupported sample rate of {_micSampleRate}, things might get weird");
            }
                
            _sendBuffer.Initialize(_micSampleRate);
            return true;
        }

        public void Restart() {
            if (IsMicRecording) {
                StopRecordingAudio();
            }
            FinalizeSentRecord();
        }

        private void SendVoiceIfReady(bool justStartedSending) {
            var currentPosition = Microphone.GetPosition();

            // We drop the first sample, because it generally starts with a lot of pre-existing, stale, audio data which we couldn’t use b/c it’s too old
            if (_totalNumSamplesSent > currentPosition) {
                Debug.Log("Resetting MumbleMicrophone._totalNumSamplesSent");
                _totalNumSamplesSent = currentPosition;
                return;
            }
            
            var leftToSend = (currentPosition - _totalNumSamplesSent) / _numSamplesPerOutgoingPacket;
            if (leftToSend == 0) return;

            _requiresFinalization = true;
            while (--leftToSend >= 0) {
                var lastPacket = leftToSend == 0 && _finalizeNext;
                var newData = new PcmArray(_numSamplesPerOutgoingPacket, SourcePos);
                _sendAudioClip.GetData(newData.Pcm, _totalNumSamplesSent);
                if (justStartedSending) {
                    justStartedSending = false;
                    for (var i = 0; i < newData.Pcm.Length; ++i) {
                        newData.Pcm[i] *= (float)(i + 1) / newData.Pcm.Length;
                    }
                }
                if (lastPacket) {
                    for (var i = 0; i < newData.Pcm.Length; ++i) {
                        newData.Pcm[i] *= 1f - (float)i / newData.Pcm.Length;
                    }
                }
                _sendBuffer.SendVoice(newData, ServerLoopback ? SpeechTarget.ServerLoopback : SpeechTarget.Normal, lastPacket);
                _totalNumSamplesSent += _numSamplesPerOutgoingPacket;
            }

            if (_finalizeNext) {
                _requiresFinalization = false;
                FinalizeSentRecord();
            }

            if (_stopMicNext) {
                StopRecordingAudio();
            }
        }

        private void StartRecordingAudio() {
            if (_expectedMicName == null) {
                Debug.Log("Not sending audio, no current mic");
                return;
            }
            
            Debug.Log("Starting to record audio");
            _sendAudioClip = Microphone.Start(_expectedMicName, NumRecordingSeconds, _micSampleRate);
            _secondsWithoutMicSamples = 0;
            IsMicRecording = true;
        }

        private void StopRecordingAudio() {
            Microphone.End();
            IsMicRecording = false;
        }

        private void FinalizeSentRecord() {
            if (_requiresFinalization) {
                _requiresFinalization = false;
                _sendBuffer.SendVoiceStopSignal();
            }
            _totalNumSamplesSent = int.MaxValue;
            IsAudioSending = false;
        }

        private bool ShouldRecordData() {
            if (RequireMicPeak) {
                return true;
            }
            switch (VoiceSendingType) {
                case MicType.None:
                    return false;
                case MicType.PushToTalk:
                    if (PushToTalkFlag) {
                        _holdUntil = DateTime.Now + TimeSpan.FromSeconds(1d);
                        return true;
                    }
                    return DateTime.Now < _holdUntil;
                default:
                    return true;
            }
        }

        public bool ImmediateSendTrigger() {
            switch (VoiceSendingType) {
                case MicType.None:
                    return false;
                case MicType.PushToTalk:
                    return PushToTalkFlag;
                case MicType.AlwaysSend:
                    return true;
                case MicType.Amplitude:
                    return AudioClip.BatchPeakVolume > MinAmplitude;
                case MicType.VoiceActivity:
                    return AudioFilterWrapper.VoiceActivityDetected;
                default:
                    return false;
            }
        }

        private bool ShouldSendData() {
            switch (VoiceSendingType) {
                case MicType.None:
                    return false;
                case MicType.PushToTalk:
                    return PushToTalkFlag;
                case MicType.AlwaysSend:
                    return true;
                case MicType.Amplitude:
                    if (AudioClip.BatchPeakVolume > MinAmplitude) {
                        _holdUntil = DateTime.Now + TimeSpan.FromSeconds(SharedSettings.VoiceHoldSeconds);
                        return true;
                    }
                    return DateTime.Now < _holdUntil;
                case MicType.VoiceActivity:
                    if (AudioFilterWrapper.VoiceActivityDetected) {
                        _holdUntil = DateTime.Now + TimeSpan.FromSeconds(SharedSettings.VoiceHoldSeconds);
                        return true;
                    }
                    return DateTime.Now < _holdUntil;
                default:
                    return false;
            }
        }

        public void Update(bool canRecord) {
            if (canRecord && ShouldRecordData() && EnsureMicIsReady()) {
                if (!IsMicRecording) {
                    StartRecordingAudio();
                    _totalNumSamplesSent = Microphone.GetPosition();
                }
                _stopMicNext = false;
                
                var currentPosition = Microphone.GetPosition();
                if (currentPosition == _lastPosition) {
                    _secondsWithoutMicSamples += Time.deltaTime;
                    if (_secondsWithoutMicSamples > MaxSecondsWithoutMicData) {
                        _secondsWithoutMicSamples = 0;
                        Debug.Log("Mic has disconnected: " + currentPosition);
                        DevicesHolder.Rescan();
                        StopRecordingAudio();
                        FinalizeSentRecord();
                        return;
                    }
                } else {
                    _secondsWithoutMicSamples = 0f;
                    _lastPosition = currentPosition;
                }
            } else if (IsMicRecording) {
                _stopMicNext = true;
            }

            if (IsMicRecording) {
                _sendAudioClip.UpdatePeakValue();
                var justStartedSending = false;
                if (canRecord && ShouldSendData()) {
                    if (!IsAudioSending) {
                        IsAudioSending = true;
                        justStartedSending = true;
                    }
                    _finalizeNext = false;
                } else if (IsAudioSending) {
                    _finalizeNext = true;
                }
                if (IsAudioSending) {
                    SendVoiceIfReady(justStartedSending);
                } else {
                    _totalNumSamplesSent += (Microphone.GetPosition() - _totalNumSamplesSent) / _numSamplesPerOutgoingPacket * _numSamplesPerOutgoingPacket;
                }
            } else {
                _totalNumSamplesSent = Microphone.GetPosition();
            }
        }
    }
}