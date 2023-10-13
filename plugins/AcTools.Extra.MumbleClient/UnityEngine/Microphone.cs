using System;

namespace UnityEngine {
    public class Microphone {
        private static AudioClip _currentRecording;

        public static AudioClip Start(string micName, int numRecordingSeconds, int sampleRate) {
            if (_currentRecording != null) throw new Exception("Already recording");
            var clip = new AudioClip(micName, numRecordingSeconds, sampleRate);
            _currentRecording = clip;
            return clip;
        }

        public static void End() {
            if (_currentRecording != null) {
                _currentRecording.End();
                _currentRecording = null;
            }
        }

        public static int GetPosition() {
            return _currentRecording?.GetPosition() ?? 0;
        }
    }
}