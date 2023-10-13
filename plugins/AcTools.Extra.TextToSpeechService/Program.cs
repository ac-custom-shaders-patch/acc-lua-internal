using System.Collections.Generic;
using System.IO.MemoryMappedFiles;
using System.Speech.Synthesis;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace AcTools.Extra.TextToSpeechService {
    internal class Program {
        private static List<SpeechSynthesizer> _pool = new List<SpeechSynthesizer>();

        private static void SaySomething(string phrase) {
            SpeechSynthesizer s;
            lock (_pool) {
                var i = _pool.Count - 1;
                s = i < 0 ? new SpeechSynthesizer() : _pool[i];
                if (i >= 0) {
                    _pool.RemoveAt(i);
                } else {
                    s.Rate = 1;
                }
            }
            Task.Run(() => {
                s.Speak(phrase);
                lock (_pool) {
                    _pool.Add(s);
                }
            });
        }

        public static void Main() {
            var lastId = -1;
            var data = new byte[256];
            MemoryMappedFile mmf = null;
            MemoryMappedViewAccessor view = null;
            try {
                while (true) {
                    if (view == null) {
                        try {
                            if (mmf != null) mmf.Dispose();
                            mmf = MemoryMappedFile.OpenExisting("AcTools.CSP.TTS.v0");
                            view = mmf.CreateViewAccessor();
                        } catch {
                            Thread.Sleep(500);
                            continue;
                        }
                    }
                    var id = view.ReadInt32(0);
                    if (id != lastId) {
                        if (lastId != -1) {
                            var len = view.ReadInt32(4);
                            if (len > data.Length) data = new byte[len + 64];
                            view.ReadArray(8, data, 0, len);
                            SaySomething(Encoding.UTF8.GetString(data));
                        }
                        lastId = id;
                    }
                    Thread.Sleep(100);
                }
            } finally {
                view?.Dispose();
                mmf?.Dispose();
            }
        }
    }
}