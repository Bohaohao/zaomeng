'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const Core = require('../reference/evidence-adoption-core');

const packageRoot = path.resolve(__dirname, '..');
const parentRoot = path.resolve(packageRoot, '..');
const calibrationPath = path.join(parentRoot, 'contract', 'cross-profession-combat-calibration-contract.json');
const contractPath = path.join(packageRoot, 'p0-evidence-collection-and-adoption-contract.json');
const sourceSnapshotPath = path.join(packageRoot, 'source-snapshots.json');
const collectionTemplatePath = path.join(packageRoot, 'templates', 'evidence-collection-templates.json');
const adoptionTemplatePath = path.join(packageRoot, 'templates', 'adoption-decision-template.json');

const calibrationBytes = fs.readFileSync(calibrationPath);
const calibrationContract = JSON.parse(calibrationBytes.toString('utf8'));
const contract = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
const sourceSnapshot = JSON.parse(fs.readFileSync(sourceSnapshotPath, 'utf8'));
const collectionTemplates = JSON.parse(fs.readFileSync(collectionTemplatePath, 'utf8'));
const adoptionTemplate = JSON.parse(fs.readFileSync(adoptionTemplatePath, 'utf8'));

let assertions = 0;

function check(condition, message) {
  assertions += 1;
  assert.ok(condition, message);
}

