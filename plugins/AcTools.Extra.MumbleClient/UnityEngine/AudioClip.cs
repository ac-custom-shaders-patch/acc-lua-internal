using System;
using System.Threading;
using System.Threading.Tasks;
using AcTools.Extra.MumbleClient.Implementation.Utils;
using NAudio.Wave;

namespace UnityEngine {
    public class AudioClip {
        public static bool OptionUseWasAPI = false;
        public static float PeakVolume;
        public static float BatchPeakVolume;
        public static float MicVolume = 1f;

        private WaveInEvent _recordingWave;
        private AudioFilterWrapper _filter;
        private float[] _data;
        private int _recorded;
        private int _recordedTotal;
        private int _peakChecked;
        private int _peakPerFrame;

        private static AudioFilterWrapper _previousFilter;
        private static readonly MemoryPool<float> Pool = new MemoryPool<float>("Mic Samples Pool", 48000);

        public AudioClip(string micName, int numRecordingSeconds, int sampleRate) {
            _data = Pool.GetOrAllocate(numRecordingSeconds * sampleRate);

            var format = new WaveFormat(sampleRate, 16, 1);
            if (Equals(_previousFilter?.Format, format)) {
                _filter = _previousFilter;
                _previousFilter = null;
            } else {
                _previousFilter?.Dispose();
                _previousFilter = null;
                _filter = new AudioFilterWrapper(format);
            }

            _peakPerFrame = (int)(MonoBehaviour._periodMs * sampleRate / 1000);

            Task.Run(() => {
                var device = DevicesHolder.GetIn(micName);
                if (device == null) {
                    return;
                }
                
                if (OptionUseWasAPI && device.Device != null) {
                    /*_recordingWasApi = new WasapiCapture(device.Device, false, 20) {
                        ShareMode = AudioClientShareMode.Shared
                    };
                    Debug.Log("Record using WasAPI: " + _recordingWasApi.WaveFormat + ", expected: " + format);
                    if (_recorded == -1) {
                        _recordingWasApi.Dispose();
                        return;
                    }
                    
                    if (_recordingWasApi.WaveFormat.Equals(format)) {
                        _recordingWasApi.DataAvailable += OnRecordedData;
                        _recordingWasApi.StartRecording();
                    } else {
                        _loopbackPlayBuffer = new CircularBuffer();
                        _resampler = new MediaFoundationResampler(new ResampleWaveProvider(this), format);
                        _resampledData = new byte[sampleRate / 50];
                        if (_recorded == -1) {
                            _recordingWasApi.Dispose();
                            _resampler.Dispose();
                        } else {
                            var bytesPerSample = _recordingWasApi.WaveFormat.BlockAlign;
                            _recordingWasApi.DataAvailable += (s, e) => {
                                _loopbackPlayBuffer.Write(e.Buffer, 0, e.BytesRecorded);
                                var samples = e.BytesRecorded / bytesPerSample;
                                Interlocked.Add(ref _bytesAwaitingResample, samples * 2);
                            };
                            _recordingWasApi.StartRecording();
                        }
                    }*/
                } else {
                    // Debug.Log("Record using WaveIn");
                    try {
                        _recordingWave = new WaveInEvent {
                            WaveFormat = format,
                            BufferMilliseconds = SharedSettings.InputBufferMilliseconds,
                            NumberOfBuffers = 3,
                            DeviceNumber = device.WaveIndex
                        };
                        if (_recorded == -1) {
                            _recordingWave.Dispose();
                        } else {
                            _recordingWave.DataAvailable += OnRecordedData;
                            _recordingWave.StartRecording();
                        }
                    } catch (Exception e) {
                        Debug.LogError($"Failed to initialize WaveIn device: {e.Message}");
                        _recordingWave?.Dispose();
                        _recordingWave = null;
                    }
                }
            });
        }
        
