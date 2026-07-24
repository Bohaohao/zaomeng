'use strict';

const crypto = require('crypto');

const CANONICAL_GATE_IDS = Object.freeze([
  'P0-GATE-01-all-12-fixed-builds-declared-and-replayed',
  'P0-GATE-02-general-physical-magical-defense-formulas-adopted',
  'P0-GATE-03-hit-crit-control-formulas-adopted',
  'P0-GATE-04-engine-action-frame-and-speed-readback',
  'P0-GATE-05-terrain-collision-and-camera-fixture',
  'P0-GATE-06-authoritative-one-to-four-member-replays',
  'P0-GATE-07-stable-object-keys-and-template-readback'
]);

const ABSOLUTE_PROJECTION_FIELDS = Object.freeze([
  'target_object_or_unit_id',
  'hp_max',
  'attack_phy',
  'attack_mag',
  'defense_phy',
  'defense_mag',
  'attack_speed',
  'attack_interval_seconds',
  'move_speed_field',
  'skill_damage',
  'skill_duration_seconds'
]);

const DIGEST_FIELDS = Object.freeze([
  'engine_build_digest',
  'object_inventory_snapshot_digest',
  'template_readback_basis_digest',
  'canonical_artifact_digest',
  'capture_basis_digest',
  'input_trace_digest'
]);

const DISALLOWED_REFERENCE_TOKENS = Object.freeze([
  'synthetic',
  'schema-test',
  'test-only',
  'preflight',
  'not-a-map-write',
  'deferred',
  'client://'
]);

const REVISION_FAMILY_FIELDS = Object.freeze([
  'engine_build_digest',
  'real_project_revision',
  'map_or_fixture_revision',
  'object_inventory_snapshot_digest',
  'template_readback_basis_digest',
  'capture_basis_digest'
]);

const IDENTIFIER_FIELDS = Object.freeze([
  'evidence_id',
  'source_capture_session_id',
  'capture_run_id',
  'real_project_revision',
  'map_or_fixture_revision'
]);

const EXTERNAL_REFERENCE_FIELDS = Object.freeze([
  'capture_provider_proof_ref',
  'collector_identity_ref',
  'reviewer_identity_ref',
  'external_artifact_ref'
]);

const GATE_SCOPE_FIELDS = Object.freeze([
  'scope_kind',
  'profile_id',
  'deterministic_run_index',
  'party_member_count',
  'formula_family',
  'readback_class'
]);

const FIXED_BUILD_PROFILE_IDS = Object.freeze([
  'CAL-C01-L41-v1',
  'CAL-C01-L55-v1',
  'CAL-C01-L60-v1',
  'CAL-C02-L41-v1',
  'CAL-C02-L55-v1',
  'CAL-C02-L60-v1',
  'CAL-C03-L41-v1',
  'CAL-C03-L55-v1',
  'CAL-C03-L60-v1',
  'CAL-C04-L41-v1',
  'CAL-C04-L55-v1',
  'CAL-C04-L60-v1'
]);

const SUBMISSION_ENVELOPE_FIELDS = Object.freeze([
  'evidence_id',
  'gate_id',
  'evidence_kind',
  'source_capture_session_id',
  'capture_run_id',
  'capture_provider_proof_ref',
  'engine_build_digest',
  'real_project_revision',
  'map_or_fixture_revision',
  'object_inventory_snapshot_digest',
  'template_readback_basis_digest',
  'canonical_artifact_digest',
  'capture_basis_digest',
  'input_trace_digest',
  'recorded_authoritative_instant',
  'collector_identity_ref',
  'reviewer_identity_ref',
  'external_artifact_ref',
  'gate_scope'
]);

const FORBIDDEN_SUBMISSION_FIELDS = Object.freeze([
  ...ABSOLUTE_PROJECTION_FIELDS,
  'stable_object_key',
  'source_template_id',
  'field_reference',
  'resource_id',
  'object_id',
  'unit_id',
  'object_binding',
  'template_binding',
  'target_selector',
  'object_field_binding',
  'resource_binding',
  'gate_promotion',
  'adoption_decision',
  'reward',
  'receipt',
  'economy_input'
]);

const EXPECTED_GATE_SCOPE_DECLARATIONS = Object.freeze([
  Object.freeze({
    gate_id: CANONICAL_GATE_IDS[0],
    scope_kind: 'fixed_build_replay',
    profile_id: 'required_canonical_profile',
    deterministic_run_index: 'required_1_to_3',
    party_member_count: null,
    formula_family: null,
    readback_class: null
  }),
  Object.freeze({
    gate_id: CANONICAL_GATE_IDS[1],
    scope_kind: 'formula_observation',
    profile_id: null,
    deterministic_run_index: null,
    party_member_count: null,
    formula_family: 'physical_magical_defense_penetration',
    readback_class: null
  }),
  Object.freeze({
    gate_id: CANONICAL_GATE_IDS[2],
    scope_kind: 'formula_observation',
    profile_id: null,
    deterministic_run_index: null,
    party_member_count: null,
    formula_family: 'hit_crit_control',
    readback_class: null
  }),
  Object.freeze({
    gate_id: CANONICAL_GATE_IDS[3],
    scope_kind: 'engine_readback',
    profile_id: null,
    deterministic_run_index: null,
    party_member_count: null,
    formula_family: null,
    readback_class: 'engine_action_frame_speed'
  }),
  Object.freeze({
    gate_id: CANONICAL_GATE_IDS[4],
    scope_kind: 'terrain_camera_fixture',
    profile_id: null,
    deterministic_run_index: null,
    party_member_count: null,
    formula_family: null,
    readback_class: 'terrain_collision_camera'
  }),
  Object.freeze({
    gate_id: CANONICAL_GATE_IDS[5],
    scope_kind: 'authority_party_replay',
    profile_id: null,
    deterministic_run_index: null,
    party_member_count: 'required_1_to_4',
    formula_family: null,
    readback_class: null
  }),
  Object.freeze({
    gate_id: CANONICAL_GATE_IDS[6],
    scope_kind: 'object_template_readback',
    profile_id: null,
    deterministic_run_index: null,
    party_member_count: null,
    formula_family: null,
    readback_class: 'object_template_inventory'
  })
]);

