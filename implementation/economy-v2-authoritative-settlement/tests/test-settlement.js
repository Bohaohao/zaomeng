'use strict';

const assert = require('assert');
const childProcess = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const packageRoot = path.resolve(__dirname, '..');
const compiler = path.join(packageRoot, 'reference', 'compile-economy-v2.js');
const {
  createStore,
  materialize,
  materializeTideTraceIntent,
  tideTraceIntentToRequest,
} = require(path.join(packageRoot, 'reference', 'settlement-materializer.js'));
const {
  canonicalJson,
  originIdentity,
  sha256,
  trustedSnapshotHmac,
} = require(path.join(packageRoot, 'reference', 'transaction-store-model.js'));

let assertions = 0;

function equal(actual, expected, message) {
  assertions += 1;
  assert.strictEqual(actual, expected, message);
}

function truthy(value, message) {
  assertions += 1;
  assert.ok(value, message);
}

function deepEqual(actual, expected, message) {
  assertions += 1;
  assert.deepStrictEqual(actual, expected, message);
}

function throws(callback, expected, message) {
  assertions += 1;
  assert.throws(callback, expected, message);
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function recomputeIdentityFingerprint(receipt, baseline) {
  const projection = {};
  for (const field of baseline.resource_table.persistent_receipt_contract.identity_fingerprint_fields) {
    projection[field] = receipt[field];
  }
  return sha256(canonicalJson(projection));
}

function emptyOwnerState() {
  return {
    balances: {},
    materials: {},
    unique_items: {},
    first_clear: {},
    pity: {},
    experience: 0,
    xp_repeat_quota: {},
    tower_first_clear: {},
    tower_weekly_tokens: {},
  };
}

function compileBaseline() {
  const tempDirectory = fs.mkdtempSync(path.join(packageRoot, 'tests', '.baseline-'));
  const output = path.join(tempDirectory, 'baseline.json');
  try {
    childProcess.execFileSync(process.execPath, [compiler, '--output', output], {
      cwd: packageRoot,
      stdio: 'pipe',
      env: { ...process.env, NODE_OPTIONS: '', NODE_PATH: '' },
    });
    return JSON.parse(fs.readFileSync(output, 'utf8'));
  } finally {
    fs.rmSync(tempDirectory, { recursive: true, force: true });
  }
}

function setupAuthorities() {
  const proofs = new Map();
  const qualifications = new Map();
  const rareRolls = new Map();
  const xpSettlements = new Map();
  const towerSnapshots = new Map();
  const authorityOriginOwners = new Map();
  return {
    proofs,
    qualifications,
    rareRolls,
    xpSettlements,
    towerSnapshots,
    authorityOriginOwners,
    resolveOwner(input) {
      const proof = proofs.get(input.authority_proof_ref);
      if (!proof) {
        return null;
      }
      if (proof.authority_origin_key !== input.authority_origin_key || proof.origin_owner_binding_verified !== true) {
        return null;
      }
      const boundOwner = authorityOriginOwners.get(input.authority_origin_key);
      if (boundOwner !== undefined && boundOwner !== proof.owner_id) {
        return null;
      }
      authorityOriginOwners.set(input.authority_origin_key, proof.owner_id);
      if (proof.canonical_tide_trace) {
        const received = input.canonical_tide_trace || {};
        const expected = proof.canonical_tide_trace;
        for (const field of TIDE_TRACE_ATTESTATION_FIELDS) {
          if (received[field] !== expected[field]) return null;
        }
      }
      return proof;
    },
    resolveQualificationSnapshot(id) {
      return qualifications.get(id) || null;
    },
    resolveRareRoll(id, proofRef) {
      const roll = rareRolls.get(`${id}:${proofRef}`);
      return roll || null;
    },
    resolveXpSettlement(id) {
      return xpSettlements.get(id) || null;
    },
    resolveTowerSnapshot(id) {
      return towerSnapshots.get(id) || null;
    },
  };
}

function installProof(authorities, request, ownerId = 'owner-character-01', canonicalTideTrace) {
  const tideAttestation = canonicalTideTrace === undefined ? {} : {
    tide_trace_attestation_ref: `tide-attestation:${request.event_id}`,
    tide_trace_canonical_digest: tideTraceCanonicalDigest(canonicalTideTrace),
  };
  authorities.proofs.set(request.authority_proof_ref, {
    owner_id: ownerId,
    actor_id: request.actor_id,
    lifecycle_id: request.lifecycle_id,
    event_id: request.event_id,
    encounter_instance_id: request.encounter_instance_id,
    source_profile: request.source_profile,
    event_type: request.event_type,
    authority_origin_key: originIdentity(request),
    origin_owner_binding_verified: true,
    canonical_tide_trace: canonicalTideTrace,
    ...tideAttestation,
  });
}

function fallbackTideIntent() {
  return {
    schema_version: 1,
    source_event_type: 'trace_action_completed',
    event_type: 'drop_bundle',
    source_profile: 'HG_DROP_WATERFALL_ELITE',
    reward_slot_key: 'base_bundle',
    event_id: 'trace-event-1',
    actor_id: 'actor-100',
    lifecycle_id: 100,
    encounter_key: 'HG_E_TIDE_TRACE',
    encounter_instance_id: 'trace-instance-1',
    target_id: 'trace-target-1',
    target_lifecycle_id: 'trace-target-life-1',
    encounter_action_key: 'stabilize_tide_trace',
    action_token: 'trace-action-1',
    combat_scope: 'public',
    completed_tick: 12,
    authority_proof_ref: 'proof-tide-1',
    source_identity_fingerprint: 'trace-source-fingerprint-1',
    target_scope: 'explicit',
    credit_personal_progress: true,
    rare_eligibility: 'none',
  };
}

// This is intentionally independent from the emitted file.  The Fengari lane
// must reproduce the exact evidence from the real Tide Trace fixture before
// Node creates its fake authority record; otherwise the two halves would only
// be self-authenticating each other.
const EXPECTED_EMITTED_TIDE_INTENT = {
  schema_version: 1,
  source_event_type: 'trace_action_completed',
  event_type: 'drop_bundle',
  source_profile: 'HG_DROP_WATERFALL_ELITE',
  reward_slot_key: 'base_bundle',
  event_id: 'economy-v2-trace-event-1',
  actor_id: 'trace-actor-a',
  lifecycle_id: 7,
  encounter_key: 'HG_E_TIDE_TRACE',
  encounter_instance_id: 'economy-v2-trace-instance-1',
  target_id: 'economy-v2-trace-target-1',
  target_lifecycle_id: 'economy-v2-trace-life-1',
  encounter_action_key: 'stabilize_tide_trace',
  action_token: 'economy-v2-trace-instance-1:trace-actor-a:7:1',
  combat_scope: 'public',
  completed_tick: 12,
  authority_proof_ref: 'fixture:public_trace_action_complete:economy-v2-trace-event-1',
  source_identity_fingerprint: 'event_id=economy-v2-trace-event-1|actor_id=trace-actor-a|lifecycle_id=7|combat_scope=public|encounter_instance_id=economy-v2-trace-instance-1|target_id=economy-v2-trace-target-1|target_lifecycle_id=economy-v2-trace-life-1|encounter_action_key=stabilize_tide_trace|action_token=economy-v2-trace-instance-1:trace-actor-a:7:1|completed_tick=12',
  target_scope: 'explicit',
  credit_personal_progress: true,
  rare_eligibility: 'none',
};

// Matches the offline core's attested Tide Trace projection.  The proof ref
// remains outside the digest because the receipt contract revalidates a
// rotated proof on replay rather than treating the transport proof as a new
// economic identity.
const TIDE_TRACE_ATTESTATION_FIELDS = [
  'schema_version', 'source_event_type', 'event_type', 'source_profile', 'reward_slot_key',
  'event_id', 'actor_id', 'lifecycle_id', 'encounter_key', 'encounter_instance_id',
  'target_id', 'target_lifecycle_id', 'encounter_action_key', 'action_token', 'combat_scope',
  'completed_tick', 'source_identity_fingerprint', 'target_scope', 'credit_personal_progress',
  'rare_eligibility',
];

function tideTraceCanonicalDigest(intent) {
  const projection = {};
  for (const field of TIDE_TRACE_ATTESTATION_FIELDS) projection[field] = intent[field];
  return sha256(canonicalJson(projection));
}

// Cross-implementation origin-key vector. The expected digest is calculated
// from a literal UTF-8 JSON byte string, not via canonicalJson/originIdentity.
const ORIGIN_KEY_TEST_VECTOR = {
  request: {
    actor_id: 'trace-actor-a',
    lifecycle_id: 7,
    encounter_instance_id: 'economy-v2-trace-instance-1',
    event_id: 'economy-v2-trace-event-1',
    source_profile: 'HG_DROP_WATERFALL_ELITE',
    reward_slot_key: 'base_bundle',
  },
  canonicalUtf8Json: '["trace-actor-a",7,"economy-v2-trace-instance-1","economy-v2-trace-event-1","HG_DROP_WATERFALL_ELITE","base_bundle"]',
  sha256: '17bb857c14e4893d7076819afee3a150496a26b4d8e0b6f2840bbcea0041e463',
  authorityOriginKey: 'economy-v2-origin:17bb857c14e4893d7076819afee3a150496a26b4d8e0b6f2840bbcea0041e463',
};

function requestBase(baseline, fields) {
  return {
    resource_table_version: baseline.source.resource_table_version,
    resource_table_file_sha256: baseline.source.resource_table_file_sha256,
    actor_id: 'actor-100',
    lifecycle_id: 'life-100',
    authority_proof_ref: 'proof-default',
    event_id: 'event-default',
    encounter_instance_id: 'instance-default',
    event_type: 'drop_bundle',
    source_profile: 'HG_DROP_WATERFALL_ELITE',
    reward_slot_key: 'base_bundle',
    ...fields,
  };
}

function publicSnapshot(id, ownerId, eventId, instanceId, extra = {}) {
  return {
    schema_version: 1,
    policy_id: 'P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION',
    snapshot_id: id,
    owner_id: ownerId,
    encounter_instance_id: instanceId,
    boss_instance_id: instanceId,
    phase_id: 'phase-1',
    event_id: eventId,
    public_action_window_opened: true,
    action_window_id: 'window-1',
    damage_ratio: 0.04,
    valid_break: false,
    valid_guard: false,
    valid_public_action: true,
    rare_clear_attested: true,
    authority_proof_ref: 'snapshot-proof-public',
    ...extra,
  };
}

function teamSnapshot(id, ownerId, eventId, instanceId, extra = {}) {
  return {
    schema_version: 1,
    policy_id: 'TEAM_RAID_RARE_ELIGIBILITY_V1',
    snapshot_id: id,
    raid_instance_id: instanceId,
    completion_event_id: eventId,
    profile_key: 'HG_DROP_OX_RAID',
    completed: true,
    rare_clear_attested: true,
    authority_proof_ref: 'snapshot-proof-team',
    members: [{
      owner_id: ownerId,
      joined_before_lock: true,
      present_at_completion: true,
      actor_alive_at_completion: true,
      contribution_attested: true,
      rare_clear_attested: true,
    }],
    ...extra,
  };
}

function towerSnapshot(id, ownerId, eventId, instanceId, cycleId, week, extra = {}) {
  return {
    schema_version: 1,
    policy_id: 'TOWER_FIRST_CYCLE_QUALIFICATION_V1',
    snapshot_id: id,
    tower_run_id: instanceId,
    tower_cycle_id: cycleId,
    tower_week_bucket: week,
    tower_mode: 'first_cycle',
    completion_event_id: eventId,
    authority_proof_ref: 'snapshot-proof-tower',
    members: [{
      owner_id: ownerId,
      entry_level: 55,
      entry_qualified: true,
      joined_before_run_lock: true,
      present_at_authoritative_completion: true,
      actor_alive_at_authoritative_completion: true,
      contribution_attested: true,
      eligible: true,
    }],
    ...extra,
  };
}

function storeWithOwner(ownerId, mutate) {
  const store = createStore();
  store.transact((state) => {
    state.owners[ownerId] = emptyOwnerState();
    mutate(state.owners[ownerId]);
  });
  return store;
}

function run() {
  const independentlyCalculatedOriginDigest = crypto.createHash('sha256')
    .update(Buffer.from(ORIGIN_KEY_TEST_VECTOR.canonicalUtf8Json, 'utf8'))
    .digest('hex');
  equal(independentlyCalculatedOriginDigest, ORIGIN_KEY_TEST_VECTOR.sha256, 'origin-key vector has the frozen SHA-256 digest');
  equal(originIdentity(ORIGIN_KEY_TEST_VECTOR.request), ORIGIN_KEY_TEST_VECTOR.authorityOriginKey, 'originIdentity follows the frozen UTF-8 array algorithm');

  const baseline = compileBaseline();
  equal(baseline.baseline_schema_version, 1, 'compiler emits baseline schema v1');
  equal(baseline.source.resource_table_version, 'economy-v2', 'compiler binds economy-v2');
  equal(baseline.source.resource_table_file_sha256, '3288BD9CD1BFBB516DB4808EF002C45FECCF5F1C7F4C80499DB81E31B2F84EAE', 'compiler retains exact SHA');

  const forgedBaseline = clone(baseline);
  forgedBaseline.resource_table.drops_and_pity.reward_bundles.waterfall_elite[0].amount = 987654;
  const forgedBaselineRequest = requestBase(baseline, {
    authority_proof_ref: 'proof-forged-baseline',
    event_id: 'forged-baseline-event-1',
    encounter_instance_id: 'forged-baseline-instance-1',
  });
  const forgedBaselineAuthorities = setupAuthorities();
  installProof(forgedBaselineAuthorities, forgedBaselineRequest);
  const forgedBaselineStore = createStore();
  const forgedBaselineResult = materialize(forgedBaseline, forgedBaselineAuthorities, forgedBaselineStore, forgedBaselineRequest);
  equal(forgedBaselineResult.status, 'rejected', 'a table-mutated baseline is rejected before derivation');
  equal(forgedBaselineResult.receipt, null, 'a table-mutated baseline cannot produce a receipt');
  equal(forgedBaselineStore.exportState().owners['owner-character-01'], undefined, 'a table-mutated baseline cannot create owner state');

  const getterBaseline = clone(baseline);
  const getterBundleEntry = getterBaseline.resource_table.drops_and_pity.reward_bundles.waterfall_elite[0];
  let getterBaselineReads = 0;
  Object.defineProperty(getterBundleEntry, 'amount', {
    enumerable: true,
    get() {
      getterBaselineReads += 1;
      return getterBaselineReads === 1 ? 24 : 999;
    },
  });
  const getterBaselineRequest = requestBase(baseline, {
    authority_proof_ref: 'proof-getter-baseline', event_id: 'getter-baseline-event',
    encounter_instance_id: 'getter-baseline-instance',
  });
  const getterBaselineAuthorities = setupAuthorities();
  installProof(getterBaselineAuthorities, getterBaselineRequest);
  const getterBaselineResult = materialize(getterBaseline, getterBaselineAuthorities, createStore(), getterBaselineRequest);
  equal(getterBaselineResult.status, 'committed', 'baseline is detached before hash validation and derivation');
  equal(getterBaselineResult.receipt.balance_delta.CUR_GOLD, 24, 'baseline accessor cannot change an already-validated frozen award');
  equal(getterBaselineReads, 1, 'baseline accessor is read once into the detached compiled baseline');

  const tideIntentArgument = process.argv[2];
  const tideIntent = tideIntentArgument === undefined
    ? fallbackTideIntent()
    : JSON.parse(fs.readFileSync(path.resolve(tideIntentArgument), 'utf8'));
  if (tideIntentArgument !== undefined) {
    deepEqual(tideIntent, EXPECTED_EMITTED_TIDE_INTENT, 'Fengari-emitted Tide Trace intent matches independent canonical evidence');
  }
  const authorities = setupAuthorities();
  // A test-only key is created in process memory for this run. It is never
  // written to an artifact, environment variable, snapshot, or package file.
  const stateIntegrityKey = crypto.randomBytes(32);
  const store = createStore(undefined, { integrity_key: stateIntegrityKey });
  const tide = tideTraceIntentToRequest(baseline, tideIntent);
  for (const [invalidLifecycle, label] of [
    ['life-100', 'string'],
    [7.5, 'fractional'],
    [9007199254740992, 'unsafe-integer'],
  ]) {
    throws(
      () => tideTraceIntentToRequest(baseline, { ...fallbackTideIntent(), lifecycle_id: invalidLifecycle }),
      /invalid_tide_trace_lifecycle_id/,
      `Tide Trace Node entry rejects ${label} lifecycle_id outside the adapter contract`,
    );
  }
  const canonicalTideEvidence = tideIntentArgument === undefined ? tideIntent : EXPECTED_EMITTED_TIDE_INTENT;
  installProof(authorities, tide, 'owner-character-01', canonicalTideEvidence);
  const firstTide = materializeTideTraceIntent(baseline, authorities, store, tideIntent);
  equal(firstTide.status, 'committed', 'canonical Tide Trace mapped ordinary bundle commits');
  equal(firstTide.replayed, false, 'first Tide Trace settlement is not a replay');
  equal(firstTide.receipt.owner_id, 'owner-character-01', 'proof resolves stable owner distinct from actor');
  equal(firstTide.receipt.balance_delta.CUR_GOLD, 24, 'waterfall elite exact gold is table driven');
  equal(firstTide.receipt.material_delta.MAT_STRENGTHEN_SHARD, 2, 'waterfall elite exact material is table driven');
  equal(firstTide.receipt.commit_state, 'committed', 'new receipt is terminal committed');
  deepEqual(firstTide.receipt.offline_award_plan.tide_trace_authority_attestation, {
    tide_trace_attestation_ref: `tide-attestation:${canonicalTideEvidence.event_id}`,
    tide_trace_canonical_digest: tideTraceCanonicalDigest(canonicalTideEvidence),
  }, 'terminal Tide receipt plan binds the resolver attestation and canonical evidence digest');
  const afterFirstTide = store.digest();
  const reorderedTide = {};
  for (const key of Object.keys(tideIntent).reverse()) {
    reorderedTide[key] = tideIntent[key];
  }
  const tideReplay = materializeTideTraceIntent(baseline, authorities, store, reorderedTide);
  equal(tideReplay.status, 'committed', 'key reordering is canonical replay');
  equal(tideReplay.replayed, true, 'same input returns original receipt');
  equal(tideReplay.receipt.receipt_id, firstTide.receipt.receipt_id, 'replay retains receipt id');
  equal(store.digest(), afterFirstTide, 'replay has no economic mutation');

  const tamperedTideIntent = { ...tideIntent, source_profile: 'HG_DROP_DRAGON_REVERSE' };
  const beforeTamperedTide = store.digest();
  const tamperedTideResult = materializeTideTraceIntent(baseline, authorities, store, tamperedTideIntent);
  equal(tamperedTideResult.status, 'rejected', 'Node Trace boundary rejects a tampered adapter profile');
  equal(tamperedTideResult.receipt, null, 'tampered adapter intent cannot create a receipt');
  equal(store.digest(), beforeTamperedTide, 'tampered adapter intent has no side effect');

  const getterTideSource = {
    ...fallbackTideIntent(), event_id: 'getter-tide-event', encounter_instance_id: 'getter-tide-instance',
    authority_proof_ref: 'proof-getter-tide', action_token: 'getter-tide-action',
    source_identity_fingerprint: 'getter-tide-source-fingerprint',
  };
  const getterTideIntent = { ...getterTideSource };
  let getterTideReads = 0;
  Object.defineProperty(getterTideIntent, 'source_profile', {
    enumerable: true,
    get() {
      getterTideReads += 1;
      return getterTideReads === 1 ? 'HG_DROP_WATERFALL_ELITE' : 'HG_DROP_DRAGON_REVERSE';
    },
  });
  const getterTideAuthorities = setupAuthorities();
  const getterTideRequest = tideTraceIntentToRequest(baseline, getterTideSource);
  installProof(getterTideAuthorities, getterTideRequest, 'owner-character-01', getterTideSource);
  const getterTideResult = materializeTideTraceIntent(baseline, getterTideAuthorities, createStore(), getterTideIntent);
  equal(getterTideResult.status, 'committed', 'Tide intent is detached before adapter and authority validation');
  equal(getterTideResult.receipt.source_profile, 'HG_DROP_WATERFALL_ELITE', 'Tide intent accessor cannot substitute its profile after validation');
  equal(getterTideReads, 1, 'Tide intent accessor is read once into detached intent evidence');

  const replayProof = { ...tideIntent, authority_proof_ref: 'proof-tide-1-replay' };
  const replayProofCoreRequest = tideTraceIntentToRequest(baseline, replayProof);
  installProof(authorities, replayProofCoreRequest, 'owner-character-01', replayProof);
  const reproof = materializeTideTraceIntent(baseline, authorities, store, replayProof);
  equal(reproof.replayed, true, 'different valid proof reference revalidates then replays');
  equal(store.digest(), afterFirstTide, 'new proof cannot mint a second grant');
  equal(
    authorities.proofs.get(replayProof.authority_proof_ref).tide_trace_attestation_ref,
    firstTide.receipt.offline_award_plan.tide_trace_authority_attestation.tide_trace_attestation_ref,
    'a valid rotated proof retains the evidence-stable Tide attestation reference required for replay',
  );

  const unstableAttestationProof = { ...tideIntent, authority_proof_ref: 'proof-tide-unstable-attestation' };
  const unstableAttestationCoreRequest = tideTraceIntentToRequest(baseline, unstableAttestationProof);
  installProof(authorities, unstableAttestationCoreRequest, 'owner-character-01', unstableAttestationProof);
  authorities.proofs.get(unstableAttestationProof.authority_proof_ref).tide_trace_attestation_ref = 'tide-attestation:unstable-proof-rotation';
  const unstableAttestationResult = materializeTideTraceIntent(baseline, authorities, store, unstableAttestationProof);
  equal(unstableAttestationResult.status, 'conflict', 'an evidence-equivalent proof with a changed attestation reference cannot silently replay');
  equal(unstableAttestationResult.code, 'receipt_identity_conflict', 'unstable Tide attestation reference has a stable conflict code');
  equal(store.digest(), afterFirstTide, 'unstable Tide attestation reference has no economic side effect');

  const legacyResolverAuthorities = {
    ...authorities,
    resolveOwner(input) {
      const proof = authorities.proofs.get(input.authority_proof_ref);
      if (!proof) return null;
      const {
        tide_trace_attestation_ref: _ignoredRef,
        tide_trace_canonical_digest: _ignoredDigest,
        ...legacyProof
      } = proof;
      return legacyProof;
    },
  };
  const unverifiedTideIntent = {
    ...tideIntent,
    target_id: 'trace-target-unverified',
    action_token: 'trace-action-unverified',
    completed_tick: 13,
    source_identity_fingerprint: 'trace-source-unverified',
  };
  const beforeUnverifiedTide = store.digest();
  const unverifiedTideResult = materializeTideTraceIntent(baseline, legacyResolverAuthorities, store, unverifiedTideIntent);
  equal(unverifiedTideResult.status, 'rejected', 'a resolver that ignores Tide evidence cannot settle a syntactically valid intent');
  equal(unverifiedTideResult.code, 'invalid_tide_trace_authority_attestation', 'Tide attestation omission has a stable rejection code');
  equal(unverifiedTideResult.receipt, null, 'missing Tide attestation cannot create a receipt');
  equal(store.digest(), beforeUnverifiedTide, 'missing Tide attestation has no economic side effect');

  const attestedVariant = {
    ...unverifiedTideIntent,
    authority_proof_ref: 'proof-tide-attested-variant',
  };
  const attestedVariantRequest = tideTraceIntentToRequest(baseline, attestedVariant);
  installProof(authorities, attestedVariantRequest, 'owner-character-01', attestedVariant);
  const attestedVariantResult = materializeTideTraceIntent(baseline, authorities, store, attestedVariant);
  equal(attestedVariantResult.status, 'conflict', 'changed canonical Tide evidence conflicts with the existing semantic receipt');
  equal(attestedVariantResult.code, 'receipt_identity_conflict', 'changed Tide attestation has a stable conflict code');
  equal(store.digest(), afterFirstTide, 'a Tide evidence variant cannot mint a second grant');

  const ownerSwitchProof = { ...tideIntent, authority_proof_ref: 'proof-tide-owner-switch' };
  const ownerSwitchCoreRequest = tideTraceIntentToRequest(baseline, ownerSwitchProof);
  installProof(authorities, ownerSwitchCoreRequest, 'owner-character-02', ownerSwitchProof);
  const beforeOwnerSwitch = store.digest();
  const ownerSwitchResult = materializeTideTraceIntent(baseline, authorities, store, ownerSwitchProof);
  equal(ownerSwitchResult.status, 'rejected', 'a proof may not remap one origin to a second owner');
  equal(ownerSwitchResult.code, 'invalid_authority_result', 'trusted authority refuses an owner switch before the ledger');
  equal(ownerSwitchResult.receipt, null, 'owner-switch rejection does not create a foreign receipt');
  equal(store.digest(), beforeOwnerSwitch, 'owner-switch rejection has no persistent side effect');
  equal(store.exportState().owners['owner-character-02'], undefined, 'owner-switch proof cannot create owner-B state');

  const maliciousOwnerSwitchAuthorities = {
    ...authorities,
    resolveOwner() {
      return { ...authorities.proofs.get('proof-tide-owner-switch') };
    },
  };
  const beforeLedgerOwnerSwitch = store.digest();
  const ledgerOwnerSwitchResult = materializeTideTraceIntent(baseline, maliciousOwnerSwitchAuthorities, store, ownerSwitchProof);
  equal(ledgerOwnerSwitchResult.status, 'rejected', 'ledger independently refuses a malicious resolver owner switch after commitment');
  equal(ledgerOwnerSwitchResult.code, 'authority_owner_origin_conflict', 'ledger owner-switch backstop has a stable rejection code');
  equal(ledgerOwnerSwitchResult.receipt, null, 'ledger owner-switch backstop creates no foreign receipt');
  equal(store.digest(), beforeLedgerOwnerSwitch, 'ledger owner-switch backstop has no persistent side effect');

  const restartedStore = createStore(store.exportTrustedSnapshot(), { integrity_key: stateIntegrityKey });
  const restartReplay = materializeTideTraceIntent(baseline, authorities, restartedStore, replayProof);
  equal(restartReplay.replayed, true, 'serialized restart preserves terminal replay');
  equal(restartedStore.digest(), afterFirstTide, 'restart replay does not alter state');

  const rawRestartState = store.exportState();
  throws(() => createStore(rawRestartState), /trusted snapshot restore requires an external integrity key/, 'raw exported state cannot be treated as a restart snapshot');

  const orphanedRestart = store.exportTrustedSnapshot();
  const committedIdentity = Object.keys(orphanedRestart.state.receipts_by_identity)[0];
  delete orphanedRestart.state.receipts_by_identity[committedIdentity];
  throws(() => createStore(orphanedRestart, { integrity_key: stateIntegrityKey }), /trusted snapshot integrity mismatch/, 'restart import rejects a tampered receipt-id index before it can be trusted');

  const tamperedRestart = store.exportTrustedSnapshot();
  const tamperedIdentity = Object.keys(tamperedRestart.state.receipts_by_identity)[0];
  const tamperedReceiptId = tamperedRestart.state.receipts_by_identity[tamperedIdentity].receipt_id;
  const tamperedReceipt = tamperedRestart.state.receipts_by_identity[tamperedIdentity];
  tamperedReceipt.offline_award_plan.balance_delta.CUR_GOLD = 999;
  tamperedReceipt.balance_delta.CUR_GOLD = 999;
  tamperedReceipt.award_plan_hash = sha256(canonicalJson(tamperedReceipt.offline_award_plan));
  tamperedReceipt.identity_fingerprint = recomputeIdentityFingerprint(tamperedReceipt, baseline);
  tamperedRestart.state.receipts_by_id[tamperedReceiptId] = clone(tamperedReceipt);
  tamperedRestart.state.owners['owner-character-01'].balances.CUR_GOLD = 999;
  throws(() => createStore(tamperedRestart, { integrity_key: stateIntegrityKey }), /trusted snapshot integrity mismatch/, 'restart import rejects an internally self-consistent but unsigned reward rewrite');

  const invalidTowerCounterSnapshot = store.exportTrustedSnapshot();
  const invalidTowerCounterIdentity = Object.keys(invalidTowerCounterSnapshot.state.receipts_by_identity)[0];
  const invalidTowerCounterReceipt = invalidTowerCounterSnapshot.state.receipts_by_identity[invalidTowerCounterIdentity];
  invalidTowerCounterReceipt.tower_weekly_token_before = 0;
  invalidTowerCounterReceipt.tower_weekly_token_after = '[object Object]3';
  invalidTowerCounterSnapshot.state.receipts_by_id[invalidTowerCounterReceipt.receipt_id] = clone(invalidTowerCounterReceipt);
  invalidTowerCounterSnapshot.state_hmac_sha256 = trustedSnapshotHmac(invalidTowerCounterSnapshot.state, stateIntegrityKey);
  throws(() => createStore(invalidTowerCounterSnapshot, { integrity_key: stateIntegrityKey }), /tower counters invalid/, 'a correctly sealed snapshot still rejects non-integer tower counters');

  const invalidXpLevelSnapshot = store.exportTrustedSnapshot();
  const invalidXpLevelIdentity = Object.keys(invalidXpLevelSnapshot.state.receipts_by_identity)[0];
  const invalidXpLevelReceipt = invalidXpLevelSnapshot.state.receipts_by_identity[invalidXpLevelIdentity];
  invalidXpLevelReceipt.xp_character_level_before = -1;
  invalidXpLevelSnapshot.state.receipts_by_id[invalidXpLevelReceipt.receipt_id] = clone(invalidXpLevelReceipt);
  invalidXpLevelSnapshot.state_hmac_sha256 = trustedSnapshotHmac(invalidXpLevelSnapshot.state, stateIntegrityKey);
  throws(() => createStore(invalidXpLevelSnapshot, { integrity_key: stateIntegrityKey }), /XP character level invalid/, 'a correctly sealed snapshot still rejects an invalid XP level');

  const getterSnapshotSource = store.exportTrustedSnapshot();
  const getterSnapshotForgedState = clone(getterSnapshotSource.state);
  getterSnapshotForgedState.owners['owner-character-01'].balances.CUR_GOLD = 999;
  let getterSnapshotReads = 0;
  const getterSnapshot = {
    snapshot_schema_version: getterSnapshotSource.snapshot_schema_version,
    state_hmac_sha256: getterSnapshotSource.state_hmac_sha256,
  };
  Object.defineProperty(getterSnapshot, 'state', {
    enumerable: true,
    get() {
      getterSnapshotReads += 1;
      return getterSnapshotReads === 1 ? getterSnapshotSource.state : getterSnapshotForgedState;
    },
  });
  const getterSnapshotRestored = createStore(getterSnapshot, { integrity_key: stateIntegrityKey });
  equal(getterSnapshotReads, 1, 'trusted snapshot accessor is read exactly once before HMAC verification');
  equal(getterSnapshotRestored.digest(), store.digest(), 'trusted snapshot accessor cannot swap state after HMAC verification');

  const versionDrift = { ...tide, authority_proof_ref: 'proof-tide-version-drift', resource_table_version: 'economy-v3' };
  installProof(authorities, versionDrift);
  const versionConflict = materialize(baseline, authorities, store, versionDrift);
  equal(versionConflict.status, 'conflict', 'cross-version same identity is a conflict');
  equal(versionConflict.code, 'receipt_identity_conflict', 'cross-version conflict code is frozen');
  equal(store.digest(), afterFirstTide, 'cross-version conflict has no side effect');

  const forgedReward = { ...tide, event_id: 'trace-event-forged', authority_proof_ref: 'proof-forged', balance_delta: { CUR_GOLD: 999 } };
  const beforeForgedReward = store.digest();
  const forgedRewardResult = materialize(baseline, authorities, store, forgedReward);
  equal(forgedRewardResult.status, 'rejected', 'inline reward is rejected before settlement');
  equal(forgedRewardResult.receipt, null, 'client reward injection creates no receipt');
  equal(store.digest(), beforeForgedReward, 'inline reward injection creates no mutation');

  const invalidProof = { ...tide, event_id: 'trace-event-invalid-proof', encounter_instance_id: 'trace-instance-invalid-proof', authority_proof_ref: 'proof-missing' };
  const beforeInvalidProof = store.digest();
  const invalidProofResult = materialize(baseline, authorities, store, invalidProof);
  equal(invalidProofResult.status, 'rejected', 'unknown proof fails closed');
  equal(invalidProofResult.receipt, null, 'unknown proof creates no durable identity');
  equal(store.digest(), beforeInvalidProof, 'unknown proof has zero state side effect');

  const numericLifecycleOwner = requestBase(baseline, {
    authority_proof_ref: 'proof-raw-numeric-lifecycle-owner', event_id: 'numeric-lifecycle-owner-event',
    encounter_instance_id: 'numeric-lifecycle-owner-instance', lifecycle_id: 7,
  });
  installProof(authorities, numericLifecycleOwner, '7');
  const beforeNumericLifecycleOwner = store.digest();
  const numericLifecycleOwnerResult = materialize(baseline, authorities, store, numericLifecycleOwner);
  equal(numericLifecycleOwnerResult.status, 'rejected', 'numeric lifecycle stringification cannot become a character owner');
  equal(numericLifecycleOwnerResult.code, 'raw_identity_cannot_be_owner', 'raw numeric lifecycle owner has a stable failure code');
  equal(numericLifecycleOwnerResult.receipt, null, 'raw numeric lifecycle owner creates no receipt');
  equal(store.digest(), beforeNumericLifecycleOwner, 'raw numeric lifecycle owner has no state side effect');

  const reservedOwnerRequest = requestBase(baseline, {
    authority_proof_ref: 'proof-reserved-owner', event_id: 'reserved-owner-event',
    encounter_instance_id: 'reserved-owner-instance',
  });
  installProof(authorities, reservedOwnerRequest, '__proto__');
  const beforeReservedOwner = store.digest();
  const reservedOwnerResult = materialize(baseline, authorities, store, reservedOwnerRequest);
  equal(reservedOwnerResult.status, 'rejected', 'a prototype-reserved owner id is rejected before the owner map is touched');
  equal(reservedOwnerResult.code, 'invalid_resolved_owner_id', 'reserved owner ids have a stable fail-closed code');
  equal(reservedOwnerResult.receipt, null, 'a prototype-reserved owner cannot create a receipt');
  equal(store.digest(), beforeReservedOwner, 'a prototype-reserved owner has zero state side effect');

  const getterRequestSource = requestBase(baseline, {
    authority_proof_ref: 'proof-getter-request', event_id: 'getter-request-event',
    encounter_instance_id: 'getter-request-instance', source_profile: 'HG_DROP_WATERFALL_COMMON',
  });
  const getterRequest = { ...getterRequestSource };
  let getterRequestReads = 0;
  Object.defineProperty(getterRequest, 'source_profile', {
    enumerable: true,
    get() {
      getterRequestReads += 1;
      return getterRequestReads === 1 ? 'HG_DROP_WATERFALL_COMMON' : 'HG_DROP_DRAGON_OLD';
    },
  });
  const getterRequestAuthorities = setupAuthorities();
  getterRequestAuthorities.proofs.set('proof-getter-request', {
    owner_id: 'owner-character-01', actor_id: getterRequestSource.actor_id,
    lifecycle_id: getterRequestSource.lifecycle_id, event_id: getterRequestSource.event_id,
    encounter_instance_id: getterRequestSource.encounter_instance_id,
    source_profile: 'HG_DROP_WATERFALL_COMMON', event_type: 'drop_bundle',
    authority_origin_key: originIdentity(getterRequestSource), origin_owner_binding_verified: true,
  });
  const getterRequestResult = materialize(baseline, getterRequestAuthorities, createStore(), getterRequest);
  equal(getterRequestResult.status, 'committed', 'request is detached before proof binding and derivation');
  equal(getterRequestResult.receipt.source_profile, 'HG_DROP_WATERFALL_COMMON', 'request accessor cannot change source profile after authority binding');
  equal(getterRequestResult.receipt.balance_delta.CUR_GOLD, 10, 'request accessor cannot substitute a higher-value bundle');
  equal(getterRequestReads, 1, 'request accessor is read once into the detached request');

  const forgedProfile = requestBase(baseline, {
    authority_proof_ref: 'proof-forged-profile',
    event_id: 'forged-profile-event-1',
    encounter_instance_id: 'forged-profile-instance-1',
  });
  installProof(authorities, forgedProfile);
  authorities.proofs.get('proof-forged-profile').source_profile = 'HG_DROP_DRAGON_REVERSE';
  const beforeForgedProfile = store.digest();
  const forgedProfileResult = materialize(baseline, authorities, store, forgedProfile);
  equal(forgedProfileResult.status, 'rejected', 'authority proof must bind the exact requested source profile');
  equal(forgedProfileResult.code, 'authority_source_profile_mismatch', 'forged authority profile has a stable failure code');
  equal(forgedProfileResult.receipt, null, 'forged authority profile creates no receipt');
  equal(store.digest(), beforeForgedProfile, 'forged authority profile has no side effect');

  const forgedEventType = requestBase(baseline, {
    authority_proof_ref: 'proof-forged-event-type',
    event_id: 'forged-event-type-1',
    encounter_instance_id: 'forged-event-type-instance-1',
  });
  installProof(authorities, forgedEventType);
  authorities.proofs.get('proof-forged-event-type').event_type = 'tower_reward';
  const beforeForgedEventType = store.digest();
  const forgedEventTypeResult = materialize(baseline, authorities, store, forgedEventType);
  equal(forgedEventTypeResult.status, 'rejected', 'authority proof must bind the exact requested event type');
  equal(forgedEventTypeResult.code, 'authority_event_type_mismatch', 'forged authority event type has a stable failure code');
  equal(forgedEventTypeResult.receipt, null, 'forged authority event type creates no receipt');
  equal(store.digest(), beforeForgedEventType, 'forged authority event type has no side effect');

  const lowercaseHash = requestBase(baseline, {
    authority_proof_ref: 'proof-lowercase-hash',
    event_id: 'trace-event-lowercase-hash',
    encounter_instance_id: 'trace-instance-lowercase-hash',
    resource_table_file_sha256: baseline.source.resource_table_file_sha256.toLowerCase(),
  });
  installProof(authorities, lowercaseHash);
  const beforeLowercaseHash = store.digest();
  const lowercaseHashResult = materialize(baseline, authorities, store, lowercaseHash);
  equal(lowercaseHashResult.status, 'rejected', 'noncanonical source SHA spelling is rejected');
  equal(lowercaseHashResult.receipt, null, 'noncanonical source SHA cannot consume a semantic identity');
  equal(store.digest(), beforeLowercaseHash, 'noncanonical source SHA has no state side effect');

  const secondInstance = requestBase(baseline, {
    authority_proof_ref: 'proof-tide-2',
    event_id: 'trace-event-1',
    encounter_instance_id: 'trace-instance-2',
  });
  installProof(authorities, secondInstance);
  const secondInstanceResult = materialize(baseline, authorities, store, secondInstance);
  equal(secondInstanceResult.status, 'committed', 'same event id in another authoritative instance may settle');
  equal(secondInstanceResult.replayed, false, 'instance is part of semantic identity');

  const capStore = storeWithOwner('owner-character-01', (owner) => {
    owner.balances.CUR_GOLD = 9999980;
  });
  const capRequest = requestBase(baseline, {
    authority_proof_ref: 'proof-cap',
    event_id: 'cap-event-1',
    encounter_instance_id: 'cap-instance-1',
  });
  installProof(authorities, capRequest);
  const capResult = materialize(baseline, authorities, capStore, capRequest);
  equal(capResult.status, 'committed', 'cap path remains a terminal committed receipt');
  equal(capResult.receipt.award_outcome, 'balance_or_stack_cap_reached', 'cap outcome is exact');
  deepEqual(capResult.receipt.balance_delta, {}, 'cap produces no partial currency award');
  deepEqual(capResult.receipt.material_delta, {}, 'cap produces no partial material award');
  const capOwner = capStore.exportState().owners['owner-character-01'];
  equal(capOwner.balances.CUR_GOLD, 9999980, 'cap keeps balance unchanged');
  equal(capOwner.materials.MAT_STRENGTHEN_SHARD, undefined, 'cap keeps material unchanged');

  const publicStore = createStore();
  const chest = requestBase(baseline, {
    authority_proof_ref: 'proof-public-chest',
    event_id: 'public-event-1',
    encounter_instance_id: 'public-instance-1',
    event_type: 'participation_chest',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC',
    reward_slot_key: 'participation_chest',
    qualification_snapshot_id: 'p1-snapshot-1',
  });
  installProof(authorities, chest);
  authorities.qualifications.set('p1-snapshot-1', publicSnapshot('p1-snapshot-1', 'owner-character-01', 'public-event-1', 'public-instance-1'));
  const chestResult = materialize(baseline, authorities, publicStore, chest);
  equal(chestResult.status, 'committed', 'eligible P1 participation chest commits');
  equal(chestResult.receipt.p1_policy_id, 'P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION', 'P1 policy is derived not supplied');
  equal(chestResult.receipt.balance_delta.CUR_GOLD, 50, 'public base bundle uses frozen public bundle');

  const malformedPublicChest = requestBase(baseline, {
    authority_proof_ref: 'proof-public-malformed-snapshot',
    event_id: 'public-event-malformed-snapshot',
    encounter_instance_id: 'public-instance-malformed-snapshot',
    event_type: 'participation_chest',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC',
    reward_slot_key: 'participation_chest',
    qualification_snapshot_id: 'p1-snapshot-malformed',
  });
  installProof(authorities, malformedPublicChest);
  const malformedPublicSnapshot = publicSnapshot('p1-snapshot-malformed', 'owner-character-01', 'public-event-malformed-snapshot', 'public-instance-malformed-snapshot');
  delete malformedPublicSnapshot.rare_clear_attested;
  authorities.qualifications.set('p1-snapshot-malformed', malformedPublicSnapshot);
  const beforeMalformedPublicSnapshot = publicStore.digest();
  const malformedPublicResult = materialize(baseline, authorities, publicStore, malformedPublicChest);
  equal(malformedPublicResult.status, 'rejected', 'public snapshot with a missing frozen field fails closed');
  equal(malformedPublicResult.receipt, null, 'malformed public snapshot cannot persist a partial receipt');
  equal(publicStore.digest(), beforeMalformedPublicSnapshot, 'malformed public snapshot has no state side effect');

  const publicBundleAttempt = requestBase(baseline, {
    authority_proof_ref: 'proof-public-direct',
    event_id: 'public-event-direct',
    encounter_instance_id: 'public-instance-direct',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC',
  });
  installProof(authorities, publicBundleAttempt);
  const beforePublicBundleAttempt = publicStore.digest();
  const publicBundleRejected = materialize(baseline, authorities, publicStore, publicBundleAttempt);
  equal(publicBundleRejected.status, 'rejected', 'public profile cannot bypass participation chest');
  equal(publicBundleRejected.receipt.award_outcome, 'rejected', 'public bypass is terminal rejected receipt');
  equal(publicStore.digest() === beforePublicBundleAttempt, false, 'rejection receipt is permitted while economic state is frozen');
  const publicAfterReject = publicStore.exportState().owners['owner-character-01'];
  equal(publicAfterReject.balances.CUR_GOLD, 50, 'rejected public bypass did not mint currency');
  equal(publicAfterReject.materials.MAT_STRENGTHEN_SHARD, 3, 'rejected public bypass did not mint materials');

  const publicRare = requestBase(baseline, {
    authority_proof_ref: 'proof-public-rare',
    event_id: 'public-event-1',
    encounter_instance_id: 'public-instance-1',
    event_type: 'public_rare_drop',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC',
    reward_slot_key: 'rare_drop',
    qualification_snapshot_id: 'p1-snapshot-1',
    participation_chest_receipt_id: chestResult.receipt.receipt_id,
    participation_chest_receipt_fingerprint: chestResult.receipt.identity_fingerprint,
    drop_roll_id: 'public-roll-1',
    drop_roll_proof_ref: 'public-roll-proof-1',
  });
  installProof(authorities, publicRare);
  authorities.rareRolls.set('public-roll-1:public-roll-proof-1', {
    drop_roll_id: 'public-roll-1',
    drop_roll_proof_ref: 'public-roll-proof-1',
    owner_id: 'owner-character-01',
    event_id: 'public-event-1',
    encounter_instance_id: 'public-instance-1',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC',
    resource_table_version: 'economy-v2',
    pity_before: 0,
    resolution_branch: 'miss',
    roll_basis_points: 9999,
  });
  const publicRareResult = materialize(baseline, authorities, publicStore, publicRare);
  equal(publicRareResult.status, 'committed', 'trusted public rare miss commits its pity transition');
  equal(publicRareResult.receipt.rare_roll_outcome, 'miss', 'rare miss disposition is frozen');
  equal(publicRareResult.receipt.rare_grant_disposition, 'not_applicable', 'rare miss has no grant disposition');
  equal(publicRareResult.receipt.pity_before, 0, 'first rare receipt reads pity before');
  equal(publicRareResult.receipt.pity_after, 1, 'first rare miss increments pity');

  const stalePityStore = createStore();
  const stalePityChest = requestBase(baseline, {
    authority_proof_ref: 'proof-stale-pity-chest', event_id: 'public-event-stale-pity',
    encounter_instance_id: 'public-instance-stale-pity', event_type: 'participation_chest',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC', reward_slot_key: 'participation_chest',
    qualification_snapshot_id: 'p1-snapshot-stale-pity',
  });
  installProof(authorities, stalePityChest);
  authorities.qualifications.set('p1-snapshot-stale-pity', publicSnapshot('p1-snapshot-stale-pity', 'owner-character-01', 'public-event-stale-pity', 'public-instance-stale-pity'));
  const stalePityChestResult = materialize(baseline, authorities, stalePityStore, stalePityChest);
  equal(stalePityChestResult.status, 'committed', 'stale-pity fixture has an eligible chest');
  const stalePityRare = requestBase(baseline, {
    authority_proof_ref: 'proof-stale-pity-rare', event_id: 'public-event-stale-pity',
    encounter_instance_id: 'public-instance-stale-pity', event_type: 'public_rare_drop',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC', reward_slot_key: 'rare_drop',
    qualification_snapshot_id: 'p1-snapshot-stale-pity',
    participation_chest_receipt_id: stalePityChestResult.receipt.receipt_id,
    participation_chest_receipt_fingerprint: stalePityChestResult.receipt.identity_fingerprint,
    drop_roll_id: 'public-roll-stale-pity', drop_roll_proof_ref: 'public-roll-proof-stale-pity',
  });
  installProof(authorities, stalePityRare);
  authorities.rareRolls.set('public-roll-stale-pity:public-roll-proof-stale-pity', {
    drop_roll_id: 'public-roll-stale-pity', drop_roll_proof_ref: 'public-roll-proof-stale-pity',
    owner_id: 'owner-character-01', event_id: 'public-event-stale-pity',
    encounter_instance_id: 'public-instance-stale-pity', source_profile: 'HG_DROP_MACAQUE_PUBLIC',
    resource_table_version: 'economy-v2', pity_before: 1, resolution_branch: 'miss', roll_basis_points: 9999,
  });
  const beforeStalePity = stalePityStore.digest();
  const stalePityResult = materialize(baseline, authorities, stalePityStore, stalePityRare);
  equal(stalePityResult.status, 'rejected', 'a rare roll with stale pity counter fails closed');
  equal(stalePityResult.code, 'rare_roll_binding_mismatch', 'stale rare pity has a stable failure code');
  equal(stalePityResult.receipt, null, 'stale rare pity cannot persist a partial receipt');
  equal(stalePityStore.digest(), beforeStalePity, 'stale rare pity has no state side effect');

  const wrongBranchStore = createStore();
  const wrongBranchChest = requestBase(baseline, {
    authority_proof_ref: 'proof-wrong-branch-chest', event_id: 'public-event-wrong-branch',
    encounter_instance_id: 'public-instance-wrong-branch', event_type: 'participation_chest',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC', reward_slot_key: 'participation_chest',
    qualification_snapshot_id: 'p1-snapshot-wrong-branch',
  });
  installProof(authorities, wrongBranchChest);
  authorities.qualifications.set('p1-snapshot-wrong-branch', publicSnapshot('p1-snapshot-wrong-branch', 'owner-character-01', 'public-event-wrong-branch', 'public-instance-wrong-branch'));
  const wrongBranchChestResult = materialize(baseline, authorities, wrongBranchStore, wrongBranchChest);
  equal(wrongBranchChestResult.status, 'committed', 'wrong-branch fixture has an eligible chest');
  const wrongBranchRare = requestBase(baseline, {
    authority_proof_ref: 'proof-wrong-branch-rare', event_id: 'public-event-wrong-branch',
    encounter_instance_id: 'public-instance-wrong-branch', event_type: 'public_rare_drop',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC', reward_slot_key: 'rare_drop',
    qualification_snapshot_id: 'p1-snapshot-wrong-branch',
    participation_chest_receipt_id: wrongBranchChestResult.receipt.receipt_id,
    participation_chest_receipt_fingerprint: wrongBranchChestResult.receipt.identity_fingerprint,
    drop_roll_id: 'public-roll-wrong-branch', drop_roll_proof_ref: 'public-roll-proof-wrong-branch',
  });
  installProof(authorities, wrongBranchRare);
  authorities.rareRolls.set('public-roll-wrong-branch:public-roll-proof-wrong-branch', {
    drop_roll_id: 'public-roll-wrong-branch', drop_roll_proof_ref: 'public-roll-proof-wrong-branch',
    owner_id: 'owner-character-01', event_id: 'public-event-wrong-branch',
    encounter_instance_id: 'public-instance-wrong-branch', source_profile: 'HG_DROP_MACAQUE_PUBLIC',
    resource_table_version: 'economy-v2', pity_before: 0, resolution_branch: 'chance_success', roll_basis_points: 9999,
  });
  const beforeWrongBranch = wrongBranchStore.digest();
  const wrongBranchResult = materialize(baseline, authorities, wrongBranchStore, wrongBranchRare);
  equal(wrongBranchResult.status, 'rejected', 'a rare roll with inconsistent branch fails closed');
  equal(wrongBranchResult.code, 'rare_roll_resolution_branch_mismatch', 'wrong rare branch has a stable failure code');
  equal(wrongBranchResult.receipt, null, 'wrong rare branch cannot persist a partial receipt');
  equal(wrongBranchStore.digest(), beforeWrongBranch, 'wrong rare branch has no state side effect');

  const forcedPityStore = storeWithOwner('owner-character-01', (owner) => {
    owner.pity.PITY_HG_PUBLIC_GEAR = 4;
  });
  const forcedChest = requestBase(baseline, {
    authority_proof_ref: 'proof-forced-chest',
    event_id: 'public-event-forced',
    encounter_instance_id: 'public-instance-forced',
    event_type: 'participation_chest',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC',
    reward_slot_key: 'participation_chest',
    qualification_snapshot_id: 'p1-snapshot-forced',
  });
  installProof(authorities, forcedChest);
  authorities.qualifications.set('p1-snapshot-forced', publicSnapshot('p1-snapshot-forced', 'owner-character-01', 'public-event-forced', 'public-instance-forced'));
  const forcedChestResult = materialize(baseline, authorities, forcedPityStore, forcedChest);
  equal(forcedChestResult.status, 'committed', 'forced-pity fixture has an eligible settled chest');
  const forcedRare = requestBase(baseline, {
    authority_proof_ref: 'proof-forced-rare',
    event_id: 'public-event-forced',
    encounter_instance_id: 'public-instance-forced',
    event_type: 'public_rare_drop',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC',
    reward_slot_key: 'rare_drop',
    qualification_snapshot_id: 'p1-snapshot-forced',
    participation_chest_receipt_id: forcedChestResult.receipt.receipt_id,
    participation_chest_receipt_fingerprint: forcedChestResult.receipt.identity_fingerprint,
    drop_roll_id: 'public-roll-forced',
    drop_roll_proof_ref: 'public-roll-proof-forced',
  });
  installProof(authorities, forcedRare);
  authorities.rareRolls.set('public-roll-forced:public-roll-proof-forced', {
    drop_roll_id: 'public-roll-forced',
    drop_roll_proof_ref: 'public-roll-proof-forced',
    owner_id: 'owner-character-01',
    event_id: 'public-event-forced',
    encounter_instance_id: 'public-instance-forced',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC',
    resource_table_version: 'economy-v2',
    pity_before: 4,
    resolution_branch: 'pity_forced_success',
    roll_basis_points: 9999,
  });
  const forcedRareResult = materialize(baseline, authorities, forcedPityStore, forcedRare);
  equal(forcedRareResult.status, 'committed', 'guarantee threshold produces a committed rare receipt');
  equal(forcedRareResult.receipt.rare_roll_outcome, 'pity_forced_success', 'pity threshold forces success regardless of roll');
  equal(forcedRareResult.receipt.pity_before, 4, 'forced rare preserves pity before');
  equal(forcedRareResult.receipt.pity_after, 0, 'forced rare resets pity');
  deepEqual(forcedRareResult.receipt.unique_grants, ['EQ_HG_TRINKET_T1'], 'forced rare grants the frozen unique item');

  const capRareStore = storeWithOwner('owner-character-01', (owner) => {
    owner.balances.CUR_GOLD = 9999990;
    owner.unique_items.EQ_HG_TRINKET_T1 = true;
    owner.pity.PITY_HG_PUBLIC_GEAR = 2;
  });
  const capRareChest = requestBase(baseline, {
    authority_proof_ref: 'proof-cap-rare-chest',
    event_id: 'public-event-cap-rare',
    encounter_instance_id: 'public-instance-cap-rare',
    event_type: 'participation_chest',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC',
    reward_slot_key: 'participation_chest',
    qualification_snapshot_id: 'p1-snapshot-cap-rare',
  });
  installProof(authorities, capRareChest);
  authorities.qualifications.set('p1-snapshot-cap-rare', publicSnapshot('p1-snapshot-cap-rare', 'owner-character-01', 'public-event-cap-rare', 'public-instance-cap-rare'));
  const capRareChestResult = materialize(baseline, authorities, capRareStore, capRareChest);
  equal(capRareChestResult.receipt.award_outcome, 'balance_or_stack_cap_reached', 'cap-blocked eligible chest remains a terminal receipt');
  const capRare = requestBase(baseline, {
    authority_proof_ref: 'proof-cap-rare',
    event_id: 'public-event-cap-rare',
    encounter_instance_id: 'public-instance-cap-rare',
    event_type: 'public_rare_drop',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC',
    reward_slot_key: 'rare_drop',
    qualification_snapshot_id: 'p1-snapshot-cap-rare',
    participation_chest_receipt_id: capRareChestResult.receipt.receipt_id,
    participation_chest_receipt_fingerprint: capRareChestResult.receipt.identity_fingerprint,
    drop_roll_id: 'public-roll-cap',
    drop_roll_proof_ref: 'public-roll-proof-cap',
  });
  installProof(authorities, capRare);
  authorities.rareRolls.set('public-roll-cap:public-roll-proof-cap', {
    drop_roll_id: 'public-roll-cap',
    drop_roll_proof_ref: 'public-roll-proof-cap',
    owner_id: 'owner-character-01',
    event_id: 'public-event-cap-rare',
    encounter_instance_id: 'public-instance-cap-rare',
    source_profile: 'HG_DROP_MACAQUE_PUBLIC',
    resource_table_version: 'economy-v2',
    pity_before: 2,
    resolution_branch: 'chance_success',
    roll_basis_points: 1,
  });
  const capRareResult = materialize(baseline, authorities, capRareStore, capRare);
  equal(capRareResult.receipt.award_outcome, 'balance_or_stack_cap_reached', 'duplicate rare conversion obeys all-or-nothing cap');
  equal(capRareResult.receipt.pity_before, 2, 'cap-blocked rare persists pity before');
  equal(capRareResult.receipt.pity_after, 2, 'cap-blocked rare cannot advance or reset pity');
  equal(capRareStore.exportState().owners['owner-character-01'].pity.PITY_HG_PUBLIC_GEAR, 2, 'cap-blocked rare leaves pity state unchanged');

  const firstClear = requestBase(baseline, {
    authority_proof_ref: 'proof-dragon-first',
    event_id: 'dragon-event-1',
    encounter_instance_id: 'dragon-instance-1',
    event_type: 'first_clear_grant',
    source_profile: 'HG_DROP_DRAGON_OLD',
    reward_slot_key: 'first_clear',
  });
  installProof(authorities, firstClear);
  const firstClearResult = materialize(baseline, authorities, publicStore, firstClear);
  equal(firstClearResult.status, 'committed', 'ordinary first clear commits');
  equal(firstClearResult.receipt.first_clear_disposition, 'first_clear_granted', 'new first clear grants frozen unique item');
  deepEqual(firstClearResult.receipt.unique_grants, ['ART_HG_TIDE_SEAL'], 'first clear unique grant is table driven');

  const repeatedFirstClear = requestBase(baseline, {
    authority_proof_ref: 'proof-dragon-first-repeated', event_id: 'dragon-event-2',
    encounter_instance_id: 'dragon-instance-2', event_type: 'first_clear_grant',
    source_profile: 'HG_DROP_DRAGON_OLD', reward_slot_key: 'first_clear',
  });
  installProof(authorities, repeatedFirstClear);
  const beforeRepeatedFirstClear = publicStore.digest();
  const repeatedFirstClearResult = materialize(baseline, authorities, publicStore, repeatedFirstClear);
  equal(repeatedFirstClearResult.status, 'rejected', 'a consumed first-clear profile cannot commit a zero award');
  equal(repeatedFirstClearResult.code, 'first_clear_already_consumed', 'consumed first-clear has a stable rejection code');
  equal(repeatedFirstClearResult.receipt.award_outcome, 'rejected', 'consumed first-clear remains terminally rejected');
  equal(repeatedFirstClearResult.receipt.first_clear_disposition, 'not_consumed_zero_award', 'rejected first-clear records no new consumption');
  equal(publicStore.exportState().owners['owner-character-01'].unique_items.ART_HG_TIDE_SEAL, true, 'rejected first-clear does not alter the unique grant');
  truthy(publicStore.digest() !== beforeRepeatedFirstClear, 'rejected first-clear writes only its terminal receipt');

  const rejectedOriginAuthorities = setupAuthorities();
  const rejectedOriginStore = storeWithOwner('owner-character-01', (owner) => {
    owner.first_clear['profile:HG_DROP_DRAGON_OLD'] = true;
  });
  const rejectedOriginA = requestBase(baseline, {
    authority_proof_ref: 'proof-rejected-origin-a', event_id: 'rejected-origin-event',
    encounter_instance_id: 'rejected-origin-instance', event_type: 'first_clear_grant',
    source_profile: 'HG_DROP_DRAGON_OLD', reward_slot_key: 'first_clear',
  });
  installProof(rejectedOriginAuthorities, rejectedOriginA, 'owner-character-01');
  const rejectedOriginAResult = materialize(baseline, rejectedOriginAuthorities, rejectedOriginStore, rejectedOriginA);
  equal(rejectedOriginAResult.status, 'rejected', 'fixture establishes a terminal rejected source origin for owner A');
  const rejectedOriginB = { ...rejectedOriginA, authority_proof_ref: 'proof-rejected-origin-b' };
  installProof(rejectedOriginAuthorities, rejectedOriginB, 'owner-character-02');
  const beforeRejectedOriginB = rejectedOriginStore.digest();
  const rejectedOriginBResult = materialize(baseline, rejectedOriginAuthorities, rejectedOriginStore, rejectedOriginB);
  equal(rejectedOriginBResult.status, 'rejected', 'trusted authority binding rejects an owner switch even after a rejected receipt');
  equal(rejectedOriginBResult.receipt, null, 'rejected-origin owner switch cannot create owner-B receipt');
  equal(rejectedOriginStore.digest(), beforeRejectedOriginB, 'rejected-origin owner switch has no ledger side effect');
  equal(rejectedOriginStore.exportState().owners['owner-character-02'], undefined, 'rejected-origin owner switch cannot create owner-B state');

  const teamStore = createStore();
  const teamBundle = requestBase(baseline, {
    authority_proof_ref: 'proof-team-bundle',
    event_id: 'team-event-1',
    encounter_instance_id: 'team-instance-1',
    source_profile: 'HG_DROP_OX_RAID',
    qualification_snapshot_id: 'team-snapshot-1',
  });
  installProof(authorities, teamBundle);
  authorities.qualifications.set('team-snapshot-1', teamSnapshot('team-snapshot-1', 'owner-character-01', 'team-event-1', 'team-instance-1'));
  const teamBundleResult = materialize(baseline, authorities, teamStore, teamBundle);
  equal(teamBundleResult.status, 'committed', 'qualified Ox team base bundle commits');
  equal(teamBundleResult.receipt.balance_delta.CUR_RAID_MARK, 1, 'team bundle grants frozen raid mark');

  const malformedTeam = requestBase(baseline, {
    authority_proof_ref: 'proof-team-malformed', event_id: 'team-event-malformed',
    encounter_instance_id: 'team-instance-malformed', source_profile: 'HG_DROP_OX_RAID',
    qualification_snapshot_id: 'team-snapshot-malformed',
  });
  installProof(authorities, malformedTeam);
  const malformedTeamSnapshot = teamSnapshot('team-snapshot-malformed', 'owner-character-01', 'team-event-malformed', 'team-instance-malformed');
  delete malformedTeamSnapshot.members[0].contribution_attested;
  authorities.qualifications.set('team-snapshot-malformed', malformedTeamSnapshot);
  const beforeMalformedTeam = teamStore.digest();
  const malformedTeamResult = materialize(baseline, authorities, teamStore, malformedTeam);
  equal(malformedTeamResult.status, 'rejected', 'team snapshot member with a missing required field fails closed');
  equal(malformedTeamResult.receipt, null, 'malformed team snapshot cannot persist a partial receipt');
  equal(teamStore.digest(), beforeMalformedTeam, 'malformed team snapshot has no state side effect');

  const duplicateTeam = requestBase(baseline, {
    authority_proof_ref: 'proof-team-duplicate-owner', event_id: 'team-event-duplicate-owner',
    encounter_instance_id: 'team-instance-duplicate-owner', source_profile: 'HG_DROP_OX_RAID',
    qualification_snapshot_id: 'team-snapshot-duplicate-owner',
  });
  installProof(authorities, duplicateTeam);
  const duplicateTeamSnapshot = teamSnapshot('team-snapshot-duplicate-owner', 'owner-character-01', 'team-event-duplicate-owner', 'team-instance-duplicate-owner');
  duplicateTeamSnapshot.members.push({ ...duplicateTeamSnapshot.members[0], contribution_attested: false });
  authorities.qualifications.set('team-snapshot-duplicate-owner', duplicateTeamSnapshot);
  const beforeDuplicateTeam = teamStore.digest();
  const duplicateTeamResult = materialize(baseline, authorities, teamStore, duplicateTeam);
  equal(duplicateTeamResult.status, 'rejected', 'team snapshot with duplicate owner rows fails closed');
  equal(duplicateTeamResult.receipt, null, 'duplicate team owner rows cannot persist a partial receipt');
  equal(teamStore.digest(), beforeDuplicateTeam, 'duplicate team owner rows have no state side effect');

  const invalidTeam = requestBase(baseline, {
    authority_proof_ref: 'proof-team-bad',
    event_id: 'team-event-bad',
    encounter_instance_id: 'team-instance-bad',
    source_profile: 'HG_DROP_OX_RAID',
    qualification_snapshot_id: 'team-snapshot-bad',
  });
  installProof(authorities, invalidTeam);
  authorities.qualifications.set('team-snapshot-bad', teamSnapshot('team-snapshot-bad', 'owner-character-01', 'team-event-bad', 'team-instance-bad', {
    members: [{
      owner_id: 'owner-character-01',
      joined_before_lock: true,
      present_at_completion: true,
      actor_alive_at_completion: true,
      contribution_attested: false,
      rare_clear_attested: false,
    }],
  }));
  const teamRejected = materialize(baseline, authorities, teamStore, invalidTeam);
  equal(teamRejected.status, 'rejected', 'ineligible team member is terminal rejected');
  const teamDigestAfterRejected = teamStore.digest();
  authorities.qualifications.set('team-snapshot-bad', teamSnapshot('team-snapshot-bad', 'owner-character-01', 'team-event-bad', 'team-instance-bad'));
  const rejectedReplay = materialize(baseline, authorities, teamStore, invalidTeam);
  equal(rejectedReplay.status, 'rejected', 'corrected snapshot cannot reopen rejected identity');
  equal(rejectedReplay.replayed, true, 'rejected receipt is terminally replayed');
  equal(teamStore.digest(), teamDigestAfterRejected, 'rejected replay has no mutation');

  const teamRare = requestBase(baseline, {
    authority_proof_ref: 'proof-team-rare',
    event_id: 'team-event-2',
    encounter_instance_id: 'team-instance-2',
    event_type: 'team_raid_rare_drop',
    source_profile: 'HG_DROP_OX_RAID',
    reward_slot_key: 'rare_drop',
    qualification_snapshot_id: 'team-snapshot-2',
    drop_roll_id: 'team-roll-1',
    drop_roll_proof_ref: 'team-roll-proof-1',
  });
  installProof(authorities, teamRare);
  authorities.qualifications.set('team-snapshot-2', teamSnapshot('team-snapshot-2', 'owner-character-01', 'team-event-2', 'team-instance-2'));
  authorities.rareRolls.set('team-roll-1:team-roll-proof-1', {
    drop_roll_id: 'team-roll-1',
    drop_roll_proof_ref: 'team-roll-proof-1',
    owner_id: 'owner-character-01',
    event_id: 'team-event-2',
    encounter_instance_id: 'team-instance-2',
    source_profile: 'HG_DROP_OX_RAID',
    resource_table_version: 'economy-v2',
    pity_before: 0,
    resolution_branch: 'chance_success',
    roll_basis_points: 1,
  });
  const teamRareResult = materialize(baseline, authorities, teamStore, teamRare);
  equal(teamRareResult.status, 'committed', 'team rare trusted roll commits');
  equal(teamRareResult.receipt.rare_grant_disposition, 'granted', 'team rare grant disposition is frozen');
  deepEqual(teamRareResult.receipt.unique_grants, ['ART_HG_FLAME_CORE'], 'team rare unique is table driven');

  const outOfRangePityStore = storeWithOwner('owner-character-01', (owner) => {
    owner.pity.PITY_HG_RAID_ARTIFACT = 6;
  });
  const outOfRangePity = requestBase(baseline, {
    authority_proof_ref: 'proof-team-pity-out-of-range', event_id: 'team-event-pity-out-of-range',
    encounter_instance_id: 'team-instance-pity-out-of-range', event_type: 'team_raid_rare_drop',
    source_profile: 'HG_DROP_OX_RAID', reward_slot_key: 'rare_drop',
    qualification_snapshot_id: 'team-snapshot-pity-out-of-range',
    drop_roll_id: 'team-roll-pity-out-of-range', drop_roll_proof_ref: 'team-roll-proof-pity-out-of-range',
  });
  installProof(authorities, outOfRangePity);
  authorities.qualifications.set('team-snapshot-pity-out-of-range', teamSnapshot('team-snapshot-pity-out-of-range', 'owner-character-01', 'team-event-pity-out-of-range', 'team-instance-pity-out-of-range'));
  authorities.rareRolls.set('team-roll-pity-out-of-range:team-roll-proof-pity-out-of-range', {
    drop_roll_id: 'team-roll-pity-out-of-range', drop_roll_proof_ref: 'team-roll-proof-pity-out-of-range',
    owner_id: 'owner-character-01', event_id: 'team-event-pity-out-of-range',
    encounter_instance_id: 'team-instance-pity-out-of-range', source_profile: 'HG_DROP_OX_RAID',
    resource_table_version: 'economy-v2', pity_before: 6, resolution_branch: 'pity_forced_success', roll_basis_points: 1,
  });
  const beforeOutOfRangePity = outOfRangePityStore.digest();
  const outOfRangePityResult = materialize(baseline, authorities, outOfRangePityStore, outOfRangePity);
  equal(outOfRangePityResult.status, 'rejected', 'pity counter at the exclusive guarantee bound fails closed');
  equal(outOfRangePityResult.code, 'pity_state_out_of_range', 'out-of-range pity has a stable failure code');
  equal(outOfRangePityResult.receipt, null, 'out-of-range pity cannot produce a partial rare receipt');
  equal(outOfRangePityStore.digest(), beforeOutOfRangePity, 'out-of-range pity cannot reset or award');

  const xpStore = createStore();
  const xpBase = requestBase(baseline, {
    authority_proof_ref: 'proof-xp-base',
    event_id: 'xp-event-1',
    encounter_instance_id: 'xp-instance-1',
    event_type: 'experience',
    source_profile: 'XP_WATERFALL',
    reward_slot_key: 'xp_grant',
    xp_authority_ref: 'xp-authority-base',
  });
  installProof(authorities, xpBase);
  authorities.xpSettlements.set('xp-authority-base', {
    owner_id: 'owner-character-01',
    event_id: 'xp-event-1',
    encounter_instance_id: 'xp-instance-1',
    xp_source_key: 'XP_WATERFALL',
    xp_character_level_before: 7,
    xp_settlement_kind: 'base_clear',
    xp_session_id: 'xp-session-1',
  });
  const xpBaseResult = materialize(baseline, authorities, xpStore, xpBase);
  equal(xpBaseResult.status, 'committed', 'authoritative base XP commits');
  equal(xpBaseResult.receipt.experience_delta, 500, 'base XP exact formula is frozen');

  const xpRepeat = requestBase(baseline, {
    authority_proof_ref: 'proof-xp-repeat',
    event_id: 'xp-event-2',
    encounter_instance_id: 'xp-instance-2',
    event_type: 'experience',
    source_profile: 'XP_WATERFALL',
    reward_slot_key: 'xp_grant',
    xp_authority_ref: 'xp-authority-repeat',
  });
  installProof(authorities, xpRepeat);
  authorities.xpSettlements.set('xp-authority-repeat', {
    owner_id: 'owner-character-01',
    event_id: 'xp-event-2',
    encounter_instance_id: 'xp-instance-2',
    xp_source_key: 'XP_WATERFALL',
    xp_character_level_before: 7,
    xp_settlement_kind: 'repeat_clear',
    xp_session_id: 'xp-session-repeat',
  });
  const xpRepeatResult = materialize(baseline, authorities, xpStore, xpRepeat);
  equal(xpRepeatResult.status, 'committed', 'authoritative repeat XP commits once');
  equal(xpRepeatResult.receipt.experience_delta, 125, 'repeat XP rounds repeat multiplier then over-level multiplier');

  const xpDuplicateQuota = { ...xpRepeat, authority_proof_ref: 'proof-xp-repeat-2', event_id: 'xp-event-3', encounter_instance_id: 'xp-instance-3', xp_authority_ref: 'xp-authority-repeat-2' };
  installProof(authorities, xpDuplicateQuota);
  authorities.xpSettlements.set('xp-authority-repeat-2', {
    owner_id: 'owner-character-01',
    event_id: 'xp-event-3',
    encounter_instance_id: 'xp-instance-3',
    xp_source_key: 'XP_WATERFALL',
    xp_character_level_before: 7,
    xp_settlement_kind: 'repeat_clear',
    xp_session_id: 'xp-session-repeat',
  });
  const xpQuotaRejected = materialize(baseline, authorities, xpStore, xpDuplicateQuota);
  equal(xpQuotaRejected.status, 'rejected', 'same repeat XP quota cannot be consumed twice');
  equal(xpQuotaRejected.receipt.award_outcome, 'rejected', 'repeat quota refusal is terminal');

  const xpCap = requestBase(baseline, {
    authority_proof_ref: 'proof-xp-cap',
    event_id: 'xp-event-cap',
    encounter_instance_id: 'xp-instance-cap',
    event_type: 'experience',
    source_profile: 'XP_WATERFALL',
    reward_slot_key: 'xp_grant',
    xp_authority_ref: 'xp-authority-cap',
  });
  installProof(authorities, xpCap);
  authorities.xpSettlements.set('xp-authority-cap', {
    owner_id: 'owner-character-01',
    event_id: 'xp-event-cap',
    encounter_instance_id: 'xp-instance-cap',
    xp_source_key: 'XP_WATERFALL',
    xp_character_level_before: 60,
    xp_settlement_kind: 'repeat_clear',
    xp_session_id: 'xp-session-cap',
  });
  const xpCapResult = materialize(baseline, authorities, xpStore, xpCap);
  equal(xpCapResult.status, 'rejected', 'level-cap XP is terminal rejected');
  equal(xpCapResult.receipt.experience_delta, 0, 'level-cap receipt preserves zero XP audit value');
  equal(xpStore.exportState().owners['owner-character-01'].xp_repeat_quota['XP_WATERFALL:xp-session-cap'], undefined, 'level-cap rejection does not consume repeat quota');

  const xpNegativeLevel = { ...xpBase,
    authority_proof_ref: 'proof-xp-negative-level', event_id: 'xp-event-negative-level',
    encounter_instance_id: 'xp-instance-negative-level', xp_authority_ref: 'xp-authority-negative-level',
  };
  installProof(authorities, xpNegativeLevel);
  authorities.xpSettlements.set('xp-authority-negative-level', {
    owner_id: 'owner-character-01',
    event_id: 'xp-event-negative-level',
    encounter_instance_id: 'xp-instance-negative-level',
    xp_source_key: 'XP_WATERFALL',
    xp_character_level_before: -1,
    xp_settlement_kind: 'base_clear',
    xp_session_id: 'xp-session-negative-level',
  });
  const beforeNegativeXp = xpStore.digest();
  const xpNegativeLevelResult = materialize(baseline, authorities, xpStore, xpNegativeLevel);
  equal(xpNegativeLevelResult.status, 'rejected', 'an authority XP record below Lv1 fails closed');
  equal(xpNegativeLevelResult.code, 'xp_authority_binding_mismatch', 'invalid authority XP level has a stable rejection code');
  equal(xpNegativeLevelResult.receipt, null, 'invalid authority XP level cannot persist a partial receipt');
  equal(xpStore.digest(), beforeNegativeXp, 'invalid authority XP level has no state side effect');

  const towerStore = createStore();
  const towerFirst = requestBase(baseline, {
    authority_proof_ref: 'proof-tower-first',
    event_id: 'tower-event-1',
    encounter_instance_id: 'tower-run-1',
    event_type: 'tower_reward',
    source_profile: 'TOWER_FIRST_CYCLE_REWARD_V1',
    reward_slot_key: 'tower_cycle_reward',
    tower_snapshot_id: 'tower-snapshot-1',
  });
  installProof(authorities, towerFirst);
  authorities.towerSnapshots.set('tower-snapshot-1', towerSnapshot('tower-snapshot-1', 'owner-character-01', 'tower-event-1', 'tower-run-1', 'cycle-A', '2026-W30'));
  const towerFirstResult = materialize(baseline, authorities, towerStore, towerFirst);
  equal(towerFirstResult.status, 'committed', 'first tower cycle reward commits');
  equal(towerFirstResult.receipt.tower_award_class, 'first_clear', 'first tower class derived from history');
  equal(towerFirstResult.receipt.balance_delta.CUR_TOWER_TOKEN, 3, 'first tower token award is frozen');

  const malformedTower = { ...towerFirst, authority_proof_ref: 'proof-tower-malformed', event_id: 'tower-event-malformed', encounter_instance_id: 'tower-run-malformed', tower_snapshot_id: 'tower-snapshot-malformed' };
  installProof(authorities, malformedTower);
  const malformedTowerSnapshot = towerSnapshot('tower-snapshot-malformed', 'owner-character-01', 'tower-event-malformed', 'tower-run-malformed', 'cycle-malformed', '2026-W30');
  delete malformedTowerSnapshot.members[0].entry_level;
  authorities.towerSnapshots.set('tower-snapshot-malformed', malformedTowerSnapshot);
  const beforeMalformedTower = towerStore.digest();
  const malformedTowerResult = materialize(baseline, authorities, towerStore, malformedTower);
  equal(malformedTowerResult.status, 'rejected', 'tower snapshot member with no entry level fails closed');
  equal(malformedTowerResult.receipt, null, 'malformed tower snapshot cannot persist a partial receipt');
  equal(towerStore.digest(), beforeMalformedTower, 'malformed tower snapshot has no state side effect');

  const duplicateTower = { ...towerFirst, authority_proof_ref: 'proof-tower-duplicate-owner', event_id: 'tower-event-duplicate-owner', encounter_instance_id: 'tower-run-duplicate-owner', tower_snapshot_id: 'tower-snapshot-duplicate-owner' };
  installProof(authorities, duplicateTower);
  const duplicateTowerSnapshot = towerSnapshot('tower-snapshot-duplicate-owner', 'owner-character-01', 'tower-event-duplicate-owner', 'tower-run-duplicate-owner', 'cycle-duplicate-owner', '2026-W30');
  duplicateTowerSnapshot.members.push({ ...duplicateTowerSnapshot.members[0], eligible: false });
  authorities.towerSnapshots.set('tower-snapshot-duplicate-owner', duplicateTowerSnapshot);
  const beforeDuplicateTower = towerStore.digest();
  const duplicateTowerResult = materialize(baseline, authorities, towerStore, duplicateTower);
  equal(duplicateTowerResult.status, 'rejected', 'tower snapshot with duplicate owner rows fails closed');
  equal(duplicateTowerResult.receipt, null, 'duplicate tower owner rows cannot persist a partial receipt');
  equal(towerStore.digest(), beforeDuplicateTower, 'duplicate tower owner rows have no state side effect');

  const towerRepeat = { ...towerFirst, authority_proof_ref: 'proof-tower-repeat', event_id: 'tower-event-2', encounter_instance_id: 'tower-run-2', tower_snapshot_id: 'tower-snapshot-2' };
  installProof(authorities, towerRepeat);
  authorities.towerSnapshots.set('tower-snapshot-2', towerSnapshot('tower-snapshot-2', 'owner-character-01', 'tower-event-2', 'tower-run-2', 'cycle-A', '2026-W30'));
  const towerRepeatResult = materialize(baseline, authorities, towerStore, towerRepeat);
  equal(towerRepeatResult.receipt.tower_award_class, 'repeat_clear', 'later same cycle derives repeat class');
  equal(towerRepeatResult.receipt.balance_delta.CUR_TOWER_TOKEN, 1, 'repeat tower award is frozen');

  const towerCapStore = storeWithOwner('owner-character-01', (owner) => {
    owner.tower_weekly_tokens['2026-W30'] = 14;
  });
  const towerCap = { ...towerFirst, authority_proof_ref: 'proof-tower-cap', event_id: 'tower-event-cap', encounter_instance_id: 'tower-run-cap', tower_snapshot_id: 'tower-snapshot-cap' };
  installProof(authorities, towerCap);
  authorities.towerSnapshots.set('tower-snapshot-cap', towerSnapshot('tower-snapshot-cap', 'owner-character-01', 'tower-event-cap', 'tower-run-cap', 'cycle-cap', '2026-W30'));
  const towerCapResult = materialize(baseline, authorities, towerCapStore, towerCap);
  equal(towerCapResult.receipt.award_outcome, 'weekly_token_cap_reached', 'tower cap is exact terminal zero award');
  equal(towerCapResult.receipt.tower_weekly_token_before, 14, 'tower cap records frozen before value');
  equal(towerCapResult.receipt.tower_weekly_token_after, 14, 'tower cap does not consume weekly token capacity');
  equal(towerCapStore.exportState().owners['owner-character-01'].tower_first_clear['cycle-cap:first_cycle'], undefined, 'tower cap does not consume first clear');

  const beforeReservedTowerBuckets = towerStore.digest();
  for (const [index, reservedBucket] of ['__proto__', 'prototype', 'constructor', '__proto__', 'prototype', 'constructor'].entries()) {
    const reservedTower = {
      ...towerFirst,
      authority_proof_ref: `proof-tower-reserved-${index}`,
      event_id: `tower-event-reserved-${index}`,
      encounter_instance_id: `tower-run-reserved-${index}`,
      tower_snapshot_id: `tower-snapshot-reserved-${index}`,
    };
    installProof(authorities, reservedTower);
    authorities.towerSnapshots.set(reservedTower.tower_snapshot_id, towerSnapshot(
      reservedTower.tower_snapshot_id,
      'owner-character-01',
      reservedTower.event_id,
      reservedTower.encounter_instance_id,
      `cycle-reserved-${index}`,
      reservedBucket,
    ));
    const reservedTowerResult = materialize(baseline, authorities, towerStore, reservedTower);
    equal(reservedTowerResult.status, 'rejected', `${reservedBucket} tower bucket is rejected before settlement`);
    equal(reservedTowerResult.code, 'tower_snapshot_mismatch', `${reservedBucket} tower bucket has a stable fail-closed code`);
    equal(reservedTowerResult.receipt, null, `${reservedBucket} tower bucket cannot create a receipt`);
  }
  equal(towerStore.digest(), beforeReservedTowerBuckets, 'reserved tower buckets cannot change weekly capacity or award state');
  deepEqual(Object.keys(towerStore.exportState().owners['owner-character-01'].tower_weekly_tokens), ['2026-W30'], 'reserved tower buckets never become own weekly-token map keys');

  const atomicStore = createStore();
  const atomicRequest = requestBase(baseline, {
    authority_proof_ref: 'proof-atomic',
    event_id: 'atomic-event-1',
    encounter_instance_id: 'atomic-instance-1',
  });
  installProof(authorities, atomicRequest);
  const beforeAtomic = atomicStore.digest();
  let injected = false;
  try {
    materialize(baseline, authorities, atomicStore, atomicRequest, {
      failpoint(stage) {
        if (stage === 'after_mutation_before_receipt') {
          injected = true;
          throw new Error('injected-abort');
        }
      },
    });
  } catch (error) {
    equal(error.message, 'injected-abort', 'fault injection reaches in-transaction stage');
  }
  equal(injected, true, 'fault injection ran');
  equal(atomicStore.digest(), beforeAtomic, 'aborted transaction leaves no mutation or receipt');
  const atomicRetry = materialize(baseline, authorities, atomicStore, atomicRequest);
  equal(atomicRetry.status, 'committed', 'retry after abort may settle exactly once');

  process.stdout.write(`PASS: ${assertions} economy-v2 settlement assertions\n`);
}

run();
