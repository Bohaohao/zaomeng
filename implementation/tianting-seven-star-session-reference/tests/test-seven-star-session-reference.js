'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  FAILURE_REASONS,
  IDENTITY_FIELDS,
  SESSION_STATES,
  SEVEN_STAR_ROUTE_SPEC_IDS,
  SevenStarSessionReference,
  createFixtureAuthority
} = require('../reference/seven-star-session-reference');

let assertionCount = 0;

function check(condition, message) {
  assertionCount += 1;
  assert.ok(condition, message);
}

function equal(actual, expected, message) {
  assertionCount += 1;
  assert.strictEqual(actual, expected, message);
}

function deepEqual(actual, expected, message) {
  assertionCount += 1;
  assert.deepStrictEqual(actual, expected, message);
}

function makeOwner(actorId, lifecycleId, observatoryOpen = true) {
  return { actor_id: actorId, lifecycle_id: lifecycleId, observatory_open: observatoryOpen };
}

function createModel(owners) {
  const authority = createFixtureAuthority(owners);
  return { authority, model: new SevenStarSessionReference({ trustedAuthority: authority }) };
}

function start(model, actorId, lifecycleId, routeSpecId, requestId) {
  return model.createSession({
    request_id: requestId,
    caller_actor_id: actorId,
    requested_owner_actor_id: actorId,
    requested_lifecycle_id: lifecycleId,
    route_spec_id: routeSpecId,
    observatory_open: false
  });
}

function identity(session) {
  const result = {};
  for (const field of IDENTITY_FIELDS) {
    result[field] = session[field];
  }
  return result;
}

function fail(model, actorId, session, failureReason, requestId) {
  return model.failSession({
    request_id: requestId,
    subject_actor_id: actorId,
    failure_reason: failureReason,
    session: identity(session)
  });
}

function complete(model, actorId, session, requestId) {
  return model.completeSession({
    request_id: requestId,
    subject_actor_id: actorId,
    session: identity(session)
  });
}

function cleanup(model, actorId, session, requestId) {
  return model.acknowledgeCleanup({
    request_id: requestId,
    subject_actor_id: actorId,
    session: identity(session)
  });
}

function testContractShape() {
  const contractPath = path.join(__dirname, '..', 'package-contract.json');
  const contract = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
  equal(contract.spec_id, 'TT_SPEC_SEVEN_STAR_SOLO_SESSION_REFERENCE', 'spec identity must be stable');
  equal(contract.production_gate, 'closed', 'production gate must stay closed');
  equal(contract.non_production, true, 'reference package must remain non-production');
  equal(contract.route_registry.length, 7, 'contract must list seven routes');
  deepEqual(contract.session_identity_fields, IDENTITY_FIELDS, 'contract and model identities must agree');
  check(!Object.prototype.hasOwnProperty.call(contract, 'runtime_key'), 'contract must not define a runtime key');
  check(contract.completion.prohibited_outputs.includes('economy_v2_handoff'), 'economy handoff must stay prohibited');
}

function testRouteRegistryAndAdmission() {
  equal(SEVEN_STAR_ROUTE_SPEC_IDS.length, 7, 'model must export exactly seven routes');
  equal(new Set(SEVEN_STAR_ROUTE_SPEC_IDS).size, 7, 'seven routes must be unique');

  const { model } = createModel({ owner: makeOwner('owner', 'life-1', true) });
  for (const [index, routeSpecId] of SEVEN_STAR_ROUTE_SPEC_IDS.entries()) {
    const actorId = `route-owner-${index + 1}`;
    const lifecycleId = `route-life-${index + 1}`;
    model.trustedAuthority.setOwner(actorId, makeOwner(actorId, lifecycleId, true));
    const created = start(model, actorId, lifecycleId, routeSpecId, `route-create-${index + 1}`);
    equal(created.accepted, true, `route ${routeSpecId} must be admitted`);
    equal(created.session.route_spec_id, routeSpecId, `route ${routeSpecId} must be retained`);
  }

  const ownerMismatch = model.createSession({
    request_id: 'owner-mismatch',
    caller_actor_id: 'intruder',
    requested_owner_actor_id: 'owner',
    requested_lifecycle_id: 'life-1',
    route_spec_id: SEVEN_STAR_ROUTE_SPEC_IDS[0]
  });
  equal(ownerMismatch.reason, 'owner_only', 'caller may not create on behalf of another owner');

  const progressDenied = createModel({ owner: makeOwner('owner', 'life-1', false) }).model;
  equal(start(progressDenied, 'owner', 'life-1', SEVEN_STAR_ROUTE_SPEC_IDS[0], 'progress-denied').reason, 'celestial_observatory_progress_required', 'request progress fields cannot bypass authority progress');

  const staleLifecycle = model.createSession({
    request_id: 'stale-lifecycle',
    caller_actor_id: 'owner',
    requested_owner_actor_id: 'owner',
    requested_lifecycle_id: 'old-life',
    route_spec_id: SEVEN_STAR_ROUTE_SPEC_IDS[0]
  });
  equal(staleLifecycle.reason, 'current_lifecycle_required', 'old lifecycle may not create a session');

  const invalidRoute = model.createSession({
    request_id: 'invalid-route',
    caller_actor_id: 'owner',
    requested_owner_actor_id: 'owner',
    requested_lifecycle_id: 'life-1',
    route_spec_id: 'TT_SPEC_SOLO_FORGED'
  });
  equal(invalidRoute.reason, 'invalid_route_spec_id', 'unknown route must be rejected');
}

