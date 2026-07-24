'use strict';

const REQUIRED_LEVELS = Object.freeze([41, 55, 60]);
const REQUIRED_PROFESSIONS = Object.freeze(['C01', 'C02', 'C03', 'C04']);
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

function invariant(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function isFiniteNonNegative(value) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function roundHalfUpNonNegative(value) {
  invariant(isFiniteNonNegative(value), 'rounding requires a finite non-negative number');
  return Math.floor(value + 0.5);
}

function getProfession(contract, professionId) {
  invariant(contract && Array.isArray(contract.combatant_baselines), 'missing combatant baselines');
  const profession = contract.combatant_baselines.find((entry) => entry.profession_id === professionId);
  invariant(profession, `unknown profession ${professionId}`);
  return profession;
}

function deriveBareStats(contract, professionId, level) {
  invariant(Number.isInteger(level) && level >= 1 && level <= 60, 'level must be an integer from 1 through 60');
  const profession = getProfession(contract, professionId);
  const result = {};
  for (const statKey of ['hp_max', 'attack_phy', 'attack_mag', 'defense_phy', 'defense_mag']) {
    const formula = profession.naked_stat_formula[statKey];
    invariant(formula && isFiniteNonNegative(formula.base) && isFiniteNonNegative(formula.per_level), `invalid ${professionId}.${statKey} formula`);
    result[statKey] = roundHalfUpNonNegative(formula.base + formula.per_level * (level - 1));
  }
  return result;
}

function validateAnchorTable(contract) {
  invariant(Array.isArray(contract.combatant_baselines) && contract.combatant_baselines.length === REQUIRED_PROFESSIONS.length, 'expected exactly four profession baselines');
  const seenProfessions = new Set();
  for (const profession of contract.combatant_baselines) {
    invariant(REQUIRED_PROFESSIONS.includes(profession.profession_id), `unexpected profession ${profession.profession_id}`);
    invariant(!seenProfessions.has(profession.profession_id), `duplicate profession ${profession.profession_id}`);
    seenProfessions.add(profession.profession_id);
    invariant(Array.isArray(profession.level_anchors) && profession.level_anchors.length === REQUIRED_LEVELS.length, `${profession.profession_id} must have three anchors`);
    const seenLevels = new Set();
    for (const anchor of profession.level_anchors) {
      invariant(REQUIRED_LEVELS.includes(anchor.level), `${profession.profession_id} has an unsupported anchor level`);
      invariant(!seenLevels.has(anchor.level), `${profession.profession_id} has duplicate anchor level ${anchor.level}`);
      seenLevels.add(anchor.level);
      const calculated = deriveBareStats(contract, profession.profession_id, anchor.level);
      for (const statKey of Object.keys(calculated)) {
        invariant(anchor[statKey] === calculated[statKey], `${profession.profession_id} Lv${anchor.level} ${statKey} anchor drift`);
      }
    }
    for (const level of REQUIRED_LEVELS) {
      invariant(seenLevels.has(level), `${profession.profession_id} is missing Lv${level}`);
    }
  }
  return true;
}

function validateBuildLedger(contract) {
  const ledger = contract.fixed_build_declaration_ledger;
  invariant(ledger && Array.isArray(ledger.profiles), 'missing fixed build declaration ledger');
  invariant(JSON.stringify(ledger.required_levels) === JSON.stringify(REQUIRED_LEVELS), 'ledger level set drift');
  const expected = new Set(REQUIRED_PROFESSIONS.flatMap((professionId) => REQUIRED_LEVELS.map((level) => `${professionId}:${level}`)));
  invariant(ledger.profiles.length === expected.size, 'fixed build ledger must have exactly twelve profiles');
  for (const profile of ledger.profiles) {
    const key = `${profile.profession_id}:${profile.level}`;
    invariant(expected.has(key), `unexpected or duplicate build profile ${key}`);
    expected.delete(key);
    invariant([
      'blocked_missing_declared_loadout',
      'partially_declared_static_target_only',
      'partially_declared_slot_recipe_only',
      'declared_and_replayed'
    ].includes(profile.status), `unsupported build status for ${key}`);
    if (profile.declaration !== null) {
      invariant(typeof profile.declaration === 'object' && !Array.isArray(profile.declaration), `invalid declaration for ${key}`);
    }
    if (profile.status === 'declared_and_replayed') {
      invariant(profile.declaration !== null, `replayed profile ${key} requires a declaration`);
      for (const requiredField of ledger.common_required_fields) {
        invariant(Object.hasOwn(profile.declaration, requiredField) && profile.declaration[requiredField] !== null, `replayed profile ${key} is missing ${requiredField}`);
      }
      invariant(Array.isArray(profile.replay_log_digests) && profile.replay_log_digests.length === 3, `replayed profile ${key} requires three replay digests`);
    }
  }
  invariant(expected.size === 0, `missing build profiles: ${[...expected].join(', ')}`);
  return true;
}

function validateFormulaBoundary(contract) {
  const formulas = contract.formula_registry;
  invariant(formulas && formulas.legacy_physical_static_target_v1, 'missing legacy formula boundary');
  const legacy = formulas.legacy_physical_static_target_v1;
  invariant(legacy.status === 'accepted_only_for_named_legacy_fixture', 'legacy formula status drift');
  invariant(legacy.allowed_fixture_id === 'COMBAT_REF_L60_BOSS_01', 'legacy fixture drift');
  invariant(legacy.allowed_damage_channel === 'physical', 'legacy damage channel drift');
  invariant(legacy.target_physical_defense === 180 && legacy.target_magic_defense === 180, 'legacy defense drift');
  for (const key of ['general_physical_damage', 'general_magical_damage', 'defense_penetration_order', 'critical_order_and_caps', 'hit_dodge_formula', 'control_duration_resistance_formula']) {
    invariant(formulas[key] === null, `${key} must remain null until separately adopted`);
  }
  return true;
}

function resolveLegacyPhysicalStaticTarget(input) {
  invariant(input && typeof input === 'object' && !Array.isArray(input), 'legacy calculation requires an object');
  invariant(input.fixture_id === 'COMBAT_REF_L60_BOSS_01', 'legacy formula rejects a different fixture');
  invariant(input.damage_channel === 'physical', 'legacy formula rejects non-physical damage');
  invariant(input.target_physical_defense === 180 && input.target_magic_defense === 180, 'legacy formula rejects a changed target defense');
  for (const flag of ['crit_enabled', 'random_damage_enabled', 'dodge_enabled', 'random_hit_enabled', 'penetration_enabled', 'break_state_enabled', 'damage_reduction_enabled', 'heal_enabled', 'summon_enabled', 'invulnerability_enabled', 'transition_enabled']) {
    invariant(input[flag] === false, `legacy formula requires ${flag}=false`);
  }
  for (const valueKey of ['final_attack_phy', 'skill_coefficient', 'explicit_same_source_multiplier']) {
    invariant(isFiniteNonNegative(input[valueKey]), `legacy formula requires finite non-negative ${valueKey}`);
  }
  const rawDamage = input.final_attack_phy * input.skill_coefficient * input.explicit_same_source_multiplier;
  const mitigatedDamage = rawDamage * 100 / (100 + input.target_physical_defense);
  return {
    fixture_id: input.fixture_id,
    raw_damage: rawDamage,
    final_damage: Math.floor(mitigatedDamage),
    rounding: 'floor_once_after_mitigation'
  };
}

function validateDamageLog(events) {
  invariant(Array.isArray(events), 'damage log must be an array');
  let previousTick = -1;
  const eventIds = new Set();
  for (const event of events) {
    invariant(event && typeof event === 'object' && !Array.isArray(event), 'damage event must be an object');
    invariant(typeof event.event_id === 'string' && event.event_id.length > 0, 'damage event requires a non-empty event_id');
    invariant(!eventIds.has(event.event_id), `duplicate damage event ${event.event_id}`);
    eventIds.add(event.event_id);
    invariant(Number.isInteger(event.tick) && event.tick >= 0, `invalid tick for ${event.event_id}`);
    invariant(event.tick >= previousTick, `damage log is not canonical at ${event.event_id}`);
    previousTick = event.tick;
    if (event.accepted === true && event.event_type === 'final_damage') {
      invariant(isFiniteNonNegative(event.final_damage), `accepted final damage requires a finite non-negative amount for ${event.event_id}`);
    }
  }
  return true;
}

function isEligibleDamageEvent(event) {
  return event.accepted === true
    && event.event_type === 'final_damage'
    && isFiniteNonNegative(event.final_damage)
    && event.scope === 'fixture_public'
    && event.session_scope !== 'private'
    && typeof event.fixture_id === 'string' && event.fixture_id.length > 0
    && typeof event.actor_id === 'string' && event.actor_id.length > 0
    && Number.isInteger(event.actor_lifecycle_id) && event.actor_lifecycle_id >= 0
    && typeof event.target_id === 'string' && event.target_id.length > 0
    && typeof event.target_lifecycle_id === 'string' && event.target_lifecycle_id.length > 0
    && event.actor_alive === true
    && event.target_alive === true
    && event.post_death !== true;
}

function calculateD90AndB10(events) {
  validateDamageLog(events);
  const eligible = events.filter(isEligibleDamageEvent);
  if (eligible.length > 0) {
    const first = eligible[0];
    const binding = [first.fixture_id, first.actor_id, first.actor_lifecycle_id, first.target_id, first.target_lifecycle_id].join('|');
    for (const event of eligible) {
      const eventBinding = [event.fixture_id, event.actor_id, event.actor_lifecycle_id, event.target_id, event.target_lifecycle_id].join('|');
      invariant(eventBinding === binding, 'D90/B10 log mixes fixture, actor or target lifecycles');
    }
  }
  const d90 = eligible
    .filter((event) => event.tick < 5400)
    .reduce((total, event) => total + event.final_damage, 0);
  let b10 = 0;
  let b10StartTick = 0;
  for (let startTick = 0; startTick <= 4800; startTick += 1) {
    const endTick = startTick + 600;
    const total = eligible
      .filter((event) => event.tick >= startTick && event.tick < endTick)
      .reduce((sum, event) => sum + event.final_damage, 0);
    if (total > b10) {
      b10 = total;
      b10StartTick = startTick;
    }
  }
  return { D90: d90, B10: b10, B10_start_tick: b10StartTick, eligible_event_count: eligible.length };
}

function designSpaceDistance(moveSpeedDesignUnitsPerSecond, elapsedTicks) {
  invariant(isFiniteNonNegative(moveSpeedDesignUnitsPerSecond), 'move speed must be finite and non-negative');
  invariant(Number.isInteger(elapsedTicks) && elapsedTicks >= 0, 'elapsed ticks must be a non-negative integer');
  return moveSpeedDesignUnitsPerSecond * elapsedTicks / 60;
}

function validateTerrainFixture(contract, fixture) {
  invariant(fixture && typeof fixture === 'object' && !Array.isArray(fixture), 'terrain fixture must be an object');
  invariant(fixture.diagram_only !== true, 'diagram-only terrain data is not collision evidence');
  const required = contract.terrain_collision_fixture.required_fields;
  for (const key of required) {
    invariant(Object.hasOwn(fixture, key) && fixture[key] !== null && fixture[key] !== '', `terrain fixture is missing ${key}`);
  }
  return true;
}

function validatePartyReplayFixture(contract, fixture) {
  invariant(fixture && typeof fixture === 'object' && !Array.isArray(fixture), 'party replay fixture must be an object');
  invariant(contract.party_replay_fixture.allowed_member_counts.includes(fixture.member_count), 'member_count must be one through four');
  for (const key of contract.party_replay_fixture.required_fields) {
    invariant(Object.hasOwn(fixture, key) && fixture[key] !== null && fixture[key] !== '', `party replay fixture is missing ${key}`);
  }
  invariant(Array.isArray(fixture.member_actor_lifecycle_pairs), 'member_actor_lifecycle_pairs must be an array');
  invariant(fixture.member_actor_lifecycle_pairs.length === fixture.member_count, 'member count does not match member snapshot');
  const identities = new Set();
  for (const member of fixture.member_actor_lifecycle_pairs) {
    invariant(member && typeof member.actor_id === 'string' && member.actor_id.length > 0, 'replay member needs actor_id');
    invariant(Number.isInteger(member.lifecycle_id) && member.lifecycle_id >= 0, 'replay member needs a non-negative lifecycle_id');
    const identity = `${member.actor_id}:${member.lifecycle_id}`;
    invariant(!identities.has(identity), `duplicate replay member ${identity}`);
    identities.add(identity);
  }
  invariant(fixture.authority_semantics === 'observational_only', 'replay fixture must not implement authority semantics');
  return true;
}

function getProjectionGateStatus(contract) {
  const gate = contract.absolute_projection_gate;
  invariant(gate && Array.isArray(gate.required_gate_ids) && Array.isArray(gate.current_satisfied_gate_ids), 'missing absolute projection gate');
  const satisfied = new Set(gate.current_satisfied_gate_ids);
  const missing = gate.required_gate_ids.filter((gateId) => !satisfied.has(gateId));
  return { ready: missing.length === 0, missing_gate_ids: missing };
}

function validateBlockedProjection(contract) {
  const gate = contract.absolute_projection_gate;
  const candidate = gate && gate.candidate;
  invariant(gate.status === 'blocked_pending_evidence', 'absolute projection gate must remain blocked');
  invariant(candidate && candidate.status === 'blocked', 'absolute projection candidate must remain blocked');
  for (const key of ABSOLUTE_PROJECTION_FIELDS) {
    invariant(candidate[key] === null, `absolute projection field ${key} must remain null`);
  }
  invariant(getProjectionGateStatus(contract).ready === false, 'offline package cannot self-promote the absolute projection gate');
  return true;
}

function validateContract(contract) {
  invariant(contract.schema_version === 1, 'unsupported contract schema version');
  invariant(contract.package_status === 'offline-calibration-reference-only', 'invalid package status');
  invariant(contract.non_production === true && contract.runtime_handoff === false && contract.production_gate === 'closed', 'offline boundary drift');
  validateAnchorTable(contract);
  validateBuildLedger(contract);
  validateFormulaBoundary(contract);
  validateBlockedProjection(contract);
  invariant(Array.isArray(contract.acceptance) && contract.acceptance.length === 18, 'expected eighteen acceptance checks');
  const acceptanceIds = new Set(contract.acceptance.map((entry) => entry.id));
  invariant(acceptanceIds.size === contract.acceptance.length, 'duplicate acceptance identifier');
  for (let index = 1; index <= 18; index += 1) {
    const expectedId = `CAL-ACC-${String(index).padStart(3, '0')}`;
    invariant(acceptanceIds.has(expectedId), `missing acceptance identifier ${expectedId}`);
  }
  return true;
}

module.exports = {
  ABSOLUTE_PROJECTION_FIELDS,
  REQUIRED_LEVELS,
  REQUIRED_PROFESSIONS,
  calculateD90AndB10,
  deriveBareStats,
  designSpaceDistance,
  getProjectionGateStatus,
  resolveLegacyPhysicalStaticTarget,
  roundHalfUpNonNegative,
  validateBlockedProjection,
  validateBuildLedger,
  validateContract,
  validateDamageLog,
  validatePartyReplayFixture,
  validateTerrainFixture
};
