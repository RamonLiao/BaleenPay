// packages/sdk/src/constants.ts

export const CLOCK_OBJECT_ID = '0x6'

export const DEFAULT_RPC_URLS: Record<string, string> = {
  mainnet: 'https://fullnode.mainnet.sui.io:443',
  testnet: 'https://fullnode.testnet.sui.io:443',
  devnet: 'https://fullnode.devnet.sui.io:443',
}

export const MAX_ORDER_ID_LENGTH = 64
export const ORDER_ID_REGEX = /^[\x21-\x7e]{1,64}$/

/** Abort code → SDK error code mapping */
export const ABORT_CODE_MAP: Record<number, { code: string; message: string }> = {
  0: { code: 'NOT_MERCHANT_OWNER', message: "MerchantCap doesn't match this account" },
  2: { code: 'MERCHANT_PAUSED', message: 'Merchant is paused' },
  3: { code: 'NOT_PAYER', message: 'Only the original payer can perform this action' },
  6: { code: 'ALREADY_REGISTERED', message: 'This address already has a merchant account' },
  7: { code: 'NO_ACTIVE_SUBSCRIPTIONS', message: 'No active subscriptions to decrement' },
  8: { code: 'INSUFFICIENT_PRINCIPAL', message: 'Insufficient idle principal for yield credit' },
  10: { code: 'ZERO_AMOUNT', message: 'Payment amount must be greater than zero' },
  11: { code: 'NOT_DUE', message: 'Subscription payment is not yet due' },
  12: { code: 'ZERO_YIELD', message: 'No yield available to claim' },
  13: { code: 'INSUFFICIENT_PREPAID', message: 'Not enough prepaid periods' },
  14: { code: 'ZERO_PERIOD', message: 'Subscription period must be greater than zero' },
  15: { code: 'INSUFFICIENT_BALANCE', message: 'Subscription escrow balance too low' },
  16: { code: 'MERCHANT_MISMATCH', message: "Subscription doesn't belong to this merchant" },
  17: { code: 'ZERO_PREPAID_PERIODS', message: 'Must prepay at least one period' },
  18: { code: 'ORDER_ALREADY_PAID', message: 'This order has already been paid' },
  19: { code: 'INVALID_ORDER_ID', message: 'Order ID must be 1-64 ASCII printable characters' },
  20: { code: 'INVALID_MODE', message: 'Invalid router mode' },
  21: { code: 'SAME_MODE', message: 'Router is already in this mode' },
  22: { code: 'EXCEEDS_MAX_PREPAID_PERIODS', message: 'Prepaid periods exceeds maximum (1000)' },
  23: { code: 'OVERFLOW', message: 'Amount × periods would overflow' },
}
