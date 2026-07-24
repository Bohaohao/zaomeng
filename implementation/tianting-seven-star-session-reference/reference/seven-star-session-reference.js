'use strict';

const SESSION_STATES = Object.freeze({
  ACTIVE: 'active',
  CLEANUP_PENDING: 'cleanup_pending',
  CLOSED: 'closed'
});

const FAILURE_REASONS = Object.freeze([
  'owner_death',
  'timeout',
  'owner_disconnect',
  'owner_lifecycle_invalid'
]);

const SEVEN_STAR_ROUTE_SPEC_IDS = Object.freeze([
  'TT_SPEC_SOLO_TIANSHU',
  'TT_SPEC_SOLO_TIANXUAN',
  'TT_SPEC_SOLO_TIANJI',
  'TT_SPEC_SOLO_TIANQUAN',
  'TT_SPEC_SOLO_YUHENG',
  'TT_SPEC_SOLO_KAIYANG',
  'TT_SPEC_SOLO_YAOGUANG'
]);

const ROUTE_SET = new Set(SEVEN_STAR_ROUTE_SPEC_IDS);
const FAILURE_SET = new Set(FAILURE_REASONS);
const IDENTITY_FIELDS = Object.freeze([
  'owner_actor_id',
  'lifecycle_id',
  'session_instance_id',
  'session_epoch',
  'revision',
  'cleanup_token'
]);

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function canonicalize(value) {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      throw new TypeError('request payload contains a non-finite number');
    }
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(canonicalize);
  }
  if (typeof value === 'object' && value !== null) {
    const result = {};
    for (const key of Object.keys(value).sort()) {
      if (typeof value[key] !== 'undefined') {
        result[key] = canonicalize(value[key]);
      }
    }
    return result;
  }
  throw new TypeError('request payload contains an unsupported value');
}

function stableStringify(value) {
  return JSON.stringify(canonicalize(value));
}

function nonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function rejected(reason) {
  return { accepted: false, reason };
}

function publicSession(session) {
  return {
    owner_actor_id: session.owner_actor_id,
    lifecycle_id: session.lifecycle_id,
    route_spec_id: session.route_spec_id,
    session_instance_id: session.session_instance_id,
    session_epoch: session.session_epoch,
    revision: session.revision,
    cleanup_token: session.cleanup_token,
    state: session.state,
    terminal_reason: session.terminal_reason,
    completion_retained: session.completion !== null
  };
}

function normalizeIdentity(value) {
  const source = value && typeof value === 'object' ? value : {};
  const result = {};
  for (const field of IDENTITY_FIELDS) {
    result[field] = source[field];
  }
  return result;
}

function identityMatches(session, identity) {
  return IDENTITY_FIELDS.every((field) => session[field] === identity[field]);
}

class SevenStarSessionReference {
  constructor({ trustedAuthority, instancePrefix = 'offline-seven-star' }) {
    if (!trustedAuthority || typeof trustedAuthority.resolveOwner !== 'function') {
      throw new TypeError('trustedAuthority.resolveOwner is required');
    }
    if (typeof trustedAuthority.validateFailureSignal !== 'function') {
      throw new TypeError('trustedAuthority.validateFailureSignal is required');
    }
    if (!nonEmptyString(instancePrefix)) {
      throw new TypeError('instancePrefix must be a non-empty string');
    }

    this.trustedAuthority = trustedAuthority;
    this.instancePrefix = instancePrefix;
    this.sessions = new Map();
    this.ownerLocks = new Map();
    this.ownerEpochs = new Map();
    this.requestLedger = new Map();
    this.sequence = 0;
  }

