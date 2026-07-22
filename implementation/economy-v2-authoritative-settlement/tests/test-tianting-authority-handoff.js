'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const packageRoot = path.resolve(__dirname, '..');
const workspaceRoot = path.resolve(packageRoot, '..', '..');
const contractPath = path.join(packageRoot, 'contract', 'tianting-authority-receipt-input-contract.json');
const packageContractPath = path.join(packageRoot, 'package-contract.json');
const tiantingContractPath = path.join(workspaceRoot, 'docs', '物编', '天庭篇主线遭遇与通天塔规格包', 'authority', 'tianting-progression-and-instance-authority-contract.json');
const tablePath = path.join(workspaceRoot, 'docs', '物编', '成长数值与经济裁决包', 'tables', 'economy-v2-resource-table.json');
const tideAdapterContractPath = path.join(packageRoot, 'contract', 'tide-trace-adapter-contract.json');
const tideFixtureClosureContractPath = path.join(packageRoot, 'contract', 'tide-trace-fixture-closure.json');

let assertions = 0;

function equal(actual, expected, message) {
  assertions += 1;
  assert.strictEqual(actual, expected, message);
}

function deepEqual(actual, expected, message) {
  assertions += 1;
  assert.deepStrictEqual(actual, expected, message);
}

function truthy(value, message) {
  assertions += 1;
  assert.ok(value, message);
}

function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function findRoute(contract, specId) {
  const route = contract.source_session_routes.find((item) => item.source_session_spec_id === specId);
  truthy(route, `handoff route exists for ${specId}`);
  return route;
}

function assertNullObject(object, name) {
  for (const [key, value] of Object.entries(object)) {
    equal(value, null, `${name}.${key} remains null`);
  }
}

function assertRuntimeKeysNull(value, logicalPath) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertRuntimeKeysNull(item, `${logicalPath}[${index}]`));
    return;
  }
  if (!value || typeof value !== 'object') {
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    const childPath = `${logicalPath}.${key}`;
    if (key === 'runtime_key' || /^runtime_.*_key$/.test(key) || /_runtime_key$/.test(key)) {
      equal(child, null, `${childPath} is null`);
    }
    assertRuntimeKeysNull(child, childPath);
  }
}

function assertExactObjectKeys(value, expected, logicalPath) {
  deepEqual(Object.keys(value).sort(), [...expected].sort(), `${logicalPath} has an exact closed field set`);
}

function assertNoForbiddenObjectFieldNames(value, forbiddenNames, logicalPath) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertNoForbiddenObjectFieldNames(item, forbiddenNames, `${logicalPath}[${index}]`));
    return;
  }
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    truthy(!forbiddenNames.has(key), `${logicalPath}.${key} is not an allowed handoff object field`);
    assertNoForbiddenObjectFieldNames(child, forbiddenNames, `${logicalPath}.${key}`);
  }
}

