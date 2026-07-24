-- TianTing offline authority core. It is intentionally engine-neutral and has no Y3 bindings.
local M = {}
local Runtime = {}
Runtime.__index = Runtime

local ENTRY_PROGRESS = 'TT_SPEC_PROGRESS_CHAPTER_ENTERED'
local OBSERVATORY_PROGRESS = 'TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN'
local MAINLINE_PROGRESS = 'TT_SPEC_PROGRESS_MAINLINE_CLEARED'

local ENTRY_PRODUCER = 'TT_SPEC_EVENT_SOUTH_GATE_TRANSITION_SUCCESS'
local OBSERVATORY_PRODUCER = 'TT_SPEC_MAINLINE_NODE_04_CELESTIAL_OBSERVATORY'
local MAINLINE_PRODUCER = 'TT_SPEC_MAINLINE_NODE_05_LINGXIAO_OUTER_COURT'

local function present(value)
    return value ~= nil and value ~= ''
end

local function copy_table(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == 'table' then
            result[key] = copy_table(value)
        else
            result[key] = value
        end
    end
    return result
end

local function receipt_key(actor_id, event_id)
    return actor_id .. '\0' .. event_id
end

local function actor_progress(runtime, actor_id)
    local progress = runtime.progress_by_actor[actor_id]
    if not progress then
        progress = {}
        runtime.progress_by_actor[actor_id] = progress
    end
    return progress
end

local function receipt_shape_is_valid(fact)
    if type(fact) ~= 'table' then return false end
    for _, field in ipairs({
        'actor_id',
        'actor_lifecycle_id',
        'event_id',
        'producer_spec_id',
        'session_instance_id',
        'session_epoch',
        'completed_tick',
        'authority_proof_ref',
        'schema_version',
    }) do
        if not present(fact[field]) and fact[field] ~= 0 then return false end
    end
    return true
end

local function session_shape_is_valid(snapshot)
    if type(snapshot) ~= 'table' or type(snapshot.members) ~= 'table' then return false end
    for _, field in ipairs({
        'session_instance_id',
        'session_epoch',
        'revision',
        'cleanup_token',
        'membership_snapshot_id',
    }) do
        if not present(snapshot[field]) and snapshot[field] ~= 0 then return false end
    end
    return #snapshot.members >= 1 and #snapshot.members <= 4
end

local function public_session(session)
    if not session then return nil end
    return copy_table(session)
end

function M.new(options)
    options = options or {}
    if type(options.authority_provider) ~= 'table' then
        error('authority_provider table is required')
    end
    return setmetatable({
        authority = options.authority_provider,
        progress_by_actor = {},
        receipts_by_actor_event = {},
        lingxiao_sessions = {},
        reentry_locks = {},
    }, Runtime)
end

function Runtime:_current_actor(actor_id)
    if type(self.authority.resolve_current_actor) ~= 'function' then return nil end
    local actor = self.authority:resolve_current_actor(actor_id)
    if type(actor) ~= 'table' or actor.actor_id ~= actor_id then return nil end
    if not present(actor.actor_lifecycle_id) or type(actor.level) ~= 'number' then return nil end
    return copy_table(actor)
end

function Runtime:_has_progress(actor_id, progress_spec_id, actor_lifecycle_id)
    local progress = self.progress_by_actor[actor_id]
    local receipt = progress and progress[progress_spec_id]
    return receipt ~= nil
        and (actor_lifecycle_id == nil or receipt.actor_lifecycle_id == actor_lifecycle_id)
end

local function same_progress_receipt(existing, fact, progress_spec_id, expected_producer)
    if existing.progress_spec_id ~= progress_spec_id or existing.producer_spec_id ~= expected_producer then
        return false
    end
    for _, field in ipairs({
        'actor_id',
        'actor_lifecycle_id',
        'event_id',
        'session_instance_id',
        'session_epoch',
        'completed_tick',
        'authority_proof_ref',
        'schema_version',
    }) do
        if existing[field] ~= fact[field] then return false end
    end
    return true
end

function Runtime:_write_progress(progress_spec_id, fact, expected_producer)
    if not receipt_shape_is_valid(fact) then return false, 'invalid-authoritative-receipt' end
    if fact.producer_spec_id ~= expected_producer then return false, 'unexpected-progress-producer' end

    local key = receipt_key(fact.actor_id, fact.event_id)
    local existing = self.receipts_by_actor_event[key]
    if existing then
        if same_progress_receipt(existing, fact, progress_spec_id, expected_producer) then
            return true, { receipt = copy_table(existing), replayed = true }
        end
        return false, 'event-id-conflict'
    end

    if progress_spec_id == OBSERVATORY_PROGRESS then
        if not self:_has_progress(fact.actor_id, ENTRY_PROGRESS) then
            return false, 'chapter-entry-required'
        end
        if not self:_has_progress(fact.actor_id, ENTRY_PROGRESS, fact.actor_lifecycle_id) then
            return false, 'chapter-entry-current-lifecycle-required'
        end
    end
    if progress_spec_id == MAINLINE_PROGRESS then
        if not self:_has_progress(fact.actor_id, ENTRY_PROGRESS)
            or not self:_has_progress(fact.actor_id, OBSERVATORY_PROGRESS) then
            return false, 'mainline-prerequisites-required'
        end
        if not self:_has_progress(fact.actor_id, ENTRY_PROGRESS, fact.actor_lifecycle_id)
            or not self:_has_progress(fact.actor_id, OBSERVATORY_PROGRESS, fact.actor_lifecycle_id) then
            return false, 'mainline-current-lifecycle-prerequisites-required'
        end
    end

    local receipt = {
        actor_id = fact.actor_id,
        actor_lifecycle_id = fact.actor_lifecycle_id,
        event_id = fact.event_id,
        producer_spec_id = expected_producer,
        session_instance_id = fact.session_instance_id,
        session_epoch = fact.session_epoch,
        completed_tick = fact.completed_tick,
        authority_proof_ref = fact.authority_proof_ref,
        schema_version = fact.schema_version,
        progress_spec_id = progress_spec_id,
    }
    self.receipts_by_actor_event[key] = receipt
    actor_progress(self, fact.actor_id)[progress_spec_id] = receipt
    return true, { receipt = copy_table(receipt), replayed = false }
end

function Runtime:enter_chapter(request)
    if type(request) ~= 'table'
        or not present(request.actor_id)
        or not present(request.entry_event_ref)
        or not present(request.handoff_ref) then
        return false, 'invalid-entry-request'
    end
    local actor = self:_current_actor(request.actor_id)
    if not actor then return false, 'authority-actor-required' end
    if actor.level < 41 then return false, 'authority-level-below-41' end
    if type(self.authority.resolve_yanluo_handoff) ~= 'function' then
        return false, 'authority-handoff-resolver-required'
    end
    local handoff = self.authority:resolve_yanluo_handoff(request.handoff_ref)
    if type(handoff) ~= 'table' then return false, 'missing-or-untrusted-yanluo-handoff-proof' end
    if handoff.actor_id ~= actor.actor_id then return false, 'proof-actor-id-differs-from-request-actor-id' end
    if handoff.source_encounter_key ~= 'DF_E_YANLUO_HALL' or handoff.source_success ~= true then
        return false, 'proof-source-is-not-yanluo-authoritative-success'
    end
    if type(self.authority.resolve_entry_success) ~= 'function' then
        return false, 'authority-entry-resolver-required'
    end
    local fact = self.authority:resolve_entry_success(request.entry_event_ref)
    if type(fact) ~= 'table' or fact.actor_id ~= actor.actor_id then
        return false, 'authority-entry-fact-mismatch'
    end
    if fact.actor_lifecycle_id ~= actor.actor_lifecycle_id then return false, 'stale-actor-lifecycle' end
    return self:_write_progress(ENTRY_PROGRESS, fact, ENTRY_PRODUCER)
end

function Runtime:open_celestial_observatory(request)
    if type(request) ~= 'table' or not present(request.actor_id) or not present(request.observatory_event_ref) then
        return false, 'invalid-observatory-request'
    end
    local actor = self:_current_actor(request.actor_id)
    if not actor then return false, 'authority-actor-required' end
    if type(self.authority.resolve_observatory_success) ~= 'function' then
        return false, 'authority-observatory-resolver-required'
    end
    local fact = self.authority:resolve_observatory_success(request.observatory_event_ref)
    if type(fact) ~= 'table' or fact.actor_id ~= actor.actor_id then
        return false, 'authority-observatory-fact-mismatch'
    end
    if fact.actor_lifecycle_id ~= actor.actor_lifecycle_id then return false, 'stale-actor-lifecycle' end
    return self:_write_progress(OBSERVATORY_PROGRESS, fact, OBSERVATORY_PRODUCER)
end

function Runtime:start_lingxiao_session(request)
    if type(request) ~= 'table' or not present(request.admission_ref) then
        return false, 'invalid-lingxiao-admission-request'
    end
    if type(self.authority.resolve_lingxiao_admission) ~= 'function' then
        return false, 'authority-admission-resolver-required'
    end
    local snapshot = self.authority:resolve_lingxiao_admission(request.admission_ref)
    if not session_shape_is_valid(snapshot) then return false, 'invalid-authoritative-membership-snapshot' end
    if snapshot.session_spec_id ~= 'TT_SPEC_SESSION_LINGXIAO_MAINLINE' then
        return false, 'invalid-session-spec'
    end
    if self.lingxiao_sessions[snapshot.session_instance_id] then return false, 'session-instance-already-known' end

    local members = {}
    for _, member in ipairs(snapshot.members) do
        if type(member) ~= 'table'
            or not present(member.actor_id)
            or not present(member.actor_lifecycle_id)
            or member.member_status ~= 'active'
            or members[member.actor_id] then
            return false, 'invalid-authoritative-member'
        end
        local actor = self:_current_actor(member.actor_id)
        if not actor or actor.actor_lifecycle_id ~= member.actor_lifecycle_id then
            return false, 'stale-member-lifecycle'
        end
        if not self:_has_progress(member.actor_id, ENTRY_PROGRESS) then
            return false, 'member-chapter-entry-required'
        end
        if not self:_has_progress(member.actor_id, ENTRY_PROGRESS, member.actor_lifecycle_id) then
            return false, 'member-chapter-entry-current-lifecycle-required'
        end
        if self.reentry_locks[member.actor_id] then return false, 'actor-reentry-locked' end
        members[member.actor_id] = {
            actor_id = member.actor_id,
            actor_lifecycle_id = member.actor_lifecycle_id,
            member_status = 'active',
            membership_snapshot_id = snapshot.membership_snapshot_id,
        }
    end

    local session = {
        session_spec_id = snapshot.session_spec_id,
        session_instance_id = snapshot.session_instance_id,
        session_epoch = snapshot.session_epoch,
        revision = snapshot.revision,
        cleanup_token = snapshot.cleanup_token,
        membership_snapshot_id = snapshot.membership_snapshot_id,
        state = 'active',
        members = members,
    }
    self.lingxiao_sessions[session.session_instance_id] = session
    for actor_id in pairs(members) do self.reentry_locks[actor_id] = session.session_instance_id end
    return true, public_session(session)
end

function Runtime:get_lingxiao_session(session_instance_id)
    return public_session(self.lingxiao_sessions[session_instance_id])
end

function Runtime:complete_lingxiao_member(request)
    if type(request) ~= 'table' or not present(request.completion_ref) then
        return false, 'invalid-lingxiao-completion-request'
    end
    if type(self.authority.resolve_lingxiao_completion) ~= 'function' then
        return false, 'authority-completion-resolver-required'
    end
    local fact = self.authority:resolve_lingxiao_completion(request.completion_ref)
    if type(fact) ~= 'table' then return false, 'invalid-authoritative-completion-fact' end
    local session = self.lingxiao_sessions[fact.session_instance_id]
    if not session then return false, 'session-not-found' end
    if session.state ~= 'active' then return false, 'session-not-active' end
    if fact.session_epoch ~= session.session_epoch or fact.revision ~= session.revision then
        return false, 'session-identity-mismatch'
    end
    local member = session.members[fact.actor_id]
    if not member then return false, 'member-not-frozen' end
    if member.member_status ~= 'active' or fact.member_status ~= 'active' or fact.effective_participation ~= true then
        return false, 'member-not-completion-eligible'
    end
    if fact.actor_lifecycle_id ~= member.actor_lifecycle_id then return false, 'stale-member-lifecycle' end
    local actor = self:_current_actor(fact.actor_id)
    if not actor or actor.actor_lifecycle_id ~= member.actor_lifecycle_id then
        return false, 'stale-member-lifecycle'
    end
    return self:_write_progress(MAINLINE_PROGRESS, fact, MAINLINE_PRODUCER)
end

function Runtime:begin_lingxiao_cleanup(request)
    if type(request) ~= 'table' or not present(request.cleanup_transition_ref) then
        return false, 'invalid-cleanup-transition-request'
    end
    if type(self.authority.resolve_lingxiao_cleanup_transition) ~= 'function' then
        return false, 'authority-cleanup-transition-resolver-required'
    end
    local transition = self.authority:resolve_lingxiao_cleanup_transition(request.cleanup_transition_ref)
    if type(transition) ~= 'table' then return false, 'invalid-authoritative-cleanup-transition' end
    local session = self.lingxiao_sessions[transition.session_instance_id]
    if not session then return false, 'session-not-found' end
    if session.state ~= 'active' then return false, 'session-not-active' end
    if transition.session_epoch ~= session.session_epoch
        or transition.revision ~= session.revision
        or transition.cleanup_token ~= session.cleanup_token then
        return false, 'cleanup-identity-mismatch'
    end
    local allowed_reasons = {
        completed = true,
        member_death = true,
        member_disconnect = true,
        timeout = true,
        lifecycle_invalid = true,
        full_wipe = true,
    }
    if allowed_reasons[transition.reason] ~= true then return false, 'invalid-cleanup-reason' end
    if transition.affected_actor_id then
        local member = session.members[transition.affected_actor_id]
        if not member or member.actor_lifecycle_id ~= transition.affected_actor_lifecycle_id then
            return false, 'cleanup-member-mismatch'
        end
        if transition.reason == 'member_disconnect' or transition.reason == 'lifecycle_invalid' then
            member.member_status = 'left'
        elseif transition.reason == 'member_death' then
            member.member_status = 'dead'
        end
    end
    session.state = 'cleanup_pending'
    return true, public_session(session)
end

function Runtime:ack_lingxiao_cleanup(request)
    if type(request) ~= 'table' or not present(request.cleanup_ack_ref) then
        return false, 'invalid-cleanup-ack-request'
    end
    if type(self.authority.resolve_lingxiao_cleanup_ack) ~= 'function' then
        return false, 'authority-cleanup-ack-resolver-required'
    end
    local acknowledgement = self.authority:resolve_lingxiao_cleanup_ack(request.cleanup_ack_ref)
    if type(acknowledgement) ~= 'table' then return false, 'invalid-authoritative-cleanup-ack' end
    local session = self.lingxiao_sessions[acknowledgement.session_instance_id]
    if not session then return false, 'session-not-found' end
    if session.state ~= 'cleanup_pending' then return false, 'session-not-cleanup-pending' end
    if acknowledgement.session_epoch ~= session.session_epoch
        or acknowledgement.revision ~= session.revision
        or acknowledgement.cleanup_token ~= session.cleanup_token then
        return false, 'cleanup-identity-mismatch'
    end
    session.state = 'closed'
    for actor_id in pairs(session.members) do
        if self.reentry_locks[actor_id] == session.session_instance_id then self.reentry_locks[actor_id] = nil end
    end
    return true, public_session(session)
end

function Runtime:get_progress_receipt(actor_id, progress_spec_id)
    local progress = self.progress_by_actor[actor_id]
    if not progress then return nil end
    return copy_table(progress[progress_spec_id])
end

return M
