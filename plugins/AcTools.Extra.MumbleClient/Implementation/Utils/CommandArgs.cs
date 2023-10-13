using System;
using System.Globalization;
using System.Text;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public class CommandArgs {
        private string _processing;
        private string[] _split;
        
        public CommandArgs(string processing) {
            _processing = processing;
        }

        public string String() {
            return _processing;
        }

        public string Multiline() {
            return Encoding.UTF8.GetString(Convert.FromBase64String(_processing));
        }

        public byte[] Bytes() {
            return Convert.FromBase64String(_processing);
        }

        public CommandArgs At(int index) {
            if (_split == null) {
                _split = _processing.Split('\t');
            }
            return new CommandArgs(_split[index]);
        }

        public int Int() {
            return int.Parse(String(), NumberStyles.Any, CultureInfo.InvariantCulture);
        }

        public float Float() {
            return float.Parse(String(), NumberStyles.Any, CultureInfo.InvariantCulture);
        }

        public bool Bool() {
            return Int() != 0;
        }
    }
}