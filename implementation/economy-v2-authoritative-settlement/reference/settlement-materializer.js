'use strict';

// economy-v2 offline acceptance reference.  This is deliberately a synchronous
// in-memory model: it proves table-driven decisions and terminal-receipt
// behavior without claiming to be a Y3 runtime or a production ledger.

const {
  OfflineTransactionStore,
  assert,
  canonicalJson,
  deepClone,
  originIdentity,
  ownerStateFor,
  saveTerminalReceipt,
  sha256,
} = require('./transaction-store-model');

const RECEIPT_SCHEMA_VERSION = 1;
const OWNER_SCOPE = 'character';
const DERIVATION_ID = 'ECO_AWARD_PLAN_DERIVATION_V2';
const XP_ROUNDING_RULE_ID = 'XP_FLOOR_REPEAT_THEN_OVERLEVEL_V1';
const FROZEN_RESOURCE_TABLE_SHA256 = '3288BD9CD1BFBB516DB4808EF002C45FECCF5F1C7F4C80499DB81E31B2F84EAE';
const FROZEN_RESOURCE_TABLE_CANONICAL_SHA256 = '22360E3F9782E0D4021FA53316811E47E28A685051498A40A566218CAE6E4934';
const FROZEN_RESOURCE_TABLE_RELATIVE_PATH = 'docs/物编/成长数值与经济裁决包/tables/economy-v2-resource-table.json';
const COMPILED_BASELINE_FORMAT = 'economy-v2-authoritative-settlement/offline-compiled-baseline/v1';
const COMPILED_BASELINE_STATUS = 'offline-acceptance-reference-only';

const INLINE_CONTROLLED_FIELDS = new Set([
  'owner_id', 'client_supplied_owner_id', 'balance_delta', 'material_delta',
  'unique_grants', 'award_plan_hash', 'receipt_id', 'commit_state',
  'award_outcome', 'pity_before', 'pity_after', 'first_clear_disposition',
  'rare_roll_outcome', 'rare_grant_disposition', 'experience_delta',
  'p1_policy_id', 'tower_award_class', 'tower_run_id', 'tower_cycle_id',
  'tower_week_bucket', 'tower_mode', 'tower_weekly_token_before',
  'tower_weekly_token_after', 'qualification_snapshot', 'team_snapshot',
  'tower_snapshot', 'xp_source_kind', 'xp_base_amount', 'xp_source_level',
  'xp_over_level_multiplier_basis_points', 'xp_repeat_multiplier_basis_points',
  'xp_settlement_kind', 'xp_session_id', 'xp_rounding_rule_id',
]);

const COMMON_REQUEST_FIELDS = new Set([
  'resource_table_version', 'resource_table_file_sha256', 'actor_id',
  'lifecycle_id', 'authority_proof_ref', 'event_id', 'encounter_instance_id',
  'event_type', 'source_profile', 'reward_slot_key',
]);

const EVENT_REQUEST_FIELDS = {
  drop_bundle: new Set(['qualification_snapshot_id']),
  first_clear_grant: new Set([
    'qualification_snapshot_id', 'participation_chest_receipt_id',
    'participation_chest_receipt_fingerprint',
  ]),
  participation_chest: new Set(['qualification_snapshot_id']),
  public_rare_drop: new Set([
    'qualification_snapshot_id', 'participation_chest_receipt_id',
    'participation_chest_receipt_fingerprint', 'drop_roll_id',
    'drop_roll_proof_ref',
  ]),
  team_raid_rare_drop: new Set([
    'qualification_snapshot_id', 'drop_roll_id', 'drop_roll_proof_ref',
  ]),
  experience: new Set(['xp_authority_ref']),
  tower_reward: new Set(['tower_snapshot_id']),
};

const TIDE_TRACE_INTENT_FIELDS = new Set([
  'schema_version', 'source_event_type', 'event_type', 'source_profile',
  'reward_slot_key', 'event_id', 'actor_id', 'lifecycle_id', 'encounter_key',
  'encounter_instance_id', 'target_id', 'target_lifecycle_id',
  'encounter_action_key', 'action_token', 'combat_scope', 'completed_tick',
  'authority_proof_ref', 'source_identity_fingerprint', 'target_scope',
  'credit_personal_progress', 'rare_eligibility',
]);

// These identifiers are later used as keys in JSON-derived ledger maps.  A
// syntactically valid JavaScript property name is not necessarily a safe map
// key: __proto__, constructor, and Object.prototype names have special
// behavior on ordinary objects.  Keep the rejection shared by request,
// authority, snapshot, and frozen-table identifiers.
const UNSAFE_OBJECT_PROPERTY_KEYS = new Set([
  ...Object.getOwnPropertyNames(Object.prototype),
  '__proto__',
  'constructor',
  'prototype',
]);

// authority_proof_ref deliberately remains outside this projection.  The
// generic receipt contract re-verifies a new valid proof on replay but does
// not let a rotated proof create a second economic identity.  Everything else
// below is immutable Tide Trace completion evidence and must stay stable.
const TIDE_TRACE_ATTESTATION_FIELDS = [
  'schema_version', 'source_event_type', 'event_type', 'source_profile', 'reward_slot_key',
  'event_id', 'actor_id', 'lifecycle_id', 'encounter_key', 'encounter_instance_id',
  'target_id', 'target_lifecycle_id', 'encounter_action_key', 'action_token', 'combat_scope',
  'completed_tick', 'source_identity_fingerprint', 'target_scope', 'credit_personal_progress',
  'rare_eligibility',
];

class PolicyFailure extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

function fail(code) {
  throw new PolicyFailure(code);
}

function hasOwn(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key);
}

function isNonEmptyString(value) {
  return typeof value === 'string' && value.length > 0;
}

function isCanonicalIdentifier(value) {
  return isNonEmptyString(value) && /^[A-Za-z0-9_.:-]+$/.test(value) &&
    !UNSAFE_OBJECT_PROPERTY_KEYS.has(value);
}

function requireString(value, field) {
  if (!isNonEmptyString(value)) {
    fail(`invalid_${field}`);
  }
  return value;
}

function requireIdentifier(value, field) {
  if (!isCanonicalIdentifier(value)) {
    fail(`invalid_${field}`);
  }
  return value;
}

function requireLifecycle(value) {
  if (!(isCanonicalIdentifier(value) || (Number.isSafeInteger(value) && value >= 0))) {
    fail('invalid_lifecycle_id');
  }
  return value;
}

function requireInteger(value, field) {
  if (!Number.isSafeInteger(value)) {
    fail(`invalid_${field}`);
  }
  return value;
}

function maybeString(value, field) {
  if (value !== undefined && value !== null && !isNonEmptyString(value)) {
    fail(`invalid_${field}`);
  }
  return value === undefined ? null : value;
}

function requireObject(value, field) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    fail(`invalid_${field}`);
  }
  return value;
}

function readNonNegativeCounter(map, key, code) {
  const value = hasOwn(map, key) ? map[key] : 0;
  if (!Number.isSafeInteger(value) || value < 0) {
    fail(code);
  }
  return value;
}

function tideTraceCanonicalProjection(intent) {
  const projection = {};
  for (const field of TIDE_TRACE_ATTESTATION_FIELDS) {
    projection[field] = intent[field];
  }
  return projection;
}

function tideTraceCanonicalDigest(intent) {
  return sha256(canonicalJson(tideTraceCanonicalProjection(intent)));
}

function normalizeTideTraceAuthorityAttestation(value, frozenIntent) {
  const attestation = normalizeOfflineTideTraceReceiptAttestation(value);
  if (attestation.tide_trace_canonical_digest !== tideTraceCanonicalDigest(frozenIntent)) {
    fail('tide_trace_authority_attestation_mismatch');
  }
  return attestation;
}

function normalizeOfflineTideTraceReceiptAttestation(value) {
  const attestation = detachJsonValue(value, 'invalid_tide_trace_authority_attestation');
  if (attestation === null || typeof attestation !== 'object' || Array.isArray(attestation) ||
      Object.keys(attestation).length !== 2 ||
      !hasOwn(attestation, 'tide_trace_attestation_ref') ||
      !hasOwn(attestation, 'tide_trace_canonical_digest')) {
    fail('invalid_tide_trace_authority_attestation');
  }
  const ref = requireIdentifier(attestation.tide_trace_attestation_ref, 'tide_trace_attestation_ref');
  const digest = requireString(attestation.tide_trace_canonical_digest, 'tide_trace_canonical_digest');
  if (!/^[0-9a-f]{64}$/.test(digest)) {
    fail('invalid_tide_trace_authority_attestation');
  }
  return {
    tide_trace_attestation_ref: ref,
    tide_trace_canonical_digest: digest,
  };
}

