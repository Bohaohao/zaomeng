'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  TIME_SLOT_TO_QUADRANT,
  MansionSessionReference,
  validateAuthorityTimeInput
} = require('../reference/mansion-session-model');

const packageRoot = path.resolve(__dirname, '..');
const packageContract = JSON.parse(fs.readFileSync(path.join(packageRoot, 'package-contract.json'), 'utf8'));
const referenceContract = JSON.parse(fs.readFileSync(path.join(packageRoot, 'contract', 'mansion-session-time-qualification-reference-contract.json'), 'utf8'));
const authorityContract = JSON.parse(fs.readFileSync(path.resolve(packageRoot, '..', '..', 'docs', '物编', '天庭篇主线遭遇与通天塔规格包', 'authority', 'tianting-progression-and-instance-authority-contract.json'), 'utf8'));

let assertions = 0;
function check(condition, message) {
  assertions += 1;
  assert.ok(condition, message);
}
function equal(actual, expected, message) {
  assertions += 1;
  assert.strictEqual(actual, expected, message);
}
function deepEqual(actual, expected, message) {
  assertions += 1;
  assert.deepStrictEqual(actual, expected, message);
}
function throws(callback, matcher, message) {
  assertions += 1;
  assert.throws(callback, matcher, message);
}
function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function authorityTime(slot, snapshotId) {
  return {
    rotation_snapshot_id: snapshotId,
    schedule_version: 'fixture-schedule-v1',
    authoritative_time_slot: slot,
    authority_time_basis_id: 'fixture-authority-time-basis',
    captured_authoritative_instant: 'fixture-authoritative-instant',
    schema_version: 1,
    timezone: 'Asia/Shanghai'
  };
}

function mainlineClear(actorId, lifecycleId) {
  return {
    spec_id: 'TT_SPEC_PROGRESS_MAINLINE_CLEARED',
    subject_actor_id: actorId,
    subject_actor_lifecycle_id: lifecycleId,
    authority_proof_ref: `fixture-mainline-proof-${actorId}-${lifecycleId}`,
    schema_version: 1
  };
}

function nightmareQualification(actorId, lifecycleId, quadrant) {
  return {
    credential_subject_actor_id: actorId,
    credential_subject_lifecycle_id: lifecycleId,
    normal_clear_rotation_snapshot_id: `fixture-normal-clear-${actorId}-${lifecycleId}`,
    normal_clear_quadrant: quadrant,
    credential_quadrant: quadrant,
    opaque_credential_ref: `fixture-opaque-qualification-${actorId}-${lifecycleId}`,
    authority_proof_ref: `fixture-qualification-proof-${actorId}-${lifecycleId}`,
    schema_version: 1
  };
}

function member(actorId, lifecycleId, difficulty, quadrant) {
  const result = {
    actor_id: actorId,
    actor_lifecycle_id: lifecycleId,
    membership_snapshot_id: `fixture-member-${actorId}-${lifecycleId}`,
    member_status: 'active',
    mainline_clear: mainlineClear(actorId, lifecycleId)
  };
  if (difficulty === 'nightmare') {
    result.nightmare_qualification = nightmareQualification(actorId, lifecycleId, quadrant);
  }
  return result;
}

function raidRequest(options = {}) {
  const difficulty = options.difficulty || 'normal';
  const slot = options.slot || '子';
  const quadrant = TIME_SLOT_TO_QUADRANT[slot];
  const raidId = options.raidInstanceId || 'fixture-raid-a';
  return {
    creation_event_id: options.creationEventId || `fixture-create-${raidId}`,
    raid_instance_id: raidId,
    boss_instance_id: options.bossInstanceId || `fixture-boss-${raidId}`,
    session_epoch: options.sessionEpoch || 1,
    phase_id: options.phaseId || 'fixture-phase-1',
    revision: options.revision || 1,
    cleanup_token: options.cleanupToken || `fixture-cleanup-${raidId}`,
    difficulty,
    instance_scope: options.instanceScope || 'fixture-mansion-raid-scope',
    authority_time_input: options.authorityTimeInput || authorityTime(slot, `fixture-snapshot-${raidId}`),
    members: options.members || [
      member('actor-a', 1, difficulty, quadrant),
      member('actor-b', 2, difficulty, quadrant)
    ]
  };
}

