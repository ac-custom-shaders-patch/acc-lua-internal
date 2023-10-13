using System;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public class SharedSettings {
        public class SettingChangeEventArgs : EventArgs {
            public SettingChangeEventArgs(string key) {
                Key = key;
            }
            
            public string Key { get; }
        }
        
        public static event EventHandler<SettingChangeEventArgs> DeviceSettingChange;

        public static string OutputStreamPrefix;
        public static string OutputDeviceName;
        public static int OutputDesiredLatency = 100;
        public static int InputBufferMilliseconds = 100;
        
        public static float AudioBloom = 0.5f;
        public static float AudioMaxDistance = 15f;
        public static float AudioMaxDistVolume = 0.25f;
        public static float AudioMinDistance = 1f;
        public static float VoiceHoldSeconds = 1f;

        public static void SetStreamPrefix(string streamPrefix) {
            if (OutputStreamPrefix == streamPrefix) return;
            OutputStreamPrefix = streamPrefix;
            DeviceSettingChange?.Invoke(null, new SettingChangeEventArgs(nameof(OutputStreamPrefix)));
        }

        public static void SetOutputDevice(string deviceName) {
            if (OutputDeviceName == deviceName) return;
            OutputDeviceName = deviceName;
            DeviceSettingChange?.Invoke(null, new SettingChangeEventArgs(nameof(OutputDeviceName)));
        }

        public static void SetOutputDesiredLatency(int latency) {
            if (OutputDesiredLatency == latency) return;
            OutputDesiredLatency = latency;
            DeviceSettingChange?.Invoke(null, new SettingChangeEventArgs(nameof(OutputDesiredLatency)));
        }

        public static void SetInputBufferMilliseconds(int buffer) {
            if (InputBufferMilliseconds == buffer) return;
            InputBufferMilliseconds = buffer;
            DeviceSettingChange?.Invoke(null, new SettingChangeEventArgs(nameof(InputBufferMilliseconds)));
        }
        
        public static readonly CommandProcessor Processor = new CommandProcessor {
            ["audio.positional.bloom"] = p => AudioBloom = p.Float(),
            ["audio.positional.maxDistance"] = p => AudioMaxDistance = p.Float(),
            ["audio.positional.maxDistanceVolume"] = p => AudioMaxDistVolume = p.Float(),
            ["audio.positional.minDistance"] = p => AudioMinDistance = p.Float(),
            ["audio.inputMode.holdSeconds"] = p => VoiceHoldSeconds = p.Float(),
            
            ["system.streamConnectPointsPrefix"] = p => SetStreamPrefix(p.String()),
            ["audio.outputDevice"] = p => SetOutputDevice(p.String()),
            ["audio.outputDesiredLatency"] = p => SetOutputDesiredLatency(p.Int()),
            ["audio.inputBufferMilliseconds"] = p => SetInputBufferMilliseconds(p.Int()),
        };
    }
}