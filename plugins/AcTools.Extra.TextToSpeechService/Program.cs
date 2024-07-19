using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Linq;
using System.Speech.Synthesis;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using NAudio.Wave;

namespace AcTools.Extra.TextToSpeechService {
    internal class Program {
        private class ThingToSay {
            public string Phrase;
            public int Flags;
            public int Rate;
            public int Volume;
            public uint VoiceID;
            public Action Callback;

            public uint VoiceKey() {
                if (VoiceID != 0) return VoiceID;
                return (uint)Flags & 3;
            }

            public VoiceGender? PreferredGender() {
                if ((Flags & 3) == 3) {
                    return VoiceGender.Neutral;
                }
                if ((Flags & 1) == 1) {
                    return VoiceGender.Male;
                }
                if ((Flags & 2) == 2) {
                    return VoiceGender.Female;
                }
                return null;
            }

            public T SelectVoice<T>(IReadOnlyCollection<T> items) {
                if (items.Count == 0) throw new Exception("Voices are missing");
                return items.ElementAt((int)(VoiceID % items.Count));
            }

            public int GetRate() {
                return Math.Min(Math.Max(Rate, -10), 10);
            }

            public int GetVolume() {
                return Math.Min(Math.Max(Volume, 0), 100);
            }

            public void Finished() {
                if ((Flags & 4) == 4) {
                    Callback?.Invoke();
                }
            }
        }

        private interface ISpeakerImplementation {
            void SaySomething(ThingToSay thing);
        }

        private class SpeakerWindows : ISpeakerImplementation {
            private Dictionary<ulong, List<SpeechSynthesizer>> _pool = new Dictionary<ulong, List<SpeechSynthesizer>>();

            void ISpeakerImplementation.SaySomething(ThingToSay thing) {
                var key = thing.VoiceKey();

                List<SpeechSynthesizer> ownPool;
                lock (_pool) {
                    if (!_pool.TryGetValue(key, out ownPool)) {
                        ownPool = new List<SpeechSynthesizer>();
                        _pool[key] = ownPool;
                    }
                }

                SpeechSynthesizer s = null;
                lock (ownPool) {
                    var i = ownPool.Count - 1;
                    if (i >= 0) {
                        s = ownPool[i];
                        ownPool.RemoveAt(i);
                    }
                }

                if (s == null) {
                    s = new SpeechSynthesizer();
                    if (thing.VoiceID != 0) {
                        s.SelectVoice(thing.SelectVoice(s.GetInstalledVoices()
                                .Where(x => x.Enabled && x.VoiceInfo.Culture.ThreeLetterISOLanguageName == "eng")
                                .ToList()).VoiceInfo.Name);
                    } else if (thing.PreferredGender() is VoiceGender gender) {
                        s.SelectVoiceByHints(gender);
                    }
                }

                s.Rate = thing.GetRate();
                s.Volume = thing.GetVolume();
                Task.Run(() => {
                    s.Speak(thing.Phrase);
                    thing.Finished();
                    lock (ownPool) {
                        ownPool.Add(s);
                    }
                });
            }
        }

        private class SpeakerPiper : ISpeakerImplementation {
            private class PiperVoice {
                public string ModelFilename;
                public int AudioFrequency;
            }

            private static int GetAudioFrequency(string modelFilename) {
                try {
                    var config = File.ReadAllText(modelFilename + ".json");
                    var match = Regex.Match(config, @"sample_rate""\s*:\s*(\d+)");
                    var group = match.Groups[1].Value;
                    Console.WriteLine($"m={modelFilename}, g={group}");
                    return int.Parse(group);
                } catch (Exception e) {
                    Console.Error.WriteLine(e.ToString());
                    return 22050;
                }
            }

            private readonly string _piperExecutable;
            private readonly List<PiperVoice> _piperVoices;

            public SpeakerPiper(string piperExecutable, string[] piperVoices) {
                _piperExecutable = piperExecutable;
                _piperVoices = piperVoices.Select(x => new PiperVoice {
                    ModelFilename = x,
                    AudioFrequency = GetAudioFrequency(x)
                }).ToList();
            }