const EVIDENCE_CONTRACT_FIELDS = Object.freeze([
  'schema_version',
  'identity',
  'source_calibration_contract',
  'capture_chain',
  'support_artifacts',
  'submission_envelope',
  'gate_scope_contract',
  'gate_collection_plans',
  'synthetic_fixture_policy',
  'adoption_controls',
  'deferred_outputs',
  'acceptance'
]);

const EVIDENCE_IDENTITY_FIELDS = Object.freeze([
  'spec_id',
  'display_name',
  'package_status',
  'production_gate',
  'runtime_handoff',
  'actual_capture_provider',
  'actual_y3_project_ref',
  'accepted_evidence_ledger',
  'adoption_decision',
  'absolute_projection_payload'
]);

const CAPTURE_CHAIN_FIELDS = Object.freeze([
  'chain_status',
  'collector_may_read_but_not_write',
  'submission_is_not_adoption',
  'canonicalization_rule',
  'stages',
  'required_environment_snapshot_fields'
]);

const CAPTURE_STAGE_FIELDS = Object.freeze(['stage_id', 'purpose', 'output']);

const ENVIRONMENT_SNAPSHOT_FIELDS = Object.freeze([
  'engine_build_digest',
  'real_project_revision',
  'map_or_fixture_revision',
  'object_inventory_snapshot_digest',
  'template_readback_basis_digest',
  'capture_clock_basis',
  'collector_toolchain_digest'
]);

const CAPTURE_STAGE_IDS = Object.freeze([
  'CAL-EVID-STAGE-01-environment-attestation',
  'CAL-EVID-STAGE-02-readonly-capture',
  'CAL-EVID-STAGE-03-canonicalization',
  'CAL-EVID-STAGE-04-independent-review',
  'CAL-EVID-STAGE-05-gate-adoption'
]);

const CAPTURE_STAGE_OUTPUTS = Object.freeze([
  'external_environment_attestation_reference',
  'external_raw_capture_reference',
  'external_canonical_artifact_reference',
  'external_independent_review_reference',
  'external_adoption_decision_reference'
]);

const SOURCE_CALIBRATION_FIELDS = Object.freeze(['artifact', 'contract_id', 'content_sha256', 'required_gate_ids']);
const SUPPORT_ARTIFACT_FIELDS = Object.freeze(['source_snapshot', 'collection_templates', 'adoption_template', 'rule']);
const SUBMISSION_ENVELOPE_CONTRACT_FIELDS = Object.freeze([
  'required_fields',
  'evidence_kind',
  'digest_fields',
  'immutable_reference_scheme',
  'disallowed_reference_tokens',
  'forbidden_fields',
  'collector_reviewer_must_differ',
  'client_claims_are_not_evidence',
  'external_artifact_must_be_immutable_reference'
]);
const GATE_SCOPE_CONTRACT_FIELDS = Object.freeze(['rule', 'exact_fields', 'fixed_build_profile_ids', 'per_gate', 'coverage_preview_rule']);
const GATE_COLLECTION_PLAN_FIELDS = Object.freeze([
  'gate_id',
  'collection_status',
  'required_evidence_classes',
  'read_only_capture_focus',
  'rejection_conditions',
  'accepted_evidence_refs',
  'adoption_status'
]);
const SYNTHETIC_FIXTURE_POLICY_FIELDS = Object.freeze([
  'test_fixture_label',
  'may_validate_schema',
  'may_count_as_external_evidence',
  'may_change_gate_status',
  'may_create_adoption',
  'may_produce_absolute_projection'
]);
const ADOPTION_CONTROL_FIELDS = Object.freeze([
  'current_adoption_state',
  'automatic_gate_promotion',
  'requires_external_trusted_capture_provider',
  'requires_independent_reviewer',
  'requires_authorized_adoption_authority',
  'requires_all_seven_gate_decisions_before_projection_review',
  'current_satisfied_gate_ids',
  'projection_review_is_separate_from_gate_adoption'
]);
const DEFERRED_OUTPUT_FIELDS = Object.freeze([
  'accepted_evidence_ledger',
  'adoption_decision',
  ...ABSOLUTE_PROJECTION_FIELDS,
  'y3_object_write',
  'plugin_script',
  'lua_write',
  'map_write',
  'ui_write',
  'reward',
  'receipt',
  'economy_input'
]);
const ACCEPTANCE_FIELDS = Object.freeze(['id', 'rule']);

const SOURCE_SNAPSHOT_FIELDS = Object.freeze(['schema_version', 'identity', 'sources', 'external_capture_family', 'acceptance']);
const SOURCE_SNAPSHOT_IDENTITY_FIELDS = Object.freeze([
  'spec_id',
  'status',
  'runtime_handoff',
  'actual_external_capture_source',
  'accepted_evidence_ledger',
  'adoption_decision'
]);
const SOURCE_SNAPSHOT_SOURCE_FIELDS = Object.freeze([
  'source_id',
  'artifact',
  'contract_id',
  'content_sha256',
  'role',
  'may_supply_external_evidence',
  'may_supply_gate_adoption',
  'may_supply_absolute_projection'
]);
const EXTERNAL_CAPTURE_FAMILY_FIELDS = Object.freeze([
  'engine_build_digest',
  'real_project_revision',
  'map_or_fixture_revision',
  'object_inventory_snapshot_digest',
  'template_readback_basis_digest',
  'capture_provider_proof_ref',
  'rule'
]);
const SOURCE_SNAPSHOT_ACCEPTANCE = Object.freeze([
  'canonical parent bytes are fingerprinted',
  'no external evidence source exists locally',
  'no adoption decision or projection is present'
]);