function run() {
  const contract = loadJson(contractPath);
  const packageContract = loadJson(packageContractPath);
  const tianting = loadJson(tiantingContractPath);
  const resourceTable = loadJson(tablePath);
  const tideAdapterContract = loadJson(tideAdapterContractPath);
  const tideFixtureClosureContract = loadJson(tideFixtureClosureContractPath);
  const rawContract = fs.readFileSync(contractPath, 'utf8');

  assertExactObjectKeys(contract, [
    'schema_version', 'contract_id', 'display_name', 'package_status', 'runtime_handoff',
    'production_gate', 'implementation_handoff', 'purpose', 'source_contracts', 'handoff_boundary',
    'source_receipt_mapping', 'source_evidence_envelope', 'source_session_routes',
    'qualification_snapshot_boundary', 'future_economy_fields',
    'replay_disconnect_and_cleanup_boundary', 'negative_cases', 'deferred',
    'forbidden_field_names', 'acceptance_invariants', 'validation',
  ], 'handoff contract');
  assertExactObjectKeys(contract.source_contracts, ['tianting_authority', 'economy_v2_authority_core'], 'handoff source_contracts');
  assertExactObjectKeys(contract.source_contracts.tianting_authority, ['path', 'spec_id', 'receipt_contract_spec_id', 'status'], 'handoff TianTing source');
  assertExactObjectKeys(contract.source_contracts.economy_v2_authority_core, ['path', 'package', 'status', 'resource_table_reference', 'resource_table_version'], 'handoff economy source');
  assertExactObjectKeys(contract.handoff_boundary, ['handoff_kind', 'not_a_settlement_request', 'settlement_entry_rule', 'client_authority_rule', 'runtime_key'], 'handoff boundary');
  assertExactObjectKeys(contract.source_receipt_mapping, [
    'required_authoritative_input_fields', 'economy_v2_projection', 'source_evidence_envelope_spec_id',
    'source_evidence_envelope_rule', 'settlement_encounter_instance_boundary',
    'future_authority_resolver_only', 'forbidden_caller_fields', 'runtime_key',
  ], 'source receipt mapping');
  assertExactObjectKeys(contract.source_receipt_mapping.economy_v2_projection, [
    'actor_id', 'lifecycle_id', 'event_id', 'encounter_instance_id', 'authority_proof_ref', 'completed_tick',
  ], 'economy-v2 projection');
  assertExactObjectKeys(contract.source_receipt_mapping.settlement_encounter_instance_boundary, [
    'current_settlement_encounter_instance_id', 'normalized_source_instance_field',
    'route_normalization', 'future_derivation_input_order', 'future_derivation_rule', 'runtime_key',
  ], 'settlement encounter instance boundary');
  assertExactObjectKeys(contract.source_receipt_mapping.settlement_encounter_instance_boundary.route_normalization, [
    'TT_SPEC_SESSION_LINGXIAO_MAINLINE', 'TT_SPEC_SESSION_SEVEN_STAR',
    'TT_SPEC_SESSION_MANSION_NORMAL', 'TT_SPEC_SESSION_MANSION_NIGHTMARE',
  ], 'settlement encounter route normalization');
  assertExactObjectKeys(contract.source_evidence_envelope, [
    'spec_id', 'source_authority_contract_spec_id', 'source_completion_receipt_contract_spec_id',
    'runtime_key', 'only_authority_resolver_may_construct_or_verify', 'caller_input_rule',
    'required_bound_fields_source', 'mansion_additional_bound_fields_source', 'atomic_binding_rule',
    'candidate_member_status', 'member_status_rule', 'replay_mutation_rule',
    'normal_completion_cleanup_rule', 'non_economic_boundary',
  ], 'source evidence envelope');
  for (const route of contract.source_session_routes) {
    assertExactObjectKeys(route, [
      'source_session_spec_id', 'source_session_kind', 'source_success_event_spec_id',
      'economy_encounter_instance_id_source_field', 'source_instance_normalization_source_field',
      'member_snapshot_fields', 'handoff_candidate_rule', 'rejected_member_statuses',
      'future_economy_route_status',
    ], `source route ${route.source_session_spec_id}`);
  }
  assertExactObjectKeys(contract.qualification_snapshot_boundary, [
    'spec_id', 'runtime_key', 'current_qualification_snapshot_id', 'purpose',
    'required_source_evidence_fields', 'mansion_additional_source_evidence_fields',
    'nightmare_admission_not_reward_qualification', 'left_member_rule', 'dead_member_rule',
  ], 'qualification snapshot boundary');
  assertExactObjectKeys(contract.future_economy_fields, [
    'settlement_encounter_instance_id', 'owner_id', 'authority_origin_key',
    'origin_owner_binding_verified', 'event_type', 'source_profile', 'reward_slot_key',
    'qualification_snapshot_id', 'drop_roll_id', 'drop_roll_proof_ref', 'pity_pool_key',
    'award_plan', 'award_plan_hash', 'receipt_id', 'balance_delta', 'material_delta',
    'unique_grants', 'experience_delta', 'tower_snapshot_id', 'runtime_key',
  ], 'future economy fields');
  assertExactObjectKeys(contract.replay_disconnect_and_cleanup_boundary, [
    'source_idempotency_key_fields', 'source_replay_rule', 'economy_identity_rule',
    'normal_success_before_cleanup_rule', 'failure_rule', 'cleanup_ack_identity_by_session', 'disconnect_rule',
  ], 'replay/disconnect/cleanup boundary');
  for (const negative of contract.negative_cases) {
    assertExactObjectKeys(negative, ['spec_id', 'case', 'expected_result'], `negative case ${negative.spec_id}`);
  }
  assertExactObjectKeys(contract.deferred, [
    'tianting_source_profile_allocation', 'tianting_reward_slot_allocation',
    'tianting_event_type_selection', 'tianting_authoritative_success_events_for_seven_star_and_mansions',
    'tianting_economy_qualification_policy', 'tianting_source_evidence_resolver',
    'tianting_owner_and_origin_resolver', 'tianting_drop_roll_and_pity_policy',
    'tianting_xp_count_and_rounding_allocation', 'tianting_persistent_economic_receipts',
    'tianting_runtime_service_and_network_integration', 'runtime_key',
  ], 'deferred handoff work');
  assertExactObjectKeys(contract.validation, ['runner', 'strict_cross_contract_assertions', 'runtime_key'], 'handoff validation');
  deepEqual(contract.forbidden_field_names, [
    'y3_id', 'map_resource_key', 'item_id', 'item_key', 'currency_key', 'reward_amount',
    'reward_exp', 'currency_amount', 'item_amount', 'drop_probability', 'pity_threshold',
    'equipment_stat_value', 'material_drop_count', 'key_consumption_amount',
  ], 'forbidden handoff field names are fixed');
  assertNoForbiddenObjectFieldNames(contract, new Set(contract.forbidden_field_names), 'handoff');

  equal(contract.schema_version, 1, 'handoff schema version is fixed');
  equal(contract.contract_id, 'ECO_V2_TT_AUTHORITY_RECEIPT_INPUT_HANDOFF', 'handoff contract identity is fixed');
  equal(contract.package_status, 'offline-design-handoff', 'handoff remains design-only');
  equal(contract.runtime_handoff, false, 'handoff cannot become runtime');
  equal(contract.production_gate, 'closed', 'handoff production gate is closed');
  equal(contract.implementation_handoff, false, 'handoff cannot authorize implementation');
  equal(contract.handoff_boundary.not_a_settlement_request, true, 'handoff is not a settlement request');
  equal(contract.handoff_boundary.runtime_key, null, 'handoff boundary has no runtime key');

  const tiantingSource = contract.source_contracts.tianting_authority;
  const economySource = contract.source_contracts.economy_v2_authority_core;
  equal(path.resolve(path.dirname(contractPath), tiantingSource.path), tiantingContractPath, 'TianTing authority source path resolves exactly');
  equal(path.resolve(path.dirname(contractPath), economySource.path), packageContractPath, 'economy core source path resolves exactly');
  equal(tiantingSource.spec_id, tianting.identity.spec_id, 'TianTing authority spec matches source contract');
  equal(tiantingSource.receipt_contract_spec_id, tianting.receipt_and_idempotency_contract.spec_id, 'TianTing receipt contract matches source contract');
  equal(economySource.package, packageContract.package, 'economy package identity matches source contract');
  equal(economySource.status, packageContract.package_status, 'economy package status matches source contract');
  equal(economySource.resource_table_version, packageContract.frozen_input_contract.resource_table.resource_table_version, 'frozen resource table version matches economy core');
  equal(path.resolve(path.dirname(contractPath), economySource.resource_table_reference), tablePath, 'frozen resource table path resolves exactly');
  equal(path.resolve(path.dirname(tiantingContractPath), tianting.source_contracts.economy_v2_authority_receipt_input_handoff), contractPath, 'TianTing authority contract points back to this exact handoff');
  truthy(tianting.source_contracts.economy_v2_authority_receipt_input_handoff_rule.includes('null/deferred'), 'TianTing reverse handoff keeps economic values deferred');
  truthy(tianting.source_contracts.economy_v2_authority_receipt_input_handoff_rule.includes('不能创建结算请求'), 'TianTing reverse handoff cannot create a settlement request');
  equal(path.resolve(path.dirname(packageContractPath), packageContract.tianting_authority_handoff.contract), contractPath, 'economy package contract points to this exact TianTing handoff');
  equal(packageContract.tianting_authority_handoff.status, 'offline-design-handoff-only', 'economy package keeps TianTing handoff offline only');
  truthy(packageContract.tianting_authority_handoff.rule.includes('cannot invoke this materializer'), 'TianTing handoff cannot invoke materializer');
  equal(path.resolve(path.dirname(tideAdapterContractPath), tideAdapterContract.upstream.fixture_closure_contract), tideFixtureClosureContractPath, 'Tide adapter contract pins the exact external fixture closure');
  equal(tideFixtureClosureContract.contract_id, 'ECO_V2_TIDE_TRACE_FIXTURE_CLOSURE_V1', 'Tide fixture closure identity is fixed');
  truthy(tideAdapterContract.downstream_authority_attestation.attestation_ref_stability_rule.includes('must not encode or rotate'), 'Tide adapter requires an evidence-stable attestation reference');
  truthy(packageContract.frozen_input_contract.canonical_evidence.authority_attestation.attestation_ref_stability_rule.includes('must be stable'), 'economy package contract requires an evidence-stable attestation reference');

  deepEqual(contract.source_receipt_mapping.required_authoritative_input_fields, [
    'actor_id', 'actor_lifecycle_id', 'event_id', 'producer_spec_id', 'completed_tick',
    'authority_proof_ref', 'schema_version', 'source_session_spec_id',
    'source_session_instance_id', 'source_session_epoch', 'source_session_revision',
    'source_membership_snapshot_id', 'source_member_status',
  ], 'source receipt input field set is fixed');
  const sourceEvidence = tianting.economy_v2_handoff_source_evidence_contract;
  const handoffEvidence = contract.source_evidence_envelope;
  equal(contract.source_receipt_mapping.source_evidence_envelope_spec_id, sourceEvidence.spec_id, 'mapped receipt fields require the TianTing source-evidence envelope');
  truthy(contract.source_receipt_mapping.source_evidence_envelope_rule.includes('not caller-supplied'), 'mapped receipt fields are not caller input');
  deepEqual(contract.source_receipt_mapping.required_authoritative_input_fields, sourceEvidence.required_bound_fields, 'handoff mapping exactly reuses TianTing authority source-evidence fields');
  equal(handoffEvidence.spec_id, sourceEvidence.spec_id, 'handoff source-evidence spec matches TianTing authority contract');
  equal(handoffEvidence.source_authority_contract_spec_id, tianting.identity.spec_id, 'handoff source-evidence source authority contract matches TianTing');
  equal(handoffEvidence.source_completion_receipt_contract_spec_id, tianting.receipt_and_idempotency_contract.spec_id, 'handoff source-evidence receipt contract matches TianTing');
  equal(handoffEvidence.runtime_key, null, 'handoff source-evidence envelope has no runtime key');
  equal(handoffEvidence.only_authority_resolver_may_construct_or_verify, true, 'only authority resolver may construct or verify source-evidence envelope');
  truthy(handoffEvidence.caller_input_rule.includes('No client'), 'source-evidence envelope rejects direct caller input');
  equal(handoffEvidence.required_bound_fields_source, 'tianting_authority.economy_v2_handoff_source_evidence_contract.required_bound_fields', 'handoff source evidence has one field source of truth');
  equal(handoffEvidence.mansion_additional_bound_fields_source, 'tianting_authority.economy_v2_handoff_source_evidence_contract.mansion_additional_bound_fields', 'handoff mansion evidence has one field source of truth');
  deepEqual(sourceEvidence.mansion_additional_bound_fields, ['rotation_snapshot_id', 'quadrant', 'difficulty'], 'TianTing mansion source-evidence fields are fixed');
  assertExactObjectKeys(sourceEvidence.session_route_instance_normalization, [
    'TT_SPEC_SESSION_LINGXIAO_MAINLINE', 'TT_SPEC_SESSION_SEVEN_STAR',
    'TT_SPEC_SESSION_MANSION_NORMAL', 'TT_SPEC_SESSION_MANSION_NIGHTMARE',
  ], 'TianTing source-evidence session route normalization');
  equal(sourceEvidence.candidate_member_status, 'active', 'TianTing source evidence requires active member status');
  equal(handoffEvidence.candidate_member_status, sourceEvidence.candidate_member_status, 'handoff candidate member status matches TianTing source evidence');
  truthy(sourceEvidence.atomic_binding_rule.includes('原子绑定'), 'TianTing source evidence atomically binds receipt and snapshot');
  truthy(handoffEvidence.atomic_binding_rule.includes('Mixed snapshots'), 'handoff rejects mixed snapshots and revisions');
  truthy(sourceEvidence.replay_mutation_rule.includes('漂移均拒绝'), 'TianTing source evidence rejects replay drift');
  truthy(handoffEvidence.replay_mutation_rule.includes('changed required_bound_fields'), 'handoff rejects mapped-field replay drift');
  truthy(handoffEvidence.member_status_rule.includes('left'), 'handoff excludes left members from source evidence candidates');
  truthy(handoffEvidence.normal_completion_cleanup_rule.includes('source fact only'), 'cleanup preserves only source fact');
  truthy(handoffEvidence.non_economic_boundary.includes('null/deferred'), 'source-evidence envelope keeps all economic values deferred');
  assertExactObjectKeys(sourceEvidence, [
    'spec_id', 'decision_status', 'runtime_key', 'source_completion_receipt_contract_spec_id',
    'record_scope', 'only_issuer', 'caller_input_rule', 'required_bound_fields',
    'session_route_instance_normalization', 'mansion_additional_bound_fields',
    'candidate_member_status', 'member_binding_rule', 'atomic_binding_rule',
    'replay_mutation_rule', 'normal_completion_cleanup_rule', 'non_economic_boundary',
  ], 'TianTing source evidence contract');
  deepEqual(contract.source_receipt_mapping.economy_v2_projection, {
    actor_id: 'actor_id',
    lifecycle_id: 'actor_lifecycle_id',
    event_id: 'event_id',
    encounter_instance_id: null,
    authority_proof_ref: 'authority_proof_ref',
    completed_tick: 'completed_tick',
  }, 'source-to-economy projection is fixed');
  const instanceBoundary = contract.source_receipt_mapping.settlement_encounter_instance_boundary;
  equal(instanceBoundary.current_settlement_encounter_instance_id, null, 'handoff cannot fabricate an economy encounter instance id');
  deepEqual(instanceBoundary.future_derivation_input_order, [
    'source_session_spec_id', 'source_session_instance_id', 'source_session_epoch',
  ], 'future encounter identity derives only from immutable source-session identity');
  equal(instanceBoundary.runtime_key, null, 'future encounter identity has no runtime key');
  truthy(instanceBoundary.future_derivation_rule.includes('Raw session_instance_id or raid_instance_id alone must never'), 'raw session ids cannot become economic semantic identities');
  truthy(contract.acceptance_invariants[2].includes('共同派生'), 'future economic encounter identity uses session spec, normalized instance, and epoch together');
  deepEqual(contract.source_receipt_mapping.future_authority_resolver_only, [
    'source_evidence_envelope', 'owner_id', 'authority_origin_key', 'origin_owner_binding_verified',
  ], 'owner and origin resolution remain authority-only');
  for (const field of [
    'owner_id', 'event_type', 'source_profile', 'reward_slot_key',
    'source_evidence_envelope',
    'qualification_snapshot_id', 'drop_roll_id', 'pity', 'award_plan', 'receipt_id',
    'balance_delta', 'material_delta', 'unique_grants', 'experience_delta',
  ]) {
    truthy(contract.source_receipt_mapping.forbidden_caller_fields.includes(field), `${field} is forbidden caller input`);
  }

  const mainline = findRoute(contract, 'TT_SPEC_SESSION_LINGXIAO_MAINLINE');
  equal(mainline.source_success_event_spec_id, 'TT_SPEC_EVENT_LINGXIAO_OUTER_COURT_SUCCESS', 'mainline success event is the authoritative completion event');
  equal(mainline.economy_encounter_instance_id_source_field, null, 'mainline cannot directly map a raw session id to an economy encounter');
  equal(mainline.source_instance_normalization_source_field, 'session_instance_id', 'mainline normalizes its source session instance field');
  deepEqual(mainline.member_snapshot_fields, tianting.mainline_final_session.member_snapshot_fields, 'mainline member snapshot mapping matches source contract');
  truthy(mainline.handoff_candidate_rule.includes('active 权威快照'), 'mainline candidate requires active authority snapshot');
  equal(mainline.future_economy_route_status, 'source_profile_unmapped_no_settlement_request', 'mainline cannot settle before profile allocation');
  truthy(mainline.rejected_member_statuses.includes('left'), 'mainline left members cannot become candidates');

  const sevenStar = findRoute(contract, 'TT_SPEC_SESSION_SEVEN_STAR');
  equal(sevenStar.source_success_event_spec_id, null, 'Seven Star success event remains deferred');
  equal(sevenStar.economy_encounter_instance_id_source_field, null, 'Seven Star cannot directly map a raw session id to an economy encounter');
  equal(sevenStar.source_instance_normalization_source_field, 'session_instance_id', 'Seven Star normalizes its source session instance field');
  equal(sevenStar.future_economy_route_status, 'completion_event_and_source_profile_deferred', 'Seven Star cannot settle before success event and profile allocation');
  truthy(sevenStar.rejected_member_statuses.includes('owner_disconnect'), 'Seven Star disconnect cannot become a candidate');
  truthy(tianting.seven_star_solo_session.failure_triggers.includes('owner_disconnect'), 'Seven Star disconnect source fact exists');

  const mansionNormal = findRoute(contract, 'TT_SPEC_SESSION_MANSION_NORMAL');
  const mansionNightmare = findRoute(contract, 'TT_SPEC_SESSION_MANSION_NIGHTMARE');
  deepEqual(contract.source_session_routes.map((route) => route.source_session_spec_id), [
    'TT_SPEC_SESSION_LINGXIAO_MAINLINE', 'TT_SPEC_SESSION_SEVEN_STAR',
    'TT_SPEC_SESSION_MANSION_NORMAL', 'TT_SPEC_SESSION_MANSION_NIGHTMARE',
  ], 'source session route set and order are fixed');
  for (const route of [mansionNormal, mansionNightmare]) {
    equal(route.source_success_event_spec_id, null, `${route.source_session_spec_id} success event remains deferred`);
    equal(route.economy_encounter_instance_id_source_field, null, `${route.source_session_spec_id} cannot directly map a raw raid id to an economy encounter`);
    equal(route.source_instance_normalization_source_field, 'raid_instance_id', `${route.source_session_spec_id} normalizes its source raid instance field`);
    truthy(route.rejected_member_statuses.includes('left'), `${route.source_session_spec_id} left members are rejected`);
    truthy(route.future_economy_route_status.includes('source_profile_deferred'), `${route.source_session_spec_id} keeps source profile deferred`);
  }
  truthy(mansionNightmare.rejected_member_statuses.includes('quadrant_mismatch'), 'nightmare quadrant mismatch is rejected');
  truthy(mansionNightmare.handoff_candidate_rule.includes('不等于 economy-v2 奖励资格快照'), 'nightmare admission is not an economic qualification');

  const snapshot = contract.qualification_snapshot_boundary;
  equal(snapshot.spec_id, 'TT_SPEC_ECONOMY_HANDOFF_QUALIFICATION_SNAPSHOT', 'logical handoff snapshot identity is fixed');
  equal(snapshot.runtime_key, null, 'logical handoff snapshot has no runtime key');
  equal(snapshot.current_qualification_snapshot_id, null, 'economy qualification snapshot is not fabricated');
  deepEqual(snapshot.required_source_evidence_fields, [
    'actor_id', 'actor_lifecycle_id', 'event_id', 'source_session_spec_id',
    'source_session_instance_id', 'source_session_epoch', 'source_session_revision',
    'source_membership_snapshot_id', 'source_member_status', 'authority_proof_ref', 'completed_tick',
  ], 'qualification snapshot evidence fields are fixed');
  deepEqual(snapshot.mansion_additional_source_evidence_fields, [
    'rotation_snapshot_id', 'quadrant', 'difficulty',
  ], 'mansion qualification evidence fields are fixed');
  truthy(snapshot.nightmare_admission_not_reward_qualification.includes('不是'), 'nightmare credential cannot become economic qualification');
  truthy(snapshot.left_member_rule.includes('不得重连'), 'left members cannot reconnect for a future economic input');
  truthy(snapshot.dead_member_rule.includes('不臆造'), 'death behavior does not invent economic qualification');

  assertNullObject(contract.future_economy_fields, 'future_economy_fields');
  const replay = contract.replay_disconnect_and_cleanup_boundary;
  deepEqual(replay.source_idempotency_key_fields, tianting.receipt_and_idempotency_contract.idempotency_key_fields, 'handoff reuses TianTing source idempotency fields');
  truthy(replay.economy_identity_rule.includes('source_profile 与 reward_slot_key 均为 null'), 'economy identity is prohibited before allocation');
  truthy(replay.normal_success_before_cleanup_rule.includes('不自动提交经济收据'), 'cleanup cannot turn success into an automatic economic receipt');
  truthy(replay.failure_rule.includes('不能形成交接候选'), 'failure paths cannot form candidates');
  deepEqual(replay.cleanup_ack_identity_by_session.TT_SPEC_SESSION_LINGXIAO_MAINLINE, tianting.mainline_final_session.cleanup_ack_identity_fields, 'mainline cleanup identity matches source contract');
  deepEqual(replay.cleanup_ack_identity_by_session.TT_SPEC_SESSION_SEVEN_STAR, tianting.seven_star_solo_session.cleanup_ack_identity_fields, 'Seven Star cleanup identity matches source contract');
  deepEqual(replay.cleanup_ack_identity_by_session.TT_SPEC_SESSION_MANSION_NORMAL, tianting.mansion_raid_session.cleanup_ack_identity_fields, 'normal mansion cleanup identity matches source contract');
  deepEqual(replay.cleanup_ack_identity_by_session.TT_SPEC_SESSION_MANSION_NIGHTMARE, tianting.mansion_raid_session.cleanup_ack_identity_fields, 'nightmare mansion cleanup identity matches source contract');
  assertExactObjectKeys(replay.cleanup_ack_identity_by_session, [
    'TT_SPEC_SESSION_LINGXIAO_MAINLINE', 'TT_SPEC_SESSION_SEVEN_STAR',
    'TT_SPEC_SESSION_MANSION_NORMAL', 'TT_SPEC_SESSION_MANSION_NIGHTMARE',
  ], 'cleanup acknowledgement session set is fixed');
  truthy(replay.disconnect_rule.includes('left'), 'disconnect rule uses left state');

  deepEqual(contract.negative_cases.map((item) => item.spec_id), [
    'ECO_V2_TT_NEGATIVE_CLIENT_REWARD_INPUT',
    'ECO_V2_TT_NEGATIVE_UNMAPPED_PROFILE',
    'ECO_V2_TT_NEGATIVE_DIFU_PROGRESS_KEY',
    'ECO_V2_TT_NEGATIVE_PROXY_OR_STALE_MEMBER',
    'ECO_V2_TT_NEGATIVE_NIGHTMARE_ADMISSION_CONFUSION',
    'ECO_V2_TT_NEGATIVE_CLEANUP_REPLAY',
    'ECO_V2_TT_NEGATIVE_SOURCE_EVIDENCE_DRIFT',
    'ECO_V2_TT_NEGATIVE_DUPLICATE_EVENT',
    'ECO_V2_TT_NEGATIVE_RUNTIME_LEAK',
  ], 'handoff negative cases are complete and stable');
  const sourceEvidenceDrift = contract.negative_cases.find((item) => item.spec_id === 'ECO_V2_TT_NEGATIVE_SOURCE_EVIDENCE_DRIFT');
  truthy(sourceEvidenceDrift.case.includes('source_session_revision'), 'source-evidence drift negative case covers revision');
  truthy(sourceEvidenceDrift.case.includes('source_membership_snapshot_id'), 'source-evidence drift negative case covers membership snapshot');
  truthy(sourceEvidenceDrift.case.includes('source_member_status'), 'source-evidence drift negative case covers member status');
  truthy(sourceEvidenceDrift.case.includes('rotation_snapshot_id'), 'source-evidence drift negative case covers rotation snapshot');
  truthy(sourceEvidenceDrift.expected_result.includes('without_second_candidate_qualification_or_economic_side_effect'), 'source-evidence drift has zero-effect rejection');
  for (const deferredValue of Object.values(contract.deferred)) {
    equal(deferredValue, null, 'all future economic and runtime work remains deferred');
  }
  assertRuntimeKeysNull(contract, 'handoff');
  truthy(!/(?:HG_DROP|CUR_|MAT_|EQ_|ART_|PITY_)/.test(rawContract), 'handoff does not embed a profile, currency, material, item, or pity key');
  equal((rawContract.match(/DF_PROGRESS_YANLUO_HALL_CLEARED/g) || []).length, 1, 'Difu progress key appears only in its explicit negative boundary');
  truthy(!JSON.stringify(resourceTable).includes('"TT_'), 'frozen economy-v2 table has no TianTing source allocation');
  truthy(tianting.hard_boundaries.economy_rule.includes('不授予'), 'TianTing authority contract forbids economic issuance');
  truthy(tianting.recovery_contract.team.member_disconnect.completion_and_reward_eligibility.includes('cannot_receive'), 'TianTing left-member reward exclusion is preserved');
  equal(contract.validation.runner, 'tests/test-tianting-authority-handoff.js', 'handoff validator path is fixed');
  equal(contract.validation.strict_cross_contract_assertions, true, 'handoff requires strict cross-contract assertions');
  equal(contract.validation.runtime_key, null, 'handoff validation has no runtime key');

  process.stdout.write(`PASS: ${assertions} economy-v2 TianTing authority-handoff assertions\n`);
}

try {
  run();
} catch (error) {
  process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
  process.exitCode = 1;
}
