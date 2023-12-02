using System;
using UnityEngine;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public class UserTransformState {
        public MuVec3 Pos = MuVec3.Invalid;
        public MuVec3 Dir = new MuVec3 { Z = 1f };
        public MuVec3 Up = new MuVec3 { Y = 1f };

        private static float CalculateGain(float dotFactor, float distance) {
            if (SharedSettings.AudioMaxDistVolume > 0.99f) {
                return Math.Min(1f, dotFactor + SharedSettings.AudioBloom);
            }
            
            if (distance < SharedSettings.AudioMinDistance) {
                var bloomFactor = SharedSettings.AudioBloom * (1f - distance / SharedSettings.AudioMinDistance);
                return Math.Min(1f, bloomFactor + dotFactor);
            }
            
            if (distance >= SharedSettings.AudioMaxDistance) {
                return SharedSettings.AudioMaxDistVolume * dotFactor;
            }
            
            var maxDistVolume = Math.Max(0.01f, SharedSettings.AudioMaxDistVolume);
            var relativeDistance = (distance - SharedSettings.AudioMinDistance)
                    / (SharedSettings.AudioMaxDistance - SharedSettings.AudioMinDistance);
            return (float)Math.Pow(10f, Math.Log10(maxDistVolume) * relativeDistance) * dotFactor;
        }
        
        private const float InterauralDelay = 0.00043f * AudioSettings.outputSampleRate;

        private static void CalculateSideValues(float dotFactor, float distance, ref float gain, ref float offset) {
            var newGain = (1f + 19f * CalculateGain(dotFactor, distance)) / 20f;
            newGain = Math.Min(newGain, Math.Max(1f - distance / SharedSettings.AudioMuteDistance, 0f));
            gain += (newGain - gain) * 0.1f;
            
            var newOffset = InterauralDelay * dotFactor;
            offset += (newOffset - offset) * 0.1f;
        }

        public void Estimate3dGainFor(MuVec3 others, ref float gainLeft, ref float gainRight, ref float offsetLeft, ref float offsetRight) {
            if (Pos.IsValid() && others.IsValid()) {
                // Source: https://github.com/mumble-voip/mumble/blob/f73db9da7ac81eda2c6eeacad6c97d97481a5e65/src/mumble/AudioOutput.cpp#L673
                var delta = Pos - others;
                var distance = delta.Length();
                if (distance < 0.001f) {
                    gainLeft = 1f;
                    gainRight = 1f;
                    offsetLeft = 0f;
                    offsetRight = 0f;
                } else {
                    var dotProduct = MuVec3.Dot(delta / distance, (MuVec3.Cross(Dir, Up).Normalize() + Dir * 0.2f).Normalize());
                    CalculateSideValues((1f + dotProduct) / 2f, distance, ref gainLeft, ref offsetLeft);
                    CalculateSideValues((1f - dotProduct) / 2f, distance, ref gainRight, ref offsetRight);
                }
            } else {
                gainLeft = 1f;
                gainRight = 1f;
                offsetLeft = 0f;
                offsetRight = 0f;
            }
        }
    }
}