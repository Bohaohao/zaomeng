'use strict';

// Offline-only transaction model. It has no filesystem, network, clock, Y3, or
// service dependencies. The strict import checks are deliberately narrower than
// a production signature/MAC scheme, but reject malformed or internally
// inconsistent restart state instead of silently trusting it.

const crypto = require('crypto');

const TERMINAL_STATES = new Set(['committed', 'rejected']);
const AWARD_OUTCOMES = new Set(['awarded', 'weekly_token_cap_reached', 'balance_or_stack_cap_reached', 'rejected']);
const TRUSTED_SNAPSHOT_SCHEMA_VERSION = 1;
const TRUSTED_SNAPSHOT_FIELDS = ['snapshot_schema_version', 'state', 'state_hmac_sha256'];
const REQUIRED_RECEIPT_FIELDS = [
  'schema_version', 'resource_table_version', 'owner_scope', 'owner_id', 'event_id', 'event_type',
  'source_profile', 'reward_slot_key', 'encounter_instance_id', 'qualification_snapshot_id', 'p1_policy_id',
  'drop_roll_id', 'drop_roll_proof_ref', 'pity_pool_key', 'participation_chest_receipt_id',
  'participation_chest_receipt_fingerprint', 'first_clear_disposition', 'rare_roll_outcome',
  'rare_grant_disposition', 'xp_source_key', 'xp_source_kind', 'xp_base_amount', 'xp_source_level',
  'xp_character_level_before', 'xp_over_level_multiplier_basis_points', 'xp_repeat_multiplier_basis_points',
  'xp_settlement_kind', 'xp_rounding_rule_id', 'xp_session_id', 'experience_delta', 'tower_run_id',
  'tower_cycle_id', 'tower_week_bucket', 'tower_mode', 'tower_award_class', 'tower_weekly_token_before',
  'tower_weekly_token_after', 'balance_delta', 'material_delta', 'unique_grants', 'pity_before', 'pity_after',
  'award_plan_hash', 'authority_proof_ref', 'receipt_id', 'commit_state', 'award_outcome',
  'identity_fingerprint', 'offline_request_fingerprint', 'offline_award_plan', 'offline_origin_key',
];
const GLOBAL_NON_NULL_FIELDS = [
  'schema_version', 'resource_table_version', 'owner_scope', 'owner_id', 'event_id', 'event_type',
  'source_profile', 'reward_slot_key', 'encounter_instance_id', 'balance_delta', 'material_delta',
  'unique_grants', 'award_plan_hash', 'authority_proof_ref', 'receipt_id', 'commit_state', 'award_outcome',
];
const IDENTITY_FINGERPRINT_FIELDS = [
  'resource_table_version', 'qualification_snapshot_id', 'p1_policy_id', 'drop_roll_id', 'drop_roll_proof_ref',
  'pity_pool_key', 'participation_chest_receipt_id', 'participation_chest_receipt_fingerprint',
  'first_clear_disposition', 'rare_roll_outcome', 'rare_grant_disposition', 'xp_source_key', 'xp_source_kind',
  'xp_base_amount', 'xp_source_level', 'xp_character_level_before', 'xp_over_level_multiplier_basis_points',
  'xp_repeat_multiplier_basis_points', 'xp_settlement_kind', 'xp_rounding_rule_id', 'xp_session_id',
  'experience_delta', 'tower_run_id', 'tower_cycle_id', 'tower_week_bucket', 'tower_mode',
  'tower_award_class', 'tower_weekly_token_before', 'tower_weekly_token_after', 'award_plan_hash',
];
const OWNER_STATE_FIELDS = [
  'balances', 'materials', 'unique_items', 'first_clear', 'pity', 'experience',
  'xp_repeat_quota', 'tower_first_clear', 'tower_weekly_tokens',
];
const FROZEN_LEVEL_CAP = 60;
const UNSAFE_OBJECT_PROPERTY_KEYS = new Set([
  ...Object.getOwnPropertyNames(Object.prototype),
  '__proto__',
  'constructor',
  'prototype',
]);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function isPlainObject(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function isSafeMapKey(value) {
  return typeof value === 'string' && value.length > 0 && !UNSAFE_OBJECT_PROPERTY_KEYS.has(value);
}

function canonicalJson(value) {
  if (value === null) return 'null';
  if (value === true) return 'true';
  if (value === false) return 'false';
  if (typeof value === 'string') return JSON.stringify(value);
  if (typeof value === 'number') {
    assert(Number.isFinite(value), 'canonical JSON rejects non-finite numbers');
    return JSON.stringify(Object.is(value, -0) ? 0 : value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (isPlainObject(value)) {
    return `{${Object.keys(value).sort().map((key) => {
      const child = value[key];
      assert(child !== undefined, `canonical JSON rejects undefined value for ${key}`);
      return `${JSON.stringify(key)}:${canonicalJson(child)}`;
    }).join(',')}}`;
  }
  throw new Error(`canonical JSON rejects ${typeof value}`);
}

function sha256(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function normalizeIntegrityKey(value) {
  if (Buffer.isBuffer(value) && value.length >= 16) return Buffer.from(value);
  if (typeof value === 'string' && Buffer.byteLength(value, 'utf8') >= 16) return Buffer.from(value, 'utf8');
  throw new Error('trusted snapshot integrity key must contain at least 16 bytes');
}

function trustedSnapshotHmac(state, integrityKey) {
  return crypto.createHmac('sha256', normalizeIntegrityKey(integrityKey))
    .update(canonicalJson(state), 'utf8')
    .digest('hex');
}

function semanticIdentity(ownerId, receiptOrRequest) {
  return `economy-v2:${sha256(canonicalJson([
    'character', ownerId, receiptOrRequest.encounter_instance_id, receiptOrRequest.event_id,
    receiptOrRequest.source_profile, receiptOrRequest.reward_slot_key,
  ]))}`;
}

function originIdentity(input) {
  return `economy-v2-origin:${sha256(canonicalJson([
    input.actor_id, input.lifecycle_id, input.encounter_instance_id, input.event_id,
    input.source_profile, input.reward_slot_key,
  ]))}`;
}

function emptyOwnerState() {
  return {
    balances: {}, materials: {}, unique_items: {}, first_clear: {}, pity: {}, experience: 0,
    xp_repeat_quota: {}, tower_first_clear: {}, tower_weekly_tokens: {},
  };
}

function emptyState() {
  return {
    schema_version: 1,
    receipts_by_identity: {},
    receipts_by_id: {},
    origins_by_identity: {},
    owners: {},
    migration_isolation_queue: [],
  };
}

function assertExactKeys(value, fields, label) {
  assert(isPlainObject(value), `${label} must be an object`);
  const keys = Object.keys(value).sort();
  const expected = [...fields].sort();
  assert(keys.length === expected.length && keys.every((key, index) => key === expected[index]), `${label} fields mismatch`);
}

function assertTrustedSnapshot(snapshot, integrityKey) {
  // Canonicalize once before inspecting any field.  A caller-facing object can
  // otherwise use getters/Proxies to return a signed state for HMAC checking
  // and a different state when the constructor later installs it.
  const detachedSnapshot = JSON.parse(canonicalJson(snapshot));
  assertExactKeys(detachedSnapshot, TRUSTED_SNAPSHOT_FIELDS, 'trusted snapshot');
  assert(detachedSnapshot.snapshot_schema_version === TRUSTED_SNAPSHOT_SCHEMA_VERSION, 'unsupported trusted snapshot schema version');
  assert(typeof detachedSnapshot.state_hmac_sha256 === 'string' && /^[0-9a-f]{64}$/.test(detachedSnapshot.state_hmac_sha256), 'trusted snapshot HMAC is invalid');
  const expected = Buffer.from(trustedSnapshotHmac(detachedSnapshot.state, integrityKey), 'hex');
  const received = Buffer.from(detachedSnapshot.state_hmac_sha256, 'hex');
  assert(expected.length === received.length && crypto.timingSafeEqual(expected, received), 'trusted snapshot integrity mismatch');
  return detachedSnapshot.state;
}

function assertNonNegativeIntegerMap(value, label) {
  assert(isPlainObject(value), `${label} must be an object`);
  for (const [key, amount] of Object.entries(value)) {
    assert(isSafeMapKey(key) && Number.isSafeInteger(amount) && amount >= 0, `${label} has invalid entry`);
  }
}

function assertBooleanMap(value, label) {
  assert(isPlainObject(value), `${label} must be an object`);
  for (const [key, enabled] of Object.entries(value)) {
    assert(isSafeMapKey(key) && enabled === true, `${label} has invalid entry`);
  }
}

function validateOwnerState(owner, ownerId) {
  assert(isSafeMapKey(ownerId), 'owner key must be a safe non-empty map key');
  assertExactKeys(owner, OWNER_STATE_FIELDS, `owner state ${ownerId}`);
  assertNonNegativeIntegerMap(owner.balances, `owner ${ownerId} balances`);
  assertNonNegativeIntegerMap(owner.materials, `owner ${ownerId} materials`);
  assertBooleanMap(owner.unique_items, `owner ${ownerId} unique items`);
  assertBooleanMap(owner.first_clear, `owner ${ownerId} first clear`);
  assertNonNegativeIntegerMap(owner.pity, `owner ${ownerId} pity`);
  assert(Number.isSafeInteger(owner.experience) && owner.experience >= 0, `owner ${ownerId} experience invalid`);
  assertBooleanMap(owner.xp_repeat_quota, `owner ${ownerId} XP quota`);
  assertBooleanMap(owner.tower_first_clear, `owner ${ownerId} tower first clear`);
  assertNonNegativeIntegerMap(owner.tower_weekly_tokens, `owner ${ownerId} tower weekly tokens`);
}

function validateReceipt(receipt, identity) {
  assert(isPlainObject(receipt), `receipt ${identity} must be an object`);
  assertExactKeys(receipt, REQUIRED_RECEIPT_FIELDS, `receipt ${identity}`);
  for (const field of REQUIRED_RECEIPT_FIELDS) assert(Object.prototype.hasOwnProperty.call(receipt, field), `receipt ${identity} missing ${field}`);
  for (const field of GLOBAL_NON_NULL_FIELDS) assert(receipt[field] !== null && receipt[field] !== undefined, `receipt ${identity} has null ${field}`);
  assert(receipt.schema_version === 1, `receipt ${identity} schema mismatch`);
  assert(receipt.resource_table_version === 'economy-v2', `receipt ${identity} table version mismatch`);
  assert(receipt.owner_scope === 'character', `receipt ${identity} owner scope mismatch`);
  assert(TERMINAL_STATES.has(receipt.commit_state) && receipt.commit_state !== 'prepared', `receipt ${identity} is not terminal`);
  assert(AWARD_OUTCOMES.has(receipt.award_outcome), `receipt ${identity} has invalid award outcome`);
  assert((receipt.commit_state === 'committed') === (receipt.award_outcome !== 'rejected'), `receipt ${identity} terminal state/outcome mismatch`);
  assert(isSafeMapKey(receipt.owner_id), `receipt ${identity} owner invalid`);
  assert(typeof receipt.event_id === 'string' && receipt.event_id.length > 0, `receipt ${identity} event invalid`);
  assert(typeof receipt.encounter_instance_id === 'string' && receipt.encounter_instance_id.length > 0, `receipt ${identity} instance invalid`);
  assert(typeof receipt.source_profile === 'string' && receipt.source_profile.length > 0, `receipt ${identity} profile invalid`);
  assert(typeof receipt.reward_slot_key === 'string' && receipt.reward_slot_key.length > 0, `receipt ${identity} slot invalid`);
  assert(identity === semanticIdentity(receipt.owner_id, receipt), `receipt ${identity} semantic identity mismatch`);
  assert(receipt.receipt_id === `economy-v2:${sha256(identity)}`, `receipt ${identity} receipt id mismatch`);
  assertNonNegativeIntegerMap(receipt.balance_delta, `receipt ${identity} balance delta`);
  assertNonNegativeIntegerMap(receipt.material_delta, `receipt ${identity} material delta`);
  assert(Array.isArray(receipt.unique_grants) && receipt.unique_grants.every((key) => typeof key === 'string' && key.length > 0), `receipt ${identity} unique grants invalid`);
  assert(/^[0-9a-f]{64}$/.test(receipt.award_plan_hash || ''), `receipt ${identity} award plan hash invalid`);
  assert(/^[0-9a-f]{64}$/.test(receipt.identity_fingerprint || ''), `receipt ${identity} fingerprint invalid`);
  assert(/^[0-9a-f]{64}$/.test(receipt.offline_request_fingerprint || ''), `receipt ${identity} request fingerprint invalid`);
  assert(isPlainObject(receipt.offline_award_plan), `receipt ${identity} lacks offline award plan`);
  assert(sha256(canonicalJson(receipt.offline_award_plan)) === receipt.award_plan_hash, `receipt ${identity} award plan hash mismatch`);
  const towerBefore = receipt.tower_weekly_token_before;
  const towerAfter = receipt.tower_weekly_token_after;
  assert((towerBefore === null) === (towerAfter === null), `receipt ${identity} tower counter nullability mismatch`);
  if (towerBefore !== null) {
    assert(Number.isSafeInteger(towerBefore) && towerBefore >= 0 &&
      Number.isSafeInteger(towerAfter) && towerAfter >= 0, `receipt ${identity} tower counters invalid`);
  }
  if (receipt.tower_week_bucket !== null) {
    assert(isSafeMapKey(receipt.tower_week_bucket), `receipt ${identity} tower week bucket invalid`);
  }
  if (receipt.xp_character_level_before !== null) {
    assert(Number.isSafeInteger(receipt.xp_character_level_before) &&
      receipt.xp_character_level_before >= 1 && receipt.xp_character_level_before <= FROZEN_LEVEL_CAP,
    `receipt ${identity} XP character level invalid`);
  }
  const fingerprintProjection = {};
  for (const field of IDENTITY_FINGERPRINT_FIELDS) fingerprintProjection[field] = receipt[field];
  assert(sha256(canonicalJson(fingerprintProjection)) === receipt.identity_fingerprint, `receipt ${identity} identity fingerprint mismatch`);
  if (receipt.commit_state === 'committed') {
    assert(/^economy-v2-origin:[0-9a-f]{64}$/.test(receipt.offline_origin_key || ''), `receipt ${identity} origin key invalid`);
  } else {
    assert(receipt.offline_origin_key === null, `rejected receipt ${identity} may not own an origin`);
    assert(Object.keys(receipt.balance_delta).length === 0 && Object.keys(receipt.material_delta).length === 0 && receipt.unique_grants.length === 0, `rejected receipt ${identity} has economic award`);
  }
}

function validateState(state) {
  assert(isPlainObject(state), 'store state must be an object');
  assert(state.schema_version === 1, 'unsupported store schema version');
  for (const key of ['receipts_by_identity', 'receipts_by_id', 'origins_by_identity', 'owners', 'migration_isolation_queue']) {
    assert(Object.prototype.hasOwnProperty.call(state, key), `store state missing ${key}`);
  }
  assert(isPlainObject(state.receipts_by_identity), 'receipt identity index must be an object');
  assert(isPlainObject(state.receipts_by_id), 'receipt id index must be an object');
  assert(isPlainObject(state.origins_by_identity), 'origin index must be an object');
  assert(isPlainObject(state.owners), 'owner index must be an object');
  assert(Array.isArray(state.migration_isolation_queue), 'migration isolation queue must be an array');
  for (const [ownerId, owner] of Object.entries(state.owners)) validateOwnerState(owner, ownerId);

  const seenReceiptIds = new Set();
  for (const [identity, receipt] of Object.entries(state.receipts_by_identity)) {
    assert(isSafeMapKey(identity), `receipt identity ${identity} key invalid`);
    validateReceipt(receipt, identity);
    assert(Object.prototype.hasOwnProperty.call(state.owners, receipt.owner_id), `receipt ${identity} owner state missing`);
    assert(!seenReceiptIds.has(receipt.receipt_id), `duplicate receipt id ${receipt.receipt_id}`);
    seenReceiptIds.add(receipt.receipt_id);
    assert(Object.prototype.hasOwnProperty.call(state.receipts_by_id, receipt.receipt_id), `receipt ${identity} absent from id index`);
    assert(canonicalJson(state.receipts_by_id[receipt.receipt_id]) === canonicalJson(receipt), `receipt id index mismatch for ${identity}`);
  }
  assert(Object.keys(state.receipts_by_id).length === seenReceiptIds.size, 'receipt id index has orphaned record');
  for (const [receiptId, receipt] of Object.entries(state.receipts_by_id)) {
    assert(isSafeMapKey(receiptId), `receipt id ${receiptId} key invalid`);
    assert(isPlainObject(receipt), `receipt id ${receiptId} must be an object`);
    const identity = semanticIdentity(receipt.owner_id, receipt);
    assert(receipt.receipt_id === receiptId && Object.prototype.hasOwnProperty.call(state.receipts_by_identity, identity), `receipt id ${receiptId} has no identity record`);
    assert(canonicalJson(state.receipts_by_identity[identity]) === canonicalJson(receipt), `receipt ${receiptId} identity record mismatch`);
  }

  const committedReceipts = Object.values(state.receipts_by_identity).filter((receipt) => receipt.commit_state === 'committed');
  assert(Object.keys(state.origins_by_identity).length === committedReceipts.length, 'origin index does not match committed receipt count');
  for (const [originKey, origin] of Object.entries(state.origins_by_identity)) {
    assert(isSafeMapKey(originKey), `origin ${originKey} key invalid`);
    assert(/^economy-v2-origin:[0-9a-f]{64}$/.test(originKey), `origin ${originKey} key invalid`);
    assertExactKeys(origin, ['owner_id', 'semantic_identity', 'receipt_id'], `origin ${originKey}`);
    const receipt = state.receipts_by_identity[origin.semantic_identity];
    assert(receipt && receipt.commit_state === 'committed', `origin ${originKey} lacks committed receipt`);
    assert(receipt.owner_id === origin.owner_id && receipt.receipt_id === origin.receipt_id && receipt.offline_origin_key === originKey, `origin ${originKey} receipt mismatch`);
  }
  for (const receipt of committedReceipts) {
    const origin = state.origins_by_identity[receipt.offline_origin_key];
    assert(origin && origin.receipt_id === receipt.receipt_id, `committed receipt ${receipt.receipt_id} lacks origin`);
  }
}

class OfflineTransactionStore {
  constructor(serializedState, options = {}) {
    this._integrityKey = options.integrity_key === undefined ? null : normalizeIntegrityKey(options.integrity_key);
    this._transactionInProgress = false;
    this._transactionReentryDetected = false;
    if (serializedState === undefined) {
      this._state = emptyState();
    } else {
      assert(this._integrityKey !== null, 'trusted snapshot restore requires an external integrity key');
      this._state = deepClone(assertTrustedSnapshot(serializedState, this._integrityKey));
    }
    validateState(this._state);
  }

  // Diagnostic export only. It intentionally cannot be passed back to the
  // constructor: a restart must use a separately held integrity key.
  exportState() { return deepClone(this._state); }

  exportTrustedSnapshot() {
    assert(this._integrityKey !== null, 'trusted snapshot export requires an external integrity key');
    const state = deepClone(this._state);
    return {
      snapshot_schema_version: TRUSTED_SNAPSHOT_SCHEMA_VERSION,
      state,
      state_hmac_sha256: trustedSnapshotHmac(state, this._integrityKey),
    };
  }

  digest() { return sha256(canonicalJson(this._state)); }

  readReceiptByIdentity(identity) {
    const receipt = this._state.receipts_by_identity[identity];
    return receipt === undefined ? undefined : deepClone(receipt);
  }

  readReceiptById(receiptId) {
    const receipt = this._state.receipts_by_id[receiptId];
    return receipt === undefined ? undefined : deepClone(receipt);
  }

  // JavaScript execution is synchronous here. The callback receives a private
  // working copy only: commit a fresh detached copy after validation, so a
  // callback cannot retain an alias to the installed state. Promise/thenable
  // callbacks and re-entry would let work escape this synchronous boundary.
  transact(callback) {
    assert(typeof callback === 'function', 'transaction callback must be a function');
    if (this._transactionInProgress) {
      this._transactionReentryDetected = true;
      throw new Error('reentrant transaction is forbidden');
    }
    this._transactionInProgress = true;
    this._transactionReentryDetected = false;
    try {
      const candidate = deepClone(this._state);
      const result = callback(candidate);
      if (result !== null && (typeof result === 'object' || typeof result === 'function') && typeof result.then === 'function') {
        throw new Error('asynchronous transaction callback is forbidden');
      }
      assert(!this._transactionReentryDetected, 'reentrant transaction is forbidden');
      // Detach before validation. This both removes callback-held aliases and
      // makes validation and the installed state observe exactly one JSON value.
      const committed = deepClone(candidate);
      validateState(committed);
      this._state = committed;
      return result;
    } finally {
      this._transactionInProgress = false;
      this._transactionReentryDetected = false;
    }
  }
}

function ownerStateFor(state, ownerId) {
  assert(isSafeMapKey(ownerId), 'owner id must be a safe non-empty map key');
  if (!Object.prototype.hasOwnProperty.call(state.owners, ownerId)) state.owners[ownerId] = emptyOwnerState();
  return state.owners[ownerId];
}

function saveTerminalReceipt(state, identity, receipt) {
  assert(TERMINAL_STATES.has(receipt.commit_state), 'only terminal receipts may be saved');
  assert(receipt.commit_state !== 'prepared', 'prepared receipt is forbidden');
  assert(!Object.prototype.hasOwnProperty.call(state.receipts_by_identity, identity), `receipt identity already exists: ${identity}`);
  assert(!Object.prototype.hasOwnProperty.call(state.receipts_by_id, receipt.receipt_id), `receipt id already exists: ${receipt.receipt_id}`);
  state.receipts_by_identity[identity] = receipt;
  state.receipts_by_id[receipt.receipt_id] = receipt;
}

module.exports = {
  OfflineTransactionStore,
  TERMINAL_STATES,
  assert,
  canonicalJson,
  deepClone,
  emptyOwnerState,
  originIdentity,
  ownerStateFor,
  saveTerminalReceipt,
  semanticIdentity,
  sha256,
  trustedSnapshotHmac,
};