function identity(view) {
  return {
    raid_instance_id: view.raid_instance_id,
    session_epoch: view.session_epoch,
    revision: view.revision
  };
}

equal(packageContract.package_status, 'offline-reference-only', 'package remains an offline reference');
equal(packageContract.production_gate, 'closed', 'production gate remains closed');
equal(packageContract.runtime_handoff, false, 'package cannot hand off to runtime');
equal(packageContract.boundaries.uses_real_clock_or_time_service, false, 'package does not use a real time source');
equal(packageContract.boundaries.creates_value_or_settlement_effects, false, 'package has no value or settlement surface');
equal(referenceContract.identity.runtime_key, null, 'reference identity has no runtime key');
equal(referenceContract.authority_time_input.timezone, 'Asia/Shanghai', 'time basis is frozen to Asia/Shanghai');
equal(Object.keys(referenceContract.authority_time_input.slot_to_quadrant).length, 12, 'all twelve natural shichen are mapped');
equal(new Set(Object.values(referenceContract.authority_time_input.slot_to_quadrant)).size, 4, 'natural shichen map to four quadrants');
check(referenceContract.deferred.actual_time_provider === null && referenceContract.deferred.actual_value_material_and_settlement_rules === null, 'real providers and value rules remain deferred');
equal(referenceContract.nightmare_fixture_to_authority_crosswalk.authority_semantic_source.spec_id, 'TT_SPEC_MANSION_NIGHTMARE_CREDENTIAL', 'upper nightmare credential contract is the semantic source');
equal(referenceContract.nightmare_fixture_to_authority_crosswalk.authority_semantic_source.semantic_ownership, 'unique', 'fixture cannot become a second nightmare credential schema');
equal(referenceContract.nightmare_fixture_to_authority_crosswalk.fixture_adapter_status, 'test_only_not_an_independent_schema', 'fixture field names are adapter-only');
check(referenceContract.nightmare_fixture_to_authority_crosswalk.authority_semantic_source.required_fields.includes('nightmare_access_credential'), 'crosswalk retains the upper opaque credential field');
check(referenceContract.nightmare_fixture_to_authority_crosswalk.field_crosswalk.credential_quadrant.includes('fixture-only'), 'fixture credential quadrant is explicitly non-authoritative');
deepEqual(referenceContract.nightmare_fixture_to_authority_crosswalk.authority_semantic_source.required_fields, authorityContract.nightmare_qualification_contract.required_fields, 'crosswalk exactly follows the upper nightmare credential required field list');
equal(referenceContract.nightmare_fixture_to_authority_crosswalk.authority_semantic_source.spec_id, authorityContract.nightmare_qualification_contract.spec_id, 'crosswalk cannot substitute another authority credential contract');

validateAuthorityTimeInput(authorityTime('子', 'fixture-snapshot-time-input'));
throws(() => validateAuthorityTimeInput({ ...authorityTime('子', 'fixture-snapshot-extra'), client_clock: 'client-value' }), /unsupported or missing fields/, 'client clock cannot enter authority time input');
throws(() => validateAuthorityTimeInput({ ...authorityTime('子', 'fixture-snapshot-quadrant'), timezone: 'UTC' }), /Asia\/Shanghai/, 'non-Shanghai authority input is rejected');
throws(() => validateAuthorityTimeInput({ ...authorityTime('子', 'fixture-snapshot-slot'), authoritative_time_slot: '未知' }), /natural shichen/, 'unknown shichen is rejected');

