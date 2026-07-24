'use strict';

const TIME_SLOT_TO_QUADRANT = Object.freeze({
  子: '东方青龙',
  辰: '东方青龙',
  申: '东方青龙',
  丑: '南方朱雀',
  巳: '南方朱雀',
  酉: '南方朱雀',
  寅: '西方白虎',
  午: '西方白虎',
  戌: '西方白虎',
  卯: '北方玄武',
  未: '北方玄武',
  亥: '北方玄武'
});

const QUADRANTS = Object.freeze([...new Set(Object.values(TIME_SLOT_TO_QUADRANT))]);
const DIFFICULTIES = Object.freeze(['normal', 'nightmare']);
const SESSION_STATES = Object.freeze(['active', 'cleanup_pending', 'closed']);

function fail(message) {
  throw new Error(`mansion-session-reference: ${message}`);
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function requirePlainObject(value, label) {
  if (!isPlainObject(value)) {
    fail(`${label} must be a plain object`);
  }
}

function requireString(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    fail(`${label} must be a non-empty string`);
  }
}

function requirePositiveInteger(value, label) {
  if (!Number.isInteger(value) || value <= 0) {
    fail(`${label} must be a positive integer`);
  }
}

function requireExactKeys(value, keys, label) {
  requirePlainObject(value, label);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    fail(`${label} has unsupported or missing fields`);
  }
}

function canonicalize(value) {
  if (Array.isArray(value)) {
    return value.map(canonicalize);
  }
  if (isPlainObject(value)) {
    return Object.keys(value).sort().reduce((result, key) => {
      result[key] = canonicalize(value[key]);
      return result;
    }, {});
  }
  return value;
}

function fingerprint(value) {
  return JSON.stringify(canonicalize(value));
}

function assertQuadrant(value, label) {
  requireString(value, label);
  if (!QUADRANTS.includes(value)) {
    fail(`${label} is not a supported quadrant`);
  }
}

function validateAuthorityTimeInput(input) {
  requireExactKeys(input, [
    'rotation_snapshot_id',
    'schedule_version',
    'authoritative_time_slot',
    'authority_time_basis_id',
    'captured_authoritative_instant',
    'schema_version',
    'timezone'
  ], 'authority_time_input');
  requireString(input.rotation_snapshot_id, 'authority_time_input.rotation_snapshot_id');
  requireString(input.schedule_version, 'authority_time_input.schedule_version');
  requireString(input.authoritative_time_slot, 'authority_time_input.authoritative_time_slot');
  requireString(input.authority_time_basis_id, 'authority_time_input.authority_time_basis_id');
  requireString(input.captured_authoritative_instant, 'authority_time_input.captured_authoritative_instant');
  requirePositiveInteger(input.schema_version, 'authority_time_input.schema_version');
  if (input.timezone !== 'Asia/Shanghai') {
    fail('authority_time_input.timezone must be Asia/Shanghai');
  }
  if (!Object.prototype.hasOwnProperty.call(TIME_SLOT_TO_QUADRANT, input.authoritative_time_slot)) {
    fail('authority_time_input.authoritative_time_slot is not a supported natural shichen');
  }
}

function freezeRotationSnapshot(input, difficulty, instanceScope) {
  validateAuthorityTimeInput(input);
  requireString(instanceScope, 'instance_scope');
  if (!DIFFICULTIES.includes(difficulty)) {
    fail('difficulty must be normal or nightmare');
  }
  return Object.freeze({
    rotation_snapshot_id: input.rotation_snapshot_id,
    schedule_version: input.schedule_version,
    authoritative_time_slot: input.authoritative_time_slot,
    quadrant: TIME_SLOT_TO_QUADRANT[input.authoritative_time_slot],
    difficulty,
    instance_scope: instanceScope,
    authority_time_basis_id: input.authority_time_basis_id,
    captured_authoritative_instant: input.captured_authoritative_instant,
    schema_version: input.schema_version
  });
}

function validateMainlineClear(proof, member) {
  requireExactKeys(proof, [
    'spec_id',
    'subject_actor_id',
    'subject_actor_lifecycle_id',
    'authority_proof_ref',
    'schema_version'
  ], 'mainline_clear');
  if (proof.spec_id !== 'TT_SPEC_PROGRESS_MAINLINE_CLEARED') {
    fail('mainline_clear.spec_id must be TT_SPEC_PROGRESS_MAINLINE_CLEARED');
  }
  requireString(proof.subject_actor_id, 'mainline_clear.subject_actor_id');
  requirePositiveInteger(proof.subject_actor_lifecycle_id, 'mainline_clear.subject_actor_lifecycle_id');
  requireString(proof.authority_proof_ref, 'mainline_clear.authority_proof_ref');
  requirePositiveInteger(proof.schema_version, 'mainline_clear.schema_version');
  if (proof.subject_actor_id !== member.actor_id || proof.subject_actor_lifecycle_id !== member.actor_lifecycle_id) {
    fail('mainline_clear must belong to the frozen actor and current lifecycle');
  }
}

