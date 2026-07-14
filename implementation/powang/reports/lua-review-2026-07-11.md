# Powang Lua Review Report

## Task

- Scope: Powang hero growth, resource loop, eight active skills, eight passives, ultimate, twelve effects, adapter contract, runtime orchestration, and the provisional Y3 bridge.
- Route: `y3-lua-pipeline`.
- Runtime target: Y3 Lua 5.4.
- Offline parser/runtime: Fengari Lua 5.3.4.

## Files Reviewed

- `lua/powang_config.lua`
- `lua/powang_core.lua`
- `lua/powang_skills.lua`
- `lua/powang_effects.lua`
- `lua/powang_target_contract.lua`
- `lua/powang_adapter_contract.lua`
- `lua/powang_runtime.lua`
- `lua/powang_y3_adapter.lua`
- `lua/powang_y3_targeting.lua`
- `lua/powang_y3_control_ledger.lua`
- `lua/powang_y3_controller.lua`

## API Compliance

- Adapter-neutral core Y3 API calls: 0.
- Y3 bridge baseline: `y3-lualib main@fe2fb0e55a76f73490cdcbef8cbfe7a61d124d63`.
- Verified public modules: Unit, Ability, Buff, Timer, Trigger, Mover, Game, Point, Selector, Shape.
- Verified synchronized events: `单位-受到伤害后`、`单位-造成伤害后`、`单位-升级`、`单位-死亡`、`单位-施放技能`。
- `GameAPI` calls: 0.
- `GlobalAPI` calls: 0.
- `CAPI` calls: 0.
- Known bad API patterns: 0.
- The package now includes a provisional public-API adapter while keeping all production IDs and project target selectors injectable.

## Static And Offline Runtime Checks

- All eleven modules parse through Fengari; the target contract and control ledger execute without Y3 globals.
- `tests/test_powang.lua`: 159 assertions passed.
- `tests/test_bridge_targeting.lua`: 18 assertions passed.
- `tests/test_bridge_lifecycle.lua`: 18 assertions passed.
- `tests/run-all.ps1`: uses the local cached Fengari CLI first and falls back to `pnpm dlx` only when the cache is unavailable.
- `tests/preflight.ps1`: 18 abilities, 12 modifiers, and 31 total stable keys validated.
- `tests/test-materializer.ps1`: 31 synthetic create commands plus the required post-create attack-range edit generated in dependency order; unresolved production manifest refused.
- `tests/run-all.ps1`: passed.

## Coverage

- Hero breakpoints: Lv1, Lv20, Lv40, Lv60.
- Battle momentum generation, cap, decay, 79/80 Dongming boundary, spend commit, hit confirmation, and cleanup.
- Four generators, four spenders, eight passive mechanics, and all three ultimate tiers.
- Shared-highest Xianwang, source-bound Poxi, same-source shield refresh, source cleanup, and actor isolation.
- Adapter validation, explicit self/primary/selected/team targets, source cleanup, overlapping roots, actor registration teardown, level resync, sequential charges, deferred hit confirmation, guard damage events, movement-end passive refresh, default geometry targeting, normal-attack events, skill use, ultimate use, effect-store integration, derived Dongming synchronization, and transient clearing.

## Repaired Bridge Risks

- Modifier commands now require `target_scope`; self buffs cannot fall through to the selected enemy list.
- Root control is lease-counted by target ID, so an earlier expiry cannot clear another active root.
- Controller teardown removes the timer and every unit Trigger before an actor ID can be reused.

## Runtime Verification Status

- Offline deterministic logic: passed.
- Offline design-and-construction stage: accepted on `2026-07-11`.
- Y3 script-root loading: not run.
- Editor object binding: not run.
- Multiplayer synchronization: not run.
- Trace/log inspection: not run.

## Risks And Exceptions

- No valid `maps/EntryMap/script` or `global_script/map` exists in the current workspace.
- No `y3editor` or `y3runtime` MCP is available.
- Object IDs, resources, melee template, and distance scale remain unresolved. Cast enums are pinned to the current API baseline but have not been read back from a live map.
- Fengari validates portable Lua behavior but does not replace Y3 Lua 5.4 or engine testing.
- Per the project decision on `2026-07-11`, editor integration and in-game acceptance are deferred. Reopen these risks before assigning `verified` status.
