using System;
using System.Threading.Tasks;
using AcTools.Extra.MumbleClient.Implementation.Filters;
using NAudio.Wave;
using Debug = UnityEngine.Debug;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public class AudioFilterWrapper : IDisposable {
        public static readonly ConfigVirtualProcessor FilterConfig = new ConfigVirtualProcessor(x => x.StartsWith("filter."));

        public static bool VoiceActivityDetected { get; private set; }

        private FilterSpeexDSP _filterSpeexDSP;
        private FilterRNNoise _filterRNN;
        private bool _dirty;
        private bool _disposed;

        public readonly WaveFormat Format;

        public AudioFilterWrapper(WaveFormat format) {
            Format = format;
            _dirty = true;
            FilterConfig.Update += OnConfigUpdate;
        }

        private void OnConfigUpdate(object sender, ConfigVirtualProcessor.ConfigEventArgs args) {
            _dirty = true;
        }

        private void ValidateSettings() {
            if (!_dirty) return;
            _dirty = false;

            var config = FilterConfig;
            if (config.Bool("filter.speexDSP") ?? false) {
                if (_filterSpeexDSP == null) {
                    _filterSpeexDSP = new FilterSpeexDSP(Format);
                }
            } else {
                _filterSpeexDSP?.Dispose();
                _filterSpeexDSP = null;
            }

            if (_filterSpeexDSP != null) {
                _filterSpeexDSP.NoiseSupress = config.Int("filter.speexDSP.denoise.suppress") ?? -25;
                _filterSpeexDSP.DenoiseActive = config.Bool("filter.speexDSP.denoise") ?? false;

                _filterSpeexDSP.EchoSuppressActive = config.Int("filter.speexDSP.echo.suppressActive") ?? -45;
                _filterSpeexDSP.EchoSupress = config.Int("filter.speexDSP.echo.suppress") ?? -45;
                _filterSpeexDSP.EchoActive = config.Bool("filter.speexDSP.echo") ?? false;

                _filterSpeexDSP.VadProbStart = config.Int("filter.speexDSP.voiceActivityDetector.start") ?? 85;
                _filterSpeexDSP.VadProbContinue = config.Int("filter.speexDSP.voiceActivityDetector.continue") ?? 65;
                _filterSpeexDSP.VadActive = config.Bool("filter.speexDSP.voiceActivityDetector") ?? false;

                _filterSpeexDSP.AgcLevel = config.Int("filter.speexDSP.autoGainControl.level") ?? 24000;
                _filterSpeexDSP.AgcActive = config.Bool("filter.speexDSP.autoGainControl") ?? false;
            }

            if (config.Bool("filter.rnnNoise") ?? false) {
                if (_filterRNN == null) {
                    _filterRNN = new FilterRNNoise();
                }
            } else {
                _filterRNN?.Dispose();
                _filterRNN = null;
            }
        }

        public void Process(byte[] data, int count) {
            if (_disposed) return;
            try {
                ValidateSettings();
                if (_filterSpeexDSP != null) {
                    _filterSpeexDSP.Process(data, count);
                    VoiceActivityDetected = _filterSpeexDSP.IsTalking;
                } else {
                    VoiceActivityDetected = false;
                }
            } catch (Exception e) {
                Debug.LogWarning("Failed to run PCM16 filter: " + e);
            }
        }

        public void Process(float[] data, int offset, int count) {
            if (_disposed) return;
            try {
                _filterRNN?.Process(data, offset, count);
            } catch (Exception e) {
                Debug.LogWarning("Failed to run float filter: " + e);
            }
        }

        public void Dispose() {
            _disposed = true;
            FilterConfig.Update -= OnConfigUpdate;
            Task.Delay(200).ContinueWith(r => {
                _filterSpeexDSP?.Dispose();
                _filterRNN?.Dispose();
            });
        }
    }
}