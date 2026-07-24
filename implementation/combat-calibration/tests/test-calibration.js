'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const Core = require('../reference/calibration-core');

const packageRoot = path.resolve(__dirname, '..');
const contract = JSON.parse(fs.readFileSync(path.join(packageRoot, 'contract', 'cross-profession-combat-calibration-contract.json'), 'utf8'));

let assertions = 0;
function check(condition, message) {
  assertions += 1;
  assert.ok(condition, message);
}
function equal(actual, expected, message) {
  assertions += 1;
  assert.strictEqual(actual, expected, message);
}
function throws(callback, matcher, message) {
  assertions += 1;
  assert.throws(callback, matcher, message);
}

Core.validateContract(contract);
check(true, 'full contract validation');

const expectedAnchors = {
  C01: {
    41: { hp_max: 3340, attack_phy: 276, attack_mag: 0, defense_phy: 98, defense_mag: 76 },
    55: { hp_max: 4292, attack_phy: 356, attack_mag: 0, defense_phy: 125, defense_mag: 97 },
    60: { hp_max: 4632, attack_phy: 384, attack_mag: 0, defense_phy: 134, defense_mag: 105 }
  },
  C02: {
    41: { hp_max: 3920, attack_phy: 230, attack_mag: 0, defense_phy: 120, defense_mag: 92 },
    55: { hp_max: 5040, attack_phy: 296, attack_mag: 0, defense_phy: 152, defense_mag: 117 },
    60: { hp_max: 5440, attack_phy: 319, attack_mag: 0, defense_phy: 164, defense_mag: 126 }
  },
  C03: {
    41: { hp_max: 3150, attack_phy: 112, attack_mag: 296, defense_phy: 82, defense_mag: 94 },
    55: { hp_max: 4046, attack_phy: 143, attack_mag: 381, defense_phy: 104, defense_mag: 119 },
    60: { hp_max: 4366, attack_phy: 154, attack_mag: 412, defense_phy: 112, defense_mag: 128 }
  },
  C04: {
    41: { hp_max: 2880, attack_phy: 264, attack_mag: 0, defense_phy: 79, defense_mag: 84 },
    55: { hp_max: 3692, attack_phy: 340, attack_mag: 0, defense_phy: 101, defense_mag: 107 },
    60: { hp_max: 3982, attack_phy: 368, attack_mag: 0, defense_phy: 108, defense_mag: 115 }
  }
};

for (const [professionId, levels] of Object.entries(expectedAnchors)) {
  for (const [levelText, expected] of Object.entries(levels)) {
    assert.deepStrictEqual(Core.deriveBareStats(contract, professionId, Number(levelText)), expected, `${professionId} Lv${levelText} anchor`);
    assertions += 1;
  }
}
equal(Core.roundHalfUpNonNegative(149.55), 150, 'C04-style stat rounding is half-up, not truncation');
throws(() => Core.deriveBareStats(contract, 'C99', 60), /unknown profession/, 'unknown professions fail closed');
throws(() => Core.deriveBareStats(contract, 'C01', 61), /level must be/, 'out-of-range levels fail closed');

const legacy = Core.resolveLegacyPhysicalStaticTarget({
  fixture_id: 'COMBAT_REF_L60_BOSS_01',
  damage_channel: 'physical',
  final_attack_phy: 384,
  skill_coefficient: 1,
  explicit_same_source_multiplier: 1,
  target_physical_defense: 180,
  target_magic_defense: 180,
  crit_enabled: false,
  random_damage_enabled: false,
  dodge_enabled: false,
  random_hit_enabled: false,
  penetration_enabled: false,
  break_state_enabled: false,
  damage_reduction_enabled: false,
  heal_enabled: false,
  summon_enabled: false,
  invulnerability_enabled: false,
  transition_enabled: false
});
equal(legacy.raw_damage, 384, 'legacy raw physical damage');
equal(legacy.final_damage, 137, 'legacy final physical damage floors once after mitigation');