// Public request/intent objects may be accessor-backed or Proxy-backed.  Read
// them once into a canonical JSON value before validation so no later phase can
// observe a different owner/profile/event than the proof resolver observed.
function detachJsonValue(value, code) {
  try {
    return JSON.parse(canonicalJson(value));
  } catch (_) {
    fail(code);
  }
}

function assertExactKeys(value, requiredKeys, code) {
  const keys = Object.keys(value).sort();
  const expected = [...requiredKeys].sort();
  if (keys.length !== expected.length || keys.some((key, index) => key !== expected[index])) {
    fail(code);
  }
}

function isBoolean(value) {
  return value === true || value === false;
}

function cloneWithoutTransportFields(request) {
  const filtered = {};
  for (const key of Object.keys(request)) {
    if (key !== 'actor_id' && key !== 'lifecycle_id' && key !== 'authority_proof_ref') {
      filtered[key] = request[key];
    }
  }
  return filtered;
}

function readTable(compiledBaseline) {
  const baseline = detachJsonValue(compiledBaseline, 'invalid_compiled_baseline');
  const table = baseline && (baseline.resource_table || baseline.table);
  if (table === null || typeof table !== 'object' || Array.isArray(table)) {
    throw new Error('compiled baseline lacks resource_table');
  }
  const source = baseline.source || {};
  if (baseline.baseline_schema_version !== 1 ||
      baseline.compiler_id !== 'economy-v2-authoritative-settlement-offline-compiler-v1' ||
      baseline.format !== COMPILED_BASELINE_FORMAT ||
      baseline.package_status !== COMPILED_BASELINE_STATUS ||
      table.resource_table_version !== 'economy-v2' ||
      table.runtime_handoff !== false || table.production_gate !== 'closed' ||
      source.relative_path !== FROZEN_RESOURCE_TABLE_RELATIVE_PATH ||
      source.resource_table_version !== 'economy-v2' ||
      source.runtime_handoff !== false || source.production_gate !== 'closed' ||
      source.resource_table_file_sha256 !== FROZEN_RESOURCE_TABLE_SHA256 ||
      sha256(canonicalJson(table)).toUpperCase() !== FROZEN_RESOURCE_TABLE_CANONICAL_SHA256) {
    throw new Error('compiled baseline violates economy-v2 closed-gate contract');
  }
  return { table, source };
}

function makeIndexes(table) {
  const drops = table.drops_and_pity || {};
  const currencies = (table.currencies_and_materials || {}).currencies || [];
  const materials = (table.currencies_and_materials || {}).material_keys || [];
  const progression = table.progression || {};
  const profiles = new Map();
  const bundles = new Map(Object.entries(drops.reward_bundles || {}));
  const currencyCaps = new Map(currencies.map((entry) => [entry.currency_key, entry.balance_cap]));
  const materialCaps = new Map(materials.map((entry) => [entry.material_key, entry.stack_cap]));
  const xpRows = new Map((progression.huaguoshan_source_rows || []).map((entry) => [entry.source_key, entry]));
  for (const profile of drops.profiles || drops.source_profiles || []) {
    profiles.set(profile.profile_key, profile);
  }
  const receipt = table.persistent_receipt_contract || {};
  if (profiles.size === 0 || bundles.size === 0 || xpRows.size === 0 ||
      currencyCaps.size === 0 || materialCaps.size === 0 ||
      receipt.schema_version !== 1) {
    throw new Error('compiled economy-v2 table lacks required indexes');
  }
  return { profiles, bundles, currencyCaps, materialCaps, xpRows, receipt, progression };
}

function initializeReceipt(context) {
  return {
    schema_version: RECEIPT_SCHEMA_VERSION,
    resource_table_version: context.table.resource_table_version,
    owner_scope: OWNER_SCOPE,
    owner_id: context.owner_id,
    event_id: context.request.event_id,
    event_type: context.request.event_type,
    source_profile: context.request.source_profile,
    reward_slot_key: context.request.reward_slot_key,
    encounter_instance_id: context.request.encounter_instance_id,
    qualification_snapshot_id: null,
    p1_policy_id: null,
    drop_roll_id: null,
    drop_roll_proof_ref: null,
    pity_pool_key: null,
    participation_chest_receipt_id: null,
    participation_chest_receipt_fingerprint: null,
    first_clear_disposition: null,
    rare_roll_outcome: null,
    rare_grant_disposition: null,
    xp_source_key: null,
    xp_source_kind: null,
    xp_base_amount: null,
    xp_source_level: null,
    xp_character_level_before: null,
    xp_over_level_multiplier_basis_points: null,
    xp_repeat_multiplier_basis_points: null,
    xp_settlement_kind: null,
    xp_rounding_rule_id: null,
    xp_session_id: null,
    experience_delta: null,
    tower_run_id: null,
    tower_cycle_id: null,
    tower_week_bucket: null,
    tower_mode: null,
    tower_award_class: null,
    tower_weekly_token_before: null,
    tower_weekly_token_after: null,
    balance_delta: {},
    material_delta: {},
    unique_grants: [],
    pity_before: null,
    pity_after: null,
    authority_proof_ref: context.request.authority_proof_ref,
    receipt_id: `economy-v2:${sha256(context.identity)}`,
    commit_state: 'committed',
    award_outcome: 'awarded',
    identity_fingerprint: null,
    offline_request_fingerprint: null,
    offline_award_plan: null,
    offline_origin_key: null,
  };
}

function fingerprintProjection(receipt, receiptContract) {
  const result = {};
  for (const field of receiptContract.identity_fingerprint_fields || []) {
    result[field] = receipt[field];
  }
  return result;
}

function finishReceipt(context, receipt, plan, requestFingerprint) {
  receipt.offline_award_plan = deepClone(plan);
  receipt.award_plan_hash = sha256(canonicalJson(plan));
  receipt.offline_request_fingerprint = requestFingerprint;
  receipt.identity_fingerprint = sha256(canonicalJson(fingerprintProjection(receipt, context.indexes.receipt)));
  return receipt;
}

function semanticIdentity(ownerId, request) {
  return `economy-v2:${sha256(canonicalJson([
    OWNER_SCOPE,
    ownerId,
    request.encounter_instance_id,
    request.event_id,
    request.source_profile,
    request.reward_slot_key,
  ]))}`;
}

function assertRequestShape(request) {
  if (request === null || typeof request !== 'object' || Array.isArray(request)) {
    fail('invalid_request');
  }
  for (const field of INLINE_CONTROLLED_FIELDS) {
    if (hasOwn(request, field)) {
      fail(`client_controlled_${field}`);
    }
  }
  for (const field of COMMON_REQUEST_FIELDS) {
    if (!hasOwn(request, field)) {
      fail(`missing_${field}`);
    }
  }
  requireIdentifier(request.actor_id, 'actor_id');
  requireLifecycle(request.lifecycle_id);
  requireIdentifier(request.authority_proof_ref, 'authority_proof_ref');
  requireIdentifier(request.event_id, 'event_id');
  requireIdentifier(request.encounter_instance_id, 'encounter_instance_id');
  requireIdentifier(request.event_type, 'event_type');
  requireIdentifier(request.source_profile, 'source_profile');
  requireIdentifier(request.reward_slot_key, 'reward_slot_key');
  requireString(request.resource_table_version, 'resource_table_version');
  requireString(request.resource_table_file_sha256, 'resource_table_file_sha256');
  const allowed = new Set([...COMMON_REQUEST_FIELDS, ...(EVENT_REQUEST_FIELDS[request.event_type] || [])]);
  if (!EVENT_REQUEST_FIELDS[request.event_type]) {
    fail('unsupported_event_type');
  }
  for (const key of Object.keys(request)) {
    if (!allowed.has(key)) {
      fail(`unexpected_request_field_${key}`);
    }
  }
}

function normalizeAuthorityResult(value, request, authorityOriginKey) {
  const result = requireObject(value, 'authority_result');
  const ownerId = requireIdentifier(result.owner_id, 'resolved_owner_id');
  if (ownerId === request.actor_id || ownerId === String(request.lifecycle_id)) {
    fail('raw_identity_cannot_be_owner');
  }
  for (const [field, expected] of Object.entries({
    actor_id: request.actor_id,
    lifecycle_id: request.lifecycle_id,
    event_id: request.event_id,
    encounter_instance_id: request.encounter_instance_id,
  })) {
    if (result[field] !== expected) {
      fail(`authority_${field}_mismatch`);
    }
  }
  if (result.source_profile !== request.source_profile) {
    fail('authority_source_profile_mismatch');
  }
  if (result.event_type !== request.event_type) {
    fail('authority_event_type_mismatch');
  }
  if (result.authority_origin_key !== authorityOriginKey || result.origin_owner_binding_verified !== true) {
    fail('authority_origin_owner_binding_mismatch');
  }
  return ownerId;
}