const COLLECTION_TEMPLATE_FIELDS = Object.freeze(['schema_version', 'identity', 'common_submission_shape', 'gate_templates', 'template_values_are_not_evidence']);
const COLLECTION_TEMPLATE_IDENTITY_FIELDS = Object.freeze(['spec_id', 'status', 'actual_capture_records', 'accepted_evidence_ledger', 'absolute_projection_payload']);
const COLLECTION_COMMON_SHAPE_FIELDS = Object.freeze(['use', 'required_envelope_fields', 'forbidden_local_payloads']);
const COLLECTION_GATE_TEMPLATE_FIELDS = Object.freeze(['gate_id', 'external_record_shape', 'local_records']);

const ADOPTION_TEMPLATE_FIELDS = Object.freeze(['schema_version', 'identity', 'gate_decisions', 'rule']);
const ADOPTION_TEMPLATE_IDENTITY_FIELDS = Object.freeze(['spec_id', 'status', 'adoption_authority_ref', 'adoption_bundle_digest', 'absolute_projection_entitlement']);
const ADOPTION_GATE_DECISION_FIELDS = Object.freeze(['gate_id', 'decision', 'evidence_bundle_digest', 'reviewer_proof_ref', 'reason']);

function invariant(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function hasOwn(value, key) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function nonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function exactArray(actual, expected, message) {
  invariant(Array.isArray(actual), `${message}: expected array`);
  invariant(actual.length === expected.length, `${message}: unexpected length`);
  for (let index = 0; index < expected.length; index += 1) {
    invariant(actual[index] === expected[index], `${message}: mismatch at ${index}`);
  }
}

function assertExactObjectKeys(value, expectedKeys, label) {
  invariant(value && typeof value === 'object' && !Array.isArray(value), `${label}: expected object`);
  const prototype = Object.getPrototypeOf(value);
  invariant(prototype === Object.prototype || prototype === null, `${label}: expected a plain data object`);
  invariant(Object.getOwnPropertySymbols(value).length === 0, `${label}: symbol properties are not allowed`);
  const actualKeys = Object.getOwnPropertyNames(value).sort();
  const sortedExpected = [...expectedKeys].sort();
  exactArray(actualKeys, sortedExpected, `${label} key set`);
  for (const key of actualKeys) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    invariant(descriptor && descriptor.enumerable === true && hasOwn(descriptor, 'value'), `${label}.${key} must be an enumerable data property`);
  }
}

function sha256Hex(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function assertNullFields(object, fields, label) {
  invariant(object && typeof object === 'object' && !Array.isArray(object), `${label}: expected object`);
  for (const field of fields) {
    invariant(hasOwn(object, field), `${label}.${field} must be reserved explicitly`);
    invariant(object[field] === null, `${label}.${field} must remain null`);
  }
}

function isSha256(value) {
  return typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
}

function isOpaqueIdentifier(value) {
  return typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$/.test(value);
}

function isExternalReference(value) {
  return typeof value === 'string' && /^external:\/\/[A-Za-z0-9][A-Za-z0-9._:/-]{2,255}$/.test(value);
}

function containsDisallowedReferenceToken(value, tokens) {
  const lower = value.toLowerCase();
  return tokens.some((token) => lower.includes(token));
}

function isUtcRfc3339Seconds(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(value)) {
    return false;
  }
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString() === `${value.slice(0, -1)}.000Z`;
}

function validateGateScope(contract, gateId, scope) {
  const scopeContract = contract.gate_scope_contract;
  assertExactObjectKeys(scope, GATE_SCOPE_FIELDS, 'submission gate_scope');
  const declaration = scopeContract.per_gate.find((entry) => entry.gate_id === gateId);
  const expectedDeclaration = EXPECTED_GATE_SCOPE_DECLARATIONS.find((entry) => entry.gate_id === gateId);
  invariant(declaration, 'submission gate scope gate declaration is missing');
  invariant(expectedDeclaration, 'submission gate scope expected declaration is missing');
  for (const field of ['gate_id', ...GATE_SCOPE_FIELDS]) {
    invariant(declaration[field] === expectedDeclaration[field], `submission gate scope contract drift for ${gateId}/${field}`);
  }
  invariant(scope.scope_kind === expectedDeclaration.scope_kind, `submission gate_scope.scope_kind drift for ${gateId}`);
  for (const field of ['profile_id', 'deterministic_run_index', 'party_member_count', 'formula_family', 'readback_class']) {
    const expected = expectedDeclaration[field];
    if (expected === null) {
      invariant(scope[field] === null, `submission gate_scope.${field} must be null for ${gateId}`);
    }
  }
  if (gateId === CANONICAL_GATE_IDS[0]) {
    invariant(FIXED_BUILD_PROFILE_IDS.includes(scope.profile_id), 'submission gate_scope.profile_id is not canonical');
    invariant(Number.isInteger(scope.deterministic_run_index) && scope.deterministic_run_index >= 1 && scope.deterministic_run_index <= 3, 'submission gate_scope.deterministic_run_index must be 1..3');
  } else if (gateId === CANONICAL_GATE_IDS[5]) {
    invariant(Number.isInteger(scope.party_member_count) && scope.party_member_count >= 1 && scope.party_member_count <= 4, 'submission gate_scope.party_member_count must be 1..4');
  } else if (gateId === CANONICAL_GATE_IDS[1] || gateId === CANONICAL_GATE_IDS[2]) {
    invariant(scope.formula_family === expectedDeclaration.formula_family, `submission gate_scope.formula_family drift for ${gateId}`);
  } else {
    invariant(scope.readback_class === expectedDeclaration.readback_class, `submission gate_scope.readback_class drift for ${gateId}`);
  }
  return true;
}