const unsafeLegacy = {
  fixture_id: 'COMBAT_REF_L60_BOSS_01',
  damage_channel: 'physical',
  final_attack_phy: 384,
  skill_coefficient: 1,
  explicit_same_source_multiplier: 1,
  target_physical_defense: 180,
  target_magic_defense: 180,
  crit_enabled: false,
  random_damage_enabled: false,
  dodge_enabled: false,
  random_hit_enabled: false,
  penetration_enabled: false,
  break_state_enabled: false,
  damage_reduction_enabled: false,
  heal_enabled: false,
  summon_enabled: false,
  invulnerability_enabled: false,
  transition_enabled: false
};
throws(() => Core.resolveLegacyPhysicalStaticTarget({ ...unsafeLegacy, damage_channel: 'magical' }), /non-physical/, 'legacy fixture rejects magic extension');
throws(() => Core.resolveLegacyPhysicalStaticTarget({ ...unsafeLegacy, target_physical_defense: 179 }), /changed target defense/, 'legacy fixture rejects defense drift');
throws(() => Core.resolveLegacyPhysicalStaticTarget({ ...unsafeLegacy, crit_enabled: true }), /crit_enabled/, 'legacy fixture rejects enabled random inputs');

const syntheticLog = [
  { event_id: 'd-001', tick: 0, accepted: true, event_type: 'final_damage', final_damage: 5, scope: 'fixture_public', session_scope: 'public', fixture_id: 'synthetic-fixture', actor_id: 'actor-a', actor_lifecycle_id: 1, target_id: 'target-a', target_lifecycle_id: 'target-life-a', actor_alive: true, target_alive: true },
  { event_id: 'd-002', tick: 100, accepted: true, event_type: 'final_damage', final_damage: 20, scope: 'fixture_public', session_scope: 'public', fixture_id: 'synthetic-fixture', actor_id: 'actor-a', actor_lifecycle_id: 1, target_id: 'target-a', target_lifecycle_id: 'target-life-a', actor_alive: true, target_alive: true },
  { event_id: 'd-003', tick: 700, accepted: true, event_type: 'final_damage', final_damage: 30, scope: 'fixture_public', session_scope: 'public', fixture_id: 'synthetic-fixture', actor_id: 'actor-a', actor_lifecycle_id: 1, target_id: 'target-a', target_lifecycle_id: 'target-life-a', actor_alive: true, target_alive: true },
  { event_id: 'd-004', tick: 800, accepted: true, event_type: 'final_damage', final_damage: 10, scope: 'fixture_public', session_scope: 'public', fixture_id: 'synthetic-fixture', actor_id: 'actor-a', actor_lifecycle_id: 1, target_id: 'target-a', target_lifecycle_id: 'target-life-a', actor_alive: true, target_alive: true },
  { event_id: 'd-005', tick: 4800, accepted: true, event_type: 'final_damage', final_damage: 50, scope: 'fixture_public', session_scope: 'public', fixture_id: 'synthetic-fixture', actor_id: 'actor-a', actor_lifecycle_id: 1, target_id: 'target-a', target_lifecycle_id: 'target-life-a', actor_alive: true, target_alive: true },
  { event_id: 'd-006', tick: 5399, accepted: true, event_type: 'final_damage', final_damage: 40, scope: 'fixture_public', session_scope: 'public', fixture_id: 'synthetic-fixture', actor_id: 'actor-a', actor_lifecycle_id: 1, target_id: 'target-a', target_lifecycle_id: 'target-life-a', actor_alive: true, target_alive: true },
  { event_id: 'd-007', tick: 5399, accepted: false, event_type: 'final_damage', final_damage: 1000, scope: 'fixture_public', session_scope: 'public', fixture_id: 'synthetic-fixture', actor_id: 'actor-a', actor_lifecycle_id: 1, target_id: 'target-a', target_lifecycle_id: 'target-life-a', actor_alive: true, target_alive: true },
  { event_id: 'd-008', tick: 5399, accepted: true, event_type: 'final_damage', final_damage: 1000, scope: 'fixture_public', session_scope: 'private', fixture_id: 'synthetic-fixture', actor_id: 'actor-a', actor_lifecycle_id: 1, target_id: 'target-a', target_lifecycle_id: 'target-life-a', actor_alive: true, target_alive: true }
];
const metrics = Core.calculateD90AndB10(syntheticLog);
equal(metrics.D90, 155, 'D90 counts only accepted public alive damage within [0, 5400)');
equal(metrics.B10, 90, 'B10 is the maximum exact 600-tick window');
equal(metrics.B10_start_tick, 4800, 'B10 ties use the earliest applicable maximum window');
throws(() => Core.calculateD90AndB10([...syntheticLog].reverse()), /not canonical/, 'noncanonical damage logs fail closed');

