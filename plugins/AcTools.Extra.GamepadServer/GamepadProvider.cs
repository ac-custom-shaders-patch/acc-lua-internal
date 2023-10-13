using System;
using System.IO.MemoryMappedFiles;

namespace AcTools.Extra.GamepadServer {
    public class GamepadProvider : IDisposable {
        private MemoryMappedFile _mmf;
        private MemoryMappedViewStream _stream;
        private MemoryMappedViewStream _streamAlt;
        private readonly GamepadStateWriter _writer = new GamepadStateWriter();

        private void Update() {
            if (_mmf == null) {
                _mmf = MemoryMappedFile.CreateOrOpen(@"AcTools.GamepadState.v1", GamepadOutputState.Size + GamepadState.Size,
                        MemoryMappedFileAccess.ReadWrite);
                _stream = _mmf.CreateViewStream();
                _streamAlt = _mmf.CreateViewStream();
                _writer.WriteDefaults(_stream, GamepadOutputState.Defaults);
            }
        }

        public void Open() {
            Update();
            var state = new GamepadState();
            _writer.Write(_stream, ref state);
        }

        public void Write(ref GamepadState state) {
            Update();
            _writer.Write(_stream, ref state);
        }

        public void WriteTime(long time) {
            if (_streamAlt != null) {
                _writer.WriteTime(_streamAlt, time);
            }
        }

        public void Read(ref string response, ref GamepadOutputState outputState, bool fullRefresh) {
            Update();
            _writer.Read(_stream, ref response, ref outputState, fullRefresh);
        }

        public void Dispose() {
            _mmf?.Dispose();
        }
    }
}