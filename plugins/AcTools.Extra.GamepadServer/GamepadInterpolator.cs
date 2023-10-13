using System.Diagnostics;

namespace AcTools.Extra.GamepadServer {
    public class GamepadInterpolator {
        private readonly Stopwatch _timer = Stopwatch.StartNew();
        private long _pingMs;

        public long GetCurrentTime() {
            return _timer.ElapsedMilliseconds;
        }

        public void ReportPing(long value) {
            _pingMs = (_timer.ElapsedMilliseconds - value) / 2;
        }

        public int GetPingMs() {
            return (int)_pingMs;
        }
    }
}