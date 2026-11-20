# Confetti engine A/B — 2026-11-20

**Answer:** A custom sim drawn as one CALayer per particle ("layers") matches the current
CAEmitterLayer on GPU, finishes ~0.3s sooner, and adds drag + 3D flutter. It costs ~80 ms more
CPU in our process per burst. A full-screen CAMetalLayer renderer ("metal") roughly doubles
system GPU load and was rejected.

Prototype: `Prototypes/MetalConfetti` (engines `ca`, `metal`, `layers`, `split`; `ab.sh` runs the A/B).
Raw rows: `2026-11-20-confetti-engine-ab-run2.jsonl` (4 engines), `…-run3.jsonl` (ca vs layers after
the one-property-per-layer optimisation).

## Setup

- MacBook Air, Apple M4, macOS 27.2.1, built-in display only (3420×2224 px, 60 Hz). No external/QHD
  or ProMotion display tested.
- One burst per run: 2 cannons × 144 particles (matches CA default 24 cells × 40/s × 0.15 s).
- 5 rounds per engine, order rotated each round, 1.5 s gap; "idle" = 5 s with nothing running.
- `gpu_util_avg`: system-wide AGX "Device Utilization %" from `ioreg`, sampled ~10 Hz (coarse).
- `ws_cpu_ms`: WindowServer CPU time over the run from `ps` (10 ms resolution, noisy: idle varies
  ±200 ms because other apps on screen are live).

## Results (median, min–max)

Run 2 (all engines, before layers optimisation):

| | ca (current) | metal 2× | metal 1× | layers | idle |
|---|---|---|---|---|---|
| GPU util % | 14.9 (13–17) | 32.1 (30–34) | 30.4 (28–32) | 12.5 (9–16) | 1.2 (0–7) |
| our process CPU ms | 52.7 | 203.4 | 209.1 | 165.4 | — |
| WindowServer CPU ms | 2360 | 2210 | 2200 | 2300 | 2210 |
| overlay on screen ms | 4915 | 4602 | 4627 | 4592 | — |
| launch → first commit ms | 101.7 | 119.6 | 132.2 | 108.3 | — |
| hitches (>1.5× frame) | 0 | 0 | 0 | 0 | — |

Run 3 (layers sets only the affine transform per frame — position folded in):

| | ca | layers | idle |
|---|---|---|---|
| GPU util % | 12.5 (12–19) | 14.2 (8–18) | 1.1 (0–10) |
| our process CPU ms | 56.7 (51–66) | 137.3 (118–174) | — |
| layers CPU per frame µs (avg / p99) | — | 225 / 455 | — |
| WindowServer CPU ms | 2350 (2330–2370) | 2250 (2090–2320) | 2180 (1970–2360) |
| overlay on screen ms | 4915 | 4576 | — |

## Findings

- **Metal's cost is compositing, not drawing.** Dropping the drawable to 1× (¼ the pixels) cut the
  app's GPU time per frame from 626 to 188 µs but system GPU only from 32% to 30%. A full-screen
  non-opaque surface that changes every frame is what's expensive. CAEmitterLayer and per-particle
  CALayers avoid it: the render server draws small quads directly.
- **Simulation CPU is negligible**: 288 particles step in ~6 µs (10k in ~214 µs) on M4, -O build.
- **Metal shader compile** from source: ~200 ms cold, 5–8 ms warm (system shader cache).
- **CAEmitterLayer size bug** (independent of the rewrite): `NSImage.cgImage()` returns 28×14 px on a
  2× main screen but `CAEmitterCell.contentsScale` defaults to 1, so particles draw at 2× design
  size, and would be half that if the main screen were 1×.
- WindowServer CPU was highest for `ca` in both runs (consistent with the emitter sim running in the
  render server), but the difference is inside the noise. Unverified.

## Not verified

- External / QHD monitors, multiple screens, 120 Hz ProMotion.
- GPU power (needs `sudo powermetrics`) or Instruments Metal System Trace.
- Visual quality is judged from screenshots only.

## Update (same day): "baked" engine

**Answer:** Running the sim to completion at launch and handing every particle to Core Animation as
pre-computed animations ("baked") removes all per-frame app work. Against the current
CAEmitterLayer it uses less GPU, is on screen 0.28 s less, and costs ~10 ms more app CPU and ~9 MB
more memory per burst. It looks the same as "layers" (screenshots compared).

How it works (`Prototypes/MetalConfetti/Sources/MetalConfetti/BakedOverlay.swift`):
- Sim runs at 60 Hz for the whole burst in ~4 ms; positions sampled at 20 Hz into a
  `CAKeyframeAnimation` (`.cubic`). Spin and flutter are constant-rate, so they're given as rates:
  outer layer `transform.rotation.z`, inner layer repeating `transform.scale.x` = cos and a discrete
  `contents` swap to a darker back-face image. 2 layers + 5 animations per particle, one commit.
- `isRemovedOnCompletion = false`: with the default, the app woke to remove each of the 1,440
  animations as it ended — ~40 ms of CPU during the "idle" phase.
- Exit via `DispatchSource` timer with 1 ms leeway: `asyncAfter` fired ~220 ms late (timer
  coalescing), keeping an empty overlay up. **The current CLI has the same late exit**
  (`Sources/confetti/main.swift` `asyncAfter(deadline: .now() + exitDuration)`): CA runs measure
  4.91 s on screen for a 4.65 s animation.
- 10 Hz sampling instead of 20 saved ~1.5 ms CPU, inside noise; kept 20 Hz.

Run 4 (ca / layers / baked / idle, before the exit-timer fix; idle GPU baseline was higher this run):

| | ca | layers | baked | idle |
|---|---|---|---|---|
| GPU util % | 18.9 (19–20) | 16.6 (16–17) | 17.2 (16–18) | 10.8 (10–12) |
| our process CPU ms | 53.1 | 118.3 | 71.1 | — |
| max RSS MB | 60.3 | 62.1 | 69.1 | — |

Run 5 (ca / baked / idle, with exit-timer fix):

| | ca | baked | idle |
|---|---|---|---|
| GPU util % | 20.4 (18–21) | 18.5 (17–20) | 12.7 (10–15) |
| our process CPU ms | 62.3 (50–79) | 72.7 (67–74) | — |
| on screen ms | 4914 | 4631 | — |
| launch → first commit ms | 107.5 | 122.0 | — |
| max RSS MB | 60.5 | 69.1 | — |
| app work per frame | none (render server) | none (render server) | — |

Baked CPU breakdown (checkpoints): launch ~26–35 ms, windows ~11 ms, bake ~4 ms, build + commit
animations ~13 ms, idle phase ~0–20 ms (usually flat; cause of occasional tail not found —
`sample` returned an empty call graph).

WindowServer CPU stayed unusable as a signal (idle measured higher than the engines in runs 4–5).
Still not verified: external/QHD, multiple screens, ProMotion, GPU power.