function validateNightmareQualification(qualification, member, snapshot) {
  requireExactKeys(qualification, [
    'credential_subject_actor_id',
    'credential_subject_lifecycle_id',
    'normal_clear_rotation_snapshot_id',
    'normal_clear_quadrant',
    'credential_quadrant',
    'opaque_credential_ref',
    'authority_proof_ref',
    'schema_version'
  ], 'nightmare_qualification');
  requireString(qualification.credential_subject_actor_id, 'nightmare_qualification.credential_subject_actor_id');
  requirePositiveInteger(qualification.credential_subject_lifecycle_id, 'nightmare_qualification.credential_subject_lifecycle_id');
  requireString(qualification.normal_clear_rotation_snapshot_id, 'nightmare_qualification.normal_clear_rotation_snapshot_id');
  assertQuadrant(qualification.normal_clear_quadrant, 'nightmare_qualification.normal_clear_quadrant');
  assertQuadrant(qualification.credential_quadrant, 'nightmare_qualification.credential_quadrant');
  requireString(qualification.opaque_credential_ref, 'nightmare_qualification.opaque_credential_ref');
  requireString(qualification.authority_proof_ref, 'nightmare_qualification.authority_proof_ref');
  requirePositiveInteger(qualification.schema_version, 'nightmare_qualification.schema_version');
  if (qualification.credential_subject_actor_id !== member.actor_id || qualification.credential_subject_lifecycle_id !== member.actor_lifecycle_id) {
    fail('nightmare qualification must belong to the frozen actor and current lifecycle');
  }
  if (qualification.normal_clear_quadrant !== qualification.credential_quadrant || qualification.credential_quadrant !== snapshot.quadrant) {
    fail('nightmare qualification must satisfy normal_clear.quadrant == credential.quadrant == frozen_snapshot.quadrant');
  }
}

function validateMember(member, difficulty, snapshot) {
  const requiredKeys = [
    'actor_id',
    'actor_lifecycle_id',
    'membership_snapshot_id',
    'member_status',
    'mainline_clear'
  ];
  if (difficulty === 'nightmare') {
    requiredKeys.push('nightmare_qualification');
  }
  requireExactKeys(member, requiredKeys, 'member');
  requireString(member.actor_id, 'member.actor_id');
  requirePositiveInteger(member.actor_lifecycle_id, 'member.actor_lifecycle_id');
  requireString(member.membership_snapshot_id, 'member.membership_snapshot_id');
  if (member.member_status !== 'active') {
    fail('only active authority members may enter a frozen roster');
  }
  validateMainlineClear(member.mainline_clear, member);
  if (difficulty === 'nightmare') {
    validateNightmareQualification(member.nightmare_qualification, member, snapshot);
  }
}

function freezeMembers(members, difficulty, snapshot) {
  if (!Array.isArray(members) || members.length < 1 || members.length > 4) {
    fail('frozen roster must contain one through four members');
  }
  const seenActors = new Set();
  const seenActorLifecycles = new Set();
  const frozen = members.map((member) => {
    validateMember(member, difficulty, snapshot);
    const actorLifecycle = `${member.actor_id}\u0000${member.actor_lifecycle_id}`;
    if (seenActors.has(member.actor_id) || seenActorLifecycles.has(actorLifecycle)) {
      fail('frozen roster cannot contain duplicate actors or actor lifecycles');
    }
    seenActors.add(member.actor_id);
    seenActorLifecycles.add(actorLifecycle);
    return {
      actor_id: member.actor_id,
      actor_lifecycle_id: member.actor_lifecycle_id,
      membership_snapshot_id: member.membership_snapshot_id,
      member_status: 'active'
    };
  });
  return frozen;
}

