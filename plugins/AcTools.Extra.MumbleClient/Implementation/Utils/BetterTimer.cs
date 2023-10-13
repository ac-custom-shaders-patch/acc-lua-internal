using System;
using System.Runtime.InteropServices;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public class BetterTimer : IDisposable {
        private readonly Action _callback;
        // ReSharper disable once PrivateFieldCanBeConvertedToLocalVariable
        private readonly TimerEventHandler _handler;
        private readonly int _timer;
        private bool _running;

        public BetterTimer(int interval, Action callback) {
            //timeBeginPeriod(1);
            _callback = callback;
            _handler = OnEventTrigger;
            _timer = timeSetEvent(interval, 5, _handler, IntPtr.Zero, TimePeriodic);
        }

        public void Dispose() {
            timeKillEvent(_timer);
            //timeEndPeriod(1);
        }

        private void OnEventTrigger(int id, int msg, IntPtr user, int dw1, int dw2) {
            if (_running) return;
            _running = true;
            _callback();
            _running = false;
        }

        private delegate void TimerEventHandler(int id, int msg, IntPtr user, int dw1, int dw2);

        private const int TimePeriodic = 1;

        [DllImport("winmm.dll")]
        private static extern int timeSetEvent(int delay, int resolution, TimerEventHandler handler, IntPtr user, int eventType);

        [DllImport("winmm.dll")]
        private static extern int timeKillEvent(int id);

        [DllImport("winmm.dll")]
        private static extern int timeBeginPeriod(int msec);

        [DllImport("winmm.dll")]
        private static extern int timeEndPeriod(int msec);
    }
}