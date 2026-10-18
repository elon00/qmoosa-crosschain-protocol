export enum SwapState {
  INVALID = "INVALID",
  FUNDED = "FUNDED",
  CLAIMED = "CLAIMED",
  REFUNDED = "REFUNDED"
}

export interface SwapParams {
  sender: string;
  recipient: string;
  token: string;
  amount: bigint;
  hashlock: string;
  timelock: number;
  sourceChainId: number;
  destChainId: number;
  nonce: number;
}

export interface SwapRecord extends SwapParams {
  swapId: string;
  state: SwapState;
  createdAt: number;
  claimedAt?: number;
  refundedAt?: number;
  secret?: string;
}

export interface TimelockSafetyReport {
  isValid: boolean;
  sourceTimelock: number;
  destTimelock: number;
  deltaSeconds: number;
  safetyMarginSeconds: number;
  reason?: string;
}
