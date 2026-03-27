import type { Transaction, TransactionArgument } from '@mysten/sui/transactions'

export interface StableLayerClientConfig {
  packageId: string
  registryId: string
  busdCoinType: string
  mockFarmPackageId?: string
  mockFarmRegistryId?: string
}

export interface BuildMintOptions {
  tx: Transaction
  usdcCoin: TransactionArgument
  autoTransfer?: boolean
}

export interface BuildClaimOptions {
  tx: Transaction
  autoTransfer?: boolean
}

/**
 * Thin wrapper around StableLayer protocol for PTB composition.
 * Does NOT make network calls — only builds transaction commands.
 */
export class StableLayerClient {
  readonly packageId: string
  readonly registryId: string
  readonly busdCoinType: string

  constructor(config: StableLayerClientConfig) {
    this.packageId = config.packageId
    this.registryId = config.registryId
    this.busdCoinType = config.busdCoinType
  }

  buildMintTx({ tx, usdcCoin, autoTransfer = false }: BuildMintOptions): TransactionArgument {
    const busdCoin = tx.moveCall({
      target: `${this.packageId}::stable_layer::mint`,
      typeArguments: [this.busdCoinType],
      arguments: [
        tx.object(this.registryId),
        usdcCoin,
      ],
    })

    if (autoTransfer) {
      tx.transferObjects([busdCoin], tx.pure.address(''))
    }

    return busdCoin
  }

  buildClaimTx({ tx, autoTransfer = false }: BuildClaimOptions): TransactionArgument {
    const usdbCoin = tx.moveCall({
      target: `${this.packageId}::stable_layer::claim`,
      typeArguments: [this.busdCoinType],
      arguments: [
        tx.object(this.registryId),
      ],
    })

    if (autoTransfer) {
      tx.transferObjects([usdbCoin], tx.pure.address(''))
    }

    return usdbCoin
  }
}
