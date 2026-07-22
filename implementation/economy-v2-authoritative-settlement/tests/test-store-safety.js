'use strict';

const assert = require('assert');
const path = require('path');

const {
  OfflineTransactionStore,
  emptyOwnerState,
} = require(path.resolve(__dirname, '..', 'reference', 'transaction-store-model.js'));

let assertions = 0;

function equal(actual, expected, message) {
  assertions += 1;
  assert.strictEqual(actual, expected, message);
}

function throws(callback, expected, message) {
  assertions += 1;
  assert.throws(callback, expected, message);
}

function makeStore() {
  const store = new OfflineTransactionStore();
  store.transact((state) => {
    state.owners['owner-safety-01'] = emptyOwnerState();
    state.owners['owner-safety-01'].balances.CUR_GOLD = 10;
  });
  return store;
}

function gold(store) {
  return store.exportState().owners['owner-safety-01'].balances.CUR_GOLD;
}

async function run() {
  // A transaction callback may return or retain its working state, but it may
  // never mutate the committed store through that escaped reference.
  const aliasStore = makeStore();
  let escapedCandidate;
  const returnedCandidate = aliasStore.transact((state) => {
    escapedCandidate = state;
    state.owners['owner-safety-01'].balances.CUR_GOLD = 11;
    return state;
  });
  equal(returnedCandidate, escapedCandidate, 'the fixture retains the callback candidate');
  equal(gold(aliasStore), 11, 'the synchronous candidate change commits');
  escapedCandidate.owners['owner-safety-01'].balances.CUR_GOLD = 777;
  equal(gold(aliasStore), 11, 'a retained callback candidate cannot mutate committed state');

  // An async callback schedules its continuation after transact has returned.
  // It must be rejected, and its retained candidate must remain detached.
  const asyncStore = makeStore();
  let releaseAsyncContinuation;
  let asyncCandidate;
  const asyncGate = new Promise((resolve) => { releaseAsyncContinuation = resolve; });
  throws(() => asyncStore.transact(async (state) => {
    asyncCandidate = state;
    await asyncGate;
    state.owners['owner-safety-01'].balances.CUR_GOLD = 888;
  }), /asynchronous transaction callback is forbidden/, 'a Promise-returning transaction callback is rejected');
  equal(gold(asyncStore), 10, 'a rejected async transaction does not commit its synchronous prefix');
  releaseAsyncContinuation();
  await Promise.resolve();
  await Promise.resolve();
  equal(asyncCandidate.owners['owner-safety-01'].balances.CUR_GOLD, 888, 'the async continuation did run against its private candidate');
  equal(gold(asyncStore), 10, 'the async continuation cannot mutate committed state');

  const thenableStore = makeStore();
  throws(() => thenableStore.transact((state) => {
    state.owners['owner-safety-01'].balances.CUR_GOLD = 666;
    return { then() {} };
  }), /asynchronous transaction callback is forbidden/, 'a non-Promise thenable transaction callback is rejected');
  equal(gold(thenableStore), 10, 'a rejected thenable transaction cannot commit its candidate');

  // Nested transactions are forbidden and an outer abort leaves no inner or
  // outer mutation behind. A later independent transaction proves finally
  // cleared the guard.
  const reentrantStore = makeStore();
  const beforeReentrant = reentrantStore.digest();
  throws(() => reentrantStore.transact((state) => {
    state.owners['owner-safety-01'].balances.CUR_GOLD = 100;
    reentrantStore.transact((inner) => {
      inner.owners['owner-safety-01'].balances.CUR_GOLD = 999;
    });
  }), /reentrant transaction is forbidden/, 'a nested transaction is rejected');
  equal(reentrantStore.digest(), beforeReentrant, 'a reentrant outer failure preserves the prior state');
  reentrantStore.transact((state) => {
    state.owners['owner-safety-01'].balances.CUR_GOLD = 12;
  });
  equal(gold(reentrantStore), 12, 'the re-entry guard is cleared after failure');

  process.stdout.write(`PASS: ${assertions} economy-v2 transaction-store safety assertions\n`);
}

run().catch((error) => {
  process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
  process.exitCode = 1;
});