function summarizePreviewCoverage(gateId, submissions) {
  if (gateId === CANONICAL_GATE_IDS[0]) {
    const byProfile = new Map();
    for (const submission of submissions) {
      const scope = submission.gate_scope;
      const runs = byProfile.get(scope.profile_id) || new Map();
      invariant(!runs.has(scope.deterministic_run_index), `submission set cannot repeat fixed-build profile/run scope ${scope.profile_id}/${scope.deterministic_run_index}`);
      runs.set(scope.deterministic_run_index, submission);
      byProfile.set(scope.profile_id, runs);
    }
    const missing = [];
    for (const profileId of FIXED_BUILD_PROFILE_IDS) {
      const runs = byProfile.get(profileId) || new Map();
      const present = [...runs.values()];
      if (present.length > 1) {
        const inputDigest = present[0].input_trace_digest;
        const canonicalDigest = present[0].canonical_artifact_digest;
        for (const submission of present.slice(1)) {
          invariant(submission.input_trace_digest === inputDigest, `submission set has mixed input_trace_digest for ${profileId}`);
          invariant(submission.canonical_artifact_digest === canonicalDigest, `submission set has mixed canonical_artifact_digest for ${profileId}`);
        }
      }
      for (const runIndex of [1, 2, 3]) {
        if (!runs.has(runIndex)) {
          missing.push(`${profileId}/run-${runIndex}`);
        }
      }
    }
    return {
      expected_scope_count: FIXED_BUILD_PROFILE_IDS.length * 3,
      present_scope_count: submissions.length,
      missing_scopes: missing,
      coverage_status: missing.length === 0 ? 'structurally_complete_preview_not_adoptable' : 'incomplete_preview'
    };
  }
  if (gateId === CANONICAL_GATE_IDS[5]) {
    const presentCounts = new Set();
    for (const submission of submissions) {
      const memberCount = submission.gate_scope.party_member_count;
      invariant(!presentCounts.has(memberCount), `submission set cannot repeat party_member_count ${memberCount}`);
      presentCounts.add(memberCount);
    }
    const missing = [1, 2, 3, 4].filter((count) => !presentCounts.has(count));
    return {
      expected_member_counts: [1, 2, 3, 4],
      present_member_counts: [...presentCounts].sort((left, right) => left - right),
      missing_member_counts: missing,
      coverage_status: missing.length === 0 ? 'structurally_complete_preview_not_adoptable' : 'incomplete_preview'
    };
  }
  return {
    expected_scope_count: null,
    present_scope_count: submissions.length,
    missing_scopes: null,
    coverage_status: 'shape_only_preview_not_adoptable'
  };
}

function assertEvidenceContractKeysets(contract) {
  assertExactObjectKeys(contract, EVIDENCE_CONTRACT_FIELDS, 'evidence contract');
  assertExactObjectKeys(contract.identity, EVIDENCE_IDENTITY_FIELDS, 'evidence contract identity');
  assertExactObjectKeys(contract.source_calibration_contract, SOURCE_CALIBRATION_FIELDS, 'evidence source calibration contract');
  assertExactObjectKeys(contract.capture_chain, CAPTURE_CHAIN_FIELDS, 'capture chain');
  invariant(Array.isArray(contract.capture_chain.stages), 'capture chain stages must be an array');
  for (const stage of contract.capture_chain.stages) {
    assertExactObjectKeys(stage, CAPTURE_STAGE_FIELDS, 'capture chain stage');
  }
  assertExactObjectKeys(contract.support_artifacts, SUPPORT_ARTIFACT_FIELDS, 'support artifacts');
  assertExactObjectKeys(contract.submission_envelope, SUBMISSION_ENVELOPE_CONTRACT_FIELDS, 'submission envelope contract');
  assertExactObjectKeys(contract.gate_scope_contract, GATE_SCOPE_CONTRACT_FIELDS, 'gate scope contract');
  invariant(Array.isArray(contract.gate_scope_contract.per_gate), 'gate scope declarations must be an array');
  for (const declaration of contract.gate_scope_contract.per_gate) {
    assertExactObjectKeys(declaration, ['gate_id', ...GATE_SCOPE_FIELDS], 'gate scope declaration');
  }
  invariant(Array.isArray(contract.gate_collection_plans), 'gate collection plans must be an array');
  for (const plan of contract.gate_collection_plans) {
    assertExactObjectKeys(plan, GATE_COLLECTION_PLAN_FIELDS, 'gate collection plan');
  }
  assertExactObjectKeys(contract.synthetic_fixture_policy, SYNTHETIC_FIXTURE_POLICY_FIELDS, 'synthetic fixture policy');
  assertExactObjectKeys(contract.adoption_controls, ADOPTION_CONTROL_FIELDS, 'adoption controls');
  assertExactObjectKeys(contract.deferred_outputs, DEFERRED_OUTPUT_FIELDS, 'deferred outputs');
  invariant(Array.isArray(contract.acceptance), 'evidence acceptance must be an array');
  for (const acceptance of contract.acceptance) {
    assertExactObjectKeys(acceptance, ACCEPTANCE_FIELDS, 'evidence acceptance');
  }
}

