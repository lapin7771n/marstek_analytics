#!/bin/bash
# check.sh <file.mp4> [bpm] — facts about a rendered social video, and a tiled frame sheet <file>.sheet.png.
# Black and freeze hits are reported only: a story's reading holds are meant to stand still.
set -eu

file="${1:-}"
bpm="${2:-}"
here="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$file" ] || [ ! -f "$file" ]; then
  echo "usage: check.sh <file.mp4> [bpm]" >&2
  exit 2
fi

echo "== facts"
ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,profile,width,height,r_frame_rate,nb_frames,pix_fmt,color_space,color_primaries,color_transfer,color_range \
  -of default=noprint_wrappers=1 "$file"
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1 "$file"
audio="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of default=noprint_wrappers=1 "$file")"
if [ -n "$audio" ]; then
  echo "$audio" | sed 's/^/audio_/'
else
  echo "audio: none"
fi

echo "== blackdetect d=0.1"
black="$(ffmpeg -hide_banner -nostats -i "$file" -vf blackdetect=d=0.1 -an -f null - 2>&1 | grep 'black_start' || true)"
if [ -n "$black" ]; then echo "$black"; else echo "none"; fi

echo "== freezedetect n=-60dB d=0.5 (report only)"
freeze="$(ffmpeg -hide_banner -nostats -i "$file" -vf freezedetect=n=-60dB:d=0.5 -an -f null - 2>&1 | grep -E 'freeze_(start|duration)' | sed 's/.*lavfi\.//' || true)"
if [ -n "$freeze" ]; then echo "$freeze"; else echo "none"; fi

if [ -n "$audio" ]; then
  echo "== loudness"
  ffmpeg -hide_banner -nostats -i "$file" -vn -af ebur128=peak=true -f null - 2>&1 \
    | awk '/Summary:/ { on = 1 } on && /^ +I:/ { sub(/^ +I: +/, ""); print "integrated loudness: " $0 } on && /^ +Peak:/ { sub(/^ +Peak: +/, ""); print "true peak: " $0 }'
  if [ -n "$bpm" ]; then
    echo "== beat grid $bpm bpm"
    python3 "$here/beat.py" "$file" --check "$bpm"
  fi
elif [ -n "$bpm" ]; then
  echo "== beat grid: skipped, the file has no audio"
fi

echo "== sheet"
seconds="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file")"
rows="$(awk -v d="$seconds" 'BEGIN { r = int((d + 9.999) / 10); if (r < 1) r = 1; print r }')"
ffmpeg -y -v error -i "$file" -vf "fps=1,scale=216:-1,tile=10x${rows}" -frames:v 1 "$file.sheet.png"
echo "$file.sheet.png"
