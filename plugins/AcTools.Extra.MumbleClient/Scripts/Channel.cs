using System.Collections.Generic;
using MumbleProto;
using System;

namespace Mumble {
    public class Channel {
        public string Name => _channelState.Name;
        
        public ChannelState State => _channelState;

        public uint ChannelId => _channelState.ChannelId;

        public uint[] Links => _channelState.Links;

        private readonly ChannelState _channelState;
        private readonly HashSet<Channel> _sharedAudioChannels = new HashSet<Channel>();
        private readonly object _lock = new object();

        public bool CanEnter => _channelState.CanEnter;

        internal Channel(ChannelState initialState) {
            _channelState = initialState;
            UpdateLinks(initialState.LinksAdds, initialState.LinksRemoves);
        }

        public bool DoesShareAudio(Channel other) {
            lock (_lock) {
                return other.ChannelId == ChannelId || _sharedAudioChannels.Contains(other);
            }
        }

        internal void UpdateSharedAudioChannels(Dictionary<uint, Channel> channels) {
            lock (_lock) {
                _sharedAudioChannels.Clear();

                if (_channelState.Links == null || _channelState.Links.Length == 0) {
                    return;
                }
                
                // We can use a faster data structure here
                var checkedChannels = new HashSet<uint>();
                var channelsToCheck = new Stack<Channel>();
                channelsToCheck.Push(this);

                while (channelsToCheck.Count > 0) {
                    var chan = channelsToCheck.Pop();
                    checkedChannels.Add(chan.ChannelId);

                    if (chan.Links == null || chan.Links.Length == 0) {
                        continue;
                    }
                    
                    // Iterate through all links, making sure not to re-check already inspected channels
                    for (var i = 0; i < chan.Links.Length; i++) {
                        var val = chan.Links[i];
                        if (!checkedChannels.Contains(val)) {
                            if (!channels.TryGetValue(val, out var linkedChan)) continue;
                            _sharedAudioChannels.Add(linkedChan);
                            channelsToCheck.Push(linkedChan);
                        }
                    }
                }
            }
        }

        private void UpdateLinks(uint[] addedLinks, uint[] removedLinks) {
            if (_channelState.Links == null || _channelState.Links.Length == 0) {
                _channelState.Links = addedLinks;
                return;
            }

            // Get the updated number of links to add
            var newNumLinks = _channelState.Links.Length;
            if (addedLinks != null) {
                newNumLinks += addedLinks.Length;
            }
            if (removedLinks != null) {
                newNumLinks -= removedLinks.Length;
            }

            var oldLinks = _channelState.Links;
            _channelState.Links = new uint[newNumLinks];

            if (newNumLinks != 0) {
                // First add the old links
                var dstIdx = 0;
                if (removedLinks == null || removedLinks.Length == 0) {
                    Array.Copy(oldLinks, _channelState.Links, oldLinks.Length);
                    dstIdx = oldLinks.Length;
                } else {
                    foreach (var t in oldLinks) {
                        if (Array.IndexOf(removedLinks, t) == -1) {
                            _channelState.Links[dstIdx] = t;
                            dstIdx++;
                        }
                    }
                }

                // Now add all the new links
                if (addedLinks != null) {
                    Array.Copy(addedLinks, 0, _channelState.Links, dstIdx, addedLinks.Length);
                }
            }
        }

        internal void UpdateFromState(ChannelState deltaState) {
            if (deltaState.ShouldSerializeParent()) _channelState.Parent = deltaState.Parent;
            if (deltaState.ShouldSerializeDescription()) _channelState.Description = deltaState.Description;
            if (deltaState.ShouldSerializeName()) _channelState.Name = deltaState.Name;
            if (deltaState.ShouldSerializeDescriptionHash()) _channelState.DescriptionHash = deltaState.DescriptionHash;
            if (deltaState.ShouldSerializeMaxUsers()) _channelState.MaxUsers = deltaState.MaxUsers;
            if (deltaState.ShouldSerializePosition()) _channelState.Position = deltaState.Position;
            if (deltaState.ShouldSerializeIsEnterRestricted()) _channelState.IsEnterRestricted = deltaState.IsEnterRestricted;
            if (deltaState.ShouldSerializeCanEnter()) _channelState.CanEnter = deltaState.CanEnter;

            // Link updates happen in a sorta weird way
            if (deltaState.Links != null) _channelState.Links = deltaState.Links;
            UpdateLinks(deltaState.LinksAdds, deltaState.LinksRemoves);
        }
    }
}