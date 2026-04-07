import type { BaleenPayConfig } from '@baleenpay/sdk'

export const DEMO_CONFIG: BaleenPayConfig = {
  network: 'testnet',
  packageId: '0x9b13868fe76b775524ae10ca2e1fb19b7cc306b9d0a7879f21487752cb845ec2',
  merchantId: '0x9ec4bd37033ccfa03da3a74a1c0d251b840610d602417ed17cc7f98cc9be221b',
  registryId: '0xff0c94c12da1bc55072dcfcd18ff61bf51b5f64ddfd287aa6659197418fcf586',
  routerConfigId: '0x931b0a2c6738a448e79ccbc6c06573a8860a8e1e97979b2f2f49983461749839',
  vaultId: '0x6c7f42f261ba273c360d88c7518b8d70968ff915d25e62466c60923543203dad',
  yieldVaultId: '0xe90a8e473936b8d920afb5c5a793181a0fc8d7a62a9021f4d270205e69b23775',
  stablecoinVaultId: '0x7c295154e2aff2de0a2381ee98dfb26be0cb184dcc30c6956a1b22e2f36ee1a5',
}

/** MerchantCap object ID — needed for dashboard admin actions */
export const MERCHANT_CAP_ID = '0x7ba95f5f4932423df5c6fb6a6d65d3298aa2f874eb5741348ba4bb35b9bdb83f'

/** SuiScan URL for tx digest links */
export const SUISCAN_URL = 'https://suiscan.xyz/testnet/tx'