            void ISpeakerImplementation.SaySomething(ThingToSay thing) {
                Task.Run(() => {
                    PiperVoice voice;
                    if (thing.VoiceID != 0) {
                        voice = thing.SelectVoice(_piperVoices);
                    } else if (thing.PreferredGender() is VoiceGender g && g == VoiceGender.Female) {
                        voice = _piperVoices.FirstOrDefault(x => x.ModelFilename.Contains("en_US-kristin-"))
                                ?? _piperVoices.FirstOrDefault();
                    } else {
                        voice = _piperVoices.FirstOrDefault(x => x.ModelFilename.Contains("en_US-joe-"))
                                ?? _piperVoices.FirstOrDefault();
                    }
                    if (voice == null) {
                        Console.Error.WriteLine("Failed to find fitting voice");
                        return;
                    }
                    using (var process = new Process()) {
                        process.StartInfo = new ProcessStartInfo {
                            FileName = _piperExecutable,
                            Arguments = $"-m \"{voice.ModelFilename}\" --output_raw",
                            UseShellExecute = false,
                            RedirectStandardInput = true,
                            RedirectStandardOutput = true,
                            RedirectStandardError = true,
                            CreateNoWindow = true
                        };
                        process.ErrorDataReceived += (sender, args) => Console.Error.Write(args.Data);
                        process.Start();
                        using (var inputWriter = process.StandardInput) {
                            inputWriter.WriteLine(thing.Phrase);
                        }
                        Console.WriteLine($"Running Piper: {voice.ModelFilename}");
                        using (var waveOut = new WaveOut())
                        using (var stream = new RawSourceWaveStream(process.StandardOutput.BaseStream,
                                new WaveFormat((int)(voice.AudioFrequency * (1f + thing.GetRate() * 0.01f)), 16, 1))) {
                            waveOut.Volume = thing.GetVolume() / 100f;
                            waveOut.Init(stream);
                            waveOut.Play();
                            do {
                                Thread.Sleep(50);
                            } while (waveOut.PlaybackState != PlaybackState.Stopped);
                        }
                        thing.Finished();
                        process.WaitForExit();
                        Console.WriteLine($"Piper exited: {process.ExitCode}");
                    }
                });
            }
        }

        private static ISpeakerImplementation ConstructImplementation() {
            var piperExecutable = Environment.GetEnvironmentVariable("TTS_PIPER_EXECUTABLE");
            var piperVoices = Environment.GetEnvironmentVariable("TTS_PIPER_VOICES");
            if (piperExecutable != null && piperVoices != null) {
                var foundVoices = Directory.GetFiles(piperVoices, "*.onnx");
                if (foundVoices.Length > 0) {
                    return new SpeakerPiper(piperExecutable, foundVoices);
                }
            }

            return new SpeakerWindows();
        }

        private static void NotifyCompleted(int id, MemoryMappedViewAccessor v) {
            var completeOffset = 8 + 4 * (65536 + 4 * 3);
            for (int i = 0; i < 8; ++i) {
                if (v.ReadInt32(completeOffset + i * 4) == 0) {
                    v.Write(completeOffset + i * 4, id);
                    return;
                }
            }
            Task.Delay(200).ContinueWith(r => NotifyCompleted(id, v));
        }

        public static void Main(string[] args) {
            if (args.Contains("--voices")) {
                var s = new SpeechSynthesizer();
                foreach (var voice in s.GetInstalledVoices()) {
                    Console.WriteLine(
                            $"Voice: {voice.VoiceInfo.Name}, enabled: {voice.Enabled}, description: {voice.VoiceInfo.Description}, age: {voice.VoiceInfo.Age}, gender: {voice.VoiceInfo.Gender}, culture: {voice.VoiceInfo.Culture.ThreeLetterISOLanguageName}");
                }
                return;
            }
            
            if (args.Contains("--launcher")) {
                Process.Start(new ProcessStartInfo {
                    FileName = args.Last(),
                    UseShellExecute = true,
                    WindowStyle = ProcessWindowStyle.Hidden,
                    CreateNoWindow = true
                });
                return;
            }

            var implementation = ConstructImplementation();
            var lastId = -1;
            var data = new byte[256];
            MemoryMappedFile mmf = null;
            var view = new MemoryMappedViewAccessor[1];
            int.TryParse(Environment.GetEnvironmentVariable("TTS_RUN_ID"), NumberStyles.Any, 
                    CultureInfo.InvariantCulture, out var runID);
            try {
                while (true) {
                    if (view[0] == null) {
                        try {
                            if (mmf != null) mmf.Dispose();
                            mmf = MemoryMappedFile.OpenExisting("AcTools.CSP.TTS.v2", MemoryMappedFileRights.ReadWrite);
                            view[0] = mmf.CreateViewAccessor();
                        } catch {
                            Thread.Sleep(500);
                            continue;
                        }
                    }
                    var v = view[0];
                    if (v.ReadInt32(0) != runID) {
                        Console.WriteLine($"Shutting down: {v.ReadInt32(0)} != {runID}");
                        return;
                    }
                    var id = v.ReadInt32(4);
                    if (id != lastId) {
                        Thread.MemoryBarrier();
                        var offset = 8 + id % 4 * (65536 + 4 * 3);
                        var len = v.ReadUInt16(offset + 2);
                        if (len > 0) {
                            if (len > data.Length) data = new byte[len + 64];
                            v.ReadArray(offset + 12, data, 0, len);
                            try {
                                implementation.SaySomething(new ThingToSay {
                                    Phrase = Encoding.UTF8.GetString(data, 0, len),
                                    Flags = v.ReadUInt16(offset),
                                    Rate = v.ReadInt16(offset + 4),
                                    Volume = v.ReadUInt16(offset + 6),
                                    VoiceID = v.ReadUInt32(offset + 8),
                                    Callback = () => NotifyCompleted(id, v),
                                });
                            } catch (Exception e) {
                                Console.Error.WriteLine(e.ToString());
                            }
                        }
                        lastId = id;
                    }
                    Thread.Sleep(50);
                }
            } finally {
                var v = view[0];
                view[0] = null;
                v?.Dispose();
                mmf?.Dispose();
            }
        }
    }
}