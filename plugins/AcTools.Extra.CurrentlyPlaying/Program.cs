using System;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Text;
using System.Threading.Tasks;
using Windows.Media.Control;

namespace AcTools.Extra.CurrentlyPlaying
{
    internal class Program
    {
        private static async Task<byte[]> ReadThumbnail(GlobalSystemMediaTransportControlsSessionMediaProperties properties)
        {
            try
            {
                var stream = await properties.Thumbnail.OpenReadAsync();
                if (stream?.Size > 0)
                {
                    var ret = new byte[stream.Size];
                    await stream.AsStream().ReadAsync(ret, 0, ret.Length).ConfigureAwait(false);
                    return ret;
                }
            }
            catch (Exception e)
            {
                Console.Error.WriteLine("Failed to read thumbnail: " + e);
            }
            return null;
        }

        private static unsafe bool ArraysEqual(byte[] a1, byte[] a2)
        {
            unchecked
            {
                if (a1 == a2) return true;
                if (a1 == null || a2 == null || a1.Length != a2.Length)
                    return false;
                fixed (byte* p1 = a1, p2 = a2)
                {
                    byte* x1 = p1, x2 = p2;
                    int l = a1.Length;
                    for (int i = 0; i < l / 8; i++, x1 += 8, x2 += 8)
                        if (*((long*)x1) != *((long*)x2)) return false;
                    if ((l & 4) != 0) { if (*((int*)x1) != *((int*)x2)) return false; x1 += 4; x2 += 4; }
                    if ((l & 2) != 0) { if (*((short*)x1) != *((short*)x2)) return false; x1 += 2; x2 += 2; }
                    if ((l & 1) != 0) if (*((byte*)x1) != *((byte*)x2)) return false;
                    return true;
                }
            }
        }

        private class DictionaryWriter : IDisposable
        {
            private BinaryWriter _writer;

            public DictionaryWriter(Stream stream)
            {
                _writer = new BinaryWriter(stream);
            }

            private void Write(string value)
            {
                var bytes = Encoding.UTF8.GetBytes(value);
                _writer.Write(bytes.Length);
                _writer.Write(bytes);
            }

            public void Write(string key, string value)
            {
                if (value == null) return;
                Write(key);
                Write(value);
            }

            public void Write(string key, int value)
            {
                Write(key);
                Write(value.ToString(CultureInfo.InvariantCulture));
            }

            public void Write(string key, long value)
            {
                Write(key);
                Write(value.ToString(CultureInfo.InvariantCulture));
            }

            public void Write(string key, bool value)
            {
                Write(key);
                Write(value ? "1" : "0");
            }

            public void Write(string key, byte[] value)
            {
                if (value == null) return;
                Write(key);
                _writer.Write(value.Length);
                _writer.Write(value);
            }

            public void Dispose()
            {
                _writer.Write(0);
                _writer?.Dispose();
            }
        }

        public class SongInfo
        {
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

            protected bool Equals(SongInfo other)
            {
                return Artist == other.Artist
                       && AlbumArtist == other.AlbumArtist
                       && AlbumTitle == other.AlbumTitle
                       && Title == other.Title
                       && AlbumTrackCount == other.AlbumTrackCount
                       && TrackNumber == other.TrackNumber
                       && SourceId == other.SourceId
                       && DurationSeconds == other.DurationSeconds
                       && StartTime == other.StartTime
                       && ArraysEqual(Thumbnail, other.Thumbnail);
            }

            public override bool Equals(object obj)
            {
                if (ReferenceEquals(null, obj)) return false;
                if (ReferenceEquals(this, obj)) return true;
                if (obj.GetType() != this.GetType()) return false;
                return Equals((SongInfo)obj);
            }

            public override int GetHashCode()
            {
                unchecked
                {
                    var hashCode = (Artist != null ? Artist.GetHashCode() : 0);
                    hashCode = (hashCode * 397) ^ (AlbumArtist != null ? AlbumArtist.GetHashCode() : 0);
                    hashCode = (hashCode * 397) ^ (AlbumTitle != null ? AlbumTitle.GetHashCode() : 0);
                    hashCode = (hashCode * 397) ^ (Title != null ? Title.GetHashCode() : 0);
                    hashCode = (hashCode * 397) ^ AlbumTrackCount;
                    hashCode = (hashCode * 397) ^ TrackNumber;
                    hashCode = (hashCode * 397) ^ (Thumbnail != null ? Thumbnail.GetHashCode() : 0);
                    hashCode = (hashCode * 397) ^ (SourceId != null ? SourceId.GetHashCode() : 0);
                    hashCode = (hashCode * 397) ^ DurationSeconds;
                    hashCode = (hashCode * 397) ^ StartTime.GetHashCode();
                    return hashCode;
                }
            }

