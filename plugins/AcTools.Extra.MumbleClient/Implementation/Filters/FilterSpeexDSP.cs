using System;
using System.Runtime.InteropServices;
using AcTools.Extra.MumbleClient.Implementation.External;
using NAudio.Utils;
using NAudio.Wave;
using UnityEngine;

namespace AcTools.Extra.MumbleClient.Implementation.Filters {
    public class FilterSpeexDSP : IDisposable {
        public bool IsTalking { get; private set; }

        public bool AnyActive => DenoiseActive || AgcActive || EchoActive || VadActive;

        private const int ApproximateSampleRate = 48000;
        private const int ChunkTimeMs = 20;
        private const int FrameSize = ApproximateSampleRate * ChunkTimeMs / 1000;
        private const int FrameSizeBytes = FrameSize * 2;
        private const int FilterLength = FrameSize;

        private readonly WaveFormat _waveFormat;
        private byte[] _echoPlayBuffer;
        private byte[] _echoFilteredBuffer;
        private CircularBuffer _loopbackPlayBuffer;
        private WasapiLoopbackCapture _loopbackCapture;
        private MediaFoundationResampler _resampler;
        private IWaveProvider _resampleWaveProvider;

        private readonly IntPtr _stateUpdate;
        private readonly IntPtr _speexPreprocessState;
        private IntPtr _speexEchoState;

        public FilterSpeexDSP(WaveFormat waveFormat) {
            _waveFormat = waveFormat;
            _speexPreprocessState = SpeexPreprocess.speex_preprocess_state_init(FrameSize, _waveFormat.SampleRate);
            _stateUpdate = Marshal.AllocHGlobal(sizeof(int));
        }

        public unsafe void Process(byte[] buffer, int count) {
            if (!AnyActive) return;
            
            var anyTalking = false;
            var echoActive = _speexEchoState != IntPtr.Zero && _resampler != null;
            if (count % FrameSizeBytes != 0) {
                Debug.LogError($"Invalid frame size: {count} samples to process, chunk is {FrameSizeBytes}");
                return;
            }

            fixed (byte* b = buffer) {
                for (var offset = 0; offset < count; offset += FrameSizeBytes) {
                    if (echoActive) {
                        var bytesRead = _resampler.Read(_echoPlayBuffer, 0, FrameSizeBytes);
                        if (bytesRead < FrameSizeBytes) Array.Clear(_echoPlayBuffer, bytesRead, FrameSizeBytes - bytesRead);
                        Buffer.BlockCopy(buffer, offset, _echoFilteredBuffer, 0, FrameSizeBytes);
                        SpeexEcho.speex_echo_cancellation(_speexEchoState, _echoFilteredBuffer, _echoPlayBuffer, &b[offset]);
                    }
                    anyTalking = SpeexPreprocess.speex_preprocess_run(_speexPreprocessState, &b[offset]) == 1 || anyTalking;
                }
            }
            
            IsTalking = anyTalking && VadActive;
        }

        public void Dispose() {
            if (_speexEchoState != IntPtr.Zero) {
                SpeexEcho.speex_echo_state_destroy(_speexEchoState);
            }
            SpeexPreprocess.speex_preprocess_state_destroy(_speexPreprocessState);
            Marshal.FreeHGlobal(_stateUpdate);
            StopCapture();
        }

        private class ResampleWaveProvider : IWaveProvider {
            private readonly FilterSpeexDSP _parent;

            public ResampleWaveProvider(FilterSpeexDSP parent) {
                _parent = parent;
            }

            public int Read(byte[] buffer, int offset, int count) {
                return _parent._loopbackPlayBuffer.Read(buffer, offset, count);
            }

            public WaveFormat WaveFormat => _parent._loopbackCapture.WaveFormat;
        }

        private void StartCapture() {
            StopCapture();

            if (_loopbackPlayBuffer == null) {
                _loopbackPlayBuffer = new CircularBuffer();
            }

            _loopbackCapture = new WasapiLoopbackCapture();
            _loopbackCapture.DataAvailable += (s, e) => _loopbackPlayBuffer.Write(e.Buffer, 0, e.BytesRecorded);
            _loopbackCapture.RecordingStopped += (s, a) => _loopbackCapture.Dispose();
            _loopbackCapture.StartRecording();
            _resampleWaveProvider = new ResampleWaveProvider(this);
            _resampler = new MediaFoundationResampler(_resampleWaveProvider, _waveFormat);
            _echoPlayBuffer = new byte[FrameSizeBytes];
            _echoFilteredBuffer = new byte[FrameSizeBytes];
        }

        private void StopCapture() {
            _resampler?.Dispose();
            _loopbackCapture?.StopRecording();
            _resampler = null;
            _echoPlayBuffer = null;
            _echoFilteredBuffer = null;
        }

        private int _noiseSupress = -1;

        public int NoiseSupress {
            get => _noiseSupress;
            set {
                if (_noiseSupress == value) return;
                _noiseSupress = value;
                Marshal.WriteInt32(_stateUpdate, value);
                SpeexPreprocess.speex_preprocess_ctl(_speexPreprocessState, SpeexPreprocess.SPEEX_PREPROCESS_SET_NOISE_SUPPRESS, _stateUpdate);
            }
        }