function enforceFrozenBaseline(context) {
  if (context.request.resource_table_version !== context.source.resource_table_version ||
      context.request.resource_table_file_sha256 !== context.source.resource_table_file_sha256) {
    fail('resource_table_binding_mismatch');
  }
}

function enforceCanonicalEvent(context) {
  const contract = context.indexes.receipt.canonical_receipt_field_contract || {};
  const sourceRule = (contract.source_profile_by_event_type || {})[context.request.event_type];
  const slot = (contract.reward_slot_key_by_event_type || {})[context.request.event_type];
  if (!sourceRule || context.request.reward_slot_key !== slot) {
    fail('canonical_event_binding_mismatch');
  }
  if (sourceRule.required_value && context.request.source_profile !== sourceRule.required_value) {
    fail('canonical_source_profile_mismatch');
  }
  if (sourceRule.allowed_values && !sourceRule.allowed_values.includes(context.request.source_profile)) {
    fail('canonical_source_profile_mismatch');
  }
}

function getProfile(context) {
  const profile = context.indexes.profiles.get(context.request.source_profile);
  if (!profile) {
    fail('unknown_source_profile');
  }
  return profile;
}

function emptyPlan() {
  return {
    balance_delta: {},
    material_delta: {},
    unique_grants: [],
    mutations: {},
    receipt_fields: {},
    award_outcome: 'awarded',
    derivation: {},
  };
}

function applyAwardsToPlan(context, plan, awardEntries) {
  for (const entry of awardEntries) {
    if (!entry || !isCanonicalIdentifier(entry.key) || !Number.isSafeInteger(entry.amount) || entry.amount < 0) {
      fail('invalid_frozen_award_entry');
    }
    if (context.indexes.currencyCaps.has(entry.key)) {
      plan.balance_delta[entry.key] = readNonNegativeCounter(
        plan.balance_delta, entry.key, 'invalid_plan_balance_counter') + entry.amount;
    } else if (context.indexes.materialCaps.has(entry.key)) {
      plan.material_delta[entry.key] = readNonNegativeCounter(
        plan.material_delta, entry.key, 'invalid_plan_material_counter') + entry.amount;
    } else {
      fail('frozen_award_uses_unknown_ledger_key');
    }
  }
}

function canApplyAwards(context, owner, plan) {
  for (const [key, amount] of Object.entries(plan.balance_delta)) {
    if (readNonNegativeCounter(owner.balances, key, 'invalid_owner_balance_counter') + amount > context.indexes.currencyCaps.get(key)) {
      return false;
    }
  }
  for (const [key, amount] of Object.entries(plan.material_delta)) {
    if (readNonNegativeCounter(owner.materials, key, 'invalid_owner_material_counter') + amount > context.indexes.materialCaps.get(key)) {
      return false;
    }
  }
  return true;
}

function zeroForCap(plan, outcome) {
  plan.balance_delta = {};
  plan.material_delta = {};
  plan.unique_grants = [];
  plan.mutations = {};
  plan.award_outcome = outcome;
  return plan;
}

function qualifyPublicSnapshot(context, snapshot, requireRare, receipt) {
  const tableQualification = context.table.qualification || {};
  const policyId = tableQualification.final_policy_id;
  assertExactKeys(snapshot, tableQualification.public_qualification_snapshot_required_fields || [], 'public_qualification_snapshot_field_mismatch');
  if (!snapshot || snapshot.schema_version !== 1 || snapshot.policy_id !== policyId ||
      snapshot.snapshot_id !== context.request.qualification_snapshot_id ||
      snapshot.owner_id !== context.owner_id || snapshot.encounter_instance_id !== context.request.encounter_instance_id ||
      snapshot.event_id !== context.request.event_id ||
      snapshot.boss_instance_id !== context.request.encounter_instance_id ||
      !isCanonicalIdentifier(snapshot.snapshot_id) || !isCanonicalIdentifier(snapshot.owner_id) ||
      !isCanonicalIdentifier(snapshot.phase_id) || !isCanonicalIdentifier(snapshot.action_window_id) ||
      !isCanonicalIdentifier(snapshot.authority_proof_ref) ||
      !Number.isFinite(snapshot.damage_ratio) || snapshot.damage_ratio < 0 || snapshot.damage_ratio > 1 ||
      !isBoolean(snapshot.public_action_window_opened) || !isBoolean(snapshot.valid_break) ||
      !isBoolean(snapshot.valid_guard) || !isBoolean(snapshot.valid_public_action) || !isBoolean(snapshot.rare_clear_attested)) {
    fail('public_qualification_snapshot_mismatch');
  }
  if (receipt) {
    receipt.qualification_snapshot_id = snapshot.snapshot_id;
  }
  const threshold = typeof snapshot.damage_ratio === 'number' && snapshot.damage_ratio >= 0.03;
  const contribution = threshold || snapshot.valid_break === true || snapshot.valid_guard === true;
  const qualified = snapshot.public_action_window_opened === true
    ? snapshot.valid_public_action === true && contribution
    : contribution;
  if (!qualified || (requireRare && snapshot.rare_clear_attested !== true)) {
    fail('public_qualification_not_eligible');
  }
  return snapshot;
}

function resolvePublicSnapshot(context, requireRare, receipt) {
  const id = requireIdentifier(context.request.qualification_snapshot_id, 'qualification_snapshot_id');
  if (typeof context.authorities.resolveQualificationSnapshot !== 'function') {
    fail('missing_qualification_snapshot_resolver');
  }
  const snapshot = context.authorities.resolveQualificationSnapshot(id, {
    owner_id: context.owner_id,
    event_id: context.request.event_id,
    encounter_instance_id: context.request.encounter_instance_id,
    source_profile: context.request.source_profile,
  });
  return qualifyPublicSnapshot(context, requireObject(snapshot, 'qualification_snapshot'), requireRare, receipt);
}

function resolveTeamSnapshot(context, requireRare, receipt) {
  const id = requireIdentifier(context.request.qualification_snapshot_id, 'qualification_snapshot_id');
  if (typeof context.authorities.resolveQualificationSnapshot !== 'function') {
    fail('missing_qualification_snapshot_resolver');
  }
  const snapshot = requireObject(context.authorities.resolveQualificationSnapshot(id, {
    owner_id: context.owner_id,
    event_id: context.request.event_id,
    encounter_instance_id: context.request.encounter_instance_id,
    source_profile: context.request.source_profile,
  }), 'qualification_snapshot');
  const expected = (((context.table.qualification || {}).team_raid_policy) || {});
  assertExactKeys(snapshot, expected.required_snapshot_fields || [], 'team_raid_snapshot_field_mismatch');
  if (snapshot.schema_version !== 1 || snapshot.policy_id !== expected.policy_id ||
      snapshot.snapshot_id !== id || snapshot.raid_instance_id !== context.request.encounter_instance_id ||
      snapshot.completion_event_id !== context.request.event_id ||
      snapshot.profile_key !== context.request.source_profile || snapshot.completed !== true ||
      !Array.isArray(snapshot.members) || snapshot.members.length < 1 || snapshot.members.length > 4 ||
      !isCanonicalIdentifier(snapshot.snapshot_id) || !isCanonicalIdentifier(snapshot.raid_instance_id) ||
      !isCanonicalIdentifier(snapshot.completion_event_id) || !isCanonicalIdentifier(snapshot.profile_key) ||
      !isCanonicalIdentifier(snapshot.authority_proof_ref) || !isBoolean(snapshot.completed) || !isBoolean(snapshot.rare_clear_attested)) {
    fail('team_raid_snapshot_mismatch');
  }
  const memberOwners = new Set();
  for (const entry of snapshot.members) {
    requireObject(entry, 'team_raid_member');
    assertExactKeys(entry, expected.required_member_fields || [], 'team_raid_member_field_mismatch');
    if (!isCanonicalIdentifier(entry.owner_id) || !isBoolean(entry.joined_before_lock) ||
        !isBoolean(entry.present_at_completion) || !isBoolean(entry.actor_alive_at_completion) ||
        !isBoolean(entry.contribution_attested) || !isBoolean(entry.rare_clear_attested)) {
      fail('team_raid_member_schema_mismatch');
    }
    if (memberOwners.has(entry.owner_id)) {
      fail('team_raid_member_duplicate_owner');
    }
    memberOwners.add(entry.owner_id);
  }
  if (receipt) {
    receipt.qualification_snapshot_id = snapshot.snapshot_id;
  }
  const member = snapshot.members.find((entry) => entry && entry.owner_id === context.owner_id);
  if (!member || member.joined_before_lock !== true || member.present_at_completion !== true ||
      member.actor_alive_at_completion !== true || member.contribution_attested !== true ||
      (requireRare && (snapshot.rare_clear_attested !== true || member.rare_clear_attested !== true))) {
    fail('team_raid_member_not_eligible');
  }
  return snapshot;
}

