using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using UnityEngine;

namespace AcTools.Extra.MumbleClient.Implementation.Utils {
    public class CommandProcessor : Dictionary<string, Action<CommandArgs>> {
        public const int MaxCommandLength = 256;
        
        private readonly List<ConfigVirtualProcessor> _linked = new List<ConfigVirtualProcessor>();
        private string _processing;

        public CommandProcessor() {
            Task.Delay(TimeSpan.FromSeconds(1d)).ContinueWith(r => {
                foreach (var value in Keys.Where(value => value.Length + 20 > MaxCommandLength)) {
                    Debug.LogError($"Command is too long: “{value}”");
                }
            });
        }

        public void ProcessKeyValue(string key, string value, bool warnOnMissing) {
            try {
                // Debug.Log($"command: {key}={value}");
                
                _processing = value;
                var found = false;
                if (TryGetValue(key, out var fn)) {
                    fn(new CommandArgs(value));
                    found = true;
                }
                for (var i = _linked.Count - 1; i >= 0; i--) {
                    found = _linked[i].Process(key, _processing) || found;
                }
                if (!found && warnOnMissing) {
                    Debug.LogWarning($"Unknown command: {key}={value}");
                }
            } catch (Exception e) {
                Debug.LogError($"Failed to process command {key}={value}: {e}");
            }
        }

        public void Process(ConfigProcessor config) {
            foreach (var pair in config) {
                ProcessKeyValue(pair.Key, pair.Value, false);
            }
        }

        public void Link(ConfigVirtualProcessor config) {
            _linked.Add(config);
        }

        public void Link(CommandProcessor config) {
            foreach (var pair in config) {
                this[pair.Key] = pair.Value;
            }
        }
    }
}