check(Math.abs(Core.designSpaceDistance(3.8, 63) - 3.99) < 1e-12, 'design-space C01 motion conversion');
check(Math.abs(Core.designSpaceDistance(3.85, 12) - 0.77) < 1e-12, 'design-space C04 motion conversion');
throws(() => Core.designSpaceDistance(3.8, 12.5), /non-negative integer/, 'fractional ticks fail closed');

throws(() => Core.validateTerrainFixture(contract, { diagram_only: true }), /diagram-only/, 'diagram-only terrain data is not collision proof');
const terrainFixture = {
  fixture_id: 'synthetic-schema-test-only',
  map_revision: 'not-a-map-write',
  camera_profile_id: 'candidate',
  actor_template_id: 'deferred',
  target_template_id: 'deferred',
  collision_shapes: 'captured',
  walkable_segments: 'captured',
  blocked_segments: 'captured',
  slope_or_height_policy: 'captured',
  line_of_sight_policy: 'captured',
  measured_positions: 'captured',
  recorded_inputs: 'captured',
  recorded_outcomes: 'captured'
};
check(Core.validateTerrainFixture(contract, terrainFixture), 'schema-only terrain fixture validates structurally but is not evidence');

const partyFixture = {
  fixture_id: 'synthetic-schema-test-only',
  member_count: 2,
  member_snapshot_digest: 'synthetic',
  encounter_snapshot_digest: 'synthetic',
  authority_time_basis_id: 'synthetic',
  member_actor_lifecycle_pairs: [{ actor_id: 'a', lifecycle_id: 1 }, { actor_id: 'b', lifecycle_id: 2 }],
  accepted_action_log_digest: 'synthetic',
  damage_log_digest: 'synthetic',
  disconnect_or_left_events: 'none',
  cleanup_result: 'observed',
  fixture_version: 'schema-test-v1',
  authority_semantics: 'observational_only'
};
check(Core.validatePartyReplayFixture(contract, partyFixture), 'one-to-four fixture schema validates without granting authority');
throws(() => Core.validatePartyReplayFixture(contract, { ...partyFixture, member_count: 5, member_actor_lifecycle_pairs: [...partyFixture.member_actor_lifecycle_pairs, { actor_id: 'c', lifecycle_id: 3 }, { actor_id: 'd', lifecycle_id: 4 }, { actor_id: 'e', lifecycle_id: 5 }] }), /one through four/, 'fifth member fails closed');
throws(() => Core.validatePartyReplayFixture(contract, { ...partyFixture, member_actor_lifecycle_pairs: [{ actor_id: 'a', lifecycle_id: 1 }, { actor_id: 'a', lifecycle_id: 1 }] }), /duplicate replay member/, 'duplicate actor lifecycle fails closed');

const gateStatus = Core.getProjectionGateStatus(contract);
equal(gateStatus.ready, false, 'absolute projection remains blocked');
equal(gateStatus.missing_gate_ids.length, 7, 'all seven projection gates remain missing');
check(Core.validateBlockedProjection(contract), 'all absolute fields remain null');
const unsafeContract = JSON.parse(JSON.stringify(contract));
unsafeContract.absolute_projection_gate.candidate.hp_max = 1;
throws(() => Core.validateBlockedProjection(unsafeContract), /hp_max must remain null/, 'a raw object field cannot leak through the gate');

console.log(`PASS: cross-profession combat calibration reference tests (${assertions} assertions)`);
