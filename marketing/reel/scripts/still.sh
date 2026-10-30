#!/bin/bash
# still.sh <frame> <out.png> [props JSON] — one frame of the composition, rendered on the PC.
set -eu
cd "$(dirname "$0")/.."
npx --no-install remotion still src/index.ts BatteryEtaReel "$2" --frame="$1" --props="${3:-{\}}"
