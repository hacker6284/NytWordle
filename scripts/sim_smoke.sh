#!/usr/bin/env bash
# Build, pre-allow network, launch Simulator, wait for nyt-verify.json from the game.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${PLAYDATE_SDK_PATH:-/Users/zachmills/Developer/PlaydateSDK}"
PDC="$SDK/bin/pdc"
SIM="$SDK/bin/Playdate Simulator.app/Contents/MacOS/Playdate Simulator"
BUNDLE="dev.playdate.nytwordle"
DATA="$SDK/Disk/Data/$BUNDLE"
VERIFY="$DATA/nyt-verify.json"
PDX="$ROOT/NytWordle.pdx"
LOG="/tmp/nytwordle-sim/sim.log"

mkdir -p /tmp/nytwordle-sim "$DATA"
printf 'net+\n' > "$DATA/Permissions"
printf '1\n' > "$DATA/run-smoke"
rm -f "$VERIFY" "$LOG"

"$PDC" -sdkpath "$SDK" "$ROOT/source" "$PDX"

pkill -f "Playdate Simulator" 2>/dev/null || true
sleep 1

"$SIM" "$PDX" >"$LOG" 2>&1 &
SIM_PID=$!

deadline=$((SECONDS + 45))
while (( SECONDS < deadline )); do
  if [[ -f "$VERIFY" ]]; then
    echo "VERIFY_FILE=$VERIFY"
    cat "$VERIFY"
    echo
    if python3 - "$VERIFY" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
ok = (
    data.get("ok") is True
    and data.get("playedGuess") is True
    and isinstance(data.get("word"), str)
    and len(data["word"]) == 5
    and data.get("probeGuess") == "crane"
    and data.get("selfCheckState") == data.get("expectedCorrect") == 2
)
print("SMOKE", "PASS" if ok else "FAIL", data)
sys.exit(0 if ok else 1)
PY
    then
      echo "DONE: simulator fetched NYT Wordle and played a guess through Game"
      exit 0
    else
      echo "FAILED: verify payload bad"
      exit 1
    fi
  fi
  if ! kill -0 "$SIM_PID" 2>/dev/null; then
    echo "FAILED: simulator exited early"
    tail -50 "$LOG" || true
    exit 1
  fi
  sleep 1
done

echo "FAILED: timed out waiting for $VERIFY"
ls -la "$DATA" || true
tail -50 "$LOG" || true
exit 1