function bindPublicChest(context, receipt) {
  const receiptId = requireString(context.request.participation_chest_receipt_id, 'participation_chest_receipt_id');
  const fingerprint = requireString(context.request.participation_chest_receipt_fingerprint, 'participation_chest_receipt_fingerprint');
  const chest = context.store.readReceiptById(receiptId);
  if (!chest || chest.commit_state !== 'committed' || chest.event_type !== 'participation_chest' ||
      chest.owner_id !== context.owner_id || chest.event_id !== context.request.event_id ||
      chest.encounter_instance_id !== context.request.encounter_instance_id ||
      chest.qualification_snapshot_id !== context.request.qualification_snapshot_id ||
      chest.source_profile !== context.request.source_profile ||
      chest.resource_table_version !== context.table.resource_table_version ||
      chest.identity_fingerprint !== fingerprint) {
    fail('participation_chest_binding_mismatch');
  }
  receipt.participation_chest_receipt_id = receiptId;
  receipt.participation_chest_receipt_fingerprint = fingerprint;
}

function deriveBundle(context, owner, receipt) {
  const profile = getProfile(context);
  if (profile.scope === 'public_boss') {
    fail('public_profile_requires_participation_chest');
  }
  if (profile.scope === 'team_raid') {
    const snapshot = resolveTeamSnapshot(context, false, receipt);
    receipt.qualification_snapshot_id = snapshot.snapshot_id;
  } else if (hasOwn(context.request, 'qualification_snapshot_id')) {
    fail('ordinary_bundle_forbids_snapshot');
  }
  const bundle = context.indexes.bundles.get(profile.bundle);
  if (!Array.isArray(bundle)) {
    fail('missing_frozen_bundle');
  }
  const plan = emptyPlan();
  applyAwardsToPlan(context, plan, bundle);
  plan.derivation = { derivation_id: DERIVATION_ID, event_type: 'drop_bundle', profile: profile.profile_key, bundle: profile.bundle };
  if (!canApplyAwards(context, owner, plan)) {
    zeroForCap(plan, 'balance_or_stack_cap_reached');
  }
  return plan;
}

function deriveParticipationChest(context, owner, receipt) {
  const profile = getProfile(context);
  if (profile.scope !== 'public_boss') {
    fail('participation_chest_requires_public_profile');
  }
  receipt.p1_policy_id = (context.table.qualification || {}).final_policy_id;
  const snapshot = resolvePublicSnapshot(context, false, receipt);
  const plan = emptyPlan();
  const bundle = context.indexes.bundles.get(profile.bundle);
  if (!Array.isArray(bundle)) {
    fail('missing_frozen_bundle');
  }
  applyAwardsToPlan(context, plan, bundle);
  plan.derivation = {
    derivation_id: DERIVATION_ID,
    event_type: 'participation_chest',
    profile: profile.profile_key,
    bundle: profile.bundle,
    qualification_snapshot_id: snapshot.snapshot_id,
    p1_policy_id: receipt.p1_policy_id,
  };
  if (!canApplyAwards(context, owner, plan)) {
    zeroForCap(plan, 'balance_or_stack_cap_reached');
  }
  return plan;
}

function deriveFirstClear(context, owner, receipt) {
  const profile = getProfile(context);
  receipt.first_clear_disposition = 'not_consumed_zero_award';
  if (!profile.first_clear) {
    fail('profile_has_no_first_clear');
  }
  if (profile.scope === 'public_boss') {
    const snapshot = resolvePublicSnapshot(context, false, receipt);
    receipt.qualification_snapshot_id = snapshot.snapshot_id;
    bindPublicChest(context, receipt);
  } else if (profile.scope === 'team_raid') {
    const snapshot = resolveTeamSnapshot(context, false, receipt);
    receipt.qualification_snapshot_id = snapshot.snapshot_id;
  } else if (hasOwn(context.request, 'qualification_snapshot_id') ||
             hasOwn(context.request, 'participation_chest_receipt_id') ||
             hasOwn(context.request, 'participation_chest_receipt_fingerprint')) {
    fail('ordinary_first_clear_forbids_snapshot');
  }
  const historyKey = `profile:${profile.profile_key}`;
  const plan = emptyPlan();
  plan.derivation = { derivation_id: DERIVATION_ID, event_type: 'first_clear_grant', profile: profile.profile_key };
  if (owner.first_clear[historyKey] === true) {
    fail('first_clear_already_consumed');
  }
  const first = profile.first_clear;
  if (owner.unique_items[first.key] === true) {
    receipt.first_clear_disposition = 'duplicate_conversion';
    applyAwardsToPlan(context, plan, [first.duplicate_conversion]);
  } else {
    receipt.first_clear_disposition = 'first_clear_granted';
    plan.unique_grants = [first.key];
    plan.mutations.first_clear_key = historyKey;
    plan.mutations.unique_grant = first.key;
  }
  plan.derivation.disposition = receipt.first_clear_disposition;
  if (!canApplyAwards(context, owner, plan)) {
    receipt.first_clear_disposition = 'not_consumed_zero_award';
    plan.derivation.disposition = receipt.first_clear_disposition;
    zeroForCap(plan, 'balance_or_stack_cap_reached');
  } else {
    plan.mutations.first_clear_key = historyKey;
  }
  return plan;
}

function resolveRareRoll(context, profile, pityBefore) {
  const id = requireIdentifier(context.request.drop_roll_id, 'drop_roll_id');
  const proof = requireIdentifier(context.request.drop_roll_proof_ref, 'drop_roll_proof_ref');
  if (typeof context.authorities.resolveRareRoll !== 'function') {
    fail('missing_rare_roll_resolver');
  }
  const result = requireObject(context.authorities.resolveRareRoll(id, proof, {
    owner_id: context.owner_id,
    event_id: context.request.event_id,
    encounter_instance_id: context.request.encounter_instance_id,
    source_profile: context.request.source_profile,
    resource_table_version: context.table.resource_table_version,
  }), 'rare_roll');
  if (result.drop_roll_id !== id || result.drop_roll_proof_ref !== proof ||
      result.owner_id !== context.owner_id || result.event_id !== context.request.event_id ||
      result.encounter_instance_id !== context.request.encounter_instance_id ||
      result.source_profile !== profile.profile_key ||
       result.resource_table_version !== context.table.resource_table_version ||
       result.pity_before !== pityBefore ||
       !['miss', 'chance_success', 'pity_forced_success'].includes(result.resolution_branch) ||
       !Number.isSafeInteger(result.roll_basis_points) || result.roll_basis_points < 1 || result.roll_basis_points > 10000) {
    fail('rare_roll_binding_mismatch');
  }
  return result;
}

