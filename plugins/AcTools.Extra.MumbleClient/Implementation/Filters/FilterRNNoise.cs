using System;
using AcTools.Extra.MumbleClient.Implementation.External;
using Mumble;

namespace AcTools.Extra.MumbleClient.Implementation.Filters {
    public class FilterRNNoise : IDisposable {
        private const int FrameSize = 480;
        private readonly float[] _processBuffer;
        private readonly IntPtr _denoiseState;

        public FilterRNNoise() {
            _processBuffer = new float[FrameSize];
            _denoiseState = RNNoise.rnnoise_create();
        }

        public void Process(float[] buffer, int offset, int count) {
            ApplyDenoise(buffer, offset, count);
        }

        public void Dispose() {
            RNNoise.rnnoise_destroy(_denoiseState);
        }

        private void ApplyDenoise(float[] buffer, int offset, int count) {
            const float scaleInput = short.MaxValue;
            const float scaleOutput = 1f / short.MaxValue;
            var processBuffer = _processBuffer;
            while (count > 0) {
                var chunk = Math.Min(count, FrameSize);
                for (var idx = 0; idx < chunk; ++idx) {
                    processBuffer[idx] = buffer[offset + idx] * scaleInput;
                }
                if (chunk < FrameSize) {
                    Array.Clear(processBuffer, chunk, FrameSize - chunk);
                }
                RNNoise.rnnoise_process_frame(_denoiseState, processBuffer, processBuffer);
                for (var idx = 0; idx < chunk; ++idx) {
                    buffer[offset + idx] = Mathf.Clamp(processBuffer[idx] * scaleOutput, -1f, 1f);
                }
                count -= chunk;
                offset += chunk;
            }
        }
    }
}