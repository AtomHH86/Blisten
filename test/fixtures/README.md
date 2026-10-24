# Cache media fixtures

These files contain 0.1 seconds of generated silence, with no external audio.
They exercise container acceptance; native playback is covered separately with
the existing loopback WAVE fixture.

Generated with FFmpeg:

```sh
ffmpeg -f lavfi -i anullsrc=r=8000:cl=mono -t 0.1 -c:a aac -b:a 16k -movflags +faststart cache-silence.m4a
ffmpeg -f lavfi -i anullsrc=r=8000:cl=mono -t 0.1 -c:a flac cache-silence.flac
```
