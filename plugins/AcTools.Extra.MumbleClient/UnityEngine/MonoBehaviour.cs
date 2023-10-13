#define PERFORMANCE_PROFILING

using System;
using System.Diagnostics;
using AcTools.Extra.MumbleClient.Implementation.Utils;

namespace UnityEngine {
    public sealed class MonoBehaviour {
        public interface IMonoRunner : IDisposable {
            void Start();
        }

        public const double _periodMs = 20;

        private class MonoRunner : IMonoRunner {
            private readonly Stopwatch _lastUpdate = Stopwatch.StartNew();
            private readonly Action _updateCallback;
            private BetterTimer _timer;
            private Stopwatch _timerStart;
            private int _timerSteps;

            public MonoRunner(Action updateCallback) {
                _updateCallback = updateCallback;
                RefreshState();
            }

            public void Start() {
                _timerStart = Stopwatch.StartNew();
                _timer = new BetterTimer((int)_periodMs, TimerUpdate);
            }

            private void TimerUpdate() {
                var step = Stopwatch.StartNew();
                try {
                    RefreshState();
                    _updateCallback?.Invoke();
                    ++_timerSteps;
                    if (_timerSteps % 4000 == 200) {
                        Debug.Log($"Timer measure: {_timerStart.Elapsed.TotalMilliseconds / _timerSteps:F4} ms");
                    }
                } catch (Exception e) {
                    Debug.LogError($"Error in main thread: {e}");
                }
                if (step.ElapsedMilliseconds > 10) {
                    Debug.LogWarning($"Update took too long: {step.Elapsed.TotalMilliseconds:F1} ms!");
                }
            }

            private void RefreshState() {
                Time.deltaTime = (float)_lastUpdate.Elapsed.TotalSeconds;
                if (++Time.phase == 5) Time.phase = 0;
                _lastUpdate.Restart();
            }

            public void Dispose() {
                _timer?.Dispose();
            }
        }

        public static IMonoRunner CreateRunner(Action updateCallback = null) {
            return new MonoRunner(updateCallback);
        }
    }
}