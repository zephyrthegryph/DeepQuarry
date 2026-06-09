// Media player — TGUI.
//
// Hosted inside the hidden rpane.mediapanel skin element. The window
// itself is never visible to the user — this component just owns an
// HTML5 <audio> element and reacts to data changes from DM:
//   - url: source URL of the track ("" = stop)
//   - start_time: seconds into the track to seek to on (re)play
//   - volume: effective playback volume (0..1)
//
// Replaces the legacy browse(PLAYER_HTML5_HTML) + output(":SetMusic")
// JS-interop dance.

import { useEffect, useRef } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';

type Data = {
  url: string;
  start_time: number;
  volume: number;
};

export const MediaPlayer = () => {
  const { data } = useBackend<Data>();
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const lastUrlRef = useRef<string>('');

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    if (!data.url) {
      audio.pause();
      audio.removeAttribute('src');
      audio.load();
      lastUrlRef.current = '';
      return;
    }

    const clampedVolume = Math.max(0, Math.min(1, data.volume));

    // Re-seek + replay only when the URL actually changes; otherwise just
    // sync volume so the slider works without restarting the track.
    if (data.url !== lastUrlRef.current) {
      const onReady = () => {
        audio.removeEventListener('canplay', onReady);
        audio.volume = clampedVolume;
        audio.currentTime = Math.max(0, data.start_time);
        audio.play().catch(() => {
          // Autoplay can be blocked; ignore — server will retry on next update.
        });
      };
      audio.addEventListener('canplay', onReady);
      audio.src = data.url;
      lastUrlRef.current = data.url;
    } else {
      audio.volume = clampedVolume;
    }
  }, [data.url, data.start_time, data.volume]);

  return (
    <Window fitted>
      <Window.Content>
        <audio ref={audioRef} />
      </Window.Content>
    </Window>
  );
};