        /*
        
        private WasapiCapture _recordingWasApi;
        private int _bytesAwaitingResample;         
        private CircularBuffer _loopbackPlayBuffer;
        private MediaFoundationResampler _resampler;
        private byte[] _resampledData;

        private class ResampleWaveProvider : IWaveProvider {
            private readonly AudioClip _parent;

            public ResampleWaveProvider(AudioClip parent) {
                _parent = parent;
            }

            public int Read(byte[] buffer, int offset, int count) {
                return _parent._loopbackPlayBuffer.Read(buffer, offset, count);
            }

            public WaveFormat WaveFormat => _parent._recordingWasApi.WaveFormat;
        }        

        private void ShoveNeedingResample() {
            while (_bytesAwaitingResample >= _resampledData.Length) {
                var readBytes = _resampler.Read(_resampledData, 0, _resampledData.Length);
                if (readBytes != _resampledData.Length) throw new Exception("What");
                ProcessChunk(_resampledData, _resampledData.Length);
                Interlocked.Add(ref _bytesAwaitingResample, -readBytes);
            }
        }*/

        // Expects single-channel PCM16 data
        private unsafe void ProcessChunk(byte[] buffer, int bytes) {
            _filter.Process(buffer, bytes);

            var recorded = _recorded;
            var left = _data.Length - recorded;
            if (left == 0) {
                left = recorded;
                recorded = 0;
            }
            var count = bytes / 2;
            var mult = MicVolume / short.MaxValue;
            var maxVolume = 0f;
            if (count <= left) {
                var start = recorded;
                fixed (byte* raw = buffer) {
                    var src = (short*)raw;
                    for (var i = count; i != 0; --i) {
                        var v = *src++ * mult;
                        var a = Math.Abs(v);
                        if (a > maxVolume) maxVolume = a;
                        _data[recorded++] = v;
                    }
                }
                _filter.Process(_data, start, recorded - start);
            } else {
                var start = recorded;
                fixed (byte* raw = buffer) {
                    var src = (short*)raw;
                    for (var i = left; i != 0; --i) {
                        var v = *src++ * mult;
                        var a = Math.Abs(v);
                        if (a > maxVolume) maxVolume = a;
                        _data[recorded++] = v;
                    }
                    recorded = 0;
                    for (var i = count - left; i != 0; --i) {
                        var v = *src++ * mult;
                        var a = Math.Abs(v);
                        if (a > maxVolume) maxVolume = a;
                        _data[recorded++] = v;
                    }
                }
                _filter.Process(_data, start, _data.Length - start);
                _filter.Process(_data, 0, recorded);
            }
            _peakChecked = _recorded;
            _recorded = recorded;
            BatchPeakVolume = maxVolume;
            
            Interlocked.MemoryBarrier();
            _recordedTotal += count;
        }

        private void OnRecordedData(object s, WaveInEventArgs a) {
            ProcessChunk(a.Buffer, a.BytesRecorded);
        }

        public void GetData(float[] dst, int offset) {
            if (_recorded <= 0) {
                Array.Clear(dst, 0, dst.Length);
                return;
            }

            offset %= _data.Length;
            if (offset + dst.Length > _data.Length) {
                var bytes1 = Math.Min(dst.Length, _data.Length - offset) * sizeof(float);
                Buffer.BlockCopy(_data, offset * sizeof(float), dst, 0, bytes1);
                Buffer.BlockCopy(_data, 0, dst, bytes1, dst.Length * sizeof(float) - bytes1);
            } else {
                Buffer.BlockCopy(_data, offset * sizeof(float), dst, 0, dst.Length * sizeof(float));
            }
        }

        public void UpdatePeakValue() {
            var limit = Math.Min(_data.Length, _peakChecked + _peakPerFrame);
            if (_peakChecked < limit) {
                var maxVolume = 0f;
                for (var i = _peakChecked; i < limit; ++i) {
                    maxVolume = Math.Max(maxVolume, Math.Abs(_data[i]));
                }
                _peakChecked = limit;
                PeakVolume = maxVolume;
            } else {
                PeakVolume *= 0.8f;
            }
        }

        public int GetPosition() {
            /*if (_bytesAwaitingResample > 0) {
                ShoveNeedingResample();
            }*/
            return _recordedTotal;
        }

        public void End() {
            _recorded = -1;
            _recordedTotal = 0;
            _recordingWave?.StopRecording();
            _recordingWave?.Dispose();
            // _bytesAwaitingResample = 0;
            // _recordingWasApi?.StopRecording();
            // _recordingWasApi?.Dispose();
            // _resampler?.Dispose();
            _previousFilter = _filter;
            Pool.Release(ref _data);
        }
    }
}