function throws(fn, pattern, message) {
  assertions += 1;
  assert.throws(fn, pattern, message);
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function digest(character) {
  return character.repeat(64);
}

function fixedBuildScope(profileId = Core.FIXED_BUILD_PROFILE_IDS[0], runIndex = 1) {
  return {
    scope_kind: 'fixed_build_replay',
    profile_id: profileId,
    deterministic_run_index: runIndex,
    party_member_count: null,
    formula_family: null,
    readback_class: null
  };
}

function partyReplayScope(memberCount) {
  return {
    scope_kind: 'authority_party_replay',
    profile_id: null,
    deterministic_run_index: null,
    party_member_count: memberCount,
    formula_family: null,
    readback_class: null
  };
}

function formulaScope(formulaFamily) {
  return {
    scope_kind: 'formula_observation',
    profile_id: null,
    deterministic_run_index: null,
    party_member_count: null,
    formula_family: formulaFamily,
    readback_class: null
  };
}

function submission(overrides = {}) {
  return {
    evidence_id: 'evidence-001',
    gate_id: Core.CANONICAL_GATE_IDS[0],
    evidence_kind: 'real_y3_readonly_capture',
    source_capture_session_id: 'session-001',
    capture_run_id: 'run-001',
    capture_provider_proof_ref: 'external://proof/provider-a',
    engine_build_digest: digest('a'),
    real_project_revision: 'project-revision-001',
    map_or_fixture_revision: 'fixture-revision-001',
    object_inventory_snapshot_digest: digest('b'),
    template_readback_basis_digest: digest('c'),
    canonical_artifact_digest: digest('d'),
    capture_basis_digest: digest('e'),
    input_trace_digest: digest('f'),
    recorded_authoritative_instant: '2026-07-24T00:00:00Z',
    collector_identity_ref: 'external://identity/collector-a',
    reviewer_identity_ref: 'external://identity/reviewer-b',
    external_artifact_ref: 'external://artifact/immutable-evidence-001',
    gate_scope: fixedBuildScope(),
    ...overrides
  };
}

check(Core.CANONICAL_GATE_IDS.length === 7, 'canonical P0 gate list has seven entries');
check(Core.validateContract(contract, calibrationContract, calibrationBytes, sourceSnapshot, collectionTemplates, adoptionTemplate), 'offline evidence package validates');
check(contract.source_calibration_contract.content_sha256 === Core.sha256Hex(calibrationBytes), 'parent calibration bytes are fingerprinted');
check(contract.adoption_controls.current_satisfied_gate_ids.length === 0, 'evidence package cannot mark gates satisfied');
check(contract.deferred_outputs.hp_max === null, 'absolute HP remains deferred');
check(sourceSnapshot.external_capture_family.capture_provider_proof_ref === null, 'source snapshot has no external provider');
check(collectionTemplates.gate_templates.length === 7, 'collection templates cover every canonical gate');
check(adoptionTemplate.gate_decisions.every((entry) => entry.decision === null), 'adoption template contains no gate decision');

const preview = Core.validateSubmission(contract, submission());
check(preview.collection_status === 'blocked_provider_unavailable', 'well-shaped submission remains blocked without a trusted provider');
check(preview.adoption_status === 'not_attempted' && preview.projection_status === 'not_attempted', 'preview cannot adopt or project fields');

throws(() => Core.validateSubmission(contract, submission({ external_artifact_ref: 'external://synthetic-schema-test-only' })), /disallowed reference token/, 'synthetic fixture is rejected');
throws(() => Core.validateSubmission(contract, submission({ external_artifact_ref: 'client://combat/result' })), /immutable external reference/, 'client claim is rejected');
throws(() => Core.validateSubmission(contract, submission({ collector_identity_ref: 'external://identity/same', reviewer_identity_ref: 'external://identity/same' })), /collector and reviewer must differ/, 'self-review is rejected');
throws(() => Core.validateSubmission(contract, submission({ canonical_artifact_digest: 'free-text-digest' })), /lowercase SHA-256/, 'free-text digest is rejected');
throws(() => Core.validateSubmission(contract, submission({ hp_max: 1 })), /key set/, 'absolute field injection is rejected');
throws(() => Core.validateSubmission(contract, submission({ stable_object_key: 'guessed-key' })), /key set/, 'stable object-key injection is rejected');
throws(() => Core.validateSubmission(contract, submission({ target_selector: 'guessed-target' })), /key set/, 'target selector injection is rejected');
throws(() => Core.validateSubmission(contract, submission({ gate_promotion: 'accepted' })), /key set/, 'self-promotion is rejected');
throws(() => Core.validateSubmission(contract, submission({ metadata: { hp_max: 999, stable_object_key: 'x' } })), /key set/, 'nested metadata injection is rejected');
throws(() => Core.validateSubmission(contract, submission({ copyFrom: 'template-x' })), /key set/, 'template alias injection is rejected');
throws(() => Core.validateSubmission(contract, submission({ future_projection_payload: { target_object_or_unit_id: 'x' } })), /key set/, 'nested projection payload injection is rejected');
throws(() => Core.validateSubmission(contract, submission({ evidence_id: 'synthetic-evidence-001' })), /disallowed reference token/, 'synthetic capture identity is rejected');
throws(() => Core.validateSubmission(contract, submission({ source_capture_session_id: 'schema-test-session' })), /disallowed reference token/, 'test capture session is rejected');
throws(() => Core.validateSubmission(contract, submission({ real_project_revision: 'deferred-project' })), /disallowed reference token/, 'deferred project revision is rejected');
throws(() => Core.validateSubmission(contract, submission({ recorded_authoritative_instant: '2026-99-99T99:99:99Z' })), /real UTC RFC3339 second/, 'invalid timestamp is rejected');
throws(() => Core.validateSubmission(contract, submission({ gate_scope: { ...fixedBuildScope(), metadata: { hp_max: 999 } } })), /key set/, 'nested gate-scope injection is rejected');
throws(() => Core.validateSubmission(contract, submission({ gate_scope: fixedBuildScope('CAL-C99-L99-v1', 1) })), /profile_id is not canonical/, 'unknown fixed-build profile is rejected');
throws(() => Core.validateSubmission(contract, submission({ gate_id: 'P0-GATE-99-invented' })), /not canonical/, 'unknown gate is rejected');
const inheritedTopLevelSubmission = Object.assign(Object.create({ hp_max: 999 }), submission());
throws(() => Core.validateSubmission(contract, inheritedTopLevelSubmission), /plain data object/, 'an inherited top-level projection field is rejected');
const inheritedGateScope = Object.assign(Object.create({ target_object_or_unit_id: 'invented-unit' }), fixedBuildScope());
throws(() => Core.validateSubmission(contract, submission({ gate_scope: inheritedGateScope })), /plain data object/, 'an inherited gate-scope object field is rejected');
const hiddenTopLevelSubmission = submission();
Object.defineProperty(hiddenTopLevelSubmission, 'future_projection_payload', { value: null, enumerable: false });
throws(() => Core.validateSubmission(contract, hiddenTopLevelSubmission), /key set/, 'a non-enumerable top-level projection field is rejected');
const hiddenGateScope = fixedBuildScope();
Object.defineProperty(hiddenGateScope, 'metadata', { value: null, enumerable: false });
throws(() => Core.validateSubmission(contract, submission({ gate_scope: hiddenGateScope })), /key set/, 'a non-enumerable gate-scope metadata field is rejected');
const accessorSubmission = submission();
Object.defineProperty(accessorSubmission, 'evidence_id', { get: () => 'evidence-from-getter', enumerable: true });
throws(() => Core.validateSubmission(contract, accessorSubmission), /enumerable data property/, 'a getter-backed evidence field is rejected');
const symbolSubmission = submission();
symbolSubmission[Symbol('hidden-projection')] = null;
throws(() => Core.validateSubmission(contract, symbolSubmission), /symbol properties/, 'a symbol-backed hidden field is rejected');
const injectedEnvelopeContract = clone(contract);
injectedEnvelopeContract.submission_envelope.required_fields.push('target_object_or_unit_id');
injectedEnvelopeContract.submission_envelope.forbidden_fields = [];
throws(() => Core.validateSubmission(injectedEnvelopeContract, submission({ target_object_or_unit_id: 'invented-unit' })), /envelope fields/, 'a caller cannot extend the trusted submission envelope with an object target');
const injectedScopeContract = clone(contract);
injectedScopeContract.gate_scope_contract.exact_fields.push('target_object_or_unit_id');
throws(() => Core.validateSubmission(injectedScopeContract, submission({ gate_scope: { ...fixedBuildScope(), target_object_or_unit_id: 'invented-unit' } })), /gate scope fields/, 'a caller cannot extend the trusted gate scope with an object target');
const forgedTokenContract = clone(contract);
forgedTokenContract.submission_envelope.disallowed_reference_tokens = [];
throws(() => Core.validateSubmission(forgedTokenContract, submission({ evidence_id: 'synthetic-evidence-001' })), /disallowed reference tokens/, 'a caller cannot remove the static synthetic-reference rejection list');
const forgedAdoptionControlContract = clone(contract);
forgedAdoptionControlContract.adoption_controls.current_adoption_state = 'open';
forgedAdoptionControlContract.adoption_controls.current_satisfied_gate_ids = [Core.CANONICAL_GATE_IDS[0]];
throws(() => Core.validateSubmission(forgedAdoptionControlContract, submission()), /adoption state drift/, 'a caller cannot claim an open or partially adopted gate state');
const forgedCaptureChainContract = clone(contract);
forgedCaptureChainContract.capture_chain.chain_status = 'external_evidence_collected';
forgedCaptureChainContract.capture_chain.collector_may_read_but_not_write = false;
throws(() => Core.validateSubmission(forgedCaptureChainContract, submission()), /capture chain status drift/, 'a caller cannot present a locally forged collected capture chain');
const hiddenCaptureChainContract = clone(contract);
hiddenCaptureChainContract.capture_chain.absolute_projection_payload = null;
throws(() => Core.validateContract(hiddenCaptureChainContract, calibrationContract, calibrationBytes, sourceSnapshot, collectionTemplates, adoptionTemplate), /capture chain key set/, 'a hidden projection field cannot be added to the capture chain');

const duplicatedRun = submission({ evidence_id: 'evidence-002', gate_scope: fixedBuildScope(Core.FIXED_BUILD_PROFILE_IDS[0], 2) });
throws(() => Core.validateSubmissionSet(contract, [submission(), duplicatedRun]), /repeat capture_run_id/, 'same run cannot be replayed as distinct evidence');
const mixedRevision = submission({ evidence_id: 'evidence-003', capture_run_id: 'run-003', engine_build_digest: digest('9'), gate_scope: fixedBuildScope(Core.FIXED_BUILD_PROFILE_IDS[0], 2) });
throws(() => Core.validateSubmissionSet(contract, [submission(), mixedRevision]), /mixed engine_build_digest/, 'mixed engine revisions are rejected');
const mixedMap = submission({ evidence_id: 'evidence-004', capture_run_id: 'run-004', map_or_fixture_revision: 'fixture-revision-002', gate_scope: fixedBuildScope(Core.FIXED_BUILD_PROFILE_IDS[0], 2) });
throws(() => Core.validateSubmissionSet(contract, [submission(), mixedMap]), /mixed map_or_fixture_revision/, 'mixed map fixture revisions are rejected');
const mixedCaptureBasis = submission({ evidence_id: 'evidence-005', capture_run_id: 'run-005', capture_basis_digest: digest('9'), gate_scope: fixedBuildScope(Core.FIXED_BUILD_PROFILE_IDS[0], 2) });
throws(() => Core.validateSubmissionSet(contract, [submission(), mixedCaptureBasis]), /mixed capture_basis_digest/, 'mixed capture bases are rejected');
const mixedInput = submission({ evidence_id: 'evidence-006', capture_run_id: 'run-006', input_trace_digest: digest('9'), gate_scope: fixedBuildScope(Core.FIXED_BUILD_PROFILE_IDS[0], 2) });
throws(() => Core.validateSubmissionSet(contract, [submission(), mixedInput]), /mixed input_trace_digest/, 'same fixed-build triplet rejects mixed inputs');
throws(() => Core.validateSubmissionSet(contract, [
  submission(),
  submission({
    evidence_id: 'evidence-007',
    capture_run_id: 'run-007',
    gate_id: Core.CANONICAL_GATE_IDS[1],
    gate_scope: formulaScope('physical_magical_defense_penetration')
  })
]), /exactly one canonical gate/, 'review bundle cannot mix gates');
const previewSet = Core.validateSubmissionSet(contract, [submission(), submission({ evidence_id: 'evidence-008', capture_run_id: 'run-008', gate_scope: fixedBuildScope(Core.FIXED_BUILD_PROFILE_IDS[0], 2) })]);
check(previewSet.review_bundle_status === 'blocked_provider_unavailable' && previewSet.outcomes.length === 2 && previewSet.coverage.coverage_status === 'incomplete_preview', 'partial preview set remains non-adoptable');
const partyPreview = Core.validateSubmissionSet(contract, [1, 2, 3, 4].map((memberCount) => submission({
  evidence_id: `party-evidence-${memberCount}`,
  gate_id: Core.CANONICAL_GATE_IDS[5],
  capture_run_id: `party-run-${memberCount}`,
  input_trace_digest: digest(String(memberCount)),
  external_artifact_ref: `external://artifact/party-evidence-${memberCount}`,
  gate_scope: partyReplayScope(memberCount)
})));
check(partyPreview.coverage.coverage_status === 'structurally_complete_preview_not_adoptable' && partyPreview.review_bundle_status === 'blocked_provider_unavailable', 'one-to-four party coverage remains a blocked preview');
throws(() => Core.validateSubmissionSet(contract, [
  submission({
    evidence_id: 'party-duplicate-evidence-1',
    gate_id: Core.CANONICAL_GATE_IDS[5],
    capture_run_id: 'party-duplicate-run-1',
    external_artifact_ref: 'external://artifact/party-duplicate-evidence-1',
    gate_scope: partyReplayScope(1)
  }),
  submission({
    evidence_id: 'party-duplicate-evidence-2',
    gate_id: Core.CANONICAL_GATE_IDS[5],
    capture_run_id: 'party-duplicate-run-2',
    external_artifact_ref: 'external://artifact/party-duplicate-evidence-2',
    gate_scope: partyReplayScope(1)
  })
]), /repeat party_member_count/, 'party replay preview cannot pad a repeated member count');
const completeFixedBuildPreview = Core.validateSubmissionSet(contract, Core.FIXED_BUILD_PROFILE_IDS.flatMap((profileId, profileIndex) => [1, 2, 3].map((runIndex) => submission({
  evidence_id: `fixed-evidence-${profileIndex}-${runIndex}`,
  capture_run_id: `fixed-run-${profileIndex}-${runIndex}`,
  canonical_artifact_digest: digest(profileIndex.toString(16)),
  input_trace_digest: digest(profileIndex.toString(16)),
  external_artifact_ref: `external://artifact/fixed-evidence-${profileIndex}-${runIndex}`,
  gate_scope: fixedBuildScope(profileId, runIndex)
}))));
check(completeFixedBuildPreview.coverage.coverage_status === 'structurally_complete_preview_not_adoptable' && completeFixedBuildPreview.review_bundle_status === 'blocked_provider_unavailable', 'twelve-by-three coverage remains a blocked preview');
throws(() => Core.attemptAdoption(contract, submission()), /cannot adopt a P0 gate/, 'offline reference cannot adopt a gate');

const badDigestContract = clone(contract);
badDigestContract.source_calibration_contract.content_sha256 = digest('0');
throws(() => Core.validateContract(badDigestContract, calibrationContract, calibrationBytes, sourceSnapshot, collectionTemplates, adoptionTemplate), /parent calibration contract digest drift/, 'parent contract drift is rejected');
const badPlanContract = clone(contract);
badPlanContract.gate_collection_plans[0].accepted_evidence_refs = ['external://artifact/pretend-accepted'];
throws(() => Core.validateContract(badPlanContract, calibrationContract, calibrationBytes, sourceSnapshot, collectionTemplates, adoptionTemplate), /cannot carry accepted evidence/, 'local accepted evidence is rejected');
const badDeferredContract = clone(contract);
badDeferredContract.deferred_outputs.hp_max = 1;
throws(() => Core.validateContract(badDeferredContract, calibrationContract, calibrationBytes, sourceSnapshot, collectionTemplates, adoptionTemplate), /deferred_outputs.hp_max must remain null/, 'absolute projection output is rejected');
const badEnvelopeContract = clone(contract);
badEnvelopeContract.submission_envelope.required_fields.pop();
throws(() => Core.validateContract(badEnvelopeContract, calibrationContract, calibrationBytes, sourceSnapshot, collectionTemplates, adoptionTemplate), /submission envelope field sequence/, 'submission envelope cannot remove its exact gate-scope field');
const badGateScopeContract = clone(contract);
badGateScopeContract.gate_scope_contract.per_gate[3].readback_class = 'invented_engine_readback';
throws(() => Core.validateContract(badGateScopeContract, calibrationContract, calibrationBytes, sourceSnapshot, collectionTemplates, adoptionTemplate), /gate scope declaration drift/, 'gate-scope declaration cannot change an authoritative readback class');
const badSourceSnapshot = clone(sourceSnapshot);
badSourceSnapshot.identity.actual_external_capture_source = 'external://provider/pretend-live';
throws(() => Core.validateSourceSnapshot(badSourceSnapshot, calibrationContract, calibrationBytes), /must remain null/, 'local source snapshot cannot name a live provider');
const hiddenSourceSnapshotIdentity = clone(sourceSnapshot);
hiddenSourceSnapshotIdentity.identity.hidden_adoption = null;
throws(() => Core.validateSourceSnapshot(hiddenSourceSnapshotIdentity, calibrationContract, calibrationBytes), /source snapshot identity key set/, 'source snapshot identity cannot hide an adoption field');
const hiddenExternalCaptureFamily = clone(sourceSnapshot);
hiddenExternalCaptureFamily.external_capture_family.hidden_provider = null;
throws(() => Core.validateSourceSnapshot(hiddenExternalCaptureFamily, calibrationContract, calibrationBytes), /external capture family key set/, 'source snapshot capture family cannot hide a provider field');
const badTemplates = clone(collectionTemplates);
badTemplates.gate_templates[0].local_records = ['pretend-record'];
throws(() => Core.validateCollectionTemplates(badTemplates, contract), /must not contain local records/, 'template record injection is rejected');
const hiddenCollectionTemplateIdentity = clone(collectionTemplates);
hiddenCollectionTemplateIdentity.identity.hidden_projection = null;
throws(() => Core.validateCollectionTemplates(hiddenCollectionTemplateIdentity, contract), /collection template identity key set/, 'collection template identity cannot hide a projection field');
const hiddenCollectionGateTemplate = clone(collectionTemplates);
hiddenCollectionGateTemplate.gate_templates[0].hidden_object_key = null;
throws(() => Core.validateCollectionTemplates(hiddenCollectionGateTemplate, contract), /collection template .* key set/, 'collection gate template cannot hide an object key');
const badAdoptionTemplate = clone(adoptionTemplate);
badAdoptionTemplate.gate_decisions[0].decision = 'accepted';
throws(() => Core.validateAdoptionDecisionTemplate(badAdoptionTemplate), /must remain null/, 'local template cannot create an adoption decision');
const hiddenAdoptionTemplateIdentity = clone(adoptionTemplate);
hiddenAdoptionTemplateIdentity.identity.hidden_entitlement = null;
throws(() => Core.validateAdoptionDecisionTemplate(hiddenAdoptionTemplateIdentity), /adoption template identity key set/, 'adoption template identity cannot hide an entitlement');
const hiddenAdoptionDecision = clone(adoptionTemplate);
hiddenAdoptionDecision.gate_decisions[0].hidden_projection = null;
throws(() => Core.validateAdoptionDecisionTemplate(hiddenAdoptionDecision), /adoption template .* key set/, 'adoption decision template cannot hide a projection');

console.log(`PASS: P0 evidence-adoption reference tests (${assertions} assertions)`);