  createSession(request) {
    const payload = {
      caller_actor_id: request && request.caller_actor_id,
      requested_owner_actor_id: request && request.requested_owner_actor_id,
      requested_lifecycle_id: request && request.requested_lifecycle_id,
      route_spec_id: request && request.route_spec_id
    };

    return this._claim('create', request, payload, () => {
      if (!nonEmptyString(payload.caller_actor_id) || !nonEmptyString(payload.requested_owner_actor_id)) {
        return rejected('owner_identity_required');
      }
      if (payload.caller_actor_id !== payload.requested_owner_actor_id) {
        return rejected('owner_only');
      }
      if (!nonEmptyString(payload.requested_lifecycle_id)) {
        return rejected('lifecycle_id_required');
      }
      if (!ROUTE_SET.has(payload.route_spec_id)) {
        return rejected('invalid_route_spec_id');
      }

      const owner = this._resolveOwner(payload.requested_owner_actor_id);
      if (!owner || owner.actor_id !== payload.requested_owner_actor_id) {
        return rejected('owner_not_resolved');
      }
      if (owner.lifecycle_id !== payload.requested_lifecycle_id) {
        return rejected('current_lifecycle_required');
      }
      if (owner.observatory_open !== true) {
        return rejected('celestial_observatory_progress_required');
      }

      const lockedSessionId = this.ownerLocks.get(payload.requested_owner_actor_id);
      if (lockedSessionId) {
        const lockedSession = this.sessions.get(lockedSessionId);
        if (lockedSession && lockedSession.state !== SESSION_STATES.CLOSED) {
          return rejected('reentry_denied_until_matching_cleanup');
        }
      }

      const nextEpoch = (this.ownerEpochs.get(payload.requested_owner_actor_id) || 0) + 1;
      this.ownerEpochs.set(payload.requested_owner_actor_id, nextEpoch);
      this.sequence += 1;

      const session = {
        owner_actor_id: payload.requested_owner_actor_id,
        lifecycle_id: payload.requested_lifecycle_id,
        route_spec_id: payload.route_spec_id,
        session_instance_id: `${this.instancePrefix}-${this.sequence}`,
        session_epoch: nextEpoch,
        revision: 1,
        cleanup_token: `${this.instancePrefix}-cleanup-${this.sequence}-${nextEpoch}`,
        state: SESSION_STATES.ACTIVE,
        terminal_reason: null,
        completion: null
      };

      this.sessions.set(session.session_instance_id, session);
      this.ownerLocks.set(session.owner_actor_id, session.session_instance_id);
      return { accepted: true, operation: 'create', session: publicSession(session) };
    });
  }

  failSession(request) {
    const payload = {
      subject_actor_id: request && request.subject_actor_id,
      failure_reason: request && request.failure_reason,
      session: normalizeIdentity(request && request.session)
    };

    return this._claim('failure', request, payload, () => {
      const sessionOrFailure = this._boundSession(payload.session);
      if (sessionOrFailure.reason) {
        return sessionOrFailure;
      }
      const session = sessionOrFailure;
      if (payload.subject_actor_id !== session.owner_actor_id) {
        return rejected('owner_only');
      }
      if (session.state !== SESSION_STATES.ACTIVE) {
        return rejected('session_not_active');
      }
      if (!FAILURE_SET.has(payload.failure_reason)) {
        return rejected('invalid_failure_reason');
      }

      const owner = this._resolveOwner(session.owner_actor_id);
      if (payload.failure_reason === 'owner_lifecycle_invalid' && owner && owner.lifecycle_id === session.lifecycle_id) {
        return rejected('lifecycle_still_current');
      }
      if (this._validateFailureSignal(payload.failure_reason, session) !== true) {
        return rejected('untrusted_failure_signal');
      }

      session.terminal_reason = payload.failure_reason;
      session.state = SESSION_STATES.CLEANUP_PENDING;
      session.revision += 1;
      return { accepted: true, operation: 'failure', session: publicSession(session) };
    });
  }

  completeSession(request) {
    const payload = {
      subject_actor_id: request && request.subject_actor_id,
      session: normalizeIdentity(request && request.session)
    };

    return this._claim('complete', request, payload, () => {
      const sessionOrFailure = this._boundSession(payload.session);
      if (sessionOrFailure.reason) {
        return sessionOrFailure;
      }
      const session = sessionOrFailure;
      if (payload.subject_actor_id !== session.owner_actor_id) {
        return rejected('owner_only');
      }
      if (session.state !== SESSION_STATES.ACTIVE) {
        return rejected('session_not_active');
      }

      const owner = this._resolveOwner(session.owner_actor_id);
      if (!owner || owner.actor_id !== session.owner_actor_id || owner.lifecycle_id !== session.lifecycle_id) {
        return rejected('current_lifecycle_required');
      }
      if (owner.observatory_open !== true) {
        return rejected('celestial_observatory_progress_required');
      }

      session.completion = {
        owner_actor_id: session.owner_actor_id,
        session_instance_id: session.session_instance_id,
        session_epoch: session.session_epoch,
        accepted_revision: session.revision,
        process_local_only: true
      };
      session.terminal_reason = 'normal_completion';
      session.state = SESSION_STATES.CLEANUP_PENDING;
      session.revision += 1;
      return { accepted: true, operation: 'complete', session: publicSession(session) };
    });
  }