function deriveRare(context, owner, receipt, publicRare) {
  const profile = getProfile(context);
  if ((publicRare && profile.scope !== 'public_boss') || (!publicRare && profile.scope !== 'team_raid') || !profile.rare) {
    fail('rare_profile_scope_mismatch');
  }
  let snapshot;
  if (publicRare) {
    snapshot = resolvePublicSnapshot(context, true, receipt);
    receipt.qualification_snapshot_id = snapshot.snapshot_id;
    bindPublicChest(context, receipt);
  } else {
    snapshot = resolveTeamSnapshot(context, true, receipt);
    receipt.qualification_snapshot_id = snapshot.snapshot_id;
  }
  const rare = profile.rare;
  const before = readNonNegativeCounter(owner.pity, rare.pity_pool_key, 'invalid_pity_state');
  if (!Number.isSafeInteger(before) || before < 0 || before >= rare.guarantee_on_eligible_attempt) {
    fail('pity_state_out_of_range');
  }
  const roll = resolveRareRoll(context, profile, before);
  const forced = before >= rare.guarantee_on_eligible_attempt - 1;
  const success = forced || roll.roll_basis_points <= rare.chance_basis_points;
  const resolutionBranch = forced ? 'pity_forced_success' : (success ? 'chance_success' : 'miss');
  if (roll.resolution_branch !== resolutionBranch) {
    fail('rare_roll_resolution_branch_mismatch');
  }
  const plan = emptyPlan();
  receipt.drop_roll_id = roll.drop_roll_id;
  receipt.drop_roll_proof_ref = roll.drop_roll_proof_ref;
  receipt.pity_pool_key = rare.pity_pool_key;
  receipt.pity_before = before;
  receipt.pity_after = success ? 0 : before + 1;
  if (!success) {
    receipt.rare_roll_outcome = resolutionBranch;
    receipt.rare_grant_disposition = 'not_applicable';
    plan.mutations.pity = { key: rare.pity_pool_key, after: receipt.pity_after };
  } else if (owner.unique_items[rare.key] === true) {
    receipt.rare_roll_outcome = resolutionBranch;
    receipt.rare_grant_disposition = 'duplicate_conversion';
    applyAwardsToPlan(context, plan, [rare.duplicate_conversion]);
    plan.mutations.pity = { key: rare.pity_pool_key, after: 0 };
  } else {
    receipt.rare_roll_outcome = resolutionBranch;
    receipt.rare_grant_disposition = 'granted';
    plan.unique_grants = [rare.key];
    plan.mutations.unique_grant = rare.key;
    plan.mutations.pity = { key: rare.pity_pool_key, after: 0 };
  }
  plan.derivation = {
    derivation_id: DERIVATION_ID,
    event_type: publicRare ? 'public_rare_drop' : 'team_raid_rare_drop',
    profile: profile.profile_key,
    qualification_snapshot_id: snapshot.snapshot_id,
    roll: roll.roll_basis_points,
    pity_pool_key: rare.pity_pool_key,
    pity_before: receipt.pity_before,
    pity_after: receipt.pity_after,
    rare_roll_outcome: receipt.rare_roll_outcome,
    rare_grant_disposition: receipt.rare_grant_disposition,
  };
  if (!canApplyAwards(context, owner, plan)) {
    receipt.pity_after = before;
    plan.derivation.pity_after = before;
    zeroForCap(plan, 'balance_or_stack_cap_reached');
  }
  return plan;
}

function overLevelMultiplier(table, characterLevel, sourceLevel) {
  const rows = (((table.progression || {}).party_policy || {}).over_level_multipliers) || [];
  const delta = characterLevel - sourceLevel;
  for (const row of rows) {
    if (delta <= row.max_over_source_level) {
      return row.multiplier_basis_points;
    }
  }
  fail('missing_over_level_multiplier');
}

function deriveExperience(context, owner, receipt) {
  if (typeof context.authorities.resolveXpSettlement !== 'function') {
    fail('missing_xp_authority_resolver');
  }
  const reference = requireIdentifier(context.request.xp_authority_ref, 'xp_authority_ref');
  const resolved = requireObject(context.authorities.resolveXpSettlement(reference, {
    owner_id: context.owner_id,
    event_id: context.request.event_id,
    encounter_instance_id: context.request.encounter_instance_id,
  }), 'xp_authority_record');
  const source = context.indexes.xpRows.get(resolved.xp_source_key);
  const levelCap = context.table.progression && context.table.progression.level_cap;
  if (!source || resolved.owner_id !== context.owner_id || resolved.event_id !== context.request.event_id ||
      resolved.encounter_instance_id !== context.request.encounter_instance_id ||
      context.request.source_profile !== source.source_key ||
      !Number.isSafeInteger(levelCap) || levelCap < 1 ||
      !Number.isSafeInteger(resolved.xp_character_level_before) || resolved.xp_character_level_before < 1 ||
      resolved.xp_character_level_before > levelCap ||
      !['base_clear', 'repeat_clear'].includes(resolved.xp_settlement_kind) ||
      !isCanonicalIdentifier(resolved.xp_session_id)) {
    fail('xp_authority_binding_mismatch');
  }
  const plan = emptyPlan();
  receipt.xp_source_key = source.source_key;
  receipt.xp_source_kind = source.source_kind;
  receipt.xp_base_amount = source.base_xp;
  receipt.xp_source_level = source.source_level;
  receipt.xp_character_level_before = resolved.xp_character_level_before;
  receipt.xp_over_level_multiplier_basis_points = overLevelMultiplier(context.table, resolved.xp_character_level_before, source.source_level);
  receipt.xp_repeat_multiplier_basis_points = resolved.xp_settlement_kind === 'repeat_clear' ? 2500 : 10000;
  receipt.xp_settlement_kind = resolved.xp_settlement_kind;
  receipt.xp_rounding_rule_id = XP_ROUNDING_RULE_ID;
  receipt.xp_session_id = resolved.xp_session_id;
  if (resolved.xp_character_level_before >= levelCap) {
    receipt.experience_delta = 0;
    fail('xp_level_cap_reached');
  }
  const quotaKey = `${source.source_key}:${resolved.xp_session_id}`;
  if (resolved.xp_settlement_kind === 'repeat_clear' && owner.xp_repeat_quota[quotaKey] === true) {
    receipt.experience_delta = 0;
    fail('xp_repeat_quota_already_consumed');
  }
  const repeatAdjusted = Math.floor(source.base_xp * receipt.xp_repeat_multiplier_basis_points / 10000);
  receipt.experience_delta = Math.floor(repeatAdjusted * receipt.xp_over_level_multiplier_basis_points / 10000);
  plan.mutations.experience_delta = receipt.experience_delta;
  if (resolved.xp_settlement_kind === 'repeat_clear') {
    plan.mutations.xp_repeat_quota_key = quotaKey;
  }
  plan.derivation = {
    derivation_id: DERIVATION_ID,
    event_type: 'experience',
    source_key: source.source_key,
    source_kind: source.source_kind,
    base_xp: source.base_xp,
    source_level: source.source_level,
    character_level_before: receipt.xp_character_level_before,
    over_level_multiplier_basis_points: receipt.xp_over_level_multiplier_basis_points,
    repeat_multiplier_basis_points: receipt.xp_repeat_multiplier_basis_points,
    settlement_kind: receipt.xp_settlement_kind,
    xp_session_id: receipt.xp_session_id,
    experience_delta: receipt.experience_delta,
  };
  return plan;
}

function resolveTowerSnapshot(context) {
  if (typeof context.authorities.resolveTowerSnapshot !== 'function') {
    fail('missing_tower_snapshot_resolver');
  }
  const id = requireIdentifier(context.request.tower_snapshot_id, 'tower_snapshot_id');
  const snapshot = requireObject(context.authorities.resolveTowerSnapshot(id, {
    owner_id: context.owner_id,
    event_id: context.request.event_id,
    encounter_instance_id: context.request.encounter_instance_id,
  }), 'tower_snapshot');
  const policy = (context.table.tower_rewards || {}).qualification_policy || {};
  assertExactKeys(snapshot, policy.required_snapshot_fields || [], 'tower_snapshot_field_mismatch');
  if (snapshot.schema_version !== 1 || snapshot.policy_id !== policy.policy_id || snapshot.snapshot_id !== id ||
      snapshot.tower_run_id !== context.request.encounter_instance_id ||
      snapshot.completion_event_id !== context.request.event_id || snapshot.tower_mode !== 'first_cycle' ||
      !isCanonicalIdentifier(snapshot.tower_cycle_id) || !isCanonicalIdentifier(snapshot.tower_week_bucket) ||
      !isCanonicalIdentifier(snapshot.snapshot_id) || !isCanonicalIdentifier(snapshot.tower_run_id) ||
      !isCanonicalIdentifier(snapshot.completion_event_id) || !isCanonicalIdentifier(snapshot.authority_proof_ref) ||
      !Array.isArray(snapshot.members)) {
    fail('tower_snapshot_mismatch');
  }
  const memberOwners = new Set();
  for (const entry of snapshot.members) {
    requireObject(entry, 'tower_member');
    assertExactKeys(entry, policy.required_member_fields || [], 'tower_member_field_mismatch');
    if (!isCanonicalIdentifier(entry.owner_id) || !Number.isSafeInteger(entry.entry_level) || entry.entry_level < 0 ||
        !isBoolean(entry.entry_qualified) || !isBoolean(entry.joined_before_run_lock) ||
        !isBoolean(entry.present_at_authoritative_completion) || !isBoolean(entry.actor_alive_at_authoritative_completion) ||
        !isBoolean(entry.contribution_attested) || !isBoolean(entry.eligible)) {
      fail('tower_member_schema_mismatch');
    }
    if (memberOwners.has(entry.owner_id)) {
      fail('tower_member_duplicate_owner');
    }
    memberOwners.add(entry.owner_id);
  }
  const member = snapshot.members.find((entry) => entry && entry.owner_id === context.owner_id);
  if (!member || !Number.isSafeInteger(member.entry_level) || member.entry_level < 55 || member.entry_qualified !== true ||
      member.joined_before_run_lock !== true || member.present_at_authoritative_completion !== true ||
      member.actor_alive_at_authoritative_completion !== true || member.contribution_attested !== true ||
      member.eligible !== true) {
    fail('tower_member_not_eligible');
  }
  return snapshot;
}

