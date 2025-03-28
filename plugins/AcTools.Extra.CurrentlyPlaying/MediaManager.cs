using System;
using System.Collections.Generic;
using Windows.Foundation;
using Windows.Media.Control;

namespace AcTools.Extra.CurrentlyPlaying {
    public static class MediaManager {
        public delegate void MediaSessionDelegate(MediaSession session);

        /// <summary>
        /// Triggered when a new media source gets added to the MediaSessions
        /// </summary>
        public static event MediaSessionDelegate OnNewSource;

        /// <summary>
        /// Triggered when a media source gets removed from the MediaSessions
        /// </summary>
        public static event MediaSessionDelegate OnRemovedSource;

        /// <summary>
        /// Triggered when a playback state changes of a MediaSession
        /// </summary>
        public static event TypedEventHandler<MediaSession, GlobalSystemMediaTransportControlsSessionPlaybackInfo> OnPlaybackStateChanged;

        /// <summary>
        /// Triggered when a song changes of a MediaSession
        /// </summary>
        public static event TypedEventHandler<MediaSession, GlobalSystemMediaTransportControlsSession> OnSongChanged;

        /// <summary>
        /// A dictionary of the current MediaSessions
        /// </summary>
        public static Dictionary<string, MediaSession> CurrentMediaSessions = new Dictionary<string, MediaSession>();

        private static bool _isStarted;

        /// <summary>
        /// This starts the MediaManager
        /// This can be changed to a constructor if you don't care for the first few 'new sources' events
        /// </summary>
        public static void Start() {
            if (!_isStarted) {
                var sessionManager = GlobalSystemMediaTransportControlsSessionManager.RequestAsync().GetAwaiter().GetResult();
                SessionsChanged(sessionManager);
                sessionManager.SessionsChanged += SessionsChanged;
                _isStarted = true;
            }
        }

        private static void SessionsChanged(GlobalSystemMediaTransportControlsSessionManager sender, SessionsChangedEventArgs args = null) {
            var sessionList = sender.GetSessions();

            foreach (var session in sessionList) {
                if (!CurrentMediaSessions.ContainsKey(session.SourceAppUserModelId)) {
                    MediaSession mediaSession = new MediaSession(session);
                    CurrentMediaSessions[session.SourceAppUserModelId] = mediaSession;
                    OnNewSource?.Invoke(mediaSession);
                    mediaSession.OnSongChange(session);
                }
            }
        }

        private static void RemoveSession(MediaSession mediaSession) {
            CurrentMediaSessions.Remove(mediaSession.ControlSession.SourceAppUserModelId);
            OnRemovedSource?.Invoke(mediaSession);
        }

        public class MediaSession {
            public GlobalSystemMediaTransportControlsSession ControlSession;

            public MediaSession(GlobalSystemMediaTransportControlsSession ctrlSession) {
                ControlSession = ctrlSession;
                ControlSession.MediaPropertiesChanged += OnSongChange;
                ControlSession.PlaybackInfoChanged += OnPlaybackInfoChanged;
            }

            private void OnPlaybackInfoChanged(GlobalSystemMediaTransportControlsSession session, PlaybackInfoChangedEventArgs args = null) {
                var props = session.GetPlaybackInfo();
                if (props.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Closed) {
                    session.PlaybackInfoChanged -= OnPlaybackInfoChanged;
                    session.MediaPropertiesChanged -= OnSongChange;
                    RemoveSession(this);
                } else {
                    OnPlaybackStateChanged?.Invoke(this, props);
                }
            }

            internal void OnSongChange(GlobalSystemMediaTransportControlsSession session, MediaPropertiesChangedEventArgs args = null) {
                OnSongChanged?.Invoke(this, session);
            }
        }
    }
}