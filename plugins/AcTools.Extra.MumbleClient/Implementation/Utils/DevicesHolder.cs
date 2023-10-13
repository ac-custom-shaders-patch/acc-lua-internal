using System;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using Debug = UnityEngine.Debug;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public class DevicesHolder {
        internal static event EventHandler DevicesUpdated;

        internal static DeviceInfo GetIn(string deviceName) => Implementation.Get().In(deviceName);
        internal static DeviceInfo GetOut(string deviceName) => Implementation.Get().Out(deviceName);
        internal static DeviceInfo[] GetIns() => Implementation.Get()._inDeviceInfos;
        internal static DeviceInfo[] GetOuts() => Implementation.Get()._outDeviceInfos;

        public class DeviceInfo {
            public MMDevice Device;
            public string FullName;
            public string IconPath;
            public int WaveIndex;
            public int MinFrequency;
            public int MaxFrequency;
            public bool IsActive;
            public bool IsDefault;

            public static DeviceInfo Create(MMDevice device, bool isDefault) {
                return new DeviceInfo {
                    Device = device,
                    FullName = device.FriendlyName,
                    IconPath = device.IconPath,
                    IsActive = true,
                    IsDefault = isDefault
                };
            }

            public static DeviceInfo Fallback(string shortName) {
                return new DeviceInfo {
                    FullName = shortName.Length == 32 ? shortName + "…" : shortName,
                    IconPath = null,
                    IsActive = true
                };
            }

            public override string ToString() {
                return IsDefault ? $"{FullName} [default]" : FullName;
            }

            protected bool Equals(DeviceInfo other) {
                return FullName == other.FullName && IconPath == other.IconPath && IsActive == other.IsActive && IsDefault == other.IsDefault;
            }

            public override bool Equals(object obj) {
                if (ReferenceEquals(null, obj)) {
                    return false;
                }
                if (ReferenceEquals(this, obj)) {
                    return true;
                }
                if (obj.GetType() != GetType()) {
                    return false;
                }
                return Equals((DeviceInfo)obj);
            }

            public override int GetHashCode() {
                unchecked {
                    var hashCode = (FullName != null ? FullName.GetHashCode() : 0);
                    hashCode = (hashCode * 397) ^ (IconPath != null ? IconPath.GetHashCode() : 0);
                    hashCode = (hashCode * 397) ^ IsActive.GetHashCode();
                    hashCode = (hashCode * 397) ^ IsDefault.GetHashCode();
                    return hashCode;
                }
            }
        }

        private class Implementation {
            private static readonly object InstanceLock = new object();
            private static Implementation _instance;
            private static bool _updating;

            public static Implementation Get(bool rescan = false) {
                if (!rescan) {
                    var instance = _instance;
                    if (instance != null) return instance;
                }

                lock (InstanceLock) {
                    if (_instance == null) {
                        _instance = new Implementation(null);
                    } else if (!_updating && _instance._age.Elapsed.TotalSeconds > 5d) {
                        _updating = true;
                        Task.Run(() => {
                            var i = new Implementation(_instance);
                            _instance = i;
                            _updating = false;
                            if (i._updated) {
                                DevicesUpdated?.Invoke(null, EventArgs.Empty);
                            }
                        });
                    }
                }

                return _instance;
            }

            private readonly Stopwatch _age = Stopwatch.StartNew();
            public readonly DeviceInfo[] _inDeviceInfos;
            public readonly DeviceInfo[] _outDeviceInfos;
            private readonly bool _updated;

            private Implementation(Implementation old) {
                try {
                    using (var enumerator = new MMDeviceEnumerator()) {
                        Func<string, int, DeviceInfo> PrepareInfos(DataFlow flow) {
                            var defaultDevice = enumerator.GetDefaultAudioEndpoint(flow, Role.Communications);
                            var ret = enumerator.EnumerateAudioEndPoints(flow, DeviceState.Active).Select(x => {
                                try {
                                    return DeviceInfo.Create(x, x == defaultDevice);
                                } catch (Exception e) {
                                    if (_instance == null) {
                                        Debug.LogWarning($"Failed to get details about “{x.ID}”: {e.Message}");
                                    }
                                    return DeviceInfo.Fallback(x.ID);
                                }
                            }).ToArray();
                            return (shortName, indexHint) => {
                                var candidates = ret.Select((x, i) => new { x, i }).Where(x => x.x.FullName.StartsWith(shortName)).ToList();
                                var r = candidates.Count == 0 ? DeviceInfo.Fallback(shortName) : candidates.Count == 1
                                        ? candidates[0].x : candidates.FirstOrDefault(x => x.i == indexHint)?.x ?? DeviceInfo.Fallback(shortName);
                                r.WaveIndex = indexHint;
                                return r;
                            };
                        }

                        var getOutInfo = PrepareInfos(DataFlow.Render);
                        _outDeviceInfos = Enumerable.Range(0, WaveOut.DeviceCount).Select(x =>getOutInfo(WaveOut.GetCapabilities(x).ProductName, x)).ToArray();
                        if (_outDeviceInfos.Length > 0 && !_outDeviceInfos.Any(x => x.IsDefault)) _outDeviceInfos[0].IsDefault = true;

                        var getInInfo = PrepareInfos(DataFlow.Capture);
                        _inDeviceInfos = Enumerable.Range(0, WaveInEvent.DeviceCount).Select(x => {
                            var c = WaveInEvent.GetCapabilities(x);
                            var r = getInInfo(c.ProductName, x);
                            c.GetDeviceCaps(out r.MinFrequency, out r.MaxFrequency);
                            return r;
                        }).ToArray();
                        if (_inDeviceInfos.Length > 0 && !_inDeviceInfos.Any(x => x.IsDefault)) _inDeviceInfos[0].IsDefault = true;
                    }

                    if (old == null || !_inDeviceInfos.SequenceEqual(old._inDeviceInfos) || !_outDeviceInfos.SequenceEqual(old._outDeviceInfos)) {
                        Debug.Log("Input devices:\n\t" + string.Join("\n\t", _inDeviceInfos.Select(x => x.ToString())));
                        Debug.Log("Output devices:\n\t" + string.Join("\n\t", _outDeviceInfos.Select(x => x.ToString())));
                        Debug.Log($"Scan time: {_age.Elapsed.TotalSeconds:F2} s");
                        _updated = true;
                    }
                    _age.Restart();
                } catch (Exception e) {
                    Debug.LogError(e.ToString());
                }
            }

            public DeviceInfo In(string deviceName) {
                if (!string.IsNullOrEmpty(deviceName)) {
                    var t = _inDeviceInfos.FirstOrDefault(x => x.FullName == deviceName);
                    if (t != null) return t;
                    Debug.LogWarning("Invalid input device name: " + deviceName);
                }
                return _inDeviceInfos.FirstOrDefault(x => x.IsDefault);
            }

            public DeviceInfo Out(string deviceName) {
                if (!string.IsNullOrEmpty(deviceName)) {
                    var t = _outDeviceInfos.FirstOrDefault(x => x.FullName == deviceName);
                    if (t != null) return t;
                    Debug.LogWarning("Invalid output device name: " + deviceName);
                }
                return _outDeviceInfos.FirstOrDefault(x => x.IsDefault);
            }
        }

        public static void Rescan() {
            Implementation.Get(true);
        }
    }
}