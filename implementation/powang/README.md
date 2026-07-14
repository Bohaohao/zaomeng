# Powang Preconstruction Package

## Purpose

This directory is an offline construction package for the Powang profession. It is not a Y3 map script root and is not loaded by the game.

It depends on the sibling `implementation/profession_common/lua/` library for explicit target ownership, effect storage, control leases, and adapter-command validation. The Powang-named modules remain compatibility entry points so existing project imports do not change.

The package exists because the current workspace has no `maps/EntryMap`, `global_script`, `y3editor` MCP connection, object IDs, model IDs, or icon IDs. It keeps the adopted design machine-readable without inventing production identifiers.

## Stage Status

- Template v1.1 compatibility repair is complete at offline depth. See [the P1 repair record](../../docs/归档/职业设计/07-破妄P1修订与验收.md). The remaining feature gates require a real Y3 map and are not verified in-game.
- The design and offline-construction stage was accepted on `2026-07-11`.
- Real Y3 editor integration, object readback, Lua 5.4 runtime loading, and multiplayer playtesting are deferred by the current project decision.
- Deferred work remains unverified. Nothing in this package should be described as a created or verified in-game object.

## Files

- `preconstruction-manifest.json`: confirmed object-editor fields and unresolved execution gates.
- `y3-api-baseline.json`: pinned `y3-lualib` commit, public API modules, and synchronized events used by the bridge.
- `tests/preflight.ps1`: validates counts, stable keys, level arrays, zero base damage/costs, dependencies, and hero growth breakpoints.
- `tools/materialize-object-commands.ps1`: emits ordered `y3_obj_edit.py` commands only after every production gate is resolved.
- `tests/test-materializer.ps1`: uses synthetic IDs in a temporary directory to verify 31 generated commands and production-data refusal.
- `lua/powang_config.lua`: adopted numeric configuration with no Y3 API calls.
- `lua/powang_core.lua`: pure state engine for hero growth, battle momentum, Dongming, ultimate gauge, decay, spend confirmation, and cleanup.
- `lua/powang_skills.lua`: all eight active skills expressed as adapter-neutral damage, movement, control, modifier, and cooldown commands.
- `lua/powang_effects.lua`: source-aware effect storage for shared-highest, source-bound, refresh-only, and shield-refresh policies.
- `../profession_common/lua/`: shared target, effect-store, control-lease, and adapter-contract implementation used by both completed professions.
- `lua/powang_target_contract.lua`: explicit self, primary, selected, team, and explicit target ownership shared by effects and the Y3 bridge.
- `lua/powang_adapter_contract.lua`: the minimal adapter contract that a verified Y3 integration must implement.
- `lua/powang_runtime.lua`: actor registration, skill use, ultimate use, ticking, cleanup, and command dispatch.
- `lua/powang_y3_adapter.lua`: verified Y3 Unit/Ability/Buff/Timer/Mover/Game API adapter with explicit effect targeting and root-lease integration.
- `lua/powang_y3_targeting.lua`: default synchronized geometry and target filtering through Selector/Shape/Point.
- `lua/powang_y3_control_ledger.lua`: adapter-neutral overlapping-control lease manager.
- `lua/powang_y3_controller.lua`: synchronized unit-event controller with per-actor trigger lifecycle management.
- `Y3-INTEGRATION.md`: project mappings, hooks, synchronization rules, and deferred verification gates.
- `DEFERRED-INTEGRATIONS.md`: integration contracts and acceptance TODOs for character save/reconnect, the skill-tree UI, five-slot loadouts, and four-player synchronization.
- `tests/test_powang.lua`: deterministic offline tests for the pure Lua implementation.
- `tests/test_bridge_targeting.lua`: offline bridge tests for self, explicit, and team modifier targets.
- `tests/test_bridge_lifecycle.lua`: offline bridge tests for overlapping roots and controller teardown.
- `tests/verify-y3-api.ps1`: checks the bridge against the pinned public API cache and rejects direct engine calls.
- `reports/lua-review-2026-07-11.md`: current static and offline-runtime review evidence.

## Safety

- This JSON is a project-side manifest, not a Y3 editor JSON file.
- Never copy it into `editor_table/` or `maps/*/`.
- Convert it to `y3_obj_edit.py` commands or a Y3-Helper plugin only after real IDs and resources are queried.
- Runtime Lua belongs in a valid Y3 script root after the map project is connected.

## Preflight

```powershell
powershell -ExecutionPolicy Bypass -File .\implementation\powang\tests\preflight.ps1
```

Use `-RequireConstructionReady` only after the real Y3 project has been connected and all execution gates have been filled.

Run the pure Lua tests with a Lua 5.3+ runtime. The current workspace uses Fengari only for offline verification; the final Y3 target remains Lua 5.4.
