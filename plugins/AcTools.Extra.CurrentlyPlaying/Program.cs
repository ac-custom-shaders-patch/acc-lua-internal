using System;
using System.Globalization;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Text;
using System.Threading.Tasks;
using Windows.Media.Control;

namespace AcTools.Extra.CurrentlyPlaying {
    internal class Program {
        private static async Task<byte[]> ReadThumbnail(GlobalSystemMediaTransportControlsSessionMediaProperties properties) {
            try {
                var stream = await properties.Thumbnail.OpenReadAsync();
                if (stream?.Size > 0) {
                    var ret = new byte[stream.Size];
                    await stream.AsStream().ReadAsync(ret, 0, ret.Length).ConfigureAwait(false);
                    return ret;
                }
            } catch (Exception e) {
                Console.Error.WriteLine("Failed to read thumbnail: " + e);
            }
            return null;
        }

        private class DictionaryWriter : IDisposable {
            private BinaryWriter _writer;

            public DictionaryWriter(Stream stream) {
                _writer = new BinaryWriter(stream);
            }

            private void Write(string value) {
                var bytes = Encoding.UTF8.GetBytes(value);
                _writer.Write(bytes.Length);
                _writer.Write(bytes);
            }

            public void Write(string key, string value) {
                if (value == null) return;
                Write(key);
                Write(value);
            }

            public void Write(string key, int value) {
                Write(key);
                Write(value.ToString(CultureInfo.InvariantCulture));
            }

            public void Write(string key, long value) {
                Write(key);
                Write(value.ToString(CultureInfo.InvariantCulture));
            }

            public void Write(string key, bool value) {
                Write(key);
                Write(value ? "1" : "0");
            }

            public void Write(string key, byte[] value) {
                if (value == null) return;
                Write(key);
                _writer.Write(value.Length);
                _writer.Write(value);
            }

            public void Dispose() {
                _writer.Write(0);
                _writer?.Dispose();
            }
        }

        public class SongInfo {
            public string Artist;
            public string AlbumArtist;
            public string AlbumTitle;
            public string Title;
            public int AlbumTrackCount;
            public int TrackNumber;
            public byte[] Thumbnail;
            public string SourceId;
            public int DurationSeconds;
            public long StartTime;

            public static async Task<SongInfo> CreateAsync(MediaManager.MediaSession session,
                    GlobalSystemMediaTransportControlsSessionMediaProperties properties) {
                var duration = 0;
                var position = 0;
                try {
                    var timelineProperties = session.ControlSession.GetTimelineProperties();
                    position = (int)timelineProperties.Position.TotalSeconds;
                    duration = (int)Math.Ceiling((timelineProperties.EndTime - timelineProperties.StartTime).TotalSeconds);
                } catch (Exception e) {
                    Console.Error.WriteLine(e.Message);
                }

                return new SongInfo {
                    Artist = properties.Artist,
                    AlbumArtist = properties.AlbumArtist,
                    AlbumTitle = properties.AlbumTitle,
                    Title = properties.Title,
                    AlbumTrackCount = properties.AlbumTrackCount,
                    TrackNumber = properties.TrackNumber,
                    SourceId = session.ControlSession.SourceAppUserModelId,
                    DurationSeconds = duration,
                    StartTime = DateTime.Now.ToUnixTimestamp() - position,
                    Thumbnail = await ReadThumbnail(properties).ConfigureAwait(false)
                };
            }

            private static SongInfo _previouslyWritten;
            private static MemoryMappedFile _mmf;
            private static int _updatePhase;

            public static void Write(SongInfo info) {
                if (_previouslyWritten == info && _mmf != null) return;
                _previouslyWritten = info;

                if (_mmf == null) {
                    _mmf = MemoryMappedFile.CreateOrOpen(@"AcTools.CurrentlyPlaying.v1", 512 * 1024, MemoryMappedFileAccess.ReadWrite);
                }

                using (var stream = _mmf.CreateViewStream())
                using (var writer = new DictionaryWriter(stream)) {
                    writer.Write("UpdatePhase", _updatePhase++);
                    if (_updatePhase > 999) {
                        _updatePhase = 0;
                    }
                    writer.Write("IsPlaying", info != null);
                    if (info != null) {
                        writer.Write("Artist", info.Artist);
                        writer.Write("AlbumArtist", info.AlbumArtist);
                        writer.Write("AlbumTitle", info.AlbumTitle);
                        writer.Write("Title", info.Title);
                        writer.Write("AlbumTrackCount", info.AlbumTrackCount);
                        writer.Write("TrackNumber", info.TrackNumber);
                        writer.Write("TrackStart", info.StartTime);
                        writer.Write("TrackDuration", info.DurationSeconds);
                        writer.Write("SourceId", info.SourceId);

                        if (info.Thumbnail?.Length < 500 * 1024) {
                            writer.Write("Thumbnail", info.Thumbnail);
                        }
                    }

                    Console.WriteLine("Memory mapped file updated: " + (info != null ? $"{info.Artist} - {info.Title}" : "<not playing>") + ", size="
                            + stream.Position + ", from=" + (info?.SourceId ?? "?"));
                }
            }
        }

        private static SongInfo _previousSong;

        private static bool? IsPlaying(GlobalSystemMediaTransportControlsSessionPlaybackInfo info) {
            switch (info.PlaybackStatus) {
                case GlobalSystemMediaTransportControlsSessionPlaybackStatus.Closed:
                case GlobalSystemMediaTransportControlsSessionPlaybackStatus.Paused:
                case GlobalSystemMediaTransportControlsSessionPlaybackStatus.Stopped:
                    return false;
                case GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing:
                    return true;
                default:
                    return null;
            }
        }

        public static void Main(string[] args) {
            MediaManager.Start();
            MediaManager.OnSongChanged += async (sender, properties) => {
                _previousSong = await SongInfo.CreateAsync(sender, properties).ConfigureAwait(false);
                if (IsPlaying(sender.ControlSession.GetPlaybackInfo()) is bool v) {
                    SongInfo.Write(v ? _previousSong : null);
                }
            };
            MediaManager.OnPlaybackStateChanged += (sender, info) => {
                if (IsPlaying(info) is bool v) {
                    SongInfo.Write(v ? _previousSong : null);
                }
            };
            Console.Read();
        }
    }
}