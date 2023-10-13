using System;
using System.IO.MemoryMappedFiles;
using System.Threading;
using System.Threading.Tasks;
using AcTools.Extra.MumbleClient.Implementation;
using AcTools.Extra.MumbleClient.Implementation.Utils;
using Mumble;
using MumbleProto;
using NAudio.Wave;

// ReSharper disable HeuristicUnreachableCode

#pragma warning disable CS0162

namespace UnityEngine {
    internal class AudioSource : IWaveProvider, IDisposable {
        public float volume = 1f;

        // Internal implementation:
        public static float OutputVolume = 1f;

        private const int FMOD_SOUND_FORMAT_PCMFLOAT = 5;

        private const int _samplesPerFrame = (int)(MonoBehaviour._periodMs / 1e3 * (int)AudioSettings.speakerMode * AudioSettings.outputSampleRate);
        private const int _outputLength = 1024 * 64 * (int)AudioSettings.speakerMode;
        private const AudioSpeakerMode _outSpeakerMode = AudioSpeakerMode.Stereo;
        private const int _fmodPrefixSize = 16 * sizeof(int);
        private const int _fmodItemSize = 4;
        private const int _bufferCount = 64;
        private const int _mmfItemsCount = _samplesPerFrame * _bufferCount;
        private const int _mmfDataSize = _samplesPerFrame * _bufferCount * _fmodItemSize;
        public const int _mmfSize = _fmodPrefixSize + _mmfDataSize;

        public bool _mmfOpened => _mmfPtr != IntPtr.Zero;

        WaveFormat IWaveProvider.WaveFormat { get; } = new WaveFormat(AudioSettings.outputSampleRate, 16, (int)_outSpeakerMode);

        private static readonly MemoryPool<float> OutputDataPool = new MemoryPool<float>("Playback Regrouping Buffer", _outputLength);

        private WaveOutEvent _waveOut;
        private float[] _outputData;
        private int _outputWriteCursor;
        private int _outputReadCursor;
        private int _bytesWritten;
        private int _bytesRead;
        private bool _initialized;
        private bool _disposed;

        public readonly UserState _user;
        private float _gainLeft = 1f;
        private float _gainRight = 1f;
        private float _offsetLeft;
        private float _offsetRight;

        public const float ActiveThreshold = 0.001f;
        public const float ActivePeriod = 1f;
        internal float PeakValue;
        internal float ActiveFor;

        private MemoryMappedFile _mmf;
        private MemoryMappedViewAccessor _accessor;
        private IntPtr _mmfPtr;

        /*private unsafe void ClearStorage(byte* ptr) {
            var r = new Random();
            for (var i = _fmodPrefixSize / 4; i < _mmfSize / 4 ; i++) {
                ((float*)ptr)[i] = (float)r.NextDouble();
            }
        }*/

        private unsafe void InitializeStream() {
            if (_mmf != null) {
                _mmfPtr = IntPtr.Zero;
                _accessor.Dispose();
                _mmf.Dispose();
            }

            if (_user == null) {
                return;
            }

            _mmf = MemoryMappedFile.CreateOrOpen(SharedSettings.OutputStreamPrefix + _user.AcUserID, _mmfSize, MemoryMappedFileAccess.ReadWrite);
            _accessor = _mmf.CreateViewAccessor();
            var ptr = (byte*)IntPtr.Zero;
            _accessor.SafeMemoryMappedViewHandle.AcquirePointer(ref ptr);
            *(int*)&ptr[0] = AudioSettings.outputSampleRate;
            *(int*)&ptr[4] = (int)AudioSettings.speakerMode;
            *(int*)&ptr[8] = FMOD_SOUND_FORMAT_PCMFLOAT;
            *(int*)&ptr[12] = AudioSettings.outputSampleRate / 25;
            *(int*)&ptr[16] = AudioSettings.outputSampleRate * sizeof(float) / 25;
            *(long*)&ptr[24] = 0;
            // ClearStorage(ptr);
            _mmfPtr = (IntPtr)ptr;
        }

        private int _nextPos;

        private unsafe void PushStream(float[] data, int numSamples, bool isFirst) {
            var ptr = (byte*)_mmfPtr;
            if (ptr == null || numSamples == 0) return;

            var maxValue = 0f;
            var mult = volume;
            if (isFirst) {
                _nextPos = 0;
            }

            var left = _mmfItemsCount - _nextPos;
            var block1 = Math.Min(left, numSamples);
            var dst = (float*)&ptr[_fmodPrefixSize + _nextPos * _fmodItemSize];
            for (var i = 0; i < block1; i++) {
                var f = data[i];
                var a = Math.Abs(f);
                if (a > maxValue) maxValue = a;
                *dst = f * mult;
                ++dst;
            }

            if (numSamples >= left) {
                var block2 = numSamples - left;
                if (block2 > 0) {
                    dst = (float*)&ptr[_fmodPrefixSize];
                    for (var i = 0; i < block2; i++) {
                        var f = data[left + i];
                        var a = Math.Abs(f);
                        if (a > maxValue) maxValue = a;
                        *dst = f * mult;
                        ++dst;
                    }
                }
                _nextPos = block2;
            } else {
                _nextPos += numSamples;
            }

            PeakValue = maxValue;
            if (maxValue > ActiveThreshold) {
                ActiveFor = ActivePeriod;
            }

            Interlocked.MemoryBarrier();
            if (isFirst) {
                *(long*)&ptr[24] = numSamples * _fmodItemSize;
            } else {
                *(long*)&ptr[24] += numSamples * _fmodItemSize;
            }
        }

