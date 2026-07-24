package.path = 'implementation/tianting-authority-vertical-slice/tests/?.lua;implementation/tianting-authority-vertical-slice/lua/?.lua;' .. package.path

local Core = require 'tianting_authority_core'
local FakeAuthority = require 'fake_authority_provider'

local tests = 0
local function equal(actual, expected, message)
    tests = tests + 1
    if actual ~= expected then
        error((message or 'values differ') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
    end
end

local function truthy(value, message)
    tests = tests + 1
    if not value then error(message or 'expected truthy value') end
end

local function event(actor_id, lifecycle_id, event_id, producer_spec_id, session_instance_id, session_epoch, tick)
    return {
        actor_id = actor_id,
        actor_lifecycle_id = lifecycle_id,
        event_id = event_id,
        producer_spec_id = producer_spec_id,
        session_instance_id = session_instance_id,
        session_epoch = session_epoch,
        completed_tick = tick,
        authority_proof_ref = 'proof:' .. event_id,
        schema_version = 1,
    }
end

local authority = FakeAuthority.new({
    actors = {
        a = { actor_id = 'a', actor_lifecycle_id = 'life-a-1', level = 41 },
        b = { actor_id = 'b', actor_lifecycle_id = 'life-b-1', level = 41 },
        low = { actor_id = 'low', actor_lifecycle_id = 'life-low-1', level = 40 },
        c = { actor_id = 'c', actor_lifecycle_id = 'life-c-1', level = 41 },
        leader = { actor_id = 'leader', actor_lifecycle_id = 'life-leader-1', level = 60 },
        stale = { actor_id = 'stale', actor_lifecycle_id = 'life-stale-1', level = 41 },
    },
    handoffs = {
        ['handoff-a'] = { actor_id = 'a', source_encounter_key = 'DF_E_YANLUO_HALL', source_success = true },
        ['handoff-b'] = { actor_id = 'b', source_encounter_key = 'DF_E_YANLUO_HALL', source_success = true },
        ['handoff-low'] = { actor_id = 'low', source_encounter_key = 'DF_E_YANLUO_HALL', source_success = true },
        ['handoff-stale'] = { actor_id = 'stale', source_encounter_key = 'DF_E_YANLUO_HALL', source_success = true },
        ['handoff-forged'] = { actor_id = 'c', source_encounter_key = 'OTHER_EVENT', source_success = true },
    },
    entry_events = {
        ['entry-a'] = event('a', 'life-a-1', 'event-entry-a', 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS', 'south-a', 'epoch-entry-a', 1),
        ['entry-b'] = event('b', 'life-b-1', 'event-entry-b', 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS', 'south-b', 'epoch-entry-b', 1),
        ['entry-low'] = event('low', 'life-low-1', 'event-entry-low', 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS', 'south-low', 'epoch-entry-low', 1),
        ['entry-c-forged'] = event('c', 'life-c-1', 'event-entry-c', 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS', 'south-c', 'epoch-entry-c', 1),
        ['entry-stale'] = event('stale', 'life-stale-1', 'event-entry-stale', 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS', 'south-stale', 'epoch-entry-stale', 1),
        ['entry-a-session-drift'] = event('a', 'life-a-1', 'event-entry-a', 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS', 'south-a-drift', 'epoch-entry-a', 1),
        ['entry-a-epoch-drift'] = event('a', 'life-a-1', 'event-entry-a', 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS', 'south-a', 'epoch-entry-a-drift', 1),
        ['entry-a-tick-drift'] = event('a', 'life-a-1', 'event-entry-a', 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS', 'south-a', 'epoch-entry-a', 99),
        ['entry-a-proof-drift'] = (function()
            local fact = event('a', 'life-a-1', 'event-entry-a', 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS', 'south-a', 'epoch-entry-a', 1)
            fact.authority_proof_ref = 'proof:entry-a-drift'
            return fact
        end)(),
        ['entry-a-schema-drift'] = (function()
            local fact = event('a', 'life-a-1', 'event-entry-a', 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS', 'south-a', 'epoch-entry-a', 1)
            fact.schema_version = 2
            return fact
        end)(),
    },
    observatory_events = {
        ['obs-a'] = event('a', 'life-a-1', 'event-obs-a', 'TT_SPEC_MAINLINE_NODE_04_CELESTIAL_OBSERVATORY', 'observatory-a', 'epoch-obs-a', 2),
        ['obs-b'] = event('b', 'life-b-1', 'event-obs-b', 'TT_SPEC_MAINLINE_NODE_04_CELESTIAL_OBSERVATORY', 'observatory-b', 'epoch-obs-b', 2),
        ['obs-c'] = event('c', 'life-c-1', 'event-obs-c', 'TT_SPEC_MAINLINE_NODE_04_CELESTIAL_OBSERVATORY', 'observatory-c', 'epoch-obs-c', 2),
        ['obs-stale-l2'] = event('stale', 'life-stale-2', 'event-obs-stale-l2', 'TT_SPEC_MAINLINE_NODE_04_CELESTIAL_OBSERVATORY', 'observatory-stale', 'epoch-obs-stale', 2),
    },
    admissions = {
        ['admission-bad'] = {
            session_spec_id = 'TT_SPEC_SESSION_LINGXIAO_MAINLINE', session_instance_id = 'lingxiao-bad', session_epoch = 'epoch-bad',
            revision = 1, cleanup_token = 'cleanup-bad', membership_snapshot_id = 'members-bad',
            members = {
                { actor_id = 'a', actor_lifecycle_id = 'life-a-1', member_status = 'active' },
                { actor_id = 'c', actor_lifecycle_id = 'life-c-1', member_status = 'active' },
            },
        },
        ['admission-good'] = {
            session_spec_id = 'TT_SPEC_SESSION_LINGXIAO_MAINLINE', session_instance_id = 'lingxiao-1', session_epoch = 'epoch-1',
            revision = 3, cleanup_token = 'cleanup-1', membership_snapshot_id = 'members-1',
            members = {
                { actor_id = 'a', actor_lifecycle_id = 'life-a-1', member_status = 'active' },
                { actor_id = 'b', actor_lifecycle_id = 'life-b-1', member_status = 'active' },
            },
        },
        ['admission-second'] = {
            session_spec_id = 'TT_SPEC_SESSION_LINGXIAO_MAINLINE', session_instance_id = 'lingxiao-2', session_epoch = 'epoch-2',
            revision = 1, cleanup_token = 'cleanup-2', membership_snapshot_id = 'members-2',
            members = {
                { actor_id = 'a', actor_lifecycle_id = 'life-a-1', member_status = 'active' },
                { actor_id = 'b', actor_lifecycle_id = 'life-b-1', member_status = 'active' },
            },
        },
        ['admission-third'] = {
            session_spec_id = 'TT_SPEC_SESSION_LINGXIAO_MAINLINE', session_instance_id = 'lingxiao-3', session_epoch = 'epoch-3',
            revision = 1, cleanup_token = 'cleanup-3', membership_snapshot_id = 'members-3',
            members = {
                { actor_id = 'a', actor_lifecycle_id = 'life-a-1', member_status = 'active' },
                { actor_id = 'b', actor_lifecycle_id = 'life-b-1', member_status = 'active' },
            },
        },
        ['admission-stale-l2'] = {
            session_spec_id = 'TT_SPEC_SESSION_LINGXIAO_MAINLINE', session_instance_id = 'lingxiao-stale', session_epoch = 'epoch-stale',
            revision = 1, cleanup_token = 'cleanup-stale', membership_snapshot_id = 'members-stale',
            members = {
                { actor_id = 'stale', actor_lifecycle_id = 'life-stale-2', member_status = 'active' },
            },
        },
    },
    completions = {
        ['completion-a'] = (function()
            local fact = event('a', 'life-a-1', 'event-mainline-a', 'TT_SPEC_MAINLINE_NODE_05_LINGXIAO_OUTER_COURT', 'lingxiao-1', 'epoch-1', 4)
            fact.revision = 3
            fact.member_status = 'active'
            fact.effective_participation = true
            return fact
        end)(),
        ['completion-proxy'] = (function()
            local fact = event('leader', 'life-leader-1', 'event-mainline-proxy', 'TT_SPEC_MAINLINE_NODE_05_LINGXIAO_OUTER_COURT', 'lingxiao-1', 'epoch-1', 4)
            fact.revision = 3
            fact.member_status = 'active'
            fact.effective_participation = true
            return fact
        end)(),
    },
    cleanup_transitions = {
        ['cleanup-wrong'] = { session_instance_id = 'lingxiao-1', session_epoch = 'epoch-1', revision = 3, cleanup_token = 'wrong-token', reason = 'completed' },
        ['cleanup-good'] = { session_instance_id = 'lingxiao-1', session_epoch = 'epoch-1', revision = 3, cleanup_token = 'cleanup-1', reason = 'completed' },
        ['cleanup-disconnect'] = {
            session_instance_id = 'lingxiao-2', session_epoch = 'epoch-2', revision = 1, cleanup_token = 'cleanup-2', reason = 'member_disconnect',
            affected_actor_id = 'b', affected_actor_lifecycle_id = 'life-b-1',
        },
    },
    cleanup_acks = {
        ['ack-wrong'] = { session_instance_id = 'lingxiao-1', session_epoch = 'epoch-1', revision = 3, cleanup_token = 'wrong-token' },
        ['ack-good'] = { session_instance_id = 'lingxiao-1', session_epoch = 'epoch-1', revision = 3, cleanup_token = 'cleanup-1' },
        ['ack-disconnect'] = { session_instance_id = 'lingxiao-2', session_epoch = 'epoch-2', revision = 1, cleanup_token = 'cleanup-2' },
    },
})

local runtime = Core.new({ authority_provider = authority })

local ok, error_code = runtime:enter_chapter({ actor_id = 'low', entry_event_ref = 'entry-low', handoff_ref = 'handoff-low' })
equal(ok, false, 'authority level below 41 is rejected')
equal(error_code, 'authority-level-below-41', 'level rejection is explicit')

ok, error_code = runtime:enter_chapter({ actor_id = 'c', entry_event_ref = 'entry-c-forged', handoff_ref = 'handoff-forged' })
equal(ok, false, 'forged non-Yanluo handoff is rejected')
equal(error_code, 'proof-source-is-not-yanluo-authoritative-success', 'handoff source rejection is explicit')

ok, error_code = runtime:open_celestial_observatory({ actor_id = 'c', observatory_event_ref = 'obs-c' })
equal(ok, false, 'observatory cannot open before chapter entry')
equal(error_code, 'chapter-entry-required', 'observatory prerequisite is explicit')

ok, error_code = runtime:enter_chapter({ actor_id = 'a', entry_event_ref = 'entry-a', handoff_ref = 'handoff-a' })
truthy(ok, 'authority entry succeeds for A')
equal(error_code.replayed, false, 'first entry is not a replay')
equal(error_code.receipt.progress_spec_id, 'TT_SPEC_PROGRESS_CHAPTER_ENTERED', 'entry writes only logical chapter progress')
equal(error_code.receipt.actor_id, 'a', 'entry receipt remains character-scoped')

ok, error_code = runtime:enter_chapter({ actor_id = 'a', entry_event_ref = 'entry-a', handoff_ref = 'handoff-a' })
truthy(ok, 'same actor and event replays entry')
equal(error_code.replayed, true, 'entry replay returns first result')

for _, reference in ipairs({
    'entry-a-session-drift',
    'entry-a-epoch-drift',
    'entry-a-tick-drift',
    'entry-a-proof-drift',
    'entry-a-schema-drift',
}) do
    ok, error_code = runtime:enter_chapter({ actor_id = 'a', entry_event_ref = reference, handoff_ref = 'handoff-a' })
    equal(ok, false, 'bound receipt-field drift is rejected: ' .. reference)
    equal(error_code, 'event-id-conflict', 'bound receipt-field drift has explicit rejection: ' .. reference)
end

ok, error_code = runtime:enter_chapter({ actor_id = 'stale', entry_event_ref = 'entry-stale', handoff_ref = 'handoff-stale' })
truthy(ok, 'entry succeeds before the stale actor lifecycle changes')
authority:set_actor('stale', { actor_id = 'stale', actor_lifecycle_id = 'life-stale-2', level = 41 })
ok, error_code = runtime:open_celestial_observatory({ actor_id = 'stale', observatory_event_ref = 'obs-stale-l2' })
equal(ok, false, 'entry receipt from an old lifecycle cannot open the observatory')
equal(error_code, 'chapter-entry-current-lifecycle-required', 'old-lifecycle entry prerequisite rejection is explicit')
ok, error_code = runtime:start_lingxiao_session({ admission_ref = 'admission-stale-l2' })
equal(ok, false, 'entry receipt from an old lifecycle cannot admit a mainline member')
equal(error_code, 'member-chapter-entry-current-lifecycle-required', 'old-lifecycle admission rejection is explicit')

authority:set_actor('a', { actor_id = 'a', actor_lifecycle_id = 'life-a-2', level = 41 })
ok, error_code = runtime:enter_chapter({ actor_id = 'a', entry_event_ref = 'entry-a', handoff_ref = 'handoff-a' })
equal(ok, false, 'old lifecycle cannot replay entry')
equal(error_code, 'stale-actor-lifecycle', 'old lifecycle rejection is explicit')
authority:set_actor('a', { actor_id = 'a', actor_lifecycle_id = 'life-a-1', level = 41 })

ok, error_code = runtime:enter_chapter({ actor_id = 'b', entry_event_ref = 'entry-b', handoff_ref = 'handoff-b' })
truthy(ok, 'authority entry succeeds for B')
ok, error_code = runtime:open_celestial_observatory({ actor_id = 'a', observatory_event_ref = 'obs-a' })
truthy(ok, 'observatory opens for A after entry')
equal(error_code.receipt.progress_spec_id, 'TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN', 'observatory writes its own logical record')
ok, error_code = runtime:open_celestial_observatory({ actor_id = 'b', observatory_event_ref = 'obs-b' })
truthy(ok, 'observatory opens for B after entry')

ok, error_code = runtime:start_lingxiao_session({ admission_ref = 'admission-bad' })
equal(ok, false, 'unentered frozen member rejects the entire mainline session')
equal(error_code, 'member-chapter-entry-required', 'per-member admission rejection is explicit')

ok, error_code = runtime:start_lingxiao_session({ admission_ref = 'admission-good', client_injected_member = 'leader' })
truthy(ok, 'authority snapshot starts mainline session')
equal(error_code.state, 'active', 'mainline session begins active')
equal(error_code.members.leader, nil, 'client-injected member cannot enter authority snapshot')
truthy(error_code.members.a and error_code.members.b, 'authority snapshot freezes both valid members')

ok, error_code = runtime:complete_lingxiao_member({ completion_ref = 'completion-proxy' })
equal(ok, false, 'leader outside frozen snapshot cannot proxy a completion')
equal(error_code, 'member-not-frozen', 'proxy rejection is explicit')

authority:set_actor('a', { actor_id = 'a', actor_lifecycle_id = 'life-a-2', level = 41 })
ok, error_code = runtime:complete_lingxiao_member({ completion_ref = 'completion-a' })
equal(ok, false, 'old lifecycle cannot receive mainline completion')
equal(error_code, 'stale-member-lifecycle', 'completion lifecycle rejection is explicit')
authority:set_actor('a', { actor_id = 'a', actor_lifecycle_id = 'life-a-1', level = 41 })

ok, error_code = runtime:complete_lingxiao_member({ completion_ref = 'completion-a' })
truthy(ok, 'active authority member receives mainline completion')
equal(error_code.replayed, false, 'first mainline completion is not replayed')
equal(error_code.receipt.progress_spec_id, 'TT_SPEC_PROGRESS_MAINLINE_CLEARED', 'mainline completion writes only the closure record')

ok, error_code = runtime:complete_lingxiao_member({ completion_ref = 'completion-a' })
truthy(ok, 'duplicate mainline event returns authoritative result')
equal(error_code.replayed, true, 'duplicate mainline event does not write twice')

ok, error_code = runtime:begin_lingxiao_cleanup({ cleanup_transition_ref = 'cleanup-wrong' })
equal(ok, false, 'wrong cleanup token cannot transition session')
equal(error_code, 'cleanup-identity-mismatch', 'cleanup transition keeps all identity fields')

ok, error_code = runtime:begin_lingxiao_cleanup({ cleanup_transition_ref = 'cleanup-good' })
truthy(ok, 'valid cleanup transition enters cleanup pending')
equal(error_code.state, 'cleanup_pending', 'only allowed cleanup intermediate state is used')
ok, error_code = runtime:complete_lingxiao_member({ completion_ref = 'completion-a' })
equal(ok, false, 'completion cannot write after cleanup begins')
equal(error_code, 'session-not-active', 'post-cleanup completion rejection is explicit')

ok, error_code = runtime:ack_lingxiao_cleanup({ cleanup_ack_ref = 'ack-wrong' })
equal(ok, false, 'wrong cleanup acknowledgement cannot release lock')
equal(error_code, 'cleanup-identity-mismatch', 'wrong acknowledgement is explicit')
truthy(runtime:get_progress_receipt('a', 'TT_SPEC_PROGRESS_MAINLINE_CLEARED'), 'cleanup failure cannot roll back completion receipt')

ok, error_code = runtime:start_lingxiao_session({ admission_ref = 'admission-second' })
equal(ok, false, 'members cannot reenter before cleanup acknowledgement')
equal(error_code, 'actor-reentry-locked', 'reentry lock is explicit')

ok, error_code = runtime:ack_lingxiao_cleanup({ cleanup_ack_ref = 'ack-good' })
truthy(ok, 'matching cleanup acknowledgement closes session')
equal(error_code.state, 'closed', 'cleanup acknowledgement reaches closed state')
ok, error_code = runtime:ack_lingxiao_cleanup({ cleanup_ack_ref = 'ack-good' })
equal(ok, false, 'closed session cannot release lock twice')
equal(error_code, 'session-not-cleanup-pending', 'duplicate cleanup acknowledgement is explicit')

ok, error_code = runtime:start_lingxiao_session({ admission_ref = 'admission-second' })
truthy(ok, 'members can start a distinct session after cleanup acknowledgement')
equal(error_code.session_instance_id, 'lingxiao-2', 'new instance remains distinct from closed one')
ok, error_code = runtime:begin_lingxiao_cleanup({ cleanup_transition_ref = 'cleanup-disconnect' })
truthy(ok, 'authority disconnect transition begins cleanup')
equal(error_code.members.b.member_status, 'left', 'disconnected member is marked left')
ok, error_code = runtime:start_lingxiao_session({ admission_ref = 'admission-third' })
equal(ok, false, 'left member cannot reconnect into a new session before matching cleanup acknowledgement')
equal(error_code, 'actor-reentry-locked', 'disconnect lock is explicit')
ok, error_code = runtime:ack_lingxiao_cleanup({ cleanup_ack_ref = 'ack-disconnect' })
truthy(ok, 'matching disconnect cleanup acknowledgement closes session')

print('PASS: ' .. tests .. ' TianTing authority-core assertions')
