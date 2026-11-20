#!/bin/zsh
# A/B benchmark: current ConfettiKit (CAEmitterLayer) vs Metal prototype.
# Usage: ./ab.sh [rounds] [out.jsonl] [engines...]   (default engines: ca metal metal@1 layers idle)
# Each round runs every engine once; the order is rotated per round to cancel drift.
# metal@1 = Metal engine with a 1x drawable; idle = 5s with nothing running (baseline).
# Per run it records the binary's own JSON plus:
#   ws_cpu_ms      WindowServer CPU time consumed during the run (compositing + CA particle sim)
#   gpu_util_avg   mean system-wide GPU "Device Utilization %" sampled every ~100ms
set -u
cd "${0:A:h}"
ROUNDS=${1:-6}
OUT=${2:-ab-results.jsonl}
ENGINES=(${@:3})
(( ${#ENGINES} )) || ENGINES=(ca metal metal@1 layers idle)
BIN=.build/release/MetalConfetti
swift build -c release >/dev/null || exit 1
# Never overwrite earlier results: pick a new file name instead.
if [[ -e $OUT ]]; then print -u2 "$OUT exists; pass a new output path"; exit 1; fi

ws_cpu_ms() {  # WindowServer cumulative CPU, "MMM:SS.ss" -> ms
  ps -o time= -p "$(pgrep -x WindowServer)" | awk -F: '{ printf "%d", ($1 * 60 + $2) * 1000 }'
}

gpu_sampler() {
  while true; do
    ioreg -r -d 1 -w 0 -c IOAccelerator | grep -o '"Device Utilization %"=[0-9]*' | head -1 | cut -d= -f2
    sleep 0.1
  done
}

run_one() {  # $1 = ca | metal | idle
  local engine=$1 tmp=$(mktemp) json
  gpu_sampler >> "$tmp" &   # mktemp file starts empty
  local sampler=$!
  local ws0=$(ws_cpu_ms)
  if [[ $engine == idle ]]; then
    sleep 5
    json='{"engine":"idle","overlay_ms":5000}'
  else
    if [[ $engine == *@* ]]; then
      json=$($BIN --engine "${engine%@*}" --metal-scale "${engine#*@}" --bench)
    else
      json=$($BIN --engine "$engine" --bench)
    fi
  fi
  local ws1=$(ws_cpu_ms)
  kill $sampler 2>/dev/null; wait $sampler 2>/dev/null
  local gpu=$(awk '{ s += $1; n++ } END { if (n) printf "%.1f", s / n; else print "null" }' "$tmp")
  rm -f "$tmp"
  echo "${json%\}},\"ws_cpu_ms\":$((ws1 - ws0)),\"gpu_util_avg\":$gpu}" >> "$OUT"
  print -u2 "  $engine done"
}

N=${#ENGINES}
for r in $(seq 1 $ROUNDS); do
  print -u2 "round $r/$ROUNDS"
  for k in $(seq 0 $((N - 1))); do
    e=${ENGINES[$(( (k + r - 1) % N + 1 ))]}
    run_one $e
    sleep 1.5
  done
done

python3 - "$OUT" "${ENGINES[@]}" <<'PY'
import json, statistics, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
keys = ["launch_to_fire_ms", "launch_to_first_commit_ms", "launch_to_first_present_ms", "shader_compile_ms",
        "overlay_ms", "frames", "hitches", "cpu_frame_avg_us", "cpu_frame_p99_us", "gpu_frame_avg_us",
        "process_cpu_ms", "max_rss_mb", "ws_cpu_ms", "gpu_util_avg"]
engines = [e if e != "metal@1" else "metal@1.0x" for e in sys.argv[2:]]
def med(e, k):
    xs = [r[k] for r in rows if r["engine"] == e and r.get(k) is not None]
    return (statistics.median(xs), min(xs), max(xs)) if xs else None
print(f"{'median (min–max), n=' + str(sum(r['engine']==engines[0] for r in rows)) + ' each':34}" + "".join(f"{e:>22}" for e in engines))
for k in keys:
    cells = []
    for e in engines:
        m = med(e, k)
        cells.append(f"{m[0]:.1f} ({m[1]:.0f}–{m[2]:.0f})" if m else "—")
    print(f"{k:34}" + "".join(f"{c:>22}" for c in cells))
PY