const normalModel = new MansionSessionReference();
const normalRequest = raidRequest({ raidInstanceId: 'fixture-normal-raid', creationEventId: 'fixture-create-normal' });
const normalCreated = normalModel.createRaid(normalRequest);
equal(normalCreated.state, 'active', 'new normal raid begins active');
equal(normalCreated.rotation_snapshot.quadrant, '东方青龙', '子时 freezes East Azure Dragon');
equal(normalCreated.rotation_snapshot.difficulty, 'normal', 'frozen snapshot carries normal difficulty');
equal(normalCreated.members.length, 2, 'normal roster freezes two authority members');
equal(normalCreated.members[0].member_status, 'active', 'frozen roster begins active');
deepEqual(normalModel.createRaid(clone(normalRequest)), normalCreated, 'exact creation replay returns the first result');
const firstCreationResult = clone(normalCreated);

normalCreated.members[0].member_status = 'left';
equal(normalModel.getSession(identity(normalCreated)).members[0].member_status, 'active', 'caller mutation cannot change the frozen roster');
deepEqual(normalModel.getFrozenSnapshotForRetry(identity(normalCreated)), normalCreated.rotation_snapshot, 'retry reads the existing frozen snapshot');
throws(() => normalModel.getFrozenSnapshotForRetry({ ...identity(normalCreated), authority_time_input: authorityTime('丑', 'forbidden-retry-snapshot') }), /unsupported or missing fields/, 'retry cannot submit a replacement time input');
throws(() => normalModel.createRaid({ ...clone(normalRequest), client_quadrant: '南方朱雀' }), /unsupported or missing fields/, 'client quadrant cannot enter creation');
const changedReplay = clone(normalRequest);
changedReplay.authority_time_input.authoritative_time_slot = '丑';
throws(() => normalModel.createRaid(changedReplay), /creation replay payload drift/, 'same creation event cannot recalculate a different quadrant');

const oneMemberModel = new MansionSessionReference();
const oneMemberRequest = raidRequest({
  raidInstanceId: 'fixture-one-member-raid',
  members: [member('actor-one', 7, 'normal', '东方青龙')]
});
equal(oneMemberModel.createRaid(oneMemberRequest).members.length, 1, 'one member is a valid frozen roster');

const fourMemberModel = new MansionSessionReference();
const fourMembers = [
  member('actor-1', 1, 'normal', '东方青龙'),
  member('actor-2', 2, 'normal', '东方青龙'),
  member('actor-3', 3, 'normal', '东方青龙'),
  member('actor-4', 4, 'normal', '东方青龙')
];
equal(fourMemberModel.createRaid(raidRequest({ raidInstanceId: 'fixture-four-member-raid', members: fourMembers })).members.length, 4, 'four members are a valid frozen roster');
const fiveMemberModel = new MansionSessionReference();
throws(() => fiveMemberModel.createRaid(raidRequest({
  raidInstanceId: 'fixture-five-member-raid',
  members: [...fourMembers, member('actor-5', 5, 'normal', '东方青龙')]
})), /one through four/, 'fifth frozen member is rejected');

const mainlineGateModel = new MansionSessionReference();
const missingMainline = raidRequest({ raidInstanceId: 'fixture-missing-mainline' });
missingMainline.members[1].mainline_clear.subject_actor_id = 'different-actor';
throws(() => mainlineGateModel.createRaid(missingMainline), /frozen actor and current lifecycle/, 'normal admission validates every member mainline proof');
const spectatorModel = new MansionSessionReference();
const spectatorRequest = raidRequest({ raidInstanceId: 'fixture-spectator' });
spectatorRequest.members[1].member_status = 'spectator';
throws(() => spectatorModel.createRaid(spectatorRequest), /only active authority members/, 'spectator cannot enter the frozen roster');

