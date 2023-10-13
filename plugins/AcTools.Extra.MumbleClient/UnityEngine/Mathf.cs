using System;

namespace Mumble {
    public static class Mathf {
        public static float Clamp(float v, float min, float max) {
            if (v > min) {
                return v < max ? v : max;
            }
            return min;
        }

        public static float Abs(float f) {
            return f < 0 ? -f : f;
        }

        public static int RoundToInt(float v) {
            return (int)Math.Round(v);
        }
    }
}