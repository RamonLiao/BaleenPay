import type { BaleenPayConfig } from '@baleenpay/sdk'

export const DEMO_CONFIG: BaleenPayConfig = {
  network: 'testnet',
  packageId: '0xe0eb53cce531ab129e499b06ed1a858bb64da08e6c53c18ab4c85ef01306b32a',
  merchantId: '0x4db0ff62d5402f3970028995312a4fd0c243cef9ce6d1e4ace77667155c17c24',
  registryId: '0x2b0584da2655e87873a72977a36741d64e59d68e550016ebb38be5fe243a321f',
  routerConfigId: '0x0bae66f0910b0d22b30d6be5bc2c3f0272ef9c917b34b041608c0fbd31264e8e',
}

/** MerchantCap object ID — needed for dashboard admin actions */
export const MERCHANT_CAP_ID = '0x93e30ffb648ddbee6a93518f82eb332a39c1b3457dc7c02544fb105e02d520e2'

/** SuiScan URL for tx digest links */
export const SUISCAN_URL = 'https://suiscan.xyz/testnet/tx'