const nightmareModel = new MansionSessionReference();
const nightmareRequest = raidRequest({
  difficulty: 'nightmare',
  slot: '子',
  raidInstanceId: 'fixture-nightmare-raid',
  creationEventId: 'fixture-create-nightmare'
});
const nightmareCreated = nightmareModel.createRaid(nightmareRequest);
equal(nightmareCreated.difficulty, 'nightmare', 'nightmare roster is accepted with per-member qualifications');
equal(nightmareCreated.rotation_snapshot.quadrant, '东方青龙', 'nightmare quadrant is derived from the frozen slot');
const mismatchCredentialModel = new MansionSessionReference();
const mismatchCredential = raidRequest({ difficulty: 'nightmare', slot: '子', raidInstanceId: 'fixture-mismatch-credential' });
mismatchCredential.members[1].nightmare_qualification.credential_quadrant = '南方朱雀';
throws(() => mismatchCredentialModel.createRaid(mismatchCredential), /normal_clear\.quadrant/, 'credential quadrant must match the normal clear and frozen snapshot');
const mismatchNormalModel = new MansionSessionReference();
const mismatchNormal = raidRequest({ difficulty: 'nightmare', slot: '子', raidInstanceId: 'fixture-mismatch-normal' });
mismatchNormal.members[1].nightmare_qualification.normal_clear_quadrant = '南方朱雀';
throws(() => mismatchNormalModel.createRaid(mismatchNormal), /normal_clear\.quadrant/, 'normal clear quadrant must match the credential and frozen snapshot');
const mismatchedSubjectModel = new MansionSessionReference();
const mismatchedSubject = raidRequest({ difficulty: 'nightmare', slot: '子', raidInstanceId: 'fixture-mismatch-subject' });
mismatchedSubject.members[1].nightmare_qualification.credential_subject_actor_id = 'actor-a';
throws(() => mismatchedSubjectModel.createRaid(mismatchedSubject), /frozen actor and current lifecycle/, 'nightmare credential cannot be copied from another actor');
const nightmareMainlineModel = new MansionSessionReference();
const nightmareMainline = raidRequest({ difficulty: 'nightmare', slot: '子', raidInstanceId: 'fixture-nightmare-mainline' });
nightmareMainline.members[1].mainline_clear.subject_actor_lifecycle_id = 99;
throws(() => nightmareMainlineModel.createRaid(nightmareMainline), /frozen actor and current lifecycle/, 'nightmare also validates every member mainline proof');

const leftEvent = {
  event_id: 'fixture-left-b',
  ...identity(normalCreated),
  actor_id: 'actor-b',
  actor_lifecycle_id: 2
};
const afterLeft = normalModel.markMemberLeft(leftEvent);
equal(afterLeft.members[1].member_status, 'left', 'disconnect marks the frozen member left');
deepEqual(normalModel.markMemberLeft(clone(leftEvent)), afterLeft, 'left event replay is idempotent');
deepEqual(normalModel.getCurrentInstanceCompletionEligibility({ ...identity(normalCreated), actor_id: 'actor-b', actor_lifecycle_id: 2 }), { eligible: false }, 'left member has no current instance completion eligibility');
throws(() => normalModel.requestReconnect({ ...identity(normalCreated), actor_id: 'actor-b', actor_lifecycle_id: 2 }), /cannot reconnect/, 'left member cannot reconnect to the current raid');
const continuation = normalModel.getContinuationStatus(identity(normalCreated));
equal(continuation.can_continue, true, 'remaining active members can continue after a disconnect');
deepEqual(continuation.active_member_actor_ids, ['actor-a'], 'only active frozen members remain in continuation');

throws(() => normalModel.recordCompletion({
  event_id: 'fixture-complete-left',
  ...identity(normalCreated),
  participant_actor_lifecycle_pairs: [{ actor_id: 'actor-b', actor_lifecycle_id: 2 }]
}), /active frozen current-lifecycle member/, 'left member cannot be written into completion');
throws(() => normalModel.recordCompletion({
  event_id: 'fixture-complete-stale',
  ...identity(normalCreated),
  participant_actor_lifecycle_pairs: [{ actor_id: 'actor-a', actor_lifecycle_id: 99 }]
}), /active frozen current-lifecycle member/, 'old lifecycle cannot be written into completion');

const completionEvent = {
  event_id: 'fixture-complete-a',
  ...identity(normalCreated),
  participant_actor_lifecycle_pairs: [{ actor_id: 'actor-a', actor_lifecycle_id: 1 }]
};
const completed = normalModel.recordCompletion(completionEvent);
equal(completed.state, 'cleanup_pending', 'completion transitions to cleanup pending');
equal(completed.completion.result, 'completed', 'completion result is stored before cleanup');
deepEqual(normalModel.recordCompletion(clone(completionEvent)), completed, 'completion replay returns the first authoritative result');

