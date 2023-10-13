using System.Globalization;
using System.Runtime.InteropServices;

namespace AcTools.Extra.GamepadServer {
    public struct GamepadState {
        public long CurrentTime;
        public long PacketTime;
        public float Steer;
        public float Gas;
        public float Brake;
        public float Clutch;
        public float Handbrake;

        public float Touch1X;
        public float Touch1Y;
        public float Touch2X;
        public float Touch2Y;

        [MarshalAs(UnmanagedType.I1)]
        public bool GearUp;

        [MarshalAs(UnmanagedType.I1)]
        public bool GearDown;

        [MarshalAs(UnmanagedType.I1)]
        public bool HeadlightsSwitch;

        [MarshalAs(UnmanagedType.I1)]
        public bool HeadlightsFlash;

        [MarshalAs(UnmanagedType.I1)]
        public bool ChangingCamera;

        [MarshalAs(UnmanagedType.I1)]
        public bool Horn;

        [MarshalAs(UnmanagedType.I1)]
        public bool AbsDown;

        [MarshalAs(UnmanagedType.I1)]
        public bool AbsUp;

        [MarshalAs(UnmanagedType.I1)]
        public bool TcDown;

        [MarshalAs(UnmanagedType.I1)]
        public bool TcUp;

        [MarshalAs(UnmanagedType.I1)]
        public bool TurboDown;

        [MarshalAs(UnmanagedType.I1)]
        public bool TurboUp;

        [MarshalAs(UnmanagedType.I1)]
        public bool WiperDown;

        [MarshalAs(UnmanagedType.I1)]
        public bool WiperUp;

        [MarshalAs(UnmanagedType.I1)]
        public bool Pause;

        [MarshalAs(UnmanagedType.I1)]
        public bool PovClick;

        [MarshalAs(UnmanagedType.I1)]
        public byte Pov;

        [MarshalAs(UnmanagedType.I1)]
        public bool NeutralGear;

        [MarshalAs(UnmanagedType.I1)]
        public bool LowBeams;

        [MarshalAs(UnmanagedType.I1)]
        public bool ModeSwitch;

        [MarshalAs(UnmanagedType.I1)]
        public byte BatteryCharge;

        [MarshalAs(UnmanagedType.I1)]
        public bool BatteryCharging;

        public static int Size = Marshal.SizeOf(typeof(GamepadState));

        private static float ParseWrapped(string v) {
            return int.Parse(v, NumberStyles.Any, CultureInfo.InvariantCulture) / 999f;
        }

        public bool Parse(string data, GamepadInterpolator interpolator) {
            var ret = false;
            foreach (var s in data.Split(';')) {
                if (s.Length == 0) continue;
                switch (s[0]) {
                    case 'P':
                        interpolator.ReportPing(long.Parse(s.Substring(1), NumberStyles.Any, CultureInfo.InvariantCulture));
                        break;
                    case 'S':
                        Steer = float.Parse(s.Substring(1), NumberStyles.Any, CultureInfo.InvariantCulture);
                        ret = true;
                        break;
                    case 'I': {
                        var p = s.Substring(1).Split(',');
                        Gas = ParseWrapped(p[0]);
                        Brake = ParseWrapped(p[1]);
                        Clutch = ParseWrapped(p[2]);
                        Handbrake = ParseWrapped(p[3]);
                        GearUp = p[4].IndexOf('G') != -1;
                        GearDown = p[4].IndexOf('g') != -1;
                        HeadlightsSwitch = p[4].IndexOf('L') != -1;
                        HeadlightsFlash = p[4].IndexOf('l') != -1;
                        ChangingCamera = p[4].IndexOf('C') != -1;
                        Horn = p[4].IndexOf('H') != -1;
                        AbsDown = p[4].IndexOf('A') != -1;
                        AbsUp = p[4].IndexOf('a') != -1;
                        TcDown = p[4].IndexOf('T') != -1;
                        TcUp = p[4].IndexOf('t') != -1;
                        TurboDown = p[4].IndexOf('U') != -1;
                        TurboUp = p[4].IndexOf('u') != -1;
                        WiperDown = p[4].IndexOf('W') != -1;
                        WiperUp = p[4].IndexOf('w') != -1;
                        Pause = p[4].IndexOf('E') != -1;
                        PovClick = p[4].IndexOf('P') != -1;
                        Pov = (byte)(p[4].IndexOf('^') != -1 ? 1 : p[4].IndexOf('>') != -1 ? 2
                                : p[4].IndexOf('_') != -1 ? 3 : p[4].IndexOf('<') != -1 ? 4 : 0);
                        NeutralGear = p[4].IndexOf('-') != -1;
                        LowBeams = p[4].IndexOf('b') != -1;
                        ModeSwitch = p[4].IndexOf('D') != -1;
                        break;
                    }
                    case 'T': {
                        var p = s.Substring(1).Split(',');
                        Touch1X = p.Length > 1 ? ParseWrapped(p[0]) : 0;
                        Touch1Y = p.Length > 1 ? ParseWrapped(p[1]) : 0;
                        Touch2X = p.Length > 3 ? ParseWrapped(p[2]) : 0;
                        Touch2Y = p.Length > 3 ? ParseWrapped(p[3]) : 0;
                        break;
                    }
                    case 'B': {
                        var p = s.Substring(1).Split(',');
                        BatteryCharge = (byte)int.Parse(p[0], NumberStyles.Any, CultureInfo.InvariantCulture);
                        BatteryCharging = p[1] == "1";
                        break;
                    }
                }
            }
            return ret;
        }
    }
}