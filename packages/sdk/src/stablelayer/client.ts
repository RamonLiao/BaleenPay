import type { Transaction, TransactionArgument } from '@mysten/sui/transactions'

export interface StableLayerClientConfig {
  packageId: string
  registryId: string
  farmPackageId: string
  farmRegistryId: string
  stablecoinType: string
  usdcType: string
  usdbType: string
  mockFarmEntityType: string
}

export interface BuildMintOptions {
  tx: Transaction
  usdcCoin: TransactionArgument
}

export interface BuildClaimOptions {
  tx: Transaction
}

export interface BuildRedeemOptions {
  tx: Transaction
  stablecoinCoin: TransactionArgument
}

/**
 * Thin wrapper around StableLayer + Farm protocol for PTB composition.
 *
 * On-chain `stable_layer::mint` uses a hot-potato pattern:
 *   mint<Stablecoin, USDC, FarmEntity>(registry, usdcCoin) → (Coin<Stablecoin>, Loan)
 * The Loan must be consumed in the same PTB via `farm::receive`.
 *
 * Yield is claimed via `farm::claim` (NOT stable_layer::claim) and returns Coin<USDB>.
 */
export class StableLayerClient {
  readonly packageId: string
  readonly registryId: string
  readonly farmPackageId: string
  readonly farmRegistryId: string
  readonly stablecoinType: string
  readonly usdcType: string
  readonly usdbType: string
  readonly mockFarmEntityType: string

  constructor(config: StableLayerClientConfig) {
    this.packageId = config.packageId
    this.registryId = config.registryId
    this.farmPackageId = config.farmPackageId
    this.farmRegistryId = config.farmRegistryId
    this.stablecoinType = config.stablecoinType
    this.usdcType = config.usdcType
    this.usdbType = config.usdbType
    this.mockFarmEntityType = config.mockFarmEntityType
  }

  /**
   * Build mint PTB commands: stable_layer::mint → farm::receive.
   * Returns the minted Coin<Stablecoin> (caller decides what to do with it).
   */
  buildMintTx({ tx, usdcCoin }: BuildMintOptions): TransactionArgument {
    // mint<Stablecoin, USDC, MockFarmEntity>(registry, usdcCoin)
    // → (Coin<Stablecoin>, Loan<USDC, StableFactoryEntity<Stablecoin, USDC>, MockFarmEntity>)
    const mintResult = tx.moveCall({
      target: `${this.packageId}::stable_layer::mint`,
      typeArguments: [this.stablecoinType, this.usdcType, this.mockFarmEntityType],
      arguments: [
        tx.object(this.registryId),
        usdcCoin,
      ],
    })

    // Consume the hot-potato Loan via farm::receive
    // receive<Stablecoin, USDC>(farmRegistry, loan, clock)
    tx.moveCall({
      target: `${this.farmPackageId}::farm::receive`,
      typeArguments: [this.stablecoinType, this.usdcType],
      arguments: [
        tx.object(this.farmRegistryId),
        mintResult[1], // Loan
        tx.object('0x6'), // Clock
      ],
    })

    return mintResult[0] // Coin<Stablecoin>
  }

  /**
   * Build claim PTB command: farm::claim → returns Coin<USDB>.
   */
  buildClaimTx({ tx }: BuildClaimOptions): TransactionArgument {
    // claim<Stablecoin, USDC>(farmRegistry, stableRegistry, clock) → Coin<USDB>
    const usdbCoin = tx.moveCall({
      target: `${this.farmPackageId}::farm::claim`,
      typeArguments: [this.stablecoinType, this.usdcType],
      arguments: [
        tx.object(this.farmRegistryId),
        tx.object(this.registryId),
        tx.object('0x6'), // Clock
      ],
    })

    return usdbCoin
  }

  /**
   * Build redeem PTB commands: request_burn → farm::pay → fulfill_burn.
   * Returns the redeemed Coin<USDC>.
   */
  buildRedeemTx({ tx, stablecoinCoin }: BuildRedeemOptions): TransactionArgument {
    // Step 1: request_burn — burn Stablecoin, get Request hot-potato
    const request = tx.moveCall({
      target: `${this.packageId}::stable_layer::request_burn`,
      typeArguments: [this.stablecoinType, this.usdcType],
      arguments: [
        tx.object(this.registryId),
        stablecoinCoin,
      ],
    })

    // Step 2: farm::pay — Farm settles the debt via &mut Request
    tx.moveCall({
      target: `${this.farmPackageId}::farm::pay`,
      typeArguments: [this.stablecoinType, this.usdcType],
      arguments: [
        tx.object(this.farmRegistryId),
        tx.object('0x6'), // Clock
        request,
      ],
    })

    // Step 3: fulfill_burn — consume Request, get Coin<USDC> back
    const usdcCoin = tx.moveCall({
      target: `${this.packageId}::stable_layer::fulfill_burn`,
      typeArguments: [this.stablecoinType, this.usdcType],
      arguments: [
        tx.object(this.registryId),
        request,
      ],
    })

    return usdcCoin
  }
}