const lockedReentry = raidRequest({
  raidInstanceId: 'fixture-reentry-before-cleanup',
  creationEventId: 'fixture-create-reentry-before-cleanup',
  members: [member('actor-a', 1, 'normal', '东方青龙')]
});
throws(() => normalModel.createRaid(lockedReentry), /reentry lock remains held/, 'member cannot enter another raid before matching cleanup acknowledgement');
throws(() => normalModel.acknowledgeCleanup({
  event_id: 'fixture-wrong-cleanup',
  ...identity(normalCreated),
  cleanup_token: 'wrong-token'
}), /mismatched cleanup_token/, 'wrong cleanup token cannot release the lock');
const afterWrongCleanup = normalModel.getSession(identity(normalCreated));
equal(afterWrongCleanup.state, 'cleanup_pending', 'wrong cleanup acknowledgement preserves pending state');
equal(afterWrongCleanup.completion.result, 'completed', 'wrong cleanup acknowledgement cannot roll back completion');

const cleanupFailureEvent = {
  event_id: 'fixture-cleanup-failure',
  ...identity(normalCreated),
  cleanup_token: normalCreated.cleanup_token
};
const afterCleanupFailure = normalModel.observeCleanupFailure(cleanupFailureEvent);
equal(afterCleanupFailure.state, 'cleanup_pending', 'cleanup failure observation does not close the session');
equal(afterCleanupFailure.cleanup_failure_observed, true, 'cleanup failure is observable without changing completion');
equal(afterCleanupFailure.completion.result, 'completed', 'completion survives cleanup failure observation');
deepEqual(normalModel.observeCleanupFailure(clone(cleanupFailureEvent)), afterCleanupFailure, 'cleanup failure observation replay is idempotent');

const cleanupAckEvent = {
  event_id: 'fixture-cleanup-ack',
  ...identity(normalCreated),
  cleanup_token: normalCreated.cleanup_token
};
const closed = normalModel.acknowledgeCleanup(cleanupAckEvent);
equal(closed.state, 'closed', 'matching cleanup acknowledgement closes the session');
equal(closed.completion.result, 'completed', 'closing cleanup preserves completion');
deepEqual(normalModel.acknowledgeCleanup(clone(cleanupAckEvent)), closed, 'cleanup acknowledgement replay is idempotent');
throws(() => normalModel.acknowledgeCleanup({ ...clone(cleanupAckEvent), event_id: 'fixture-old-cleanup-ack' }), /closed session/, 'old or new cleanup acknowledgement cannot modify a closed session');
const creationReplayAfterTerminal = normalModel.createRaid(clone(normalRequest));
deepEqual(creationReplayAfterTerminal, firstCreationResult, 'creation replay after completion and cleanup returns the original frozen active result');
equal(creationReplayAfterTerminal.state, 'active', 'creation replay is not polluted by terminal session state');
equal(creationReplayAfterTerminal.completion, null, 'creation replay does not expose later completion state');
equal(creationReplayAfterTerminal.members[1].member_status, 'active', 'creation replay does not expose later left-member state');

const postCleanupReentry = normalModel.createRaid(raidRequest({
  raidInstanceId: 'fixture-reentry-after-cleanup',
  creationEventId: 'fixture-create-reentry-after-cleanup',
  members: [member('actor-a', 1, 'normal', '东方青龙')]
}));
equal(postCleanupReentry.state, 'active', 'matching cleanup acknowledgement releases the member reentry lock');

const sourceText = fs.readFileSync(path.join(packageRoot, 'reference', 'mansion-session-model.js'), 'utf8');
check(!/\bDate\b|process\.|fetch\(|https?:|child_process|require\(/.test(sourceText), 'reference model has no clock, process, network, subprocess, or module-loading dependency');

console.log(`PASS: TianTing mansion session reference tests (${assertions} assertions)`);
