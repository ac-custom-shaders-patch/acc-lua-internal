using System;
using System.Linq;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public class ConfigVirtualProcessor : ConfigProcessor {
        public class ConfigEventArgs : EventArgs {
            public string Key;
            
            public ConfigEventArgs(string key) {
                Key = key;
            }
        }
        
        public EventHandler<ConfigEventArgs> Update;

        private readonly Func<string, bool> _filter;
        
        public ConfigVirtualProcessor(Func<string, bool> filter) : base(null) {
            _filter = filter;
        }

        public void Extend(ConfigProcessor processor) {
            foreach (var pair in processor.Where(pair => _filter(pair.Key))) {
                if (TryGetValue(pair.Key, out var existing) && existing == pair.Value) return;
                this[pair.Key] = pair.Value;
                Update?.Invoke(this, new ConfigEventArgs(pair.Key));
            }
        }

        public bool Process(string key, string processing) {
            if (!_filter(key)) return false;
            if (!TryGetValue(key, out var existing) || existing != processing) {
                this[key] = processing;
                Update?.Invoke(this, new ConfigEventArgs(key));
            }
            return true;
        }
    }
}