function validateSubmissionContractBoundary(contract) {
  invariant(contract && typeof contract === 'object' && !Array.isArray(contract), 'evidence submission contract must be an object');
  assertEvidenceContractKeysets(contract);
  const identity = contract.identity;
  invariant(identity.spec_id === 'CAL_SPEC_P0_EVIDENCE_COLLECTION_AND_ADOPTION_V1', 'evidence submission contract identity drift');
  invariant(identity.package_status === 'offline-evidence-collection-plan-only', 'evidence submission contract status drift');
  invariant(identity.production_gate === 'closed' && identity.runtime_handoff === false, 'evidence submission contract must remain closed and offline');
  assertNullFields(identity, [
    'actual_capture_provider',
    'actual_y3_project_ref',
    'accepted_evidence_ledger',
    'adoption_decision',
    'absolute_projection_payload'
  ], 'evidence submission contract identity');

  const chain = contract.capture_chain;
  invariant(chain.chain_status === 'external_evidence_not_collected', 'evidence submission contract capture chain status drift');
  invariant(chain.collector_may_read_but_not_write === true && chain.submission_is_not_adoption === true, 'evidence submission contract capture chain boundary drift');
  exactArray(chain.required_environment_snapshot_fields, ENVIRONMENT_SNAPSHOT_FIELDS, 'evidence submission contract environment snapshot fields');
  exactArray(chain.stages.map((stage) => stage.stage_id), CAPTURE_STAGE_IDS, 'evidence submission contract capture stage sequence');
  exactArray(chain.stages.map((stage) => stage.output), CAPTURE_STAGE_OUTPUTS, 'evidence submission contract capture stage outputs');

  const envelope = contract.submission_envelope;
  exactArray(envelope.required_fields, SUBMISSION_ENVELOPE_FIELDS, 'evidence submission contract envelope fields');
  exactArray(envelope.digest_fields, DIGEST_FIELDS, 'evidence submission contract digest fields');
  exactArray(envelope.disallowed_reference_tokens, DISALLOWED_REFERENCE_TOKENS, 'evidence submission contract disallowed reference tokens');
  exactArray(envelope.forbidden_fields, FORBIDDEN_SUBMISSION_FIELDS, 'evidence submission contract forbidden fields');
  invariant(envelope.evidence_kind === 'real_y3_readonly_capture', 'evidence submission contract kind drift');
  invariant(envelope.immutable_reference_scheme === 'external://', 'evidence submission contract reference scheme drift');
  invariant(envelope.collector_reviewer_must_differ === true && envelope.client_claims_are_not_evidence === true && envelope.external_artifact_must_be_immutable_reference === true, 'evidence submission contract envelope boundary drift');

  const scopeContract = contract.gate_scope_contract;
  exactArray(scopeContract.exact_fields, GATE_SCOPE_FIELDS, 'evidence submission contract gate scope fields');
  exactArray(scopeContract.fixed_build_profile_ids, FIXED_BUILD_PROFILE_IDS, 'evidence submission contract fixed-build profiles');
  exactArray(scopeContract.per_gate.map((entry) => entry.gate_id), CANONICAL_GATE_IDS, 'evidence submission contract gate scope sequence');
  for (let index = 0; index < EXPECTED_GATE_SCOPE_DECLARATIONS.length; index += 1) {
    const declaration = scopeContract.per_gate[index];
    const expectedDeclaration = EXPECTED_GATE_SCOPE_DECLARATIONS[index];
    for (const field of ['gate_id', ...GATE_SCOPE_FIELDS]) {
      invariant(declaration[field] === expectedDeclaration[field], `evidence submission contract gate scope drift for ${expectedDeclaration.gate_id}/${field}`);
    }
  }

  const controls = contract.adoption_controls;
  invariant(controls.current_adoption_state === 'closed', 'evidence submission contract adoption state drift');
  invariant(controls.automatic_gate_promotion === false, 'evidence submission contract automatic promotion drift');
  invariant(controls.requires_external_trusted_capture_provider === true && controls.requires_independent_reviewer === true && controls.requires_authorized_adoption_authority === true, 'evidence submission contract adoption authority boundary drift');
  invariant(controls.requires_all_seven_gate_decisions_before_projection_review === true && controls.projection_review_is_separate_from_gate_adoption === true, 'evidence submission contract projection review boundary drift');
  exactArray(controls.current_satisfied_gate_ids, [], 'evidence submission contract satisfied gates');
  return true;
}

function validateSourceSnapshot(sourceSnapshot, calibrationContract, calibrationContractBytes) {
  invariant(sourceSnapshot && typeof sourceSnapshot === 'object' && !Array.isArray(sourceSnapshot), 'source snapshot must be an object');
  assertExactObjectKeys(sourceSnapshot, SOURCE_SNAPSHOT_FIELDS, 'source snapshot');
  invariant(sourceSnapshot.schema_version === 1, 'source snapshot schema drift');
  const identity = sourceSnapshot.identity;
  assertExactObjectKeys(identity, SOURCE_SNAPSHOT_IDENTITY_FIELDS, 'source snapshot identity');
  invariant(identity && identity.spec_id === 'CAL_SPEC_P0_EVIDENCE_SOURCE_SNAPSHOT_V1', 'source snapshot identity drift');
  invariant(identity.status === 'offline-source-snapshot-only' && identity.runtime_handoff === false, 'source snapshot must remain offline');
  assertNullFields(identity, ['actual_external_capture_source', 'accepted_evidence_ledger', 'adoption_decision'], 'source snapshot identity');
  invariant(Array.isArray(sourceSnapshot.sources) && sourceSnapshot.sources.length === 1, 'source snapshot must contain only the canonical P0 source');
  const source = sourceSnapshot.sources[0];
  assertExactObjectKeys(source, SOURCE_SNAPSHOT_SOURCE_FIELDS, 'source snapshot canonical source');
  invariant(source.source_id === 'CAL-SRC-P0-CANONICAL-GATES', 'source snapshot canonical source id drift');
  invariant(source.artifact === '../contract/cross-profession-combat-calibration-contract.json', 'source snapshot parent artifact drift');
  invariant(source.contract_id === calibrationContract.contract_id, 'source snapshot parent contract id drift');
  invariant(source.content_sha256 === sha256Hex(calibrationContractBytes), 'source snapshot parent digest drift');
  invariant(source.may_supply_external_evidence === false && source.may_supply_gate_adoption === false && source.may_supply_absolute_projection === false, 'source snapshot must not become evidence or adoption');
  const externalFamily = sourceSnapshot.external_capture_family;
  assertExactObjectKeys(externalFamily, EXTERNAL_CAPTURE_FAMILY_FIELDS, 'source snapshot external capture family');
  assertNullFields(externalFamily, [
    'engine_build_digest',
    'real_project_revision',
    'map_or_fixture_revision',
    'object_inventory_snapshot_digest',
    'template_readback_basis_digest',
    'capture_provider_proof_ref'
  ], 'source snapshot external capture family');
  exactArray(sourceSnapshot.acceptance, SOURCE_SNAPSHOT_ACCEPTANCE, 'source snapshot acceptance sequence');
  return true;
}