function validateCreationRequest(request) {
  requireExactKeys(request, [
    'creation_event_id',
    'raid_instance_id',
    'boss_instance_id',
    'session_epoch',
    'phase_id',
    'revision',
    'cleanup_token',
    'difficulty',
    'instance_scope',
    'authority_time_input',
    'members'
  ], 'raid creation request');
  requireString(request.creation_event_id, 'creation_event_id');
  requireString(request.raid_instance_id, 'raid_instance_id');
  requireString(request.boss_instance_id, 'boss_instance_id');
  requirePositiveInteger(request.session_epoch, 'session_epoch');
  requireString(request.phase_id, 'phase_id');
  requirePositiveInteger(request.revision, 'revision');
  requireString(request.cleanup_token, 'cleanup_token');
  if (!DIFFICULTIES.includes(request.difficulty)) {
    fail('difficulty must be normal or nightmare');
  }
  requireString(request.instance_scope, 'instance_scope');
  if (!Array.isArray(request.members)) {
    fail('members must be an array');
  }
}

function lookupMember(session, actorId, lifecycleId) {
  return session.members.find((member) => member.actor_id === actorId && member.actor_lifecycle_id === lifecycleId) || null;
}

function validateIdentityFields(input, label, includeCleanupToken) {
  const fields = ['raid_instance_id', 'session_epoch', 'revision'];
  if (includeCleanupToken) {
    fields.push('cleanup_token');
  }
  for (const field of fields) {
    if (!(field in input)) {
      fail(`${label}.${field} is required`);
    }
  }
  requireString(input.raid_instance_id, `${label}.raid_instance_id`);
  requirePositiveInteger(input.session_epoch, `${label}.session_epoch`);
  requirePositiveInteger(input.revision, `${label}.revision`);
  if (includeCleanupToken) {
    requireString(input.cleanup_token, `${label}.cleanup_token`);
  }
}

class MansionSessionReference {
  constructor() {
    this.sessions = new Map();
    this.creationReplays = new Map();
    this.eventReplays = new Map();
    this.memberLocks = new Map();
  }

  createRaid(request) {
    validateCreationRequest(request);
    const requestFingerprint = fingerprint(request);
    const replay = this.creationReplays.get(request.creation_event_id);
    if (replay) {
      if (replay.fingerprint !== requestFingerprint) {
        fail('creation replay payload drift is rejected');
      }
      return deepClone(replay.result);
    }
    if (this.sessions.has(request.raid_instance_id)) {
      fail('raid_instance_id already exists under a different creation event');
    }
    const snapshot = freezeRotationSnapshot(request.authority_time_input, request.difficulty, request.instance_scope);
    const members = freezeMembers(request.members, request.difficulty, snapshot);
    this._assertMembersUnlocked(members);
    const session = {
      identity: Object.freeze({
        raid_instance_id: request.raid_instance_id,
        boss_instance_id: request.boss_instance_id,
        session_epoch: request.session_epoch,
        phase_id: request.phase_id,
        revision: request.revision,
        cleanup_token: request.cleanup_token
      }),
      difficulty: request.difficulty,
      instance_scope: request.instance_scope,
      state: 'active',
      rotation_snapshot: snapshot,
      members,
      completion: null,
      cleanup_failure_observed: false,
      cleanup_closed_event_id: null
    };
    this.sessions.set(request.raid_instance_id, session);
    for (const member of members) {
      this.memberLocks.set(this._memberLockKey(member), request.raid_instance_id);
    }
    const creationResult = this.getSession({
      raid_instance_id: request.raid_instance_id,
      session_epoch: request.session_epoch,
      revision: request.revision
    });
    this.creationReplays.set(request.creation_event_id, {
      fingerprint: requestFingerprint,
      identity: {
        raid_instance_id: request.raid_instance_id,
        session_epoch: request.session_epoch,
        revision: request.revision
      },
      result: deepClone(creationResult)
    });
    return creationResult;
  }

  getSession(input) {
    requireExactKeys(input, ['raid_instance_id', 'session_epoch', 'revision'], 'session lookup');
    validateIdentityFields(input, 'session lookup', false);
    const session = this.sessions.get(input.raid_instance_id);
    if (!session) {
      fail('raid session does not exist');
    }
    if (session.identity.session_epoch !== input.session_epoch || session.identity.revision !== input.revision) {
      fail('session epoch or revision does not match the frozen session');
    }
    return this._view(session);
  }

  getFrozenSnapshotForRetry(input) {
    requireExactKeys(input, ['raid_instance_id', 'session_epoch', 'revision'], 'retry lookup');
    const session = this._getActiveOrPendingSession(input, 'retry lookup', false);
    return deepClone(session.rotation_snapshot);
  }

