// packages/sdk/src/admin.ts

import { Transaction } from '@mysten/sui/transactions'
import type { FloatSyncConfig, TransactionResult, ObjectId, KeeperParams } from './types.js'
import { ValidationError } from './errors.js'
import {
  buildKeeperWithdraw,
  buildKeeperDeposit,
  buildKeeperHarvest,
} from './transactions/keeper.js'

/**
 * AdminClient for protocol-level admin operations.
 * Requires AdminCap object — these are NOT merchant operations.
 *
 * Admin ops:
 * - pause/unpause: Emergency halt of any merchant (AdminCap-gated)
 * - setRouterMode: Change yield routing strategy (AdminCap-gated)
 */
export class AdminClient {
  readonly config: FloatSyncConfig

  constructor(config: FloatSyncConfig) {
    if (!config.packageId) throw new ValidationError('MISSING_PACKAGE_ID', 'packageId is required')
    if (!config.network) throw new ValidationError('MISSING_NETWORK', 'network is required')
    this.config = config
  }

  /**
   * Emergency pause a merchant. Requires AdminCap.
   * Different from MerchantCap-gated self_pause — this is protocol-level.
   */
  pause(adminCapId: ObjectId, merchantId?: ObjectId): TransactionResult {
    const target = merchantId ?? this.config.merchantId
    if (!target) throw new ValidationError('MISSING_MERCHANT_ID', 'merchantId is required')

    const tx = new Transaction()
    tx.moveCall({
      target: `${this.config.packageId}::merchant::pause_merchant`,
      arguments: [
        tx.object(adminCapId),
        tx.object(target),
      ],
    })
    return { tx }
  }

  /**
   * Unpause a merchant. Requires AdminCap.
   */
  unpause(adminCapId: ObjectId, merchantId?: ObjectId): TransactionResult {
    const target = merchantId ?? this.config.merchantId
    if (!target) throw new ValidationError('MISSING_MERCHANT_ID', 'merchantId is required')

    const tx = new Transaction()
    tx.moveCall({
      target: `${this.config.packageId}::merchant::unpause_merchant`,
      arguments: [
        tx.object(adminCapId),
        tx.object(target),
      ],
    })
    return { tx }
  }

  /**
   * Change router yield mode. Requires AdminCap + RouterConfig.
   * Currently: mode 0 = fallback (direct to merchant). Future: mode 1 = StableLayer.
   */
  setRouterMode(adminCapId: ObjectId, routerConfigId: ObjectId, newMode: number): TransactionResult {
    if (!Number.isInteger(newMode) || newMode < 0) {
      throw new ValidationError('INVALID_MODE', 'Router mode must be a non-negative integer')
    }

    const tx = new Transaction()
    tx.moveCall({
      target: `${this.config.packageId}::router::set_mode`,
      arguments: [
        tx.object(adminCapId),
        tx.object(routerConfigId),
        tx.pure.u8(newMode),
      ],
    })
    return { tx }
  }

  /** Build a keeper_withdraw PTB. */
  keeperWithdraw(keeper: KeeperParams, amount: bigint, coinType: string): TransactionResult {
    return { tx: buildKeeperWithdraw(this.config, keeper, amount, coinType) }
  }

  /** Build composite keeper deposit PTB (withdraw → StableLayer mint). */
  keeperDeposit(keeper: KeeperParams, amount: bigint, coinType: string): TransactionResult {
    return { tx: buildKeeperDeposit(this.config, keeper, amount, coinType) }
  }

  /** Build composite keeper harvest PTB (StableLayer claim → deposit yield). */
  keeperHarvest(keeper: KeeperParams, merchantId: string, yieldCoinType: string): TransactionResult {
    return { tx: buildKeeperHarvest(this.config, keeper, merchantId, yieldCoinType) }
  }
}