function validateCollectionTemplates(collectionTemplates, contract) {
  invariant(collectionTemplates && typeof collectionTemplates === 'object' && !Array.isArray(collectionTemplates), 'collection templates must be an object');
  assertExactObjectKeys(collectionTemplates, COLLECTION_TEMPLATE_FIELDS, 'collection templates');
  invariant(collectionTemplates.schema_version === 1, 'collection template schema drift');
  const identity = collectionTemplates.identity;
  assertExactObjectKeys(identity, COLLECTION_TEMPLATE_IDENTITY_FIELDS, 'collection template identity');
  invariant(identity && identity.spec_id === 'CAL_SPEC_P0_EVIDENCE_COLLECTION_TEMPLATES_V1', 'collection template identity drift');
  invariant(identity.status === 'offline-template-only', 'collection templates must remain offline-only');
  assertNullFields(identity, ['actual_capture_records', 'accepted_evidence_ledger', 'absolute_projection_payload'], 'collection template identity');
  const commonShape = collectionTemplates.common_submission_shape;
  assertExactObjectKeys(commonShape, COLLECTION_COMMON_SHAPE_FIELDS, 'collection templates common shape');
  invariant(commonShape && Array.isArray(commonShape.required_envelope_fields), 'collection templates common shape missing');
  exactArray(commonShape.required_envelope_fields, contract.submission_envelope.required_fields, 'collection template envelope sequence');
  invariant(Array.isArray(commonShape.forbidden_local_payloads) && commonShape.forbidden_local_payloads.length >= 5, 'collection templates forbidden local payloads missing');
  invariant(Array.isArray(collectionTemplates.gate_templates) && collectionTemplates.gate_templates.length === CANONICAL_GATE_IDS.length, 'collection templates must cover seven gates');
  exactArray(collectionTemplates.gate_templates.map((entry) => entry.gate_id), CANONICAL_GATE_IDS, 'collection template gate sequence');
  for (const entry of collectionTemplates.gate_templates) {
    assertExactObjectKeys(entry, COLLECTION_GATE_TEMPLATE_FIELDS, `collection template ${entry.gate_id}`);
    invariant(Array.isArray(entry.external_record_shape) && entry.external_record_shape.length >= 3, `${entry.gate_id} collection template is incomplete`);
    invariant(entry.local_records === null, `${entry.gate_id} collection template must not contain local records`);
  }
  invariant(collectionTemplates.template_values_are_not_evidence === true, 'collection templates must not count as evidence');
  return true;
}

function validateAdoptionDecisionTemplate(adoptionTemplate) {
  invariant(adoptionTemplate && typeof adoptionTemplate === 'object' && !Array.isArray(adoptionTemplate), 'adoption template must be an object');
  assertExactObjectKeys(adoptionTemplate, ADOPTION_TEMPLATE_FIELDS, 'adoption template');
  invariant(adoptionTemplate.schema_version === 1, 'adoption template schema drift');
  const identity = adoptionTemplate.identity;
  assertExactObjectKeys(identity, ADOPTION_TEMPLATE_IDENTITY_FIELDS, 'adoption template identity');
  invariant(identity && identity.spec_id === 'CAL_SPEC_P0_EXTERNAL_ADOPTION_DECISION_TEMPLATE_V1', 'adoption template identity drift');
  invariant(identity.status === 'not_created', 'adoption template must not become a decision');
  assertNullFields(identity, ['adoption_authority_ref', 'adoption_bundle_digest', 'absolute_projection_entitlement'], 'adoption template identity');
  invariant(Array.isArray(adoptionTemplate.gate_decisions) && adoptionTemplate.gate_decisions.length === CANONICAL_GATE_IDS.length, 'adoption template must contain seven empty decisions');
  exactArray(adoptionTemplate.gate_decisions.map((entry) => entry.gate_id), CANONICAL_GATE_IDS, 'adoption template gate sequence');
  for (const decision of adoptionTemplate.gate_decisions) {
    assertExactObjectKeys(decision, ADOPTION_GATE_DECISION_FIELDS, `adoption template ${decision.gate_id}`);
    assertNullFields(decision, ['decision', 'evidence_bundle_digest', 'reviewer_proof_ref', 'reason'], `adoption template ${decision.gate_id}`);
  }
  return true;
}

