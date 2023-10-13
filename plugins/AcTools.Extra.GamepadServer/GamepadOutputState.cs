using System.Runtime.InteropServices;

namespace AcTools.Extra.GamepadServer {
    public struct GamepadOutputState {
        public int Color;
        
        [MarshalAs(UnmanagedType.I1)]
        public byte VibrationLeft;
        
        [MarshalAs(UnmanagedType.I1)]
        public byte VibrationRight;
        
        [MarshalAs(UnmanagedType.I2)]
        public ushort RelativeRpm;

        [MarshalAs(UnmanagedType.I1)]
        public bool HeadlightsActive;

        [MarshalAs(UnmanagedType.I1)]
        public bool LowBeamsActive;

        [MarshalAs(UnmanagedType.I1)]
        public bool AbsOff;

        [MarshalAs(UnmanagedType.I1)]
        public bool TcOff;

        [MarshalAs(UnmanagedType.I1)]
        public bool AbsPresent;

        [MarshalAs(UnmanagedType.I1)]
        public bool TcPresent;

        [MarshalAs(UnmanagedType.I1)]
        public bool TurboPresent;

        [MarshalAs(UnmanagedType.I1)]
        public bool ClutchPresent;

        [MarshalAs(UnmanagedType.I1)]
        public bool WipersPresent;

        [MarshalAs(UnmanagedType.I1)]
        public bool HeadlightsPresent;

        [MarshalAs(UnmanagedType.I1)]
        public bool Paused;

        [MarshalAs(UnmanagedType.I1)]
        public bool NeedsDPad;

        [MarshalAs(UnmanagedType.I1)]
        public bool DriftMode;

        [MarshalAs(UnmanagedType.I1)]
        public byte GearsCount;

        [MarshalAs(UnmanagedType.I1)]
        public byte Gear;
        
        public static int Size = Marshal.SizeOf(typeof(GamepadOutputState));

        public string SerializedColor => HexConverter(System.Drawing.Color.FromArgb(Color));
        
        public int SerializedRpm => 999 * RelativeRpm / ushort.MaxValue;

        public string SerializedGear => Gear == 0 ? "R" : Gear == 1 ? "N" : (Gear - 1).ToString();

        public static GamepadOutputState Defaults => new GamepadOutputState {
            AbsPresent = true,
            GearsCount = 5,
            Gear = 1,
            ClutchPresent = true,
            WipersPresent = true,
            HeadlightsPresent = true
        };

        private static string HexConverter(System.Drawing.Color c) {
            return "#" + c.R.ToString("X2") + c.G.ToString("X2") + c.B.ToString("X2");
        }
    }
}