  markMemberLeft(input) {
    requireExactKeys(input, [
      'event_id',
      'raid_instance_id',
      'session_epoch',
      'revision',
      'actor_id',
      'actor_lifecycle_id'
    ], 'left-member request');
    requireString(input.event_id, 'left-member request.event_id');
    requireString(input.actor_id, 'left-member request.actor_id');
    requirePositiveInteger(input.actor_lifecycle_id, 'left-member request.actor_lifecycle_id');
    const replay = this._replayEventIfExact('left', input.event_id, input);
    if (replay) {
      return replay;
    }
    const session = this._getActiveOrPendingSession(input, 'left-member request', false);
    if (session.state !== 'active') {
      fail('only an active session may accept a left-member transition');
    }
    const member = lookupMember(session, input.actor_id, input.actor_lifecycle_id);
    if (!member) {
      fail('left-member request does not match a frozen current-lifecycle member');
    }
    if (member.member_status === 'left') {
      fail('left-member transition was already recorded with a different event');
    }
    member.member_status = 'left';
    return this._recordEventResult('left', input.event_id, input, session);
  }

  requestReconnect(input) {
    requireExactKeys(input, [
      'raid_instance_id',
      'session_epoch',
      'revision',
      'actor_id',
      'actor_lifecycle_id'
    ], 'reconnect request');
    requireString(input.actor_id, 'reconnect request.actor_id');
    requirePositiveInteger(input.actor_lifecycle_id, 'reconnect request.actor_lifecycle_id');
    const session = this._getActiveOrPendingSession(input, 'reconnect request', false);
    const member = lookupMember(session, input.actor_id, input.actor_lifecycle_id);
    if (!member) {
      fail('reconnect request does not match a frozen current-lifecycle member');
    }
    if (member.member_status === 'left') {
      fail('left members cannot reconnect to the current raid instance');
    }
    fail('the offline reference has no reconnect transition');
  }

  getContinuationStatus(input) {
    requireExactKeys(input, ['raid_instance_id', 'session_epoch', 'revision'], 'continuation lookup');
    const session = this._getActiveOrPendingSession(input, 'continuation lookup', false);
    const activeMembers = session.members.filter((member) => member.member_status === 'active');
    return {
      can_continue: session.state === 'active' && activeMembers.length > 0,
      active_member_actor_ids: activeMembers.map((member) => member.actor_id)
    };
  }

  getCurrentInstanceCompletionEligibility(input) {
    requireExactKeys(input, [
      'raid_instance_id',
      'session_epoch',
      'revision',
      'actor_id',
      'actor_lifecycle_id'
    ], 'completion eligibility lookup');
    requireString(input.actor_id, 'completion eligibility lookup.actor_id');
    requirePositiveInteger(input.actor_lifecycle_id, 'completion eligibility lookup.actor_lifecycle_id');
    const session = this._getActiveOrPendingSession(input, 'completion eligibility lookup', false);
    const member = lookupMember(session, input.actor_id, input.actor_lifecycle_id);
    if (!member) {
      return { eligible: false };
    }
    return { eligible: member.member_status === 'active' };
  }

  recordCompletion(input) {
    requireExactKeys(input, [
      'event_id',
      'raid_instance_id',
      'session_epoch',
      'revision',
      'participant_actor_lifecycle_pairs'
    ], 'completion request');
    requireString(input.event_id, 'completion request.event_id');
    if (!Array.isArray(input.participant_actor_lifecycle_pairs) || input.participant_actor_lifecycle_pairs.length < 1 || input.participant_actor_lifecycle_pairs.length > 4) {
      fail('completion request must contain one through four participants');
    }
    const replay = this._replayEventIfExact('completion', input.event_id, input);
    if (replay) {
      return replay;
    }
    const session = this._getActiveOrPendingSession(input, 'completion request', false);
    if (session.state !== 'active') {
      fail('only an active session may record completion');
    }
    const seen = new Set();
    const participants = input.participant_actor_lifecycle_pairs.map((pair) => {
      requireExactKeys(pair, ['actor_id', 'actor_lifecycle_id'], 'completion participant');
      requireString(pair.actor_id, 'completion participant.actor_id');
      requirePositiveInteger(pair.actor_lifecycle_id, 'completion participant.actor_lifecycle_id');
      const key = `${pair.actor_id}\u0000${pair.actor_lifecycle_id}`;
      if (seen.has(key)) {
        fail('completion participants cannot repeat an actor lifecycle');
      }
      seen.add(key);
      const member = lookupMember(session, pair.actor_id, pair.actor_lifecycle_id);
      if (!member || member.member_status !== 'active') {
        fail('completion participant must be an active frozen current-lifecycle member');
      }
      return { actor_id: pair.actor_id, actor_lifecycle_id: pair.actor_lifecycle_id };
    });
    session.completion = Object.freeze({
      event_id: input.event_id,
      participant_actor_lifecycle_pairs: participants,
      result: 'completed'
    });
    session.state = 'cleanup_pending';
    return this._recordEventResult('completion', input.event_id, input, session);
  }

