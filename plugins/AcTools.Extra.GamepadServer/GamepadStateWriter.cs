using System;
using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;

namespace AcTools.Extra.GamepadServer {
    public class GamepadStateWriter {
        private readonly byte[] _data = new byte[GamepadState.Size];
        private readonly byte[] _outputData = new byte[GamepadOutputState.Size];

        public void Write(MemoryMappedViewStream stream, ref GamepadState state) {
            stream.Position = GamepadOutputState.Size;
            var ptr = Marshal.AllocHGlobal(GamepadState.Size);
            Marshal.StructureToPtr(state, ptr, true);
            Marshal.Copy(ptr, _data, 0, GamepadState.Size);
            Marshal.FreeHGlobal(ptr);
            stream.Write(_data, 0, _data.Length);
        }

        public void WriteDefaults(MemoryMappedViewStream stream, GamepadOutputState defaults) {
            stream.Position = 0;
            var ptr = Marshal.AllocHGlobal(GamepadOutputState.Size);
            Marshal.StructureToPtr(defaults, ptr, true);
            Marshal.Copy(ptr, _outputData, 0, GamepadOutputState.Size);
            Marshal.FreeHGlobal(ptr);
            stream.Write(_outputData, 0, _outputData.Length);
        }

        public void WriteTime(MemoryMappedViewStream stream, long time) {
            stream.Position = GamepadOutputState.Size;
            var buf = BitConverter.GetBytes(time);
            stream.Write(buf, 0, buf.Length);
        }

        public void Read(MemoryMappedViewStream stream, ref string response, ref GamepadOutputState outputState, bool fullRefresh) {
            stream.Position = 0;
            stream.Read(_outputData, 0, _outputData.Length);
            var ptr = Marshal.AllocHGlobal(GamepadOutputState.Size);
            Marshal.Copy(_outputData, 0, ptr, _outputData.Length);
            var curState = (GamepadOutputState)Marshal.PtrToStructure(ptr, typeof(GamepadOutputState));
            if (fullRefresh || curState.Color != outputState.Color) {
                response += $";L{curState.SerializedColor}";
            }
            if (fullRefresh || curState.VibrationLeft != outputState.VibrationLeft || curState.VibrationRight != outputState.VibrationRight) {
                response += $";V{(int)curState.VibrationLeft},{(int)curState.VibrationRight}";
            }
            if (fullRefresh || curState.SerializedRpm != outputState.SerializedRpm) {
                response += $";R{curState.SerializedRpm}";
            }
            if (fullRefresh || curState.Gear != outputState.Gear) {
                response += $";G{curState.SerializedGear}";
            }
            if (fullRefresh || curState.AbsPresent != outputState.AbsPresent || curState.TcPresent != outputState.TcPresent
                    || curState.TurboPresent != outputState.TurboPresent || curState.ClutchPresent != outputState.ClutchPresent
                    || curState.WipersPresent != outputState.WipersPresent || curState.GearsCount != outputState.GearsCount 
                    || curState.HeadlightsPresent != outputState.HeadlightsPresent) {
                response += $";C{(curState.AbsPresent ? '1' : '0')}{(curState.TcPresent ? '1' : '0')}{(curState.TurboPresent ? '1' : '0')}"
                        + $"{(curState.ClutchPresent ? '1' : '0')}{(curState.WipersPresent ? '1' : '0')}{(curState.HeadlightsPresent ? '1' : '0')}"
                        + $",{(int)curState.GearsCount}";
            }
            if (fullRefresh || curState.HeadlightsActive != outputState.HeadlightsActive) {
                response += $";SL{(curState.HeadlightsActive ? '1' : '0')}";
            }
            if (fullRefresh || curState.LowBeamsActive != outputState.LowBeamsActive) {
                response += $";Sl{(curState.LowBeamsActive ? '1' : '0')}";
            }
            if (fullRefresh || curState.AbsOff != outputState.AbsOff) {
                response += $";SA{(curState.AbsOff ? '1' : '0')}";
            }
            if (fullRefresh || curState.TcOff != outputState.TcOff) {
                response += $";ST{(curState.TcOff ? '1' : '0')}";
            }
            if (fullRefresh || curState.Paused != outputState.Paused) {
                response += $";SP{(curState.Paused ? '1' : '0')}";
            }
            if (fullRefresh || curState.NeedsDPad != outputState.NeedsDPad) {
                response += $";SD{(curState.NeedsDPad ? '1' : '0')}";
            }
            if (fullRefresh || curState.DriftMode != outputState.DriftMode) {
                response += $";Sd{(curState.DriftMode ? '1' : '0')}";
            }
            outputState = curState;
            Marshal.FreeHGlobal(ptr);
        }
    }
}