function deriveTower(context, owner, receipt) {
  const tower = context.table.tower_rewards || {};
  const snapshot = resolveTowerSnapshot(context);
  receipt.qualification_snapshot_id = snapshot.snapshot_id;
  receipt.tower_run_id = snapshot.tower_run_id;
  receipt.tower_cycle_id = snapshot.tower_cycle_id;
  receipt.tower_week_bucket = snapshot.tower_week_bucket;
  receipt.tower_mode = snapshot.tower_mode;
  const firstKey = `${snapshot.tower_cycle_id}:${snapshot.tower_mode}`;
  const first = owner.tower_first_clear[firstKey] !== true;
  receipt.tower_award_class = first ? 'first_clear' : 'repeat_clear';
  const awards = first ? tower.first_clear_awards : tower.repeat_clear_awards;
  if (!Array.isArray(awards)) {
    fail('tower_award_table_missing');
  }
  const plan = emptyPlan();
  applyAwardsToPlan(context, plan, awards);
  const before = readNonNegativeCounter(owner.tower_weekly_tokens, snapshot.tower_week_bucket, 'invalid_tower_weekly_token_state');
  const tokenAward = readNonNegativeCounter(plan.balance_delta, 'CUR_TOWER_TOKEN', 'invalid_tower_token_award');
  if (!Number.isSafeInteger(before + tokenAward)) {
    fail('invalid_tower_weekly_token_state');
  }
  receipt.tower_weekly_token_before = before;
  receipt.tower_weekly_token_after = before + tokenAward;
  plan.derivation = {
    derivation_id: DERIVATION_ID,
    event_type: 'tower_reward',
    snapshot_id: snapshot.snapshot_id,
    tower_cycle_id: snapshot.tower_cycle_id,
    tower_week_bucket: snapshot.tower_week_bucket,
    tower_award_class: receipt.tower_award_class,
    weekly_token_before: before,
    weekly_token_after: before + tokenAward,
  };
  if (before + tokenAward > tower.weekly_tower_token_cap) {
    receipt.tower_weekly_token_after = before;
    plan.derivation.weekly_token_after = before;
    zeroForCap(plan, 'weekly_token_cap_reached');
    return plan;
  }
  if (!canApplyAwards(context, owner, plan)) {
    receipt.tower_weekly_token_after = before;
    plan.derivation.weekly_token_after = before;
    zeroForCap(plan, 'balance_or_stack_cap_reached');
    return plan;
  }
  plan.mutations.tower_week = snapshot.tower_week_bucket;
  plan.mutations.tower_week_after = before + tokenAward;
  if (first) {
    plan.mutations.tower_first_clear_key = firstKey;
  }
  return plan;
}

function derivePlan(context, owner, receipt) {
  enforceFrozenBaseline(context);
  enforceCanonicalEvent(context);
  switch (context.request.event_type) {
    case 'drop_bundle':
      return deriveBundle(context, owner, receipt);
    case 'participation_chest':
      return deriveParticipationChest(context, owner, receipt);
    case 'first_clear_grant':
      return deriveFirstClear(context, owner, receipt);
    case 'public_rare_drop':
      return deriveRare(context, owner, receipt, true);
    case 'team_raid_rare_drop':
      return deriveRare(context, owner, receipt, false);
    case 'experience':
      return deriveExperience(context, owner, receipt);
    case 'tower_reward':
      return deriveTower(context, owner, receipt);
    default:
      fail('unsupported_event_type');
  }
}

function applyPlan(owner, plan) {
  for (const [key, amount] of Object.entries(plan.balance_delta)) {
    owner.balances[key] = readNonNegativeCounter(owner.balances, key, 'invalid_owner_balance_counter') + amount;
  }
  for (const [key, amount] of Object.entries(plan.material_delta)) {
    owner.materials[key] = readNonNegativeCounter(owner.materials, key, 'invalid_owner_material_counter') + amount;
  }
  for (const unique of plan.unique_grants) {
    owner.unique_items[unique] = true;
  }
  if (plan.mutations.first_clear_key) {
    owner.first_clear[plan.mutations.first_clear_key] = true;
  }
  if (plan.mutations.pity) {
    owner.pity[plan.mutations.pity.key] = plan.mutations.pity.after;
  }
  if (plan.mutations.experience_delta) {
    owner.experience += plan.mutations.experience_delta;
  }
  if (plan.mutations.xp_repeat_quota_key) {
    owner.xp_repeat_quota[plan.mutations.xp_repeat_quota_key] = true;
  }
  if (plan.mutations.tower_week) {
    owner.tower_weekly_tokens[plan.mutations.tower_week] = plan.mutations.tower_week_after;
  }
  if (plan.mutations.tower_first_clear_key) {
    owner.tower_first_clear[plan.mutations.tower_first_clear_key] = true;
  }
}

function rejectedPlan(context, code) {
  const plan = {
    derivation_id: DERIVATION_ID,
    terminal_rejection: true,
    rejection_code: code,
    table_version: context.table.resource_table_version,
    immutable_request: cloneWithoutTransportFields(context.request),
  };
  if (context.offline_tide_trace_attestation !== null) {
    plan.tide_trace_authority_attestation = deepClone(context.offline_tide_trace_attestation);
  }
  return plan;
}

function hasZeroAwardProjection(receipt) {
  return Object.values(receipt.balance_delta).every((amount) => amount === 0) &&
    Object.values(receipt.material_delta).every((amount) => amount === 0) &&
    receipt.unique_grants.length === 0 &&
    (receipt.experience_delta === null || receipt.experience_delta === 0);
}