            public static async Task<SongInfo> CreateAsync(MediaManager.MediaSession session,
                    GlobalSystemMediaTransportControlsSessionMediaProperties properties)
            {
                var duration = 0;
                var position = 0;
                try
                {
                    var timelineProperties = session.ControlSession.GetTimelineProperties();
                    position = (int)timelineProperties.Position.TotalSeconds;
                    duration = (int)Math.Ceiling((timelineProperties.EndTime - timelineProperties.StartTime).TotalSeconds);
                }
                catch (Exception e)
                {
                    Console.Error.WriteLine(e.Message);
                }

                return new SongInfo
                {
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

            public static void Write(SongInfo info, bool force)
            {
                if (!force && Equals(_previouslyWritten, info) == true && _mmf != null) return;
                _previouslyWritten = info;

                if (_mmf == null)
                {
                    _mmf = MemoryMappedFile.CreateOrOpen(@"AcTools.CurrentlyPlaying.v1", 1024 * 1024,
                            MemoryMappedFileAccess.ReadWrite);
                }

                using (var stream = _mmf.CreateViewStream())
                using (var writer = new DictionaryWriter(stream))
                {
                    writer.Write("UpdatePhase", _updatePhase++);
                    if (_updatePhase > 999)
                    {
                        _updatePhase = 0;
                    }
                    writer.Write("IsPlaying", info != null);
                    if (info != null)
                    {
                        writer.Write("Artist", info.Artist);
                        writer.Write("AlbumArtist", info.AlbumArtist);
                        writer.Write("AlbumTitle", info.AlbumTitle);
                        writer.Write("Title", info.Title);
                        writer.Write("AlbumTrackCount", info.AlbumTrackCount);
                        writer.Write("TrackNumber", info.TrackNumber);
                        writer.Write("TrackStart", info.StartTime);
                        writer.Write("TrackDuration", info.DurationSeconds);
                        writer.Write("SourceId", info.SourceId);
                        if (info.Thumbnail?.Length < (1024 - 128) * 1024)
                        {
                            writer.Write("Thumbnail", info.Thumbnail);
                        }
                    }

                    Console.WriteLine("Memory mapped file updated: " + (info != null ? $"{info.Artist} - {info.Title} ({info.DurationSeconds} s)" : "<not playing>") + ", size="
                            + stream.Position + ", from=" + (info?.SourceId ?? "?"));
                }
            }
        }

        private static bool? IsPlaying(GlobalSystemMediaTransportControlsSessionPlaybackInfo info)
        {
            switch (info.PlaybackStatus)
            {
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

        private static SongInfo _previousSong;
        private static int _phase;

        public static void Main(string[] args)
        {
            MediaManager.OnSongChanged += async (sender, properties) =>
            {
                var phase = ++_phase;
                {
                    await Task.Delay(100);
                    if (phase != _phase) return;
                    var props = await properties.TryGetMediaPropertiesAsync();
                    if (phase != _phase) return;
                    var song = await SongInfo.CreateAsync(sender, props).ConfigureAwait(false);
                    if (phase != _phase) return;
                    _previousSong = song;
                }
                if (IsPlaying(sender.ControlSession.GetPlaybackInfo()) is bool v)
                {
                    SongInfo.Write(v ? _previousSong : null, false);
                    /*for (var i = 0; i < 4; ++i)
                    {
                        await Task.Delay(700).ConfigureAwait(false);
                        if (phase != _phase) return;
                        var props = await properties.TryGetMediaPropertiesAsync();
                        if (phase != _phase) return;
                        var newTh = await ReadThumbnail(props).ConfigureAwait(false);
                        if (phase != _phase) return;
                        if (newTh != null && _previousSong != null && !ArraysEqual(newTh, _previousSong.Thumbnail))
                        {
                            _previousSong.Thumbnail = newTh;
                            if (IsPlaying(sender.ControlSession.GetPlaybackInfo()) is bool v1)
                            {
                                SongInfo.Write(v1 ? _previousSong : null, true);
                            }
                        }
                    }*/
                }
            };
            MediaManager.OnPlaybackStateChanged += (sender, info) =>
            {
                if (IsPlaying(info) is bool v)
                {
                    SongInfo.Write(v ? _previousSong : null, false);
                }
            };
            MediaManager.Start();
            Console.Read();
        }
    }
}