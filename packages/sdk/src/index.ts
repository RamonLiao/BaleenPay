// packages/sdk/src/index.ts

export type {
  BaleenPayConfig,
  PayParams,
  SubscribeParams,
  FundParams,
  RegisterParams,
  QueryParams,
  TransactionResult,
  ExecutedResult,
  BaleenPayEventName,
  BaleenPayEventData,
  EventCallback,
  Unsubscribe,
  MerchantInfo,
  SubscriptionInfo,
  ObjectId,
  YieldInfo,
  KeeperParams,
  StableLayerConfig,
} from './types.js'

export { ABORT_CODE_MAP, CLOCK_OBJECT_ID, MAX_ORDER_ID_LENGTH, ORDER_ID_REGEX, DEFAULT_GRPC_URLS, DEFAULT_GRAPHQL_URLS } from './constants.js'

// Coins
export { resolveCoin, coinTypeArg } from './coins/index.js'
export type { CoinConfig } from './coins/index.js'
export { prepareCoin } from './coins/index.js'
export { validateCoinType } from './coins/index.js'

// Errors
export { BaleenPayError, PaymentError, MerchantError, ValidationError, NetworkError, parseAbortCode } from './errors.js'

// Events
export { EventStream, EVENT_TYPE_MAP, normalizeEvent } from './events/index.js'

// Version
export { detectVersion } from './version.js'
export type { VersionInfo } from './version.js'

// Idempotency
export { IdempotencyGuard } from './idempotency.js'
export type { IdempotencyStatus } from './idempotency.js'

// Client
export { BaleenPay } from './client.js'
export type { BaleenPayClientOptions } from './client.js'

// Admin
export { AdminClient } from './admin.js'

// StableLayer
export { StableLayerClient, STABLELAYER_CONFIG } from './stablelayer/index.js'
export type { StableLayerNetwork } from './stablelayer/index.js'
export type { StableLayerClientConfig, BuildMintOptions, BuildClaimOptions } from './stablelayer/client.js'

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
  buildPayOnceRouted,
  buildKeeperWithdraw,
  buildKeeperDepositYield,
  buildKeeperDeposit,
  buildKeeperHarvest,
} from './transactions/index.js'