// The store validates structural integrity.  This validator applies the
// resource-table's event-specific receipt contract before a terminal receipt
// can become durable.  An early authority failure might not have enough
// trustworthy facts to form a valid receipt; it is deliberately returned as a
// non-durable rejection rather than persisting a malformed terminal record.
function validateReceiptContract(context, receipt) {
  const contract = context.indexes.receipt;
  for (const field of contract.required_record_fields || []) {
    if (!hasOwn(receipt, field)) {
      fail('receipt_contract_required_field_missing');
    }
  }
  for (const field of contract.global_required_non_null || []) {
    if (receipt[field] === null || receipt[field] === undefined) {
      fail('receipt_contract_global_non_null_missing');
    }
  }
  for (const [field, expected] of Object.entries(contract.global_fixed_values || {})) {
    if (receipt[field] !== expected) {
      fail('receipt_contract_fixed_value_mismatch');
    }
  }
  if (receipt.owner_scope !== OWNER_SCOPE || receipt.owner_id !== context.owner_id ||
      receipt.event_id !== context.request.event_id || receipt.event_type !== context.request.event_type ||
      receipt.source_profile !== context.request.source_profile ||
      receipt.reward_slot_key !== context.request.reward_slot_key ||
      receipt.encounter_instance_id !== context.request.encounter_instance_id ||
      receipt.authority_proof_ref !== context.request.authority_proof_ref ||
      !Array.isArray(contract.commit_states) || !contract.commit_states.includes(receipt.commit_state) ||
      !Array.isArray(contract.award_outcomes) || !contract.award_outcomes.includes(receipt.award_outcome)) {
    fail('receipt_contract_identity_or_state_mismatch');
  }
  const towerBefore = receipt.tower_weekly_token_before;
  const towerAfter = receipt.tower_weekly_token_after;
  if ((towerBefore === null) !== (towerAfter === null) ||
      (towerBefore !== null && (!Number.isSafeInteger(towerBefore) || towerBefore < 0 ||
       !Number.isSafeInteger(towerAfter) || towerAfter < 0)) ||
      (receipt.tower_week_bucket !== null && !isCanonicalIdentifier(receipt.tower_week_bucket))) {
    fail('receipt_contract_tower_counter_invalid');
  }
  const levelCap = context.table.progression && context.table.progression.level_cap;
  if (receipt.xp_character_level_before !== null &&
      (!Number.isSafeInteger(levelCap) || levelCap < 1 ||
       !Number.isSafeInteger(receipt.xp_character_level_before) ||
       receipt.xp_character_level_before < 1 || receipt.xp_character_level_before > levelCap)) {
    fail('receipt_contract_xp_level_invalid');
  }
  const eventRule = (contract.conditional_field_rules || []).find((rule) => rule.event_type === receipt.event_type);
  if (!eventRule) {
    fail('receipt_contract_event_rule_missing');
  }
  for (const field of eventRule.required_non_null || []) {
    if (receipt[field] === null || receipt[field] === undefined) {
      fail('receipt_contract_conditional_non_null_missing');
    }
  }
  for (const field of eventRule.required_null || []) {
    if (receipt[field] !== null) {
      fail('receipt_contract_conditional_null_mismatch');
    }
  }
  for (const profileRule of contract.receipt_profile_binding_rules || []) {
    if (!(profileRule.event_types || []).includes(receipt.event_type) ||
        !(profileRule.source_profiles || []).includes(receipt.source_profile)) {
      continue;
    }
    for (const field of profileRule.required_non_null || []) {
      if (receipt[field] === null || receipt[field] === undefined) {
        fail('receipt_contract_profile_binding_non_null_missing');
      }
    }
    for (const field of profileRule.required_null || []) {
      if (receipt[field] !== null) {
        fail('receipt_contract_profile_binding_null_mismatch');
      }
    }
  }

  const zeroAward = hasZeroAwardProjection(receipt);
  if (receipt.commit_state === 'rejected') {
    if (receipt.award_outcome !== 'rejected' || !zeroAward || receipt.offline_origin_key !== null ||
        (receipt.first_clear_disposition !== null && receipt.first_clear_disposition !== 'not_consumed_zero_award') ||
        (receipt.pity_pool_key !== null && receipt.pity_before !== receipt.pity_after) ||
        (receipt.tower_weekly_token_before !== null && receipt.tower_weekly_token_before !== receipt.tower_weekly_token_after)) {
      fail('receipt_contract_rejected_state_mutation');
    }
    return;
  }

  if (receipt.award_outcome === 'awarded' && zeroAward) {
    const rareEvent = receipt.event_type === 'public_rare_drop' || receipt.event_type === 'team_raid_rare_drop';
    if (!rareEvent || receipt.rare_roll_outcome !== 'miss' || receipt.rare_grant_disposition !== 'not_applicable') {
      fail('receipt_contract_unexpected_awarded_zero');
    }
  }
  if (receipt.award_outcome === 'weekly_token_cap_reached' || receipt.award_outcome === 'balance_or_stack_cap_reached') {
    if (!zeroAward || (receipt.first_clear_disposition !== null && receipt.first_clear_disposition !== 'not_consumed_zero_award') ||
        (receipt.pity_pool_key !== null && receipt.pity_before !== receipt.pity_after) ||
        (receipt.tower_weekly_token_before !== null && receipt.tower_weekly_token_before !== receipt.tower_weekly_token_after)) {
      fail('receipt_contract_cap_state_mutation');
    }
  }
  if (receipt.event_type === 'first_clear_grant' &&
      !['first_clear_granted', 'duplicate_conversion', 'not_consumed_zero_award'].includes(receipt.first_clear_disposition)) {
    fail('receipt_contract_first_clear_disposition');
  }
  if ((receipt.event_type === 'public_rare_drop' || receipt.event_type === 'team_raid_rare_drop') &&
      (!['miss', 'chance_success', 'pity_forced_success'].includes(receipt.rare_roll_outcome) ||
       !['not_applicable', 'granted', 'duplicate_conversion'].includes(receipt.rare_grant_disposition) ||
       ((receipt.rare_roll_outcome === 'miss') !== (receipt.rare_grant_disposition === 'not_applicable')))) {
    fail('receipt_contract_rare_outcome');
  }
}

function persistRejected(context, state, code, partialReceipt) {
  const receipt = partialReceipt || initializeReceipt(context);
  receipt.balance_delta = {};
  receipt.material_delta = {};
  receipt.unique_grants = [];
  receipt.commit_state = 'rejected';
  receipt.award_outcome = 'rejected';
  receipt.offline_origin_key = null;
  const completed = finishReceipt(context, receipt, rejectedPlan(context, code), context.request_fingerprint);
  try {
    validateReceiptContract(context, completed);
  } catch (error) {
    if (error instanceof PolicyFailure) {
      return { status: 'rejected', code, receipt: null, replayed: false };
    }
    throw error;
  }
  saveTerminalReceipt(state, context.identity, completed);
  return { status: 'rejected', code, receipt: deepClone(completed), replayed: false };
}

function tideTraceIntentToRequest(compiledBaseline, intent) {
  const { source } = readTable(compiledBaseline);
  intent = detachJsonValue(intent, 'invalid_tide_trace_intent');
  if (intent === null || typeof intent !== 'object' || Array.isArray(intent)) {
    fail('invalid_tide_trace_intent');
  }
  const keys = Object.keys(intent);
  if (keys.length !== TIDE_TRACE_INTENT_FIELDS.size || keys.some((key) => !TIDE_TRACE_INTENT_FIELDS.has(key))) {
    fail('tide_trace_intent_field_mismatch');
  }
  for (const field of TIDE_TRACE_INTENT_FIELDS) {
    if (!hasOwn(intent, field)) {
      fail(`missing_tide_trace_${field}`);
    }
  }
  if (intent.schema_version !== 1 || intent.source_event_type !== 'trace_action_completed' ||
      intent.event_type !== 'drop_bundle' || intent.source_profile !== 'HG_DROP_WATERFALL_ELITE' ||
      intent.reward_slot_key !== 'base_bundle' || intent.encounter_key !== 'HG_E_TIDE_TRACE' ||
      intent.encounter_action_key !== 'stabilize_tide_trace' || intent.combat_scope !== 'public' ||
      intent.target_scope !== 'explicit' || intent.credit_personal_progress !== true ||
      intent.rare_eligibility !== 'none') {
    fail('tide_trace_intent_fixed_field_mismatch');
  }
  for (const field of [
    'event_id', 'actor_id', 'encounter_instance_id', 'target_id', 'target_lifecycle_id',
    'action_token', 'authority_proof_ref',
  ]) {
    requireIdentifier(intent[field], `tide_trace_${field}`);
  }
  requireString(intent.source_identity_fingerprint, 'tide_trace_source_identity_fingerprint');
  if (!Number.isSafeInteger(intent.lifecycle_id) || intent.lifecycle_id < 0) {
    fail('invalid_tide_trace_lifecycle_id');
  }
  if (!Number.isSafeInteger(intent.completed_tick) || intent.completed_tick < 0) {
    fail('invalid_tide_trace_completed_tick');
  }
  return {
    resource_table_version: source.resource_table_version,
    resource_table_file_sha256: source.resource_table_file_sha256,
    actor_id: intent.actor_id,
    lifecycle_id: intent.lifecycle_id,
    authority_proof_ref: intent.authority_proof_ref,
    event_id: intent.event_id,
    encounter_instance_id: intent.encounter_instance_id,
    event_type: 'drop_bundle',
    source_profile: 'HG_DROP_WATERFALL_ELITE',
    reward_slot_key: 'base_bundle',
  };
}

function materializeTideTraceIntent(compiledBaseline, authorities, store, intent, options = {}) {
  let request;
  let frozenIntent;
  let authorityResult;
  let authorityAttestation;
  let authorityInput;
  try {
    frozenIntent = detachJsonValue(intent, 'invalid_tide_trace_intent');
    request = tideTraceIntentToRequest(compiledBaseline, frozenIntent);
    if (!authorities || typeof authorities.resolveOwner !== 'function') {
      fail('missing_owner_resolver');
    }
    authorityInput = {
      actor_id: request.actor_id,
      lifecycle_id: request.lifecycle_id,
      authority_proof_ref: request.authority_proof_ref,
      event_id: request.event_id,
      encounter_instance_id: request.encounter_instance_id,
      source_profile: request.source_profile,
      event_type: request.event_type,
      authority_origin_key: originIdentity(request),
    };
    authorityResult = detachJsonValue(authorities.resolveOwner({
      ...authorityInput,
      canonical_tide_trace: frozenIntent,
    }), 'invalid_authority_result');
    if (authorityResult === null || typeof authorityResult !== 'object' || Array.isArray(authorityResult)) {
      fail('invalid_authority_result');
    }
    authorityAttestation = normalizeTideTraceAuthorityAttestation({
      tide_trace_attestation_ref: authorityResult.tide_trace_attestation_ref,
      tide_trace_canonical_digest: authorityResult.tide_trace_canonical_digest,
    }, frozenIntent);
  } catch (error) {
    return { status: 'rejected', code: error instanceof PolicyFailure ? error.code : error.message, receipt: null, replayed: false };
  }
  const wrappedAuthorities = Object.assign({}, authorities, {
    resolveOwner(input) {
      // The proof was reverified immediately above with the complete frozen
      // Tide Trace evidence.  The generic materializer may invoke this
      // adapter only for the exact same derived core request.
      return canonicalJson(input) === canonicalJson(authorityInput) ? authorityResult : null;
    },
  });
  return materialize(compiledBaseline, wrappedAuthorities, store, request, {
    ...options,
    offline_tide_trace_attestation: authorityAttestation,
  });
}