function validateContract(contract, calibrationContract, calibrationContractBytes, sourceSnapshot, collectionTemplates, adoptionTemplate) {
  invariant(contract && typeof contract === 'object' && !Array.isArray(contract), 'evidence contract must be an object');
  assertEvidenceContractKeysets(contract);
  invariant(contract.schema_version === 1, 'unsupported evidence contract schema');
  const identity = contract.identity;
  invariant(identity && identity.spec_id === 'CAL_SPEC_P0_EVIDENCE_COLLECTION_AND_ADOPTION_V1', 'evidence identity drift');
  invariant(identity.package_status === 'offline-evidence-collection-plan-only', 'evidence package status drift');
  invariant(identity.production_gate === 'closed' && identity.runtime_handoff === false, 'evidence package must remain closed and offline');
  assertNullFields(identity, [
    'actual_capture_provider',
    'actual_y3_project_ref',
    'accepted_evidence_ledger',
    'adoption_decision',
    'absolute_projection_payload'
  ], 'identity');

  invariant(calibrationContract && calibrationContract.contract_id === 'CAL_SPEC_CROSS_PROFESSION_ABSOLUTE_COMBAT_V1', 'parent calibration contract identity drift');
  invariant(Buffer.isBuffer(calibrationContractBytes), 'parent calibration contract bytes are required');
  const source = contract.source_calibration_contract;
  invariant(source && source.artifact === '../contract/cross-profession-combat-calibration-contract.json', 'parent calibration artifact drift');
  invariant(source.contract_id === calibrationContract.contract_id, 'parent calibration contract id drift');
  invariant(source.content_sha256 === sha256Hex(calibrationContractBytes), 'parent calibration contract digest drift');
  invariant(isSha256(source.content_sha256), 'parent calibration contract digest must be lowercase SHA-256');
  exactArray(source.required_gate_ids, CANONICAL_GATE_IDS, 'evidence source gate sequence');
  exactArray(calibrationContract.absolute_projection_gate.required_gate_ids, CANONICAL_GATE_IDS, 'parent P0 gate sequence');
  exactArray(calibrationContract.absolute_projection_gate.current_satisfied_gate_ids, [], 'parent P0 satisfied gates');

  const chain = contract.capture_chain;
  invariant(chain && chain.chain_status === 'external_evidence_not_collected', 'capture chain must remain unstarted');
  invariant(chain.collector_may_read_but_not_write === true && chain.submission_is_not_adoption === true, 'capture chain authority boundary drift');
  invariant(Array.isArray(chain.stages) && chain.stages.length === 5, 'capture chain must have five stages');
  exactArray(chain.stages.map((stage) => stage.stage_id), CAPTURE_STAGE_IDS, 'capture chain stage sequence');
  exactArray(chain.stages.map((stage) => stage.output), CAPTURE_STAGE_OUTPUTS, 'capture chain stage output sequence');
  exactArray(chain.required_environment_snapshot_fields, ENVIRONMENT_SNAPSHOT_FIELDS, 'capture chain environment snapshot fields');

  const envelope = contract.submission_envelope;
  invariant(envelope && envelope.evidence_kind === 'real_y3_readonly_capture', 'submission kind drift');
  exactArray(envelope.required_fields, SUBMISSION_ENVELOPE_FIELDS, 'submission envelope field sequence');
  exactArray(envelope.digest_fields, DIGEST_FIELDS, 'submission digest field sequence');
  invariant(envelope.immutable_reference_scheme === 'external://', 'submission immutable reference scheme drift');
  exactArray(envelope.disallowed_reference_tokens, DISALLOWED_REFERENCE_TOKENS, 'submission disallowed reference tokens');
  invariant(envelope.collector_reviewer_must_differ === true, 'collector/reviewer separation must remain required');
  invariant(envelope.client_claims_are_not_evidence === true, 'client claim boundary drift');
  invariant(envelope.external_artifact_must_be_immutable_reference === true, 'immutable artifact boundary drift');
  exactArray(envelope.forbidden_fields, FORBIDDEN_SUBMISSION_FIELDS, 'submission forbidden field sequence');

  const scopeContract = contract.gate_scope_contract;
  invariant(scopeContract && typeof scopeContract === 'object', 'gate scope contract is required');
  exactArray(scopeContract.exact_fields, GATE_SCOPE_FIELDS, 'gate scope field sequence');
  exactArray(scopeContract.fixed_build_profile_ids, FIXED_BUILD_PROFILE_IDS, 'gate scope fixed-build profile sequence');
  exactArray(calibrationContract.fixed_build_declaration_ledger.profiles.map((entry) => entry.profile_id), FIXED_BUILD_PROFILE_IDS, 'parent fixed-build profile sequence');
  invariant(Array.isArray(scopeContract.per_gate) && scopeContract.per_gate.length === CANONICAL_GATE_IDS.length, 'gate scope contract must cover seven gates');
  exactArray(scopeContract.per_gate.map((entry) => entry.gate_id), CANONICAL_GATE_IDS, 'gate scope gate sequence');
  for (let index = 0; index < scopeContract.per_gate.length; index += 1) {
    const declaration = scopeContract.per_gate[index];
    const expectedDeclaration = EXPECTED_GATE_SCOPE_DECLARATIONS[index];
    assertExactObjectKeys(declaration, ['gate_id', ...GATE_SCOPE_FIELDS], `gate scope declaration ${declaration.gate_id}`);
    for (const field of ['gate_id', ...GATE_SCOPE_FIELDS]) {
      invariant(declaration[field] === expectedDeclaration[field], `gate scope declaration drift for ${declaration.gate_id}/${field}`);
    }
  }

  const supportArtifacts = contract.support_artifacts;
  invariant(supportArtifacts && supportArtifacts.source_snapshot === 'source-snapshots.json', 'source snapshot artifact drift');
  invariant(supportArtifacts.collection_templates === 'templates/evidence-collection-templates.json', 'collection templates artifact drift');
  invariant(supportArtifacts.adoption_template === 'templates/adoption-decision-template.json', 'adoption template artifact drift');

  const plans = contract.gate_collection_plans;
  invariant(Array.isArray(plans) && plans.length === CANONICAL_GATE_IDS.length, 'exactly seven gate collection plans are required');
  const planIds = plans.map((plan) => plan.gate_id);
  exactArray(planIds, CANONICAL_GATE_IDS, 'gate collection plan sequence');
  for (const plan of plans) {
    invariant(plan.collection_status === 'blocked_pending_external_evidence', `${plan.gate_id} must remain blocked`);
    invariant(Array.isArray(plan.required_evidence_classes) && plan.required_evidence_classes.length > 0, `${plan.gate_id} requires evidence classes`);
    invariant(Array.isArray(plan.read_only_capture_focus) && plan.read_only_capture_focus.length > 0, `${plan.gate_id} requires read-only focus`);
    invariant(Array.isArray(plan.rejection_conditions) && plan.rejection_conditions.length > 0, `${plan.gate_id} requires rejection conditions`);
    invariant(plan.accepted_evidence_refs === null && plan.adoption_status === 'blocked_pending_external_evidence', `${plan.gate_id} cannot carry accepted evidence`);
  }

  const synthetic = contract.synthetic_fixture_policy;
  invariant(synthetic && synthetic.test_fixture_label === 'synthetic-schema-test-only', 'synthetic fixture label drift');
  invariant(synthetic.may_validate_schema === true, 'synthetic fixtures may only validate schema');
  invariant(synthetic.may_count_as_external_evidence === false && synthetic.may_change_gate_status === false && synthetic.may_create_adoption === false && synthetic.may_produce_absolute_projection === false, 'synthetic fixtures must not promote evidence');

  const controls = contract.adoption_controls;
  invariant(controls && controls.current_adoption_state === 'closed', 'adoption state must remain closed');
  invariant(controls.automatic_gate_promotion === false, 'automatic gate promotion is forbidden');
  invariant(controls.requires_external_trusted_capture_provider === true && controls.requires_independent_reviewer === true && controls.requires_authorized_adoption_authority === true, 'external adoption controls drift');
  invariant(controls.requires_all_seven_gate_decisions_before_projection_review === true && controls.projection_review_is_separate_from_gate_adoption === true, 'projection review separation drift');
  exactArray(controls.current_satisfied_gate_ids, [], 'evidence package satisfied gates');

  assertNullFields(contract.deferred_outputs, [
    'accepted_evidence_ledger',
    'adoption_decision',
    ...ABSOLUTE_PROJECTION_FIELDS,
    'y3_object_write',
    'plugin_script',
    'lua_write',
    'map_write',
    'ui_write',
    'reward',
    'receipt',
    'economy_input'
  ], 'deferred_outputs');

  invariant(Array.isArray(contract.acceptance) && contract.acceptance.length === 13, 'expected thirteen evidence acceptance checks');
  for (let index = 1; index <= 13; index += 1) {
    const id = `CAL-EVID-ACC-${String(index).padStart(3, '0')}`;
    invariant(contract.acceptance.some((entry) => entry.id === id), `missing evidence acceptance check ${id}`);
  }
  validateSourceSnapshot(sourceSnapshot, calibrationContract, calibrationContractBytes);
  validateCollectionTemplates(collectionTemplates, contract);
  validateAdoptionDecisionTemplate(adoptionTemplate);
  return true;
}

function validateSubmission(contract, submission) {
  validateSubmissionContractBoundary(contract);
  invariant(submission && typeof submission === 'object' && !Array.isArray(submission), 'evidence submission must be an object');
  assertExactObjectKeys(submission, SUBMISSION_ENVELOPE_FIELDS, 'submission');
  for (const field of SUBMISSION_ENVELOPE_FIELDS) {
    if (field === 'gate_scope') {
      invariant(hasOwn(submission, field) && submission[field] && typeof submission[field] === 'object' && !Array.isArray(submission[field]), 'submission requires an object gate_scope');
    } else {
      invariant(hasOwn(submission, field) && nonEmptyString(submission[field]), `submission requires non-empty ${field}`);
    }
  }
  invariant(submission.evidence_kind === 'real_y3_readonly_capture', 'submission evidence kind must be real_y3_readonly_capture');
  invariant(CANONICAL_GATE_IDS.includes(submission.gate_id), 'submission gate id is not canonical');
  for (const field of IDENTIFIER_FIELDS) {
    invariant(isOpaqueIdentifier(submission[field]), `submission ${field} must be an opaque identifier`);
    invariant(!containsDisallowedReferenceToken(submission[field], DISALLOWED_REFERENCE_TOKENS), `submission ${field} uses a disallowed reference token`);
  }
  for (const field of contract.submission_envelope.digest_fields) {
    invariant(isSha256(submission[field]), `submission ${field} must be lowercase SHA-256`);
  }
  invariant(isUtcRfc3339Seconds(submission.recorded_authoritative_instant), 'submission recorded_authoritative_instant must be a real UTC RFC3339 second');
  for (const field of EXTERNAL_REFERENCE_FIELDS) {
    invariant(isExternalReference(submission[field]), `submission ${field} must be an immutable external reference`);
    invariant(!containsDisallowedReferenceToken(submission[field], DISALLOWED_REFERENCE_TOKENS), `submission ${field} uses a disallowed reference token`);
  }
  invariant(submission.collector_identity_ref !== submission.reviewer_identity_ref, 'collector and reviewer must differ');
  validateGateScope(contract, submission.gate_id, submission.gate_scope);
  for (const field of FORBIDDEN_SUBMISSION_FIELDS) {
    invariant(!hasOwn(submission, field), `submission must not include ${field}`);
  }
  return {
    gate_id: submission.gate_id,
    collection_status: 'blocked_provider_unavailable',
    adoption_status: 'not_attempted',
    projection_status: 'not_attempted'
  };
}

function validateSubmissionSet(contract, submissions) {
  invariant(Array.isArray(submissions) && submissions.length > 0, 'submission set must be non-empty');
  const evidenceIds = new Set();
  const runIds = new Set();
  const revisionFamily = new Map();
  const outcomes = [];
  let gateId = null;
  for (const submission of submissions) {
    const outcome = validateSubmission(contract, submission);
    if (gateId === null) {
      gateId = submission.gate_id;
    } else {
      invariant(gateId === submission.gate_id, 'submission set must cover exactly one canonical gate');
    }
    invariant(!evidenceIds.has(submission.evidence_id), 'submission set cannot repeat evidence_id');
    evidenceIds.add(submission.evidence_id);
    invariant(!runIds.has(submission.capture_run_id), `submission set cannot repeat capture_run_id for ${submission.gate_id}`);
    runIds.add(submission.capture_run_id);
    for (const field of REVISION_FAMILY_FIELDS) {
      if (revisionFamily.has(field)) {
        invariant(revisionFamily.get(field) === submission[field], `submission set has mixed ${field}`);
      } else {
        revisionFamily.set(field, submission[field]);
      }
    }
    outcomes.push(outcome);
  }
  return {
    gate_id: gateId,
    review_bundle_status: 'blocked_provider_unavailable',
    outcomes,
    coverage: summarizePreviewCoverage(gateId, submissions)
  };
}

function attemptAdoption(contract, submission) {
  validateSubmission(contract, submission);
  throw new Error('offline evidence package cannot adopt a P0 gate or create an absolute projection');
}

module.exports = {
  ABSOLUTE_PROJECTION_FIELDS,
  CANONICAL_GATE_IDS,
  DIGEST_FIELDS,
  EXPECTED_GATE_SCOPE_DECLARATIONS,
  FIXED_BUILD_PROFILE_IDS,
  FORBIDDEN_SUBMISSION_FIELDS,
  SUBMISSION_ENVELOPE_FIELDS,
  attemptAdoption,
  sha256Hex,
  validateAdoptionDecisionTemplate,
  validateCollectionTemplates,
  validateContract,
  validateGateScope,
  validateSourceSnapshot,
  validateSubmission,
  validateSubmissionSet
};