  acknowledgeCleanup(request) {
    const payload = {
      subject_actor_id: request && request.subject_actor_id,
      session: normalizeIdentity(request && request.session)
    };

    return this._claim('cleanup', request, payload, () => {
      const sessionOrFailure = this._boundSession(payload.session);
      if (sessionOrFailure.reason) {
        return sessionOrFailure;
      }
      const session = sessionOrFailure;
      if (payload.subject_actor_id !== session.owner_actor_id) {
        return rejected('owner_only');
      }
      if (session.state !== SESSION_STATES.CLEANUP_PENDING) {
        return rejected('cleanup_not_pending');
      }

      session.state = SESSION_STATES.CLOSED;
      session.revision += 1;
      if (this.ownerLocks.get(session.owner_actor_id) === session.session_instance_id) {
        this.ownerLocks.delete(session.owner_actor_id);
      }
      return { accepted: true, operation: 'cleanup', session: publicSession(session) };
    });
  }

  attemptReconnect(request) {
    const payload = {
      subject_actor_id: request && request.subject_actor_id,
      session: normalizeIdentity(request && request.session)
    };

    const sessionOrFailure = this._boundSession(payload.session);
    if (sessionOrFailure.reason) {
      return clone(sessionOrFailure);
    }
    const session = sessionOrFailure;
    if (payload.subject_actor_id !== session.owner_actor_id) {
      return rejected('owner_only');
    }
    if (session.state === SESSION_STATES.CLEANUP_PENDING) {
      return rejected('reconnect_forbidden_until_cleanup_closed');
    }
    if (session.state === SESSION_STATES.CLOSED) {
      return rejected('closed_session_cannot_reconnect');
    }
    return rejected('reconnect_not_supported_for_active_session');
  }

  getSessionSnapshot(sessionInstanceId) {
    const session = this.sessions.get(sessionInstanceId);
    return session ? publicSession(session) : null;
  }

  getCompletionSnapshot(sessionInstanceId) {
    const session = this.sessions.get(sessionInstanceId);
    return session && session.completion ? clone(session.completion) : null;
  }

  _claim(operation, request, payload, handler) {
    const requestId = request && request.request_id;
    if (!nonEmptyString(requestId)) {
      return rejected('request_id_required');
    }
    const ledgerKey = `${operation}:${requestId}`;
    const fingerprint = stableStringify(payload);
    const existing = this.requestLedger.get(ledgerKey);
    if (existing) {
      if (existing.fingerprint !== fingerprint) {
        return rejected('idempotency_payload_drift');
      }
      return clone(existing.result);
    }

    const result = handler();
    this.requestLedger.set(ledgerKey, { fingerprint, result: clone(result) });
    return clone(result);
  }

  _boundSession(identity) {
    if (!nonEmptyString(identity.session_instance_id)) {
      return rejected('session_instance_id_required');
    }
    const session = this.sessions.get(identity.session_instance_id);
    if (!session) {
      return rejected('session_not_found');
    }
    if (!identityMatches(session, identity)) {
      return rejected('session_identity_mismatch');
    }
    return session;
  }

  _resolveOwner(actorId) {
    try {
      const owner = this.trustedAuthority.resolveOwner(actorId);
      return owner && typeof owner === 'object' ? clone(owner) : null;
    } catch (_) {
      return null;
    }
  }

  _validateFailureSignal(failureReason, session) {
    try {
      return this.trustedAuthority.validateFailureSignal({
        failure_reason: failureReason,
        session: publicSession(session)
      }) === true;
    } catch (_) {
      return false;
    }
  }
}

function createFixtureAuthority(initialOwners = {}) {
  const owners = new Map();
  for (const [actorId, owner] of Object.entries(initialOwners)) {
    owners.set(actorId, clone(owner));
  }

  return {
    resolveOwner(actorId) {
      const owner = owners.get(actorId);
      return owner ? clone(owner) : null;
    },
    validateFailureSignal({ failure_reason, session }) {
      if (failure_reason === 'owner_lifecycle_invalid') {
        const current = owners.get(session.owner_actor_id);
        return !current || current.lifecycle_id !== session.lifecycle_id;
      }
      return FAILURE_SET.has(failure_reason);
    },
    setOwner(actorId, owner) {
      owners.set(actorId, clone(owner));
    }
  };
}

module.exports = {
  FAILURE_REASONS,
  IDENTITY_FIELDS,
  SESSION_STATES,
  SEVEN_STAR_ROUTE_SPEC_IDS,
  SevenStarSessionReference,
  createFixtureAuthority
};