        public bool _isActuallyPlaying;

        private void ResetPlayback() {
            _isActuallyPlaying = false;
            _outputWriteCursor = 0;
            _outputReadCursor = 0;
            _bytesWritten = 0;
            _bytesRead = 0;
        }

        internal bool ReadyToReceive() {
            if (_disposed) {
                return false;
            }

            var init = _initializationEnqueued;
            if (init != null) {
                _initializationEnqueued = null;
                init();
            }

            if (volume <= 0f || _user == null || !_user.IsToBeHeard) {
                ResetPlayback();
                return false;
            }

            return true;
        }

        internal void ReceiveDecodedVoice(float[] pcmData, int numSamples, MuVec3 posData, bool isFirst, bool isLast) {
            if (isFirst) {
                ResetPlayback();
            }

            if (pcmData != null) {
                if (!_isActuallyPlaying) {
                    _isActuallyPlaying = true;
                }
                
                if (isFirst) {
                    for (var i = 0; i < numSamples; ++i) {
                        pcmData[i] *= (float)(i + 1) / numSamples;
                    }
                }

                if (isLast) {
                    for (var i = 0; i < numSamples; ++i) {
                        pcmData[i] *= 1f - (float)i / numSamples;
                    }
                }

                if (!_initialized || _requiresInitialization) {
                    if (_requiresInitialization) {
                        _requiresInitialization = false;
                    } else {
                        _initialized = true;
                        if (_outputLength < _samplesPerFrame * 20
                                || _outputLength > _samplesPerFrame * 80) {
                            throw new Exception("Incorrect size of output buffer");
                        }
                        SharedSettings.DeviceSettingChange += OnOutputDeviceChange;
                    }
                    InitializeDevice();
                }

                if (!string.IsNullOrEmpty(SharedSettings.OutputStreamPrefix)) {
                    PushStream(pcmData, numSamples, isFirst);
                } else {
                    if (_outputData == null) {
                        _outputData = OutputDataPool.GetOrAllocate();
                    }

                    var maxValue = 0f;
                    for (var i = pcmData.Length - 1; i >= 0; i--) {
                        var a = Math.Abs(pcmData[i]);
                        if (a > maxValue) maxValue = a;
                    }

                    PeakValue = maxValue;
                    if (maxValue > ActiveThreshold) {
                        ActiveFor = ActivePeriod;
                    }

                    GainEstimator.Update(posData, ref _gainLeft, ref _gainRight, ref _offsetLeft, ref _offsetRight);

                    var cur = _outputWriteCursor;
                    const int outputLen = _outputLength;
                    if (cur + numSamples > outputLen) {
                        var leftToFill = outputLen - cur;
                        Buffer.BlockCopy(pcmData, 0, _outputData, cur * sizeof(float),
                                leftToFill * sizeof(float));
                        Buffer.BlockCopy(pcmData, leftToFill * sizeof(float), _outputData, 0,
                                (numSamples - leftToFill) * sizeof(float));
                        cur = numSamples - leftToFill;
                    } else {
                        Buffer.BlockCopy(pcmData, 0, _outputData, cur * sizeof(float),
                                numSamples * sizeof(float));
                        if ((cur += numSamples) == outputLen) {
                            cur = 0;
                        }
                    }
                    _outputWriteCursor = cur;

                    _bytesWritten += numSamples * 2;
                    if (_waveOut != null && _waveOut.PlaybackState != PlaybackState.Playing) {
                        _waveOut.Play();
                    }
                }
            }

            if (isLast) {
                _isActuallyPlaying = false;
                if (_waveOut != null && _waveOut.PlaybackState != PlaybackState.Stopped) {
                    _waveOut.Stop();
                }
            }
        }

        private bool _initializing;
        private bool _requiresInitialization;
        private bool _requiresReinitialization;
        private Action _initializationEnqueued;

        public AudioSource(UserState user) {
            _user = user;
        }