  observeCleanupFailure(input) {
    requireExactKeys(input, [
      'event_id',
      'raid_instance_id',
      'session_epoch',
      'revision',
      'cleanup_token'
    ], 'cleanup-failure observation');
    requireString(input.event_id, 'cleanup-failure observation.event_id');
    const replay = this._replayEventIfExact('cleanup_failure', input.event_id, input);
    if (replay) {
      return replay;
    }
    const session = this._getActiveOrPendingSession(input, 'cleanup-failure observation', true);
    if (session.state !== 'cleanup_pending') {
      fail('cleanup-failure observation requires cleanup_pending state');
    }
    session.cleanup_failure_observed = true;
    return this._recordEventResult('cleanup_failure', input.event_id, input, session);
  }

  acknowledgeCleanup(input) {
    requireExactKeys(input, [
      'event_id',
      'raid_instance_id',
      'session_epoch',
      'revision',
      'cleanup_token'
    ], 'cleanup acknowledgement');
    requireString(input.event_id, 'cleanup acknowledgement.event_id');
    const replay = this._replayEventIfExact('cleanup_ack', input.event_id, input);
    if (replay) {
      return replay;
    }
    const session = this._getActiveOrPendingSession(input, 'cleanup acknowledgement', true);
    if (session.state !== 'cleanup_pending') {
      fail('cleanup acknowledgement requires cleanup_pending state');
    }
    session.state = 'closed';
    session.cleanup_closed_event_id = input.event_id;
    for (const member of session.members) {
      const key = this._memberLockKey(member);
      if (this.memberLocks.get(key) === session.identity.raid_instance_id) {
        this.memberLocks.delete(key);
      }
    }
    return this._recordEventResult('cleanup_ack', input.event_id, input, session);
  }

  _getActiveOrPendingSession(input, label, includeCleanupToken) {
    requirePlainObject(input, label);
    validateIdentityFields(input, label, includeCleanupToken);
    const session = this.sessions.get(input.raid_instance_id);
    if (!session) {
      fail(`${label} refers to an unknown raid instance`);
    }
    if (session.identity.session_epoch !== input.session_epoch || session.identity.revision !== input.revision) {
      fail(`${label} has a stale session_epoch or revision`);
    }
    if (includeCleanupToken && session.identity.cleanup_token !== input.cleanup_token) {
      fail(`${label} has a mismatched cleanup_token`);
    }
    if (session.state === 'closed') {
      fail(`${label} cannot operate on a closed session`);
    }
    return session;
  }

  _replayEventIfExact(kind, eventId, input) {
    const replay = this.eventReplays.get(eventId);
    if (!replay) {
      return null;
    }
    if (replay.kind !== kind || replay.fingerprint !== fingerprint(input)) {
      fail('event replay payload drift is rejected');
    }
    return deepClone(replay.result);
  }

  _recordEventResult(kind, eventId, input, session) {
    const result = this._view(session);
    this.eventReplays.set(eventId, {
      kind,
      fingerprint: fingerprint(input),
      result: deepClone(result)
    });
    return result;
  }

  _memberLockKey(member) {
    return `${member.actor_id}\u0000${member.actor_lifecycle_id}`;
  }

  _assertMembersUnlocked(members) {
    for (const member of members) {
      if (this.memberLocks.has(this._memberLockKey(member))) {
        fail('member reentry lock remains held until matching cleanup acknowledgement');
      }
    }
  }

  _view(session) {
    return deepClone({
      raid_instance_id: session.identity.raid_instance_id,
      boss_instance_id: session.identity.boss_instance_id,
      session_epoch: session.identity.session_epoch,
      phase_id: session.identity.phase_id,
      revision: session.identity.revision,
      cleanup_token: session.identity.cleanup_token,
      difficulty: session.difficulty,
      instance_scope: session.instance_scope,
      state: session.state,
      rotation_snapshot: session.rotation_snapshot,
      members: session.members,
      completion: session.completion,
      cleanup_failure_observed: session.cleanup_failure_observed,
      cleanup_closed_event_id: session.cleanup_closed_event_id
    });
  }
}

module.exports = {
  TIME_SLOT_TO_QUADRANT,
  QUADRANTS,
  DIFFICULTIES,
  SESSION_STATES,
  MansionSessionReference,
  freezeRotationSnapshot,
  validateAuthorityTimeInput
};