        private bool _denoiseActive;

        public bool DenoiseActive {
            get => _denoiseActive;
            set {
                if (value == _denoiseActive) return;
                _denoiseActive = value;
                Marshal.WriteInt32(_stateUpdate, value ? 1 : 0);
                SpeexPreprocess.speex_preprocess_ctl(_speexPreprocessState, SpeexPreprocess.SPEEX_PREPROCESS_SET_DENOISE, _stateUpdate);
            }
        }

        private int _agcLevel = -1;

        public int AgcLevel {
            get => _agcLevel;
            set {
                if (_agcLevel == value) return;
                _agcLevel = value;
                Marshal.WriteInt32(_stateUpdate, value);
                SpeexPreprocess.speex_preprocess_ctl(_speexPreprocessState, SpeexPreprocess.SPEEX_PREPROCESS_SET_AGC_TARGET, _stateUpdate);
            }
        }

        private bool _agcActive;

        public bool AgcActive {
            get => _agcActive;
            set {
                if (value == _agcActive) return;
                _agcActive = value;
                Marshal.WriteInt32(_stateUpdate, _agcActive ? 1 : 0);
                SpeexPreprocess.speex_preprocess_ctl(_speexPreprocessState, SpeexPreprocess.SPEEX_PREPROCESS_SET_AGC, _stateUpdate);
            }
        }

        private int _vadProbStart = -1;

        public int VadProbStart {
            get => _vadProbStart;
            set {
                if (_vadProbStart == value) return;
                _vadProbStart = value;
                Marshal.WriteInt32(_stateUpdate, value);
                SpeexPreprocess.speex_preprocess_ctl(_speexPreprocessState, SpeexPreprocess.SPEEX_PREPROCESS_SET_PROB_START, _stateUpdate);
            }
        }

        private int _vadProbContinue = -1;

        public int VadProbContinue {
            get => _vadProbContinue;
            set {
                if (_vadProbContinue == value) return;
                _vadProbContinue = value;
                Marshal.WriteInt32(_stateUpdate, value);
                SpeexPreprocess.speex_preprocess_ctl(_speexPreprocessState, SpeexPreprocess.SPEEX_PREPROCESS_SET_PROB_CONTINUE, _stateUpdate);
            }
        }

        private bool _vadActive;

        public bool VadActive {
            get => _vadActive;
            set {
                if (value == _vadActive) return;
                _vadActive = value;
                Marshal.WriteInt32(_stateUpdate, value ? 1 : 2);
                SpeexPreprocess.speex_preprocess_ctl(_speexPreprocessState, SpeexPreprocess.SPEEX_PREPROCESS_SET_VAD, _stateUpdate);
                if (!value) {
                    IsTalking = false;
                }
            }
        }

        private int _echoSupress = -1;

        public int EchoSupress {
            get => _echoSupress;
            set {
                if (_echoSupress == value) return;
                _echoSupress = value;
                Marshal.WriteInt32(_stateUpdate, EchoSupress);
                SpeexPreprocess.speex_preprocess_ctl(_speexPreprocessState, SpeexPreprocess.SPEEX_PREPROCESS_SET_ECHO_SUPPRESS, _stateUpdate);
            }
        }

        private int _echoSuppressActive = -1;

        public int EchoSuppressActive {
            get => _echoSuppressActive;
            set {
                if (_echoSuppressActive == value) return;
                _echoSuppressActive = value;
                Marshal.WriteInt32(_stateUpdate, EchoSuppressActive);
                SpeexPreprocess.speex_preprocess_ctl(_speexPreprocessState, SpeexPreprocess.SPEEX_PREPROCESS_SET_ECHO_SUPPRESS_ACTIVE, _stateUpdate);
            }
        }

        private bool _echoActive;

        public bool EchoActive {
            get => _echoActive;
            set {
                if (value == _echoActive) return;
                _echoActive = value;
                if (value) {
                    _speexEchoState = SpeexEcho.speex_echo_state_init(FrameSize, FilterLength);
                    Marshal.WriteInt32(_stateUpdate, _waveFormat.SampleRate);
                    SpeexEcho.speex_echo_ctl(_speexEchoState, SpeexEcho.SPEEX_ECHO_SET_SAMPLING_RATE, _stateUpdate);
                    SpeexPreprocess.speex_preprocess_ctl(_speexPreprocessState, SpeexPreprocess.SPEEX_PREPROCESS_SET_ECHO_STATE, _speexEchoState);
                    StartCapture();
                } else {
                    SpeexPreprocess.speex_preprocess_ctl(_speexPreprocessState, SpeexPreprocess.SPEEX_PREPROCESS_SET_ECHO_STATE, IntPtr.Zero);
                    StopCapture();
                    SpeexEcho.speex_echo_state_destroy(_speexEchoState);
                    _speexEchoState = IntPtr.Zero;
                }
            }
        }
    }
}