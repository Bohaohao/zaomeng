'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const Core = require('../reference/external-capture-onboarding-core');

const packageRoot = path.resolve(__dirname, '..');
const calibrationRoot = path.resolve(packageRoot, '..');
const implementationRoot = path.resolve(calibrationRoot, '..');
const paths = {
  onboarding: path.join(packageRoot, 'package-contract.json'),
  parent: path.join(calibrationRoot, 'contract', 'cross-profession-combat-calibration-contract.json'),
  evidence: path.join(calibrationRoot, 'evidence-adoption', 'p0-evidence-collection-and-adoption-contract.json'),
  preflight: path.join(implementationRoot, 'tianting-y3-construction-preflight', 'package-contract.json'),
  preflightRunner: path.join(implementationRoot, 'tianting-y3-construction-preflight', 'tests', 'Invoke-TiantingY3ConstructionPreflight.ps1'),
  providerQualification: path.join(packageRoot, 'templates', 'provider-qualification-template.json'),
  sourceOriginPreflightAttestation: path.join(packageRoot, 'templates', 'source-origin-preflight-attestation-template.json'),
  environmentAttestation: path.join(packageRoot, 'templates', 'environment-attestation-template.json'),
  canonicalization: path.join(packageRoot, 'templates', 'canonicalization-profile-template.json'),
  artifactManifest: path.join(packageRoot, 'templates', 'external-artifact-manifest-template.json'),
  independentReview: path.join(packageRoot, 'templates', 'independent-review-handoff-template.json')
};

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

let assertions = 0;
function check(condition, message) {
  assertions += 1;
  assert.ok(condition, message);
}
function throws(fn, pattern, message) {
  assertions += 1;
  assert.throws(fn, pattern, message);
}

const onboardingBytes = fs.readFileSync(paths.onboarding);
const parentBytes = fs.readFileSync(paths.parent);
const evidenceBytes = fs.readFileSync(paths.evidence);
const preflightBytes = fs.readFileSync(paths.preflight);
const preflightRunnerBytes = fs.readFileSync(paths.preflightRunner);
const onboarding = JSON.parse(onboardingBytes.toString('utf8'));
const parent = JSON.parse(parentBytes.toString('utf8'));
const evidence = JSON.parse(evidenceBytes.toString('utf8'));
const preflight = JSON.parse(preflightBytes.toString('utf8'));
const templates = {
  providerQualification: readJson(paths.providerQualification),
  sourceOriginPreflightAttestation: readJson(paths.sourceOriginPreflightAttestation),
  environmentAttestation: readJson(paths.environmentAttestation),
  canonicalization: readJson(paths.canonicalization),
  artifactManifest: readJson(paths.artifactManifest),
  independentReview: readJson(paths.independentReview)
};

check(Core.validateOnboardingContract(onboarding, parent, parentBytes, evidence, evidenceBytes, preflight, preflightBytes, preflightRunnerBytes, templates), 'onboarding package validates against all frozen sources');
check(onboarding.identity.production_gate === 'closed', 'onboarding production gate remains closed');
check(onboarding.canonical_gate_snapshot.currently_satisfied_gate_ids.length === 0, 'onboarding cannot mark a P0 gate satisfied');
check(onboarding.first_fieldwork_order[1].gate_id === Core.CANONICAL_GATE_IDS[6], 'fieldwork starts real gate collection with stable object/template readback');
check(onboarding.first_fieldwork_order[7].gate_id === Core.CANONICAL_GATE_IDS[5], 'fieldwork finishes with one-to-four authority replay collection');
check(templates.artifactManifest.entries.length === 0, 'local artifact manifest contains no evidence entries');
check(templates.independentReview.gate_review_requests.every((entry) => entry.review_outcome === null), 'local independent-review template contains no outcomes');

const badParentDigest = clone(onboarding);
badParentDigest.source_contracts[0].content_sha256 = '0'.repeat(64);
throws(() => Core.validateOnboardingContract(badParentDigest, parent, parentBytes, evidence, evidenceBytes, preflight, preflightBytes, preflightRunnerBytes, templates), /parent source drift/, 'parent P0 source digest drift is rejected');
const badEvidenceDigest = clone(onboarding);
badEvidenceDigest.source_contracts[1].content_sha256 = '1'.repeat(64);
throws(() => Core.validateOnboardingContract(badEvidenceDigest, parent, parentBytes, evidence, evidenceBytes, preflight, preflightBytes, preflightRunnerBytes, templates), /evidence source drift/, 'evidence-adoption source digest drift is rejected');
const badGateOrder = clone(onboarding);
badGateOrder.canonical_gate_snapshot.required_gate_ids.reverse();
throws(() => Core.validateOnboardingContract(badGateOrder, parent, parentBytes, evidence, evidenceBytes, preflight, preflightBytes, preflightRunnerBytes, templates), /canonical gate sequence/, 'reordered P0 taxonomy is rejected');
const unsafeProvider = clone(onboarding);
unsafeProvider.identity.actual_capture_provider = 'external://provider/live';
throws(() => Core.validateOnboardingContract(unsafeProvider, parent, parentBytes, evidence, evidenceBytes, preflight, preflightBytes, preflightRunnerBytes, templates), /must remain null/, 'local provider registration is rejected');
const unsafeEndpoint = clone(onboarding);
unsafeEndpoint.trust_boundary.provider_endpoint = 'https://provider.example';
throws(() => Core.validateOnboardingContract(unsafeEndpoint, parent, parentBytes, evidence, evidenceBytes, preflight, preflightBytes, preflightRunnerBytes, templates), /must remain null/, 'local provider endpoint is rejected');
const unsafeFieldwork = clone(onboarding);
unsafeFieldwork.first_fieldwork_order[0].external_artifact_ref = 'external://artifact/pretend';
throws(() => Core.validateOnboardingContract(unsafeFieldwork, parent, parentBytes, evidence, evidenceBytes, preflight, preflightBytes, preflightRunnerBytes, templates), /must remain null/, 'local fieldwork artifact is rejected');
const unsafeManifest = clone(templates.artifactManifest);
unsafeManifest.entries.push({ gate_id: Core.CANONICAL_GATE_IDS[0] });
throws(() => Core.validateArtifactManifestTemplate(unsafeManifest), /local entries/, 'local artifact manifest cannot become an evidence ledger');
const unsafeReview = clone(templates.independentReview);
unsafeReview.gate_review_requests[0].review_outcome = 'accepted';
throws(() => Core.validateIndependentReviewTemplate(unsafeReview), /must remain null/, 'local review handoff cannot decide a gate');
const unsafeAttestation = clone(templates.environmentAttestation);
unsafeAttestation.required_environment_snapshot.engine_build_digest = 'a'.repeat(64);
throws(() => Core.validateEnvironmentAttestationTemplate(unsafeAttestation, Core.sha256Hex(parentBytes), Core.sha256Hex(evidenceBytes), Core.sha256Hex(preflightBytes), Core.sha256Hex(preflightRunnerBytes)), /must remain null/, 'local environment template cannot carry a real digest');
const hiddenTemplateField = clone(templates.providerQualification);
hiddenTemplateField.identity.hidden_provider_key = null;
throws(() => Core.validateProviderQualificationTemplate(hiddenTemplateField), /key set/, 'hidden provider credential field is rejected');

