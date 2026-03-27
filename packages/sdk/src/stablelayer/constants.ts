export const STABLELAYER_CONFIG = {
  testnet: {
    packageId: '0x9c248c80c3a757167780f17e0c00a4d293280be7276f1b81a153f6e47d2567c9',
    registryId: '0xfa0fd96e0fbc07dc6bdc23cc1ac5b4c0056f4b469b9db0a70b6ea01c14a4c7b5',
    mockFarmPackageId: '0x3a55ec8fabe5f3e982908ed3a7c3065f26e83ab226eb8d3450177dbaac25878b',
    mockFarmRegistryId: '0xc3e8d2e33e36f6a4b5c199fe2dde3ba6dc29e7af8dd045c86e62d7c21f374d02',
    busdCoinType: '0xe25a20601a1ecc2fa5ac9e5d37b52f9ce70a1ebe787856184ffb7dbe31dba4c1::stable_layer::Stablecoin',
  },
  mainnet: {
    packageId: '', // TBD
    registryId: '', // TBD
    mockFarmPackageId: '',
    mockFarmRegistryId: '',
    busdCoinType: '', // TBD
  },
} as const

export type StableLayerNetwork = keyof typeof STABLELAYER_CONFIG
