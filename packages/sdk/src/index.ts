// packages/sdk/src/index.ts

export type {
  FloatSyncConfig,
  PayParams,
  SubscribeParams,
  FundParams,
  RegisterParams,
  QueryParams,
  TransactionResult,
  ExecutedResult,
  FloatSyncEventName,
  FloatSyncEventData,
  EventCallback,
  Unsubscribe,
  MerchantInfo,
  SubscriptionInfo,
  ObjectId,
} from './types.js'

export { ABORT_CODE_MAP, CLOCK_OBJECT_ID, MAX_ORDER_ID_LENGTH, ORDER_ID_REGEX, DEFAULT_GRPC_URLS, DEFAULT_GRAPHQL_URLS } from './constants.js'

// Coins
export { resolveCoin, coinTypeArg } from './coins/index.js'
export type { CoinConfig } from './coins/index.js'
export { prepareCoin } from './coins/index.js'
export { validateCoinType } from './coins/index.js'

// Errors
export { FloatSyncError, PaymentError, MerchantError, ValidationError, NetworkError, parseAbortCode } from './errors.js'

// Events
export { EventStream, EVENT_TYPE_MAP, normalizeEvent } from './events/index.js'

// Version
export { detectVersion } from './version.js'
export type { VersionInfo } from './version.js'

// Idempotency
export { IdempotencyGuard } from './idempotency.js'
export type { IdempotencyStatus } from './idempotency.js'

// Client
export { FloatSync } from './client.js'
export type { FloatSyncClientOptions } from './client.js'

// Admin
export { AdminClient } from './admin.js'

// Transactions
export {
  buildPayOnce,
  buildPayOnceV2,
  buildSubscribe,
  buildSubscribeV2,
  buildRegisterMerchant,
  buildSelfPause,
  buildSelfUnpause,
  buildClaimYield,
  buildProcessSubscription,
  buildCancelSubscription,
  buildFundSubscription,
} from './transactions/index.js'