const missingRoleIsolation = clone(onboarding);
missingRoleIsolation.role_separation.must_not_be_same_principal_pairs = [
  ['capture_provider', 'capture_operator'],
  ['capture_provider', 'independent_reviewer'],
  ['capture_provider', 'adoption_authority'],
  ['capture_operator', 'independent_reviewer'],
  ['capture_operator', 'independent_reviewer'],
  ['independent_reviewer', 'adoption_authority']
];
throws(() => Core.validateOnboardingContract(missingRoleIsolation, parent, parentBytes, evidence, evidenceBytes, preflight, preflightBytes, preflightRunnerBytes, templates), /separation pairs/, 'a missing operator/adoption separation pair is rejected');
const unsafeNodeBoundary = clone(onboarding);
unsafeNodeBoundary.trust_boundary.node_fengari_live_capture_trust_root = true;
throws(() => Core.validateOnboardingContract(unsafeNodeBoundary, parent, parentBytes, evidence, evidenceBytes, preflight, preflightBytes, preflightRunnerBytes, templates), /node_fengari_live_capture_trust_root/, 'Node/Fengari cannot become a live capture trust root');
const unsafeProviderClaim = clone(templates.providerQualification);
unsafeProviderClaim.prohibited_claims[2] = 'provider may self-adopt a P0 gate';
throws(() => Core.validateProviderQualificationTemplate(unsafeProviderClaim), /prohibited claims/, 'provider self-adoption wording is rejected');
const unsafeAttestationRule = clone(templates.environmentAttestation);
unsafeAttestationRule.failure_rule = 'ignore drift and start capture';
throws(() => Core.validateEnvironmentAttestationTemplate(unsafeAttestationRule, Core.sha256Hex(parentBytes), Core.sha256Hex(evidenceBytes), Core.sha256Hex(preflightBytes), Core.sha256Hex(preflightRunnerBytes)), /failure rule/, 'environment drift bypass wording is rejected');
const unsafeCanonicalizationRule = clone(templates.canonicalization);
unsafeCanonicalizationRule.deterministic_rules.forbidden_non_determinism[0] = 'allow local wall clock';
throws(() => Core.validateCanonicalizationTemplate(unsafeCanonicalizationRule), /forbidden nondeterminism/, 'local wall-clock capture is rejected');
const unsafeReviewHandoff = clone(templates.independentReview);
unsafeReviewHandoff.handoff_rule = 'reviewer may directly adopt';
throws(() => Core.validateIndependentReviewTemplate(unsafeReviewHandoff), /handoff rule/, 'independent review cannot directly adopt a gate');
const unsafePreflightBoundary = clone(onboarding);
unsafePreflightBoundary.preflight_dependency.preflight_is_necessary_but_not_sufficient = false;
throws(() => Core.validateOnboardingContract(unsafePreflightBoundary, parent, parentBytes, evidence, evidenceBytes, preflight, preflightBytes, preflightRunnerBytes, templates), /necessary but insufficient/, 'structural preflight alone cannot prove real map origin');
const unsafeRunnerDigest = clone(onboarding);
unsafeRunnerDigest.preflight_dependency.preflight_runner_content_sha256 = '2'.repeat(64);
throws(() => Core.validateOnboardingContract(unsafeRunnerDigest, parent, parentBytes, evidence, evidenceBytes, preflight, preflightBytes, preflightRunnerBytes, templates), /runner digest/, 'preflight runner digest drift is rejected');
const unsafeOriginAttestation = clone(templates.sourceOriginPreflightAttestation);
unsafeOriginAttestation.source_binding.real_map_identity_digest = '3'.repeat(64);
throws(() => Core.validateSourceOriginPreflightAttestationTemplate(unsafeOriginAttestation, Core.sha256Hex(preflightBytes), Core.sha256Hex(preflightRunnerBytes)), /must remain null/, 'local source-origin attestation cannot carry a real map identity');
const unsafeManifestCycle = clone(templates.artifactManifest);
unsafeManifestCycle.bundle_binding.adoption_decision_ref = null;
throws(() => Core.validateArtifactManifestTemplate(unsafeManifestCycle), /key set/, 'manifest cannot pre-reference an adoption decision');
const unsafeManifestFamily = clone(templates.artifactManifest);
unsafeManifestFamily.environment_family_binding.capture_basis_digest = '4'.repeat(64);
throws(() => Core.validateArtifactManifestTemplate(unsafeManifestFamily), /must remain null/, 'local manifest cannot carry a frozen environment family');
throws(() => Core.attemptProviderRegistration(onboarding, { provider_id: 'external-provider' }), /cannot register a capture provider/, 'offline onboarding package cannot register a provider');

console.log(`PASS: P0 external-capture-onboarding reference tests (${assertions} assertions)`);
