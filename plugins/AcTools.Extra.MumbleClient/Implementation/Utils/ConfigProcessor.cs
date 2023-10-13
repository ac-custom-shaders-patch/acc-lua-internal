using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using UnityEngine;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public class ConfigProcessor : Dictionary<string, string> {
        public ConfigProcessor(string data) {
            if (data == null) return;
            foreach (var item in data.Split('\n')) {
                var separator = item.IndexOf('\t');
                var key = separator == -1 ? item : item.Substring(0, separator);
                this[key] = separator == -1 ? null : item.Substring(separator + 1);
            }
        }

        public string String(string key) {
            return TryGetValue(key, out var v) ? v : null;
        }

        public string Multiline(string key) {
            return TryGetValue(key, out var v) ? Encoding.UTF8.GetString(Convert.FromBase64String(v)) : null;
        }

        public byte[] Bytes(string key) {
            return TryGetValue(key, out var v) ? Convert.FromBase64String(v) : null;
        }

        public int? Int(string key) {
            if (TryGetValue(key, out var v)) return (int)double.Parse(v, NumberStyles.Any, CultureInfo.InvariantCulture);
            return null;
        }

        public float? Float(string key) {
            if (TryGetValue(key, out var v)) return (float)double.Parse(v, NumberStyles.Any, CultureInfo.InvariantCulture);
            return null;
        }

        public bool? Bool(string key) {
            if (TryGetValue(key, out var v)) return (int)double.Parse(v, NumberStyles.Any, CultureInfo.InvariantCulture) != 0;
            return null;
        }
    }
}