# QMOOSA Cross-Chain Protocol (`@qmoosa/crosschain-protocol`)

Cross-Chain Atomic Swap Specifications, Hashed Time-Locked Contracts (HTLCs), and Timelock Safety Invariants.

## Core Invariants

1. **SHA-256 Secret Commitments:** All swaps lock funds against a cryptographic hashlock `sha256(secret)`.
2. **Mutual Exclusion:** Once claimed, a swap cannot be refunded; once refunded, a swap cannot be claimed.
3. **Timelock Safety Ordering:** The initiator's source timelock must strictly exceed the counterparty's destination timelock by at least 300 seconds to prevent race conditions during claim revelation.
4. **Deterministic Swap Identification:** Swaps are uniquely keyed by `keccak256(sender, recipient, token, amount, hashlock, timelock, sourceChainId, destChainId, nonce)`.

## Test Execution

```bash
# TypeScript unit tests
npm test

# Solidity Foundry tests
cd contracts && forge test -vv
```
