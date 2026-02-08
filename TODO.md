# TODO

## Current Phase: Blizzard Integration — Ship

### Up Next
- [ ] Test multi-monitor: pile size/density on 4K vs standard displays (spawn rate is fixed, pile may look sparse on large screens)
- [ ] Update promo video if blizzard preset should be showcased

### Completed
- [x] Prompt perfection (Mode 1) — architect/prompt.md finalized
- [x] Snow accumulation prototypes (SpriteKit + Core Animation)
- [x] Architecture decision: CAEmitterLayer for confetti, SpriteKit for interactive snow only
- [x] Window level `.statusBar` for blizzard overlays (snow on top of everything)
- [x] SpriteKit confetti prototype (InteractiveConfettiSK + SnowAccumulation --mode confetti)
- [x] Integrate SpriteKit snow into ConfettiKit as `blizzard` preset
- [x] BlizzardScene, BlizzardWindow, HeightMap ported to ConfettiKit
- [x] EmissionStyle.blizzard added, ConfettiController routes to SpriteKit path
- [x] CLI support: --presets, --duration, help text updated
- [x] ConfigFile: blizzard emission style save/load
- [x] Physics tuning: gravity -0.25, linearDamping 0.15, spawnInterval 0.12
- [x] Pile max height: 25% of screen (was 55% in prototype)
- [x] Auto-stop: pile full (any column hits max), sweep threshold, stopSnowing() API
- [x] onBlizzardComplete callback for multi-screen completion tracking
- [x] Melt animation: pile shrinks + fades over 2s on wind-down
- [x] Sweep/rate/radius scale with screen size (resolution-independent)
- [x] Sweep threshold tuned to 8% of max pile area
- [x] --duration triggers stopSnowing() (melt animation) instead of hard cleanup

### Dropped
- SpriteKit confetti mode — not integrating, CAEmitterLayer confetti is already perfect
- Escape key dismiss — app is .accessory with no keyboard focus, monitor would be dead code
