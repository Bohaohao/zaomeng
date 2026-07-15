package.path = 'implementation/xunlie/lua/?.lua;' .. package.path

local Contribution = require 'xunlie_boss_contribution'

local tests = 0
local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual)) end
end
local function truthy(value, message)
    tests = tests + 1
    if not value then error(message or 'expected truthy value') end
end

local function event(overrides)
    local item = {
        kind = 'final_damage', event_id = 'C04_DMG:actor:1:1:direct:hit:main', actor_id = 'actor', lifecycle_id = 1,
        boss_instance_id = 'boss-1', phase_id = 'phase-1', target_id = 'unit-1', target_lifecycle_id = 'boss-life-1',
        skill_key = 'C04_A03', value = 10, combat_scope = 'public', session_instance_id = nil, session_epoch = nil,
    }
    for key, value in pairs(overrides or {}) do item[key] = value end
    return item
end

do
    local ledger = Contribution.new()
    truthy(ledger:accept(event()), 'valid public final damage is accepted')
    local duplicate, duplicate_error = ledger:accept(event())
    equal(duplicate, false, 'same phase event cannot score twice')
    equal(duplicate_error, 'duplicate-contribution-event', 'duplicate has an explicit rejection code')
end

do
    local ledger = Contribution.new()
    truthy(ledger:accept(event()), 'origin baseline is accepted')
    local accepted, error_code = ledger:accept(event({ phase_id = 'phase-2' }))
    equal(accepted, false, 'same event id cannot move to another phase')
    equal(error_code, 'contribution-origin-conflict', 'phase replay is rejected before accounting')
end

do
    local ledger = Contribution.new()
    local accepted, error_code = ledger:accept(event({ combat_scope = 'private_session', session_instance_id = 'session', session_epoch = 1 }))
    equal(accepted, false, 'private session never writes public Boss contribution')
    equal(error_code, 'private-or-invalid-contribution-scope', 'private session rejection is explicit')
end

do
    local ledger = Contribution.new()
    local accepted, error_code = ledger:accept(event({ value = 0 }))
    equal(accepted, false, 'zero damage is never a contribution')
    equal(error_code, 'invalid-contribution-value', 'zero damage retains its reason')
    accepted, error_code = ledger:accept(event({ skill_key = 'C04_M01_HUNT' }))
    equal(accepted, false, 'marks cannot masquerade as final damage')
    equal(error_code, 'invalid-contribution-skill', 'mark key is rejected by the contribution allowlist')
end

print('PASS: ' .. tests .. ' boss contribution assertions')
