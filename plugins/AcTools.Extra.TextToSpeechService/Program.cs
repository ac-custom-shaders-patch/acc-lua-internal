using System;
using System.Collections.Generic;
using System.IO.MemoryMappedFiles;
using System.Linq;
using System.Speech.Synthesis;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace AcTools.Extra.TextToSpeechService {
    internal class Program {
        private static Dictionary<int, List<SpeechSynthesizer>> _pool = new Dictionary<int, List<SpeechSynthesizer>>();

        private static void SaySomething(string phrase, int flags, int rate, int volume, Action callback) {
            SpeechSynthesizer s;
            lock (_pool) {
                if (!_pool.TryGetValue(flags, out var pool)) {
                    pool = new List<SpeechSynthesizer>();
                    _pool[flags] = pool;
                }
                var i = pool.Count - 1;
                if (i < 0) {
                    s = new SpeechSynthesizer();
                    if ((flags & 3) == 3) {
                        s.SelectVoiceByHints(VoiceGender.Neutral);
                    } else if ((flags & 1) == 1) {
                        s.SelectVoiceByHints(VoiceGender.Male);
                    } else if ((flags & 2) == 2) {
                        s.SelectVoiceByHints(VoiceGender.Female);
                    }  
                } else {
                    s = pool[i];
                }
                s.Rate = Math.Min(Math.Max(rate, -10), 10);
                s.Volume = Math.Min(Math.Max(volume, 0), 100);
                if (i >= 0) {
                    pool.RemoveAt(i);
                } else {
                    s.Rate = 1;
                }
            }
            Task.Run(() => {
                s.Speak(phrase);
                if ((flags & 4) == 4) {
                    callback?.Invoke();
                }
                lock (_pool) {
                    _pool[flags].Add(s);
                }
            });
        }

        public static void Main(string[] args) {
            if (args.Contains("--voices")) {
                var s = new SpeechSynthesizer();
                foreach (var voice in s.GetInstalledVoices()) {
                    Console.WriteLine($"Voice: {voice.VoiceInfo.Name}, enabled: {voice.Enabled}, description: {voice.VoiceInfo.Description}, age: {voice.VoiceInfo.Age}, gender: {voice.VoiceInfo.Gender}, culture: {voice.VoiceInfo.Culture.Name}");
                }
                return;
            }
            
            var lastId = -1;
            var data = new byte[256];
            MemoryMappedFile mmf = null;
            var view = new MemoryMappedViewAccessor[1];
            try {
                while (true) {
                    if (view[0] == null) {
                        try {
                            if (mmf != null) mmf.Dispose();
                            mmf = MemoryMappedFile.OpenExisting("AcTools.CSP.TTS.v1", MemoryMappedFileRights.ReadWrite);
                            view[0] = mmf.CreateViewAccessor();
                        } catch {
                            Thread.Sleep(500);
                            continue;
                        }
                    }
                    var v = view[0];
                    var id = v.ReadInt32(0);
                    if (id != lastId) {
                        var offset = id % 4 * (65536 + 4 * 2);
                        var len = v.ReadUInt16(offset + 6);
                        if (len > 0) {
                            var flags = v.ReadUInt16(offset + 4);
                            var rate = v.ReadInt16(offset + 8);
                            var volume = v.ReadUInt16(offset + 10);
                            
                            if (len > data.Length) data = new byte[len + 64];
                            v.ReadArray(offset + 12, data, 0, len);
                            SaySomething(Encoding.UTF8.GetString(data, 0, len), flags, rate, volume, () => {
                                Console.WriteLine($"Completed: {id}");
                            });
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