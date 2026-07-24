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

const FIELDWORK_GATE_IDS = Object.freeze([
  null,
  CANONICAL_GATE_IDS[6],
  CANONICAL_GATE_IDS[3],
  CANONICAL_GATE_IDS[4],
  CANONICAL_GATE_IDS[0],
  CANONICAL_GATE_IDS[1],
  CANONICAL_GATE_IDS[2],
  CANONICAL_GATE_IDS[5]
]);

const ONBOARDING_SEQUENCE = Object.freeze([
  'authorization_and_role_separation',
  'real_map_local_structural_preflight',
  'provider_qualification',
  'environment_attestation',
  'read_only_capture',
  'canonicalization_and_external_manifest',
  'independent_review_handoff',
  'external_adoption_authority'
]);

const ROLE_SEPARATION_PAIRS = Object.freeze([
  Object.freeze(['capture_provider', 'capture_operator']),
  Object.freeze(['capture_provider', 'independent_reviewer']),
  Object.freeze(['capture_provider', 'adoption_authority']),
  Object.freeze(['capture_operator', 'independent_reviewer']),
  Object.freeze(['capture_operator', 'adoption_authority']),
  Object.freeze(['independent_reviewer', 'adoption_authority'])
]);

const PROVIDER_REQUIRED_CLAIMS = Object.freeze([
  'authorized scope for read-only Y3/editor/authority observation',
  'isolated execution process and JSON/IPC or equivalent immutable transport',
  'authority-clock attestation capability',
  'toolchain identity and version attestation capability',
  'revocation status and incident-reporting capability'
]);

const PROVIDER_PROHIBITED_CLAIMS = Object.freeze([
  'local Node/Fengari fixture is a trusted capture provider',
  'client clock or client combat UI is authoritative evidence',
  'provider qualification itself adopts a P0 gate',
  'provider qualification authorizes object, map, Lua, UI, reward or economy writes'
]);

const CANONICALIZATION_FORBIDDEN_NON_DETERMINISM = Object.freeze([
  'local wall-clock substitution',
  'unordered map serialization',
  'unbound client-side outcome',
  'mutable file path as artifact identity',
  'post-capture log rewriting'
]);

const ENVIRONMENT_SNAPSHOT_FIELDS = Object.freeze([
  'engine_build_digest',
  'real_project_revision',
  'map_or_fixture_revision',
  'object_inventory_snapshot_digest',
  'template_readback_basis_digest',
  'capture_clock_basis',
  'collector_toolchain_digest',
  'capture_basis_digest'
]);

const MANIFEST_ENTRY_SHAPE = Object.freeze([
  'gate_id',
  'gate_scope',
  'raw_artifact_ref',
  'canonical_artifact_ref',
  'canonical_artifact_digest',
  'capture_basis_digest',
  'input_trace_digest',
  'provider_proof_ref',
  'recorded_authoritative_instant'
]);

const MANIFEST_FORBIDDEN_ENTRY_FIELDS = Object.freeze([
  'object_key',
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
  'skill_duration_seconds',
  'reward',
  'receipt',
  'economy_input',
  'lua_write',
  'map_write',
  'ui_write',
  'adoption_decision_ref'
]);

const INDEPENDENT_REVIEW_REQUIREMENTS = Object.freeze([
  'provider qualification and role separation',
  'real map-local structural preflight, bound runner/report and external source-origin attestation',
  'frozen environment, toolchain and authority-clock basis',
  'immutable raw/canonical artifact relation and digest consistency',
  'gate-specific completeness including G01 twelve-by-three and G06 one-to-four coverage',
  'rejection of client claims, local templates, synthetic fixtures, drift and post-capture rewriting'
]);

const SOURCE_ORIGIN_PROPERTIES = Object.freeze([
  'qualified provider observed an operator-supplied real map-local root under read-only authorization',
  'bound structural-preflight runner produced the stated live result and immutable report digest',
  'non-secret project and map identity digests identify one source family without storing paths',
  'issuer, authority-clock basis and revocation-aware provider qualification are externally verifiable'
]);

const DEFERRED_OUTPUT_FIELDS = Object.freeze([
  'trusted_provider_registration',
  'real_y3_project_ref',
  'source_origin_preflight_attestation',
  'environment_attestation',
  'external_artifact_manifest',
  'independent_review_handoff',
  'accepted_evidence_ledger',
  'adoption_decision',
  'absolute_projection_payload',
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
  'skill_duration_seconds',
  'y3_object_write',
  'lua_write',
  'map_write',
  'ui_write',
  'reward',
  'receipt',
  'economy_input'
]);

function invariant(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function hasOwn(value, key) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function exactArray(actual, expected, label) {
  invariant(Array.isArray(actual), `${label}: expected array`);
  invariant(actual.length === expected.length, `${label}: unexpected length`);
  for (let index = 0; index < expected.length; index += 1) {
    invariant(actual[index] === expected[index], `${label}: mismatch at ${index}`);
  }
}

function exactPairArray(actual, expected, label) {
  invariant(Array.isArray(actual), `${label}: expected array`);
  invariant(actual.length === expected.length, `${label}: unexpected length`);
  for (let index = 0; index < expected.length; index += 1) {
    exactArray(actual[index], expected[index], `${label}: pair ${index}`);
  }
}

function assertPlainDataObject(value, label) {
  invariant(value && typeof value === 'object' && !Array.isArray(value), `${label}: expected object`);
  const prototype = Object.getPrototypeOf(value);
  invariant(prototype === Object.prototype || prototype === null, `${label}: expected plain data object`);
  invariant(Object.getOwnPropertySymbols(value).length === 0, `${label}: symbols are forbidden`);
}

function assertExactObjectKeys(value, expectedKeys, label) {
  assertPlainDataObject(value, label);
  const actualKeys = Object.getOwnPropertyNames(value).sort();
  const sortedExpected = [...expectedKeys].sort();
  exactArray(actualKeys, sortedExpected, `${label} key set`);
  for (const key of actualKeys) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    invariant(descriptor && descriptor.enumerable === true && hasOwn(descriptor, 'value'), `${label}.${key} must be an enumerable data property`);
  }
}

function assertNullFields(value, fields, label) {
  assertPlainDataObject(value, label);
  for (const field of fields) {
    invariant(hasOwn(value, field), `${label}.${field} must exist`);
    invariant(value[field] === null, `${label}.${field} must remain null`);
  }
}

function sha256Hex(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function validateProviderQualificationTemplate(template) {
  assertExactObjectKeys(template, ['schema_version', 'identity', 'required_claims', 'prohibited_claims', 'future_role_binding'], 'provider qualification template');
  invariant(template.schema_version === 1, 'provider qualification template schema drift');
  assertExactObjectKeys(template.identity, ['spec_id', 'status', 'external_provider_id', 'provider_proof_ref', 'qualification_decision_ref', 'revocation_ref'], 'provider qualification identity');
  invariant(template.identity.spec_id === 'CAL_SPEC_EXTERNAL_CAPTURE_PROVIDER_QUALIFICATION_TEMPLATE_V1', 'provider qualification spec id drift');
  invariant(template.identity.status === 'not_created', 'provider qualification template must remain uncreated');
  assertNullFields(template.identity, ['external_provider_id', 'provider_proof_ref', 'qualification_decision_ref', 'revocation_ref'], 'provider qualification identity');
  exactArray(template.required_claims, PROVIDER_REQUIRED_CLAIMS, 'provider qualification required claims');
  exactArray(template.prohibited_claims, PROVIDER_PROHIBITED_CLAIMS, 'provider qualification prohibited claims');
  assertExactObjectKeys(template.future_role_binding, ['capture_provider_principal_ref', 'capture_operator_principal_ref', 'independent_reviewer_principal_ref', 'adoption_authority_principal_ref'], 'provider qualification role binding');
  assertNullFields(template.future_role_binding, ['capture_provider_principal_ref', 'capture_operator_principal_ref', 'independent_reviewer_principal_ref', 'adoption_authority_principal_ref'], 'provider qualification role binding');
  return true;
}

function validateEnvironmentAttestationTemplate(template, expectedP0Digest, expectedEvidenceDigest, expectedPreflightContractDigest, expectedPreflightRunnerDigest) {
  assertExactObjectKeys(template, ['schema_version', 'identity', 'source_binding', 'required_environment_snapshot', 'failure_rule'], 'environment attestation template');
  invariant(template.schema_version === 1, 'environment attestation template schema drift');
  assertExactObjectKeys(template.identity, ['spec_id', 'status', 'environment_attestation_ref', 'captured_authoritative_instant'], 'environment attestation identity');
  invariant(template.identity.spec_id === 'CAL_SPEC_EXTERNAL_CAPTURE_ENVIRONMENT_ATTESTATION_TEMPLATE_V1', 'environment attestation spec id drift');
  invariant(template.identity.status === 'not_created', 'environment attestation template must remain uncreated');
  assertNullFields(template.identity, ['environment_attestation_ref', 'captured_authoritative_instant'], 'environment attestation identity');
  assertExactObjectKeys(template.source_binding, ['p0_contract_sha256', 'evidence_adoption_contract_sha256', 'preflight_contract_sha256', 'preflight_runner_sha256', 'real_target_map_root', 'structural_preflight_result_ref', 'structural_preflight_report_digest', 'source_origin_preflight_attestation_ref', 'read_only_authorization_ref'], 'environment attestation source binding');
  invariant(template.source_binding.p0_contract_sha256 === expectedP0Digest, 'environment attestation P0 digest drift');
  invariant(template.source_binding.evidence_adoption_contract_sha256 === expectedEvidenceDigest, 'environment attestation evidence digest drift');
  invariant(template.source_binding.preflight_contract_sha256 === expectedPreflightContractDigest, 'environment attestation preflight contract digest drift');
  invariant(template.source_binding.preflight_runner_sha256 === expectedPreflightRunnerDigest, 'environment attestation preflight runner digest drift');
  assertNullFields(template.source_binding, ['real_target_map_root', 'structural_preflight_result_ref', 'structural_preflight_report_digest', 'source_origin_preflight_attestation_ref', 'read_only_authorization_ref'], 'environment attestation source binding');
  assertExactObjectKeys(template.required_environment_snapshot, ENVIRONMENT_SNAPSHOT_FIELDS, 'environment attestation environment snapshot');
  assertNullFields(template.required_environment_snapshot, ENVIRONMENT_SNAPSHOT_FIELDS, 'environment attestation environment snapshot');
  invariant(template.failure_rule === '任何环境字段、来源证明、结构预检报告、只读授权、合同或 runner 绑定、权威时钟缺失、无效或漂移时，不得开始或拼接任何 gate 的外部 capture bundle。', 'environment attestation failure rule drift');
  return true;
}

function validateCanonicalizationTemplate(template) {
  assertExactObjectKeys(template, ['schema_version', 'identity', 'deterministic_rules', 'future_external_bindings'], 'canonicalization template');
  invariant(template.schema_version === 1, 'canonicalization template schema drift');
  assertExactObjectKeys(template.identity, ['spec_id', 'status', 'profile_instance_ref', 'toolchain_version_ref'], 'canonicalization identity');
  invariant(template.identity.spec_id === 'CAL_SPEC_EXTERNAL_CAPTURE_CANONICALIZATION_PROFILE_TEMPLATE_V1', 'canonicalization spec id drift');
  invariant(template.identity.status === 'not_created', 'canonicalization template must remain uncreated');
  assertNullFields(template.identity, ['profile_instance_ref', 'toolchain_version_ref'], 'canonicalization identity');
  assertExactObjectKeys(template.deterministic_rules, ['canonical_encoding', 'field_order', 'hash_algorithm', 'time_format', 'raw_artifact_relation', 'forbidden_non_determinism'], 'canonicalization deterministic rules');
  invariant(template.deterministic_rules.canonical_encoding === 'utf-8-no-bom', 'canonicalization encoding drift');
  invariant(template.deterministic_rules.field_order === 'lexicographic-by-UTF-8-key-bytes', 'canonicalization field order drift');
  invariant(template.deterministic_rules.hash_algorithm === 'sha256-lowercase-hex', 'canonicalization hash algorithm drift');
  invariant(template.deterministic_rules.time_format === 'UTC RFC3339 seconds', 'canonicalization time format drift');
  invariant(template.deterministic_rules.raw_artifact_relation === 'raw external artifact is retained outside this repository; canonical artifact references raw artifact immutably', 'canonicalization raw artifact relation drift');
  exactArray(template.deterministic_rules.forbidden_non_determinism, CANONICALIZATION_FORBIDDEN_NON_DETERMINISM, 'canonicalization forbidden nondeterminism');
  assertExactObjectKeys(template.future_external_bindings, ['raw_artifact_ref', 'canonical_artifact_ref', 'canonical_artifact_digest', 'capture_basis_digest', 'input_trace_digest'], 'canonicalization future bindings');
  assertNullFields(template.future_external_bindings, ['raw_artifact_ref', 'canonical_artifact_ref', 'canonical_artifact_digest', 'capture_basis_digest', 'input_trace_digest'], 'canonicalization future bindings');
  return true;
}

function validateArtifactManifestTemplate(template) {
  assertExactObjectKeys(template, ['schema_version', 'identity', 'bundle_binding', 'environment_family_binding', 'entries', 'entry_shape', 'forbidden_entry_fields', 'rule'], 'artifact manifest template');
  invariant(template.schema_version === 1, 'artifact manifest template schema drift');
  assertExactObjectKeys(template.identity, ['spec_id', 'status', 'manifest_ref', 'manifest_digest'], 'artifact manifest identity');
  invariant(template.identity.spec_id === 'CAL_SPEC_EXTERNAL_CAPTURE_ARTIFACT_MANIFEST_TEMPLATE_V1', 'artifact manifest spec id drift');
  invariant(template.identity.status === 'not_created', 'artifact manifest template must remain uncreated');
  assertNullFields(template.identity, ['manifest_ref', 'manifest_digest'], 'artifact manifest identity');
  assertExactObjectKeys(template.bundle_binding, ['provider_qualification_ref', 'source_origin_preflight_attestation_ref', 'environment_attestation_ref', 'canonicalization_profile_ref'], 'artifact manifest bundle binding');
  assertNullFields(template.bundle_binding, ['provider_qualification_ref', 'source_origin_preflight_attestation_ref', 'environment_attestation_ref', 'canonicalization_profile_ref'], 'artifact manifest bundle binding');
  assertExactObjectKeys(template.environment_family_binding, ['environment_attestation_ref', ...ENVIRONMENT_SNAPSHOT_FIELDS], 'artifact manifest environment family binding');
  assertNullFields(template.environment_family_binding, ['environment_attestation_ref', ...ENVIRONMENT_SNAPSHOT_FIELDS], 'artifact manifest environment family binding');
  exactArray(template.entries, [], 'artifact manifest local entries');
  exactArray(template.entry_shape, MANIFEST_ENTRY_SHAPE, 'artifact manifest entry shape');
  exactArray(template.forbidden_entry_fields, MANIFEST_FORBIDDEN_ENTRY_FIELDS, 'artifact manifest forbidden entry fields');
  invariant(template.rule === 'entries 只能由外部受信任系统创建；每个 manifest 只能绑定一个与环境证明完全一致的工程/地图/模板/时钟/工具链/capture-basis 摘要族，并且只能单向交给独立审阅，不得引用采纳决定。本地模板的空数组不是证据账本、采纳决定或对象字段投影。', 'artifact manifest rule drift');
  return true;
}

function validateIndependentReviewTemplate(template) {
  assertExactObjectKeys(template, ['schema_version', 'identity', 'manifest_binding', 'review_requirements', 'gate_review_requests', 'handoff_rule'], 'independent review template');
  invariant(template.schema_version === 1, 'independent review template schema drift');
  assertExactObjectKeys(template.identity, ['spec_id', 'status', 'review_handoff_ref', 'reviewer_principal_ref', 'adoption_authority_ref'], 'independent review identity');
  invariant(template.identity.spec_id === 'CAL_SPEC_EXTERNAL_CAPTURE_INDEPENDENT_REVIEW_HANDOFF_TEMPLATE_V1', 'independent review spec id drift');
  invariant(template.identity.status === 'not_created', 'independent review template must remain uncreated');
  assertNullFields(template.identity, ['review_handoff_ref', 'reviewer_principal_ref', 'adoption_authority_ref'], 'independent review identity');
  assertExactObjectKeys(template.manifest_binding, ['external_manifest_ref', 'external_manifest_digest', 'environment_attestation_ref', 'environment_family_digest'], 'independent review manifest binding');
  assertNullFields(template.manifest_binding, ['external_manifest_ref', 'external_manifest_digest', 'environment_attestation_ref', 'environment_family_digest'], 'independent review manifest binding');
  exactArray(template.review_requirements, INDEPENDENT_REVIEW_REQUIREMENTS, 'independent review requirements');
  invariant(Array.isArray(template.gate_review_requests) && template.gate_review_requests.length === CANONICAL_GATE_IDS.length, 'independent review gate count drift');
  exactArray(template.gate_review_requests.map((entry) => entry.gate_id), CANONICAL_GATE_IDS, 'independent review gate sequence');
  for (const request of template.gate_review_requests) {
    assertExactObjectKeys(request, ['gate_id', 'external_manifest_entry_refs', 'review_outcome', 'review_reason'], `independent review request ${request.gate_id}`);
    assertNullFields(request, ['external_manifest_entry_refs', 'review_outcome', 'review_reason'], `independent review request ${request.gate_id}`);
  }
  invariant(template.handoff_rule === '独立审阅交接只能单向引用已冻结的外部 manifest 并向外部采纳机关请求进一步裁决；本地模板与审阅结论均不采纳门禁，不生成绝对字段投影，也不得反向写入或预先引用采纳决定。', 'independent review handoff rule drift');
  return true;
}

function validateSourceOriginPreflightAttestationTemplate(template, expectedPreflightContractDigest, expectedPreflightRunnerDigest) {
  assertExactObjectKeys(template, ['schema_version', 'identity', 'source_binding', 'required_origin_properties', 'failure_rule'], 'source-origin preflight attestation template');
  invariant(template.schema_version === 1, 'source-origin preflight attestation schema drift');
  assertExactObjectKeys(template.identity, ['spec_id', 'status', 'source_origin_preflight_attestation_ref', 'issuer_principal_ref'], 'source-origin preflight attestation identity');
  invariant(template.identity.spec_id === 'CAL_SPEC_EXTERNAL_CAPTURE_SOURCE_ORIGIN_PREFLIGHT_ATTESTATION_TEMPLATE_V1', 'source-origin preflight attestation spec id drift');
  invariant(template.identity.status === 'not_created', 'source-origin preflight attestation must remain uncreated');
  assertNullFields(template.identity, ['source_origin_preflight_attestation_ref', 'issuer_principal_ref'], 'source-origin preflight attestation identity');
  assertExactObjectKeys(template.source_binding, ['preflight_contract_sha256', 'preflight_runner_sha256', 'required_live_result', 'structural_preflight_report_digest', 'provider_qualification_ref', 'read_only_authorization_ref', 'captured_authoritative_instant', 'real_project_identity_digest', 'real_map_identity_digest'], 'source-origin preflight attestation binding');
  invariant(template.source_binding.preflight_contract_sha256 === expectedPreflightContractDigest, 'source-origin preflight contract digest drift');
  invariant(template.source_binding.preflight_runner_sha256 === expectedPreflightRunnerDigest, 'source-origin preflight runner digest drift');
  invariant(template.source_binding.required_live_result === 'structural_preflight_passed', 'source-origin preflight live result drift');
  assertNullFields(template.source_binding, ['structural_preflight_report_digest', 'provider_qualification_ref', 'read_only_authorization_ref', 'captured_authoritative_instant', 'real_project_identity_digest', 'real_map_identity_digest'], 'source-origin preflight attestation binding');
  exactArray(template.required_origin_properties, SOURCE_ORIGIN_PROPERTIES, 'source-origin preflight required properties');
  invariant(template.failure_rule === '结构预检通过本身不能证明真实地图来源；任一合同或 runner 摘要、报告摘要、提供方资格、只读授权、权威时间或非秘密工程/地图身份指纹缺失、无效或漂移时，拒绝整个外部 capture bundle。', 'source-origin preflight failure rule drift');
  return true;
}

function validateOnboardingContract(contract, parentContract, parentBytes, evidenceContract, evidenceBytes, preflightContract, preflightBytes, preflightRunnerBytes, templates) {
  assertExactObjectKeys(contract, ['schema_version', 'identity', 'source_contracts', 'canonical_gate_snapshot', 'trust_boundary', 'role_separation', 'preflight_dependency', 'onboarding_sequence', 'first_fieldwork_order', 'template_artifacts', 'deferred_outputs', 'acceptance'], 'onboarding contract');
  invariant(contract.schema_version === 1, 'onboarding schema drift');
  assertExactObjectKeys(contract.identity, ['spec_id', 'display_name', 'package_status', 'production_gate', 'runtime_handoff', 'actual_capture_provider', 'actual_provider_qualification', 'actual_y3_project_ref', 'actual_source_origin_preflight_attestation', 'actual_environment_attestation', 'actual_external_artifact_manifest', 'actual_independent_review_handoff', 'actual_adoption_decision'], 'onboarding identity');
  invariant(contract.identity.spec_id === 'CAL_SPEC_EXTERNAL_CAPTURE_ONBOARDING_V1', 'onboarding spec id drift');
  invariant(contract.identity.package_status === 'offline-external-capture-onboarding-only', 'onboarding status drift');
  invariant(contract.identity.production_gate === 'closed' && contract.identity.runtime_handoff === false, 'onboarding must remain closed and offline');
  assertNullFields(contract.identity, ['actual_capture_provider', 'actual_provider_qualification', 'actual_y3_project_ref', 'actual_source_origin_preflight_attestation', 'actual_environment_attestation', 'actual_external_artifact_manifest', 'actual_independent_review_handoff', 'actual_adoption_decision'], 'onboarding identity');

  invariant(parentContract.contract_id === 'CAL_SPEC_CROSS_PROFESSION_ABSOLUTE_COMBAT_V1', 'parent P0 contract identity drift');
  invariant(evidenceContract.identity.spec_id === 'CAL_SPEC_P0_EVIDENCE_COLLECTION_AND_ADOPTION_V1', 'evidence-adoption contract identity drift');
  invariant(preflightContract.identity.spec_id === 'TT_SPEC_Y3_CONSTRUCTION_PREFLIGHT', 'preflight contract identity drift');
  invariant(preflightContract.production_gate === 'closed', 'preflight production gate drift');
  invariant(Array.isArray(contract.source_contracts) && contract.source_contracts.length === 3, 'onboarding source contract count drift');
  const [parentSource, evidenceSource, preflightSource] = contract.source_contracts;
  assertExactObjectKeys(parentSource, ['artifact', 'contract_id', 'content_sha256', 'role'], 'onboarding parent source');
  assertExactObjectKeys(evidenceSource, ['artifact', 'spec_id', 'content_sha256', 'role'], 'onboarding evidence source');
  assertExactObjectKeys(preflightSource, ['artifact', 'spec_id', 'content_sha256', 'role'], 'onboarding preflight source');
  invariant(parentSource.artifact === '../contract/cross-profession-combat-calibration-contract.json' && parentSource.contract_id === parentContract.contract_id && parentSource.content_sha256 === sha256Hex(parentBytes), 'onboarding parent source drift');
  invariant(evidenceSource.artifact === '../evidence-adoption/p0-evidence-collection-and-adoption-contract.json' && evidenceSource.spec_id === evidenceContract.identity.spec_id && evidenceSource.content_sha256 === sha256Hex(evidenceBytes), 'onboarding evidence source drift');
  invariant(preflightSource.artifact === '../../tianting-y3-construction-preflight/package-contract.json' && preflightSource.spec_id === preflightContract.identity.spec_id && preflightSource.content_sha256 === sha256Hex(preflightBytes), 'onboarding preflight source drift');

  assertExactObjectKeys(contract.canonical_gate_snapshot, ['required_gate_ids', 'currently_satisfied_gate_ids', 'rule'], 'onboarding canonical gate snapshot');
  exactArray(contract.canonical_gate_snapshot.required_gate_ids, CANONICAL_GATE_IDS, 'onboarding canonical gate sequence');
  exactArray(contract.canonical_gate_snapshot.currently_satisfied_gate_ids, [], 'onboarding satisfied gate sequence');
  exactArray(parentContract.absolute_projection_gate.required_gate_ids, CANONICAL_GATE_IDS, 'parent canonical gate sequence');
  exactArray(parentContract.absolute_projection_gate.current_satisfied_gate_ids, [], 'parent satisfied gate sequence');

  assertExactObjectKeys(contract.trust_boundary, ['provider_execution_requirement', 'transport_requirement', 'local_repository_role', 'node_fengari_role', 'node_fengari_live_capture_trust_root', 'local_repository_may_register_provider', 'local_repository_may_accept_evidence', 'local_repository_may_adopt_p0_gate', 'local_repository_may_project_absolute_fields', 'provider_credentials', 'provider_endpoint', 'provider_private_key', 'local_provider_registration', 'write_authorization'], 'onboarding trust boundary');
  invariant(contract.trust_boundary.provider_execution_requirement === 'external isolated process with read-only Y3/editor/authority access', 'onboarding provider execution boundary drift');
  invariant(contract.trust_boundary.transport_requirement === 'canonical JSON/IPC or equivalent immutable external artifact transport', 'onboarding transport boundary drift');
  invariant(contract.trust_boundary.local_repository_role === 'template, fingerprint and rejection-rule only', 'onboarding local repository role drift');
  invariant(contract.trust_boundary.node_fengari_role === 'offline test or future materialization boundary only, never a trusted live capture provider', 'onboarding Node/Fengari boundary drift');
  for (const field of ['node_fengari_live_capture_trust_root', 'local_repository_may_register_provider', 'local_repository_may_accept_evidence', 'local_repository_may_adopt_p0_gate', 'local_repository_may_project_absolute_fields']) {
    invariant(contract.trust_boundary[field] === false, `onboarding trust boundary ${field} must remain false`);
  }
  invariant(contract.trust_boundary.write_authorization === false, 'onboarding must not authorize writes');
  assertNullFields(contract.trust_boundary, ['provider_credentials', 'provider_endpoint', 'provider_private_key', 'local_provider_registration'], 'onboarding trust boundary');

  assertExactObjectKeys(contract.role_separation, ['roles', 'must_not_be_same_principal_pairs', 'actual_role_bindings'], 'onboarding role separation');
  exactArray(contract.role_separation.roles, ['capture_provider', 'capture_operator', 'independent_reviewer', 'adoption_authority'], 'onboarding role sequence');
  exactPairArray(contract.role_separation.must_not_be_same_principal_pairs, ROLE_SEPARATION_PAIRS, 'onboarding separation pairs');
  assertNullFields(contract.role_separation, ['actual_role_bindings'], 'onboarding role separation');

  assertExactObjectKeys(contract.preflight_dependency, ['artifact', 'real_target_map_root', 'required_live_result', 'preflight_is_necessary_but_not_sufficient', 'preflight_runner_content_sha256', 'required_source_origin_attestation_template', 'current_workspace_result', 'rule'], 'onboarding preflight dependency');
  invariant(contract.preflight_dependency.artifact === '../../tianting-y3-construction-preflight/tests/Invoke-TiantingY3ConstructionPreflight.ps1', 'onboarding preflight runner drift');
  invariant(contract.preflight_dependency.required_live_result === 'structural_preflight_passed' && contract.preflight_dependency.current_workspace_result === 'structural_preflight_blocked', 'onboarding preflight result boundary drift');
  invariant(contract.preflight_dependency.preflight_is_necessary_but_not_sufficient === true, 'onboarding preflight must remain necessary but insufficient');
  invariant(contract.preflight_dependency.preflight_runner_content_sha256 === sha256Hex(preflightRunnerBytes), 'onboarding preflight runner digest drift');
  invariant(contract.preflight_dependency.required_source_origin_attestation_template === 'templates/source-origin-preflight-attestation-template.json', 'onboarding source-origin attestation template drift');
  invariant(contract.preflight_dependency.rule === '结构预检是开始外部环境证明的必要条件而非真实来源证明；还必须由合格提供方出具绑定预检合同与 runner 摘要、报告摘要、只读授权、权威时间与非秘密工程/地图指纹的外部来源证明。合成目录和当前离线仓库根不得充当采集源。', 'onboarding preflight rule drift');
  assertNullFields(contract.preflight_dependency, ['real_target_map_root'], 'onboarding preflight dependency');
  exactArray(contract.onboarding_sequence, ONBOARDING_SEQUENCE, 'onboarding sequence');

  invariant(Array.isArray(contract.first_fieldwork_order) && contract.first_fieldwork_order.length === FIELDWORK_GATE_IDS.length, 'fieldwork order count drift');
  for (let index = 0; index < contract.first_fieldwork_order.length; index += 1) {
    const step = contract.first_fieldwork_order[index];
    assertExactObjectKeys(step, ['step_id', 'purpose', 'gate_id', 'status', 'external_artifact_ref'], `fieldwork step ${index}`);
    invariant(step.step_id === `CAL-ONBOARD-FIELD-${String(index + 1).padStart(2, '0')}`, `fieldwork step id drift at ${index}`);
    invariant(step.gate_id === FIELDWORK_GATE_IDS[index], `fieldwork gate order drift at ${index}`);
    invariant(step.status === 'blocked_pending_external_operator', `fieldwork step status drift at ${index}`);
    assertNullFields(step, ['external_artifact_ref'], `fieldwork step ${index}`);
  }
  exactArray(contract.template_artifacts, ['templates/provider-qualification-template.json', 'templates/source-origin-preflight-attestation-template.json', 'templates/environment-attestation-template.json', 'templates/canonicalization-profile-template.json', 'templates/external-artifact-manifest-template.json', 'templates/independent-review-handoff-template.json'], 'onboarding template artifact sequence');
  assertExactObjectKeys(contract.deferred_outputs, DEFERRED_OUTPUT_FIELDS, 'onboarding deferred outputs');
  assertNullFields(contract.deferred_outputs, DEFERRED_OUTPUT_FIELDS, 'onboarding deferred outputs');
  invariant(Array.isArray(contract.acceptance) && contract.acceptance.length === 12, 'onboarding acceptance count drift');
  for (let index = 1; index <= 12; index += 1) {
    const expectedId = `CAL-ONBOARD-ACC-${String(index).padStart(3, '0')}`;
    const acceptance = contract.acceptance[index - 1];
    assertExactObjectKeys(acceptance, ['id', 'rule'], `onboarding acceptance ${index}`);
    invariant(acceptance.id === expectedId, `onboarding acceptance id drift at ${index}`);
  }

  validateProviderQualificationTemplate(templates.providerQualification);
  validateSourceOriginPreflightAttestationTemplate(templates.sourceOriginPreflightAttestation, sha256Hex(preflightBytes), sha256Hex(preflightRunnerBytes));
  validateEnvironmentAttestationTemplate(templates.environmentAttestation, sha256Hex(parentBytes), sha256Hex(evidenceBytes), sha256Hex(preflightBytes), sha256Hex(preflightRunnerBytes));
  validateCanonicalizationTemplate(templates.canonicalization);
  validateArtifactManifestTemplate(templates.artifactManifest);
  validateIndependentReviewTemplate(templates.independentReview);
  return true;
}

function attemptProviderRegistration(contract, candidate) {
  assertPlainDataObject(contract, 'provider registration contract');
  assertPlainDataObject(candidate, 'provider registration candidate');
  throw new Error('offline onboarding package cannot register a capture provider, accept evidence, adopt a P0 gate, or project absolute fields');
}

module.exports = {
  CANONICAL_GATE_IDS,
  FIELDWORK_GATE_IDS,
  attemptProviderRegistration,
  sha256Hex,
  validateArtifactManifestTemplate,
  validateCanonicalizationTemplate,
  validateEnvironmentAttestationTemplate,
  validateIndependentReviewTemplate,
  validateOnboardingContract,
  validateProviderQualificationTemplate,
  validateSourceOriginPreflightAttestationTemplate
};