function testIdentityReentryAndFailures() {
  for (const [index, failureReason] of FAILURE_REASONS.entries()) {
    const actorId = `failure-owner-${index + 1}`;
    const lifecycleId = `failure-life-${index + 1}`;
    const { authority, model } = createModel({ [actorId]: makeOwner(actorId, lifecycleId, true) });
    const created = start(model, actorId, lifecycleId, SEVEN_STAR_ROUTE_SPEC_IDS[index], `failure-create-${index + 1}`);
    equal(created.accepted, true, `${failureReason}: initial creation must succeed`);

    const reentryActive = start(model, actorId, lifecycleId, SEVEN_STAR_ROUTE_SPEC_IDS[index], `reentry-active-${index + 1}`);
    equal(reentryActive.reason, 'reentry_denied_until_matching_cleanup', `${failureReason}: active lock must deny reentry`);

    if (failureReason === 'owner_lifecycle_invalid') {
      authority.setOwner(actorId, makeOwner(actorId, 'new-life', true));
    }
    const terminal = fail(model, actorId, created.session, failureReason, `failure-${index + 1}`);
    equal(terminal.accepted, true, `${failureReason}: trusted failure must be accepted`);
    equal(terminal.session.state, SESSION_STATES.CLEANUP_PENDING, `${failureReason}: failure must enter cleanup`);
    equal(terminal.session.terminal_reason, failureReason, `${failureReason}: terminal reason must be retained`);

    const reconnect = model.attemptReconnect({
      subject_actor_id: actorId,
      session: identity(terminal.session)
    });
    equal(reconnect.reason, 'reconnect_forbidden_until_cleanup_closed', `${failureReason}: reconnect must be denied before cleanup`);

    const reentryPending = start(model, actorId, failureReason === 'owner_lifecycle_invalid' ? 'new-life' : lifecycleId, SEVEN_STAR_ROUTE_SPEC_IDS[index], `reentry-pending-${index + 1}`);
    equal(reentryPending.reason, 'reentry_denied_until_matching_cleanup', `${failureReason}: cleanup lock must deny reentry`);

    const staleIdentity = { ...identity(terminal.session), cleanup_token: 'forged-cleanup-token' };
    const badCleanup = model.acknowledgeCleanup({ request_id: `bad-cleanup-${index + 1}`, subject_actor_id: actorId, session: staleIdentity });
    equal(badCleanup.reason, 'session_identity_mismatch', `${failureReason}: forged cleanup token must be rejected`);
    equal(model.getSessionSnapshot(created.session.session_instance_id).state, SESSION_STATES.CLEANUP_PENDING, `${failureReason}: bad cleanup must not release lock`);

    const cleaned = cleanup(model, actorId, terminal.session, `cleanup-${index + 1}`);
    equal(cleaned.accepted, true, `${failureReason}: matching cleanup must close`);
    equal(cleaned.session.state, SESSION_STATES.CLOSED, `${failureReason}: session must close only after matching cleanup`);
  }
}