        private void InitializeDevice() {
            if (_initializing) {
                _requiresReinitialization = true;
                return;
            }

            _mmfPtr = IntPtr.Zero;
            _initializing = true;

            Task.Run(() => {
                WaveOutEvent waveOut = null;
                try {
                    if (!string.IsNullOrEmpty(SharedSettings.OutputStreamPrefix)) {
                        InitializeStream();
                    } else {
                        var outDevice = DevicesHolder.GetOut(SharedSettings.OutputDeviceName);
                        if (outDevice == null) {
                            throw new Exception("No output device available");
                        }
                        waveOut = new WaveOutEvent {
                            DesiredLatency = SharedSettings.OutputDesiredLatency,
                            DeviceNumber = outDevice.WaveIndex
                        };
                        waveOut.Init(this);
                    }
                } catch (Exception e) {
                    Debug.LogError("Failed to initialize output device: " + e);
                    Environment.Exit(ExitCode.AudioFailure);
                    return;
                }

                _initializationEnqueued = () => {
                    if (_disposed) {
                        Task.Run(() => {
                            waveOut?.Dispose();
                            _accessor?.Dispose();
                            _mmf?.Dispose();
                        });
                        return;
                    }

                    var old = _waveOut;
                    _waveOut = waveOut;
                    _outputWriteCursor = 0;
                    _outputReadCursor = 0;
                    _bytesWritten = 0;
                    _bytesRead = 0;
                    Task.Run(() => old?.Dispose());

                    _initializing = false;
                    if (_requiresReinitialization) {
                        InitializeDevice();
                    }
                };
            });
        }

        private void OnOutputDeviceChange(object sender, SharedSettings.SettingChangeEventArgs args) {
            if ((_waveOut != null || _mmfPtr != IntPtr.Zero)
                    && ((args.Key == nameof(SharedSettings.OutputDeviceName)
                            || args.Key == nameof(SharedSettings.OutputDesiredLatency)) && string.IsNullOrEmpty(SharedSettings.OutputStreamPrefix)
                            || args.Key == nameof(SharedSettings.OutputStreamPrefix))) {
                _requiresInitialization = true;
            }
        }

        unsafe int IWaveProvider.Read(byte[] buffer, int offsetBytes, int countBytes) {
            if (_bytesWritten < _bytesRead + countBytes * 2 || _outputData == null || ActiveFor == 0f) {
                Array.Clear(buffer, offsetBytes, countBytes);
                return countBytes;
            }

            var gapInFront = _bytesWritten - _bytesRead;
            if (gapInFront > countBytes * 6) {
                Debug.Log($"Gap is too large ({gapInFront} > {countBytes} * 6), resetting");
                var newGap = countBytes * 3 / 2;
                _bytesRead = _bytesWritten - newGap;
                _outputReadCursor = _outputWriteCursor - newGap / sizeof(float);
                if (_outputReadCursor < 0) {
                    _outputReadCursor += _outputLength;
                }
            }

            var gl = _gainLeft * volume * OutputVolume;
            var gr = _gainRight * volume * OutputVolume;
            var ol = (uint)Math.Max(Math.Round(_offsetLeft), 0f);
            var or = (uint)Math.Max(Math.Round(_offsetRight), 0f);

            _bytesRead += AudioSettings.speakerMode == AudioSpeakerMode.Mono && _outSpeakerMode == AudioSpeakerMode.Stereo ? countBytes / 2 : countBytes;
            var outputPos = _outputReadCursor;
            var countItems = countBytes / sizeof(short);
            fixed (byte* fixedBuffer = &buffer[offsetBytes]) {
                var dst = (short*)fixedBuffer;
                if (AudioSettings.speakerMode == AudioSpeakerMode.Mono) {
                    if (_outSpeakerMode == AudioSpeakerMode.Mono) {
                        for (var i = countItems; i != 0; --i) {
                            *dst++ = (short)(Mathf.Clamp(_outputData[(outputPos + ol) % _outputLength] * gl, -1f, 1f) * short.MaxValue);
                            ++outputPos;
                        }
                    } else {
                        for (var i = countItems / 2; i != 0; --i) {
                            *dst++ = (short)(Mathf.Clamp(_outputData[(outputPos + ol) % _outputLength] * gl, -1f, 1f) * short.MaxValue);
                            *dst++ = (short)(Mathf.Clamp(_outputData[(outputPos + or) % _outputLength] * gr, -1f, 1f) * short.MaxValue);
                            ++outputPos;
                        }
                    }
                } else {
                    for (var i = countItems; i != 0; --i) {
                        var v = outputPos % 2 == 0 ? gl : gr;
                        var o = outputPos % 2 == 0 ? ol : or;
                        *dst++ = (short)(Mathf.Clamp(_outputData[(outputPos++ + o) % _outputLength] * v, -1f, 1f) * short.MaxValue);
                    }
                }
            }
            _outputReadCursor = outputPos;
            return countBytes;
        }

        public unsafe void Dispose() {
            var ptr = (byte*)_mmfPtr;
            if (ptr != null) {
                *(long*)&ptr[24] = 0;
                _mmfPtr = IntPtr.Zero;
            }
            _waveOut?.Dispose();
            _accessor?.Dispose();
            _mmf?.Dispose();
            _disposed = true;
            _initializationEnqueued?.Invoke();
            SharedSettings.DeviceSettingChange -= OnOutputDeviceChange;
            OutputDataPool.Release(ref _outputData);
        }
    }
}