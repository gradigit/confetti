# Handoff — Snow Accumulation Prototypes

## What Was Done

Built two snow accumulation prototypes comparing SpriteKit vs pure Core Animation approaches:

### SnowAccumulation (SpriteKit)
- Individual `SKSpriteNode` snowflakes with `SKPhysicsBody` for per-particle physics
- Snow lands on pile surface — detected via y-position check against HeightMap each frame
- Pile grows only where snow actually falls (cosine splat deposit, radius 100pt)
- Mouse cursor repulsion field pushes falling snowflakes away
- Mouse cursor sweeps pile (lowers HeightMap near cursor when near surface)
- Landing puffs (pool of 3 `SKEmitterNode`) and sparkles (pool of 5 `SKSpriteNode`) trigger at exact landing points
- Wind via `SKFieldNode.noiseField` for organic drift
- Gradient pile fill via `SKShapeNode.fillTexture`, glow via separate stroke shape node
- 60fps, ~70 nodes at steady state

### SnowAccumulationCA (Core Animation)
- `CAEmitterLayer` for GPU-managed snow particles (zero CPU per-particle)
- `CAGradientLayer` + `CAShapeLayer` mask for pile rendering
- Time-based pile growth with 8-second delay matching fall time
- Particle lifetime dynamically adjusted as pile rises
- Surface mist emitter repositions as pile grows
- 10Hz `DispatchSourceTimer` for pile updates
- No mouse interaction (CAEmitterLayer particles are opaque GPU state)

## Current State

Both prototypes build and run. Key tuning applied:
- Wind field: strength 0.15, animation speed 0.8, snowflake mass 0.05, damping 0.3 (gentle, not chaotic)
- Pile fade-in: opacity = min(averageHeight / 8.0, 1.0) (visible after first few landings)
- FPS diagnostics enabled on SpriteKit version (`showsFPS/showsNodeCount/showsDrawCount`)
- HeightMap guards against inverted ranges from off-screen coordinates

## Open Questions

- User hasn't tested the CA prototype yet — needs visual comparison with SpriteKit version
- Performance comparison (CPU/GPU in Activity Monitor) between the two approaches not yet measured
- No decision yet on which approach to productionize (if either)
- The SpriteKit version crashed at `preferredFramesPerSecond = 0` on ProMotion — fixed with explicit 60

## First Steps

1. Read CLAUDE.md for project context
2. Run both prototypes: `cd Prototypes/SnowAccumulation && swift run` and `cd Prototypes/SnowAccumulationCA && swift run`
3. Check TODO.md if it exists for any pending items