function testCompletionCleanupAndIdempotency() {
  const { model } = createModel({ owner: makeOwner('owner', 'life-1', true) });
  const request = {
    request_id: 'create-once',
    caller_actor_id: 'owner',
    requested_owner_actor_id: 'owner',
    requested_lifecycle_id: 'life-1',
    route_spec_id: SEVEN_STAR_ROUTE_SPEC_IDS[0]
  };
  const created = model.createSession(request);
  const repeatedCreate = model.createSession({ ...request });
  deepEqual(repeatedCreate, created, 'same creation request must return its existing result');

  const driftedCreate = model.createSession({ ...request, route_spec_id: SEVEN_STAR_ROUTE_SPEC_IDS[1] });
  equal(driftedCreate.reason, 'idempotency_payload_drift', 'same creation request id with drift must be rejected');

  const impersonatedComplete = complete(model, 'intruder', created.session, 'complete-intruder');
  equal(impersonatedComplete.reason, 'owner_only', 'non-owner may not complete the session');

  const completed = complete(model, 'owner', created.session, 'complete-once');
  equal(completed.accepted, true, 'normal completion must be accepted while active');
  equal(completed.session.state, SESSION_STATES.CLEANUP_PENDING, 'normal completion must enter cleanup');
  equal(completed.session.completion_retained, true, 'normal completion must retain a process-local record');

  const repeatedCompletion = complete(model, 'owner', created.session, 'complete-once');
  deepEqual(repeatedCompletion, completed, 'same completion request must return its existing result after state changes');

  const forgedCleanupIdentity = { ...identity(completed.session), revision: completed.session.revision + 1 };
  const cleanupRejected = model.acknowledgeCleanup({ request_id: 'cleanup-forged', subject_actor_id: 'owner', session: forgedCleanupIdentity });
  equal(cleanupRejected.reason, 'session_identity_mismatch', 'wrong cleanup revision must be rejected');
  equal(model.getSessionSnapshot(created.session.session_instance_id).completion_retained, true, 'rejected cleanup must not roll back completion');
  check(model.getCompletionSnapshot(created.session.session_instance_id) !== null, 'completion record must remain inspectable after rejected cleanup');

  const cleaned = cleanup(model, 'owner', completed.session, 'cleanup-once');
  equal(cleaned.accepted, true, 'matching cleanup must close completed session');
  equal(cleaned.session.state, SESSION_STATES.CLOSED, 'cleanup must close completed session');
  equal(cleaned.session.completion_retained, true, 'matching cleanup must not roll back completion');

  const repeatedCleanup = cleanup(model, 'owner', completed.session, 'cleanup-once');
  deepEqual(repeatedCleanup, cleaned, 'same cleanup request must return its existing result after close');

  const reconnectAfterClose = model.attemptReconnect({ subject_actor_id: 'owner', session: identity(cleaned.session) });
  equal(reconnectAfterClose.reason, 'closed_session_cannot_reconnect', 'closed session may not reconnect');

  const nextSession = start(model, 'owner', 'life-1', SEVEN_STAR_ROUTE_SPEC_IDS[1], 'new-session-after-close');
  equal(nextSession.accepted, true, 'only a new session may follow matching cleanup');
  equal(nextSession.session.session_epoch, created.session.session_epoch + 1, 'new session must advance owner epoch');
}

function testOldLifecycleAndSignalBoundary() {
  const { authority, model } = createModel({ owner: makeOwner('owner', 'life-1', true) });
  const created = start(model, 'owner', 'life-1', SEVEN_STAR_ROUTE_SPEC_IDS[2], 'old-life-create');
  authority.setOwner('owner', makeOwner('owner', 'life-2', true));

  const completionDenied = complete(model, 'owner', created.session, 'old-life-complete');
  equal(completionDenied.reason, 'current_lifecycle_required', 'old lifecycle may not complete');
  equal(model.getSessionSnapshot(created.session.session_instance_id).state, SESSION_STATES.ACTIVE, 'denied completion must not change state');

  const wrongReason = fail(model, 'owner', created.session, 'owner_death', 'old-life-wrong-reason');
  equal(wrongReason.accepted, true, 'a trusted terminal signal may still clean an active old lifecycle');
  equal(wrongReason.session.state, SESSION_STATES.CLEANUP_PENDING, 'terminal signal must move old lifecycle to cleanup');

  const repeatFailure = fail(model, 'owner', created.session, 'owner_death', 'old-life-wrong-reason');
  deepEqual(repeatFailure, wrongReason, 'same failure request must be idempotent');

  const anotherOld = start(model, 'owner', 'life-2', SEVEN_STAR_ROUTE_SPEC_IDS[3], 'second-old-life-create');
  equal(anotherOld.reason, 'reentry_denied_until_matching_cleanup', 'old lifecycle cleanup lock must still deny a new lifecycle');
}

function run() {
  testContractShape();
  testRouteRegistryAndAdmission();
  testIdentityReentryAndFailures();
  testCompletionCleanupAndIdempotency();
  testOldLifecycleAndSignalBoundary();
  console.log(`PASS: tianting-seven-star-session-reference (${assertionCount} assertions)`);
}

run();
