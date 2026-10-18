import { test } from "node:test";
import assert from "node:assert/strict";
import {
  computeHashlock,
  verifyPreimage,
  computeSwapId,
  verifyTimelockSafety,
  SwapState
} from "../dist/index.js";

test("1. Hashlock derivation and preimage verification", () => {
  const secret = "atomic_secret_777";
  const hashlock = computeHashlock(secret);

  assert.ok(hashlock.startsWith("0x"));
  assert.equal(hashlock.length, 66);
  assert.equal(verifyPreimage(secret, hashlock), true);
  assert.equal(verifyPreimage("wrong_secret", hashlock), false);
});

test("2. Deterministic Swap ID derivation", () => {
  const params = {
    sender: "0xAlice1111111111111111111111111111111111",
    recipient: "0xBob222222222222222222222222222222222222",
    token: "0xToken3333333333333333333333333333333333",
    amount: 5000000000000000000n,
    hashlock: computeHashlock("secret_key"),
    timelock: 1770000000,
    sourceChainId: 1,
    destChainId: 137,
    nonce: 42
  };

  const id1 = computeSwapId(params);
  const id2 = computeSwapId(params);
  assert.equal(id1, id2);
  assert.ok(id1.startsWith("0x"));

  // Mutating amount changes id
  const id3 = computeSwapId({ ...params, amount: 6000000000000000000n });
  assert.notEqual(id1, id3);
});

test("3. Cross-chain timelock safety invariant validation", () => {
  const now = Math.floor(Date.now() / 1000);
  const sourceTimelock = now + 7200; // 2 hours
  const destTimelock = now + 3600;   // 1 hour (delta = 3600s > 300s buffer)

  const safeReport = verifyTimelockSafety(sourceTimelock, destTimelock, 300);
  assert.equal(safeReport.isValid, true);
  assert.equal(safeReport.deltaSeconds, 3600);

  // Inverted or insufficient timelock must fail closed
  const unsafeReport = verifyTimelockSafety(destTimelock, sourceTimelock, 300);
  assert.equal(unsafeReport.isValid, false);
  assert.ok(unsafeReport.reason.includes("Source timelock must exceed"));

  // Delta smaller than buffer must fail closed
  const tightReport = verifyTimelockSafety(now + 3100, now + 3000, 300);
  assert.equal(tightReport.isValid, false);
});

test("4. SwapState enum values", () => {
  assert.equal(SwapState.INVALID, "INVALID");
  assert.equal(SwapState.FUNDED, "FUNDED");
  assert.equal(SwapState.CLAIMED, "CLAIMED");
  assert.equal(SwapState.REFUNDED, "REFUNDED");
});
