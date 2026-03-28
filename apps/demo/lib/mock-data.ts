/** Mock data for investor demo — no wallet or chain needed */

export const MOCK_ACCOUNT = {
  address: '0x1509a3b2f8c7e4d6a0b9e3f1c2d5a8b4e7f0c9d6a3b1e4f7c0d8a5b2e9f6c4',
}

export const MOCK_MERCHANT = {
  brandName: 'FloatSync Demo Store',
  totalReceived: 2_847_500_000n, // 2,847.5 USDC
  idlePrincipal: 1_200_000_000n,
  accruedYield: 34_250_000n, // 34.25 USDC
  activeSubscriptions: 12,
  pausedByAdmin: false,
  pausedBySelf: false,
}

export const MOCK_YIELD_INFO = {
  accruedYield: 34_250_000n,
  vaultBalance: 1_200_000_000n,
  estimatedApy: 4.82,
}

export const MOCK_YIELD_DATA_POINTS = Array.from({ length: 30 }, (_, i) => ({
  timestamp: Date.now() - (30 - i) * 24 * 60 * 60 * 1000,
  cumulativeYield: Number(800_000_000n + BigInt(Math.floor(i * 13_500_000))) / 1e6,
  apy: 4.5 + Math.sin(i / 5) * 0.8 + i * 0.01,
}))

export const MOCK_PAYMENT_EVENTS = [
  { type: 'payment.received' as const, digest: '0xabc1...def1', payer: '0x7a3b...9c1d', amount: 49_000_000n, coin: 'USDC', orderId: 'order_001', timestamp: Date.now() - 3600_000 },
  { type: 'payment.received' as const, digest: '0xabc2...def2', payer: '0x8b4c...0d2e', amount: 149_000_000n, coin: 'USDC', orderId: 'order_002', timestamp: Date.now() - 7200_000 },
  { type: 'payment.received' as const, digest: '0xabc3...def3', payer: '0x9c5d...1e3f', amount: 19_000_000n, coin: 'USDC', orderId: 'order_003', timestamp: Date.now() - 10800_000 },
  { type: 'subscription.processed' as const, digest: '0xabc4...def4', payer: '0x0d6e...2f40', amount: 468_000_000n, coin: 'USDC', orderId: 'sub_004', timestamp: Date.now() - 86400_000 },
  { type: 'payment.received' as const, digest: '0xabc5...def5', payer: '0x1e7f...3a51', amount: 49_000_000n, coin: 'SUI', orderId: 'order_005', timestamp: Date.now() - 172800_000 },
]

export const MOCK_CLAIM_EVENTS = [
  { txDigest: '0xc1a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0', amount: 12_500_000n, timestamp: Date.now() - 86400_000 * 3 },
  { txDigest: '0xd2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2', amount: 8_750_000n, timestamp: Date.now() - 86400_000 * 7 },
]

const FAKE_DIGEST = '0xe4f8a2c1b3d5e7f9a0b2c4d6e8f0a1b3c5d7e9f1a3b5c7d9e1f3a5b7c9d1e3'

/** Simulate a transaction flow: building → signing → confirming → success */
export async function simulateTx(): Promise<string> {
  await sleep(400)  // building
  await sleep(600)  // signing
  await sleep(500)  // confirming
  return FAKE_DIGEST
}

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms))
}
