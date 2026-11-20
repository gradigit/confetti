#!/bin/zsh
# Frame-rate A/B of confetti binaries on the real display setup.
# Usage: ./fps-ab.sh [rounds] name=/path/to/confetti [name=/path ...]
#   e.g. ./fps-ab.sh 6 old=/opt/homebrew/bin/confetti rel=$HOME/.local/bin/confetti new=../../.build/release/confetti
# Each run launches the binary under Tools/hitchmeter, which watches the main display with every
# other app excluded and reports how often the confetti actually updated (fps) and how many
# display refreshes were missed. Order rotates each round; results are paired per round.
# Needs Screen Recording permission for the terminal.
set -u
cd "${0:A:h}"
ROUNDS=$1; shift
names=() bins=()
for kv in "$@"; do names+=${kv%%=*}; bins+=${kv#*=}; done
N=${#names}
mkdir -p .build
[[ ! -x .build/hitchmeter || Tools/hitchmeter.swift -nt .build/hitchmeter ]] && swiftc -O Tools/hitchmeter.swift -o .build/hitchmeter
OUT=$(mktemp)
for r in $(seq 1 $ROUNDS); do
  for k in $(seq 0 $((N - 1))); do
    i=$(( (k + r - 1) % N + 1 ))
    .build/hitchmeter ${names[$i]} ${bins[$i]} >> $OUT
    sleep 1
  done
  print -u2 "round $r/$ROUNDS done"
done
python3 - $OUT ${names[@]} <<'PY'
import json, statistics as st, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.startswith('{')]
names = sys.argv[2:]
print(f"{'engine':8} {'fps median':>10} {'missed median':>14} {'worst gap ms':>13}   runs")
for n in names:
    r = [x for x in rows if x['label'] == n]
    print(f"{n:8} {st.median(x['fps'] for x in r):10.1f} {st.median(x['missed'] for x in r):14.0f} {max(x['gap_max_ms'] for x in r):13.1f}   {[x['fps'] for x in r]}")
rounds = [rows[i:i + len(names)] for i in range(0, len(rows), len(names))]
for a in names[1:]:
    d = [next(x['fps'] for x in R if x['label'] == a) - next(x['fps'] for x in R if x['label'] == names[0]) for R in rounds]
    print(f"{a} vs {names[0]}: median {st.median(d):+.1f} fps per round  {['%+.1f' % x for x in d]}")
PY
