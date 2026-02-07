# TODO

## Current Phase: Blizzard Integration — Testing

### Up Next
- [ ] Test blizzard pile accumulation visuals (does the pile look good at 25% screen height?)
- [ ] Test fade-out animation after pile fills
- [ ] Test mouse sweep auto-stop (sweep 5% screen area worth of snow)
- [ ] Test `stopSnowing()` API for programmatic control
- [ ] Test multi-screen behavior (pile fills independently per screen?)
- [ ] Tune sweep threshold if too sensitive or too hard to trigger
- [ ] Update promo video if blizzard preset should be showcased

### Completed
- [x] Prompt perfection (Mode 1) — architect/prompt.md finalized
- [x] Snow accumulation prototypes (SpriteKit + Core Animation)
- [x] Architecture decision: CAEmitterLayer for confetti, SpriteKit for interactive snow only
- [x] Window level `.floating` for overlays
- [x] SpriteKit confetti prototype (InteractiveConfettiSK + SnowAccumulation --mode confetti)
- [x] Integrate SpriteKit snow into ConfettiKit as `blizzard` preset
- [x] Preset name chosen: `blizzard`
- [x] BlizzardScene, BlizzardWindow, HeightMap ported to ConfettiKit
- [x] EmissionStyle.blizzard added, ConfettiController routes to SpriteKit path
- [x] CLI support: --presets, --duration, help text updated
- [x] ConfigFile: blizzard emission style save/load
- [x] Physics tuning: gravity -0.25, linearDamping 0.15, spawnInterval 0.12
- [x] Pile max height: 25% of screen (was 55% in prototype)
- [x] Auto-stop: pile full, sweep threshold, stopSnowing() API
- [x] onBlizzardComplete callback for multi-screen completion tracking
- [x] Graceful wind-down: stop spawn → flakes settle → pile fade → complete

### Dropped
- SpriteKit confetti mode — not integrating, CAEmitterLayer confetti is already perfect
