import crypto from "node:crypto";
import { SwapParams, TimelockSafetyReport } from "./types.js";

/**
 * Computes SHA-256 hashlock from a secret string or buffer.
 */
export function computeHashlock(secret: string | Buffer | Uint8Array): string {
  const buf = typeof secret === "string" ? Buffer.from(secret, "utf8") : Buffer.from(secret);
  return "0x" + crypto.createHash("sha256").update(buf).digest("hex");
}

/**
 * Verifies if secret preimage matches the expected SHA-256 hashlock.
 */
export function verifyPreimage(secret: string | Buffer | Uint8Array, expectedHashlock: string): boolean {
  const computed = computeHashlock(secret);
  const normExpected = expectedHashlock.startsWith("0x") ? expectedHashlock.toLowerCase() : "0x" + expectedHashlock.toLowerCase();
  return computed.toLowerCase() === normExpected;
}

/**
 * Derives unique deterministic Swap ID.
 */
export function computeSwapId(params: SwapParams): string {
  const normHashlock = params.hashlock.startsWith("0x") ? params.hashlock.slice(2) : params.hashlock;
  const payload = [
    params.sender.toLowerCase(),
    params.recipient.toLowerCase(),
    params.token.toLowerCase(),
    params.amount.toString(10),
    normHashlock.toLowerCase(),
    params.timelock.toString(10),
    params.sourceChainId.toString(10),
    params.destChainId.toString(10),
    params.nonce.toString(10)
  ].join(":");

  return "0x" + crypto.createHash("sha256").update(Buffer.from(payload, "utf8")).digest("hex");
}

/**
 * Verifies cross-chain timelock safety invariant:
 * In a two-chain atomic swap, the initiator's source chain timelock MUST be
 * strictly greater than the responder's destination chain timelock by at least
 * the safety margin buffer to prevent double-spend or front-running claim races.
 */
export function verifyTimelockSafety(
  sourceTimelock: number,
  destTimelock: number,
  requiredBufferSeconds: number = 300
): TimelockSafetyReport {
  const delta = sourceTimelock - destTimelock;
  if (delta < requiredBufferSeconds) {
    return {
      isValid: false,
      sourceTimelock,
      destTimelock,
      deltaSeconds: delta,
      safetyMarginSeconds: requiredBufferSeconds,
      reason: `Source timelock must exceed destination timelock by at least ${requiredBufferSeconds}s (actual delta: ${delta}s)`
    };
  }

  return {
    isValid: true,
    sourceTimelock,
    destTimelock,
    deltaSeconds: delta,
    safetyMarginSeconds: requiredBufferSeconds
  };
}