function materialize(compiledBaseline, authorities, store, request, options = {}) {
  let tableAndSource;
  try {
    request = detachJsonValue(request, 'invalid_request');
    tableAndSource = readTable(compiledBaseline);
    assertRequestShape(request);
  } catch (error) {
    return { status: 'rejected', code: error instanceof PolicyFailure ? error.code : error.message, receipt: null, replayed: false };
  }
  if (!(store instanceof OfflineTransactionStore)) {
    throw new Error('materialize requires OfflineTransactionStore');
  }
  const indexes = makeIndexes(tableAndSource.table);
  const authorityOriginKey = originIdentity(request);
  let ownerId;
  try {
    if (typeof authorities.resolveOwner !== 'function') {
      fail('missing_owner_resolver');
    }
    ownerId = normalizeAuthorityResult(authorities.resolveOwner({
      actor_id: request.actor_id,
      lifecycle_id: request.lifecycle_id,
      authority_proof_ref: request.authority_proof_ref,
      event_id: request.event_id,
      encounter_instance_id: request.encounter_instance_id,
      source_profile: request.source_profile,
      event_type: request.event_type,
      authority_origin_key: authorityOriginKey,
    }), request, authorityOriginKey);
  } catch (error) {
    return { status: 'rejected', code: error instanceof PolicyFailure ? error.code : error.message, receipt: null, replayed: false };
  }
  let offlineTideTraceAttestation;
  let requestFingerprint;
  try {
    offlineTideTraceAttestation = options.offline_tide_trace_attestation === undefined
      ? null
      : normalizeOfflineTideTraceReceiptAttestation(options.offline_tide_trace_attestation);
    const requestFingerprintProjection = cloneWithoutTransportFields(request);
    if (offlineTideTraceAttestation !== null) {
      requestFingerprintProjection.tide_trace_authority_attestation = offlineTideTraceAttestation;
    }
    requestFingerprint = sha256(canonicalJson(requestFingerprintProjection));
  } catch (error) {
    return { status: 'rejected', code: error.message, receipt: null, replayed: false };
  }
  const context = {
    table: tableAndSource.table,
    source: tableAndSource.source,
    indexes,
    authorities,
    store,
    request,
    owner_id: ownerId,
    request_fingerprint: requestFingerprint,
    identity: semanticIdentity(ownerId, request),
    origin_identity: authorityOriginKey,
    offline_tide_trace_attestation: offlineTideTraceAttestation,
  };

  return store.transact((state) => {
    const existingOrigin = state.origins_by_identity[context.origin_identity];
    if (existingOrigin && existingOrigin.owner_id !== ownerId) {
      // The same authoritative actor/lifecycle/event origin may not be
      // remapped to a second character by swapping proofs.  Do not create a
      // rejected receipt here: the foreign semantic identity must not be able
      // to block a later legitimate owner reconciliation.
      return { status: 'rejected', code: 'authority_owner_origin_conflict', receipt: null, replayed: false };
    }
    const existing = state.receipts_by_identity[context.identity];
    if (existing) {
      if (existing.offline_request_fingerprint === context.request_fingerprint) {
        return { status: existing.commit_state === 'committed' ? 'committed' : 'rejected', code: null, receipt: deepClone(existing), replayed: true };
      }
      return { status: 'conflict', code: 'receipt_identity_conflict', receipt: deepClone(existing), replayed: false };
    }
    try {
      // A caller may echo the frozen version/hash for transport diagnostics,
      // but that echo is not an authority input and must never consume a new
      // semantic identity when it is malformed.
      enforceFrozenBaseline(context);
    } catch (error) {
      if (error instanceof PolicyFailure) {
        return { status: 'rejected', code: error.code, receipt: null, replayed: false };
      }
      throw error;
    }
    const owner = ownerStateFor(state, ownerId);
    let receipt = initializeReceipt(context);
    let plan;
    try {
      plan = derivePlan(context, owner, receipt);
    } catch (error) {
      if (error instanceof PolicyFailure) {
        return persistRejected(context, state, error.code, receipt);
      }
      throw error;
    }
    receipt.balance_delta = deepClone(plan.balance_delta);
    receipt.material_delta = deepClone(plan.material_delta);
    receipt.unique_grants = deepClone(plan.unique_grants);
    receipt.award_outcome = plan.award_outcome;
    const completePlan = {
      ...plan.derivation,
      source_profile: receipt.source_profile,
      reward_slot_key: receipt.reward_slot_key,
      balance_delta: receipt.balance_delta,
      material_delta: receipt.material_delta,
      unique_grants: receipt.unique_grants,
      qualification_snapshot_id: receipt.qualification_snapshot_id,
      p1_policy_id: receipt.p1_policy_id,
      first_clear_disposition: receipt.first_clear_disposition,
      drop_roll_id: receipt.drop_roll_id,
      drop_roll_proof_ref: receipt.drop_roll_proof_ref,
      pity_pool_key: receipt.pity_pool_key,
      pity_before: receipt.pity_before,
      pity_after: receipt.pity_after,
      rare_roll_outcome: receipt.rare_roll_outcome,
      rare_grant_disposition: receipt.rare_grant_disposition,
      xp: {
        source_key: receipt.xp_source_key,
        source_kind: receipt.xp_source_kind,
        base_amount: receipt.xp_base_amount,
        source_level: receipt.xp_source_level,
        character_level_before: receipt.xp_character_level_before,
        over_level_multiplier_basis_points: receipt.xp_over_level_multiplier_basis_points,
        repeat_multiplier_basis_points: receipt.xp_repeat_multiplier_basis_points,
        settlement_kind: receipt.xp_settlement_kind,
        rounding_rule_id: receipt.xp_rounding_rule_id,
        session_id: receipt.xp_session_id,
        experience_delta: receipt.experience_delta,
      },
      tower: {
        run_id: receipt.tower_run_id,
        cycle_id: receipt.tower_cycle_id,
        week_bucket: receipt.tower_week_bucket,
        mode: receipt.tower_mode,
        award_class: receipt.tower_award_class,
        token_before: receipt.tower_weekly_token_before,
        token_after: receipt.tower_weekly_token_after,
      },
      award_outcome: receipt.award_outcome,
      resource_table_version: receipt.resource_table_version,
    };
    if (context.offline_tide_trace_attestation !== null) {
      completePlan.tide_trace_authority_attestation = deepClone(context.offline_tide_trace_attestation);
    }
    receipt.offline_origin_key = context.origin_identity;
    receipt = finishReceipt(context, receipt, completePlan, context.request_fingerprint);
    try {
      validateReceiptContract(context, receipt);
    } catch (error) {
      if (error instanceof PolicyFailure) {
        return { status: 'rejected', code: error.code, receipt: null, replayed: false };
      }
      throw error;
    }
    if (typeof options.failpoint === 'function') {
      options.failpoint('before_mutation_and_receipt', { receipt: deepClone(receipt), plan: deepClone(plan) });
    }
    applyPlan(owner, plan);
    if (typeof options.failpoint === 'function') {
      options.failpoint('after_mutation_before_receipt', { receipt: deepClone(receipt), plan: deepClone(plan) });
    }
    saveTerminalReceipt(state, context.identity, receipt);
    state.origins_by_identity[context.origin_identity] = {
      owner_id: ownerId,
      semantic_identity: context.identity,
      receipt_id: receipt.receipt_id,
    };
    if (typeof options.failpoint === 'function') {
      options.failpoint('after_terminal_receipt', { receipt: deepClone(receipt), plan: deepClone(plan) });
    }
    return { status: 'committed', code: null, receipt: deepClone(receipt), replayed: false };
  });
}

function createStore(serializedState, options) {
  return new OfflineTransactionStore(serializedState, options);
}

module.exports = {
  DERIVATION_ID,
  OfflineTransactionStore,
  XP_ROUNDING_RULE_ID,
  createStore,
  materialize,
  materializeTideTraceIntent,
  tideTraceIntentToRequest,
};
