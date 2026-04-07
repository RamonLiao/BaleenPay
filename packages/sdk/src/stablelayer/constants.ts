export const STABLELAYER_CONFIG = {
  testnet: {
    packageId: '0x9c248c80c3a757167780f17e0c00a4d293280be7276f1b81a153f6e47d2567c9',
    registryId: '0xfa0fd96e0fbc07dc6bdc23cc1ac5b4c0056f4b469b9db0a70b6ea01c14a4c7b5',
    farmPackageId: '0x3a55ec8fabe5f3e982908ed3a7c3065f26e83ab226eb8d3450177dbaac25878b',
    farmRegistryId: '0xc3e8d2e33e36f6a4b5c199fe2dde3ba6dc29e7af8dd045c86e62d7c21f374d02',
    stablecoinType: '0xe25a20601a1ecc2fa5ac9e5d37b52f9ce70a1ebe787856184ffb7dbe31dba4c1::stable_layer::Stablecoin',
    usdcType: '0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC',
    usdbType: '0x673d4118c17de717b0b90c326f8f52f87b5fff8678f513edd2ae575a55175954::usdb::USDB',
    mockFarmEntityType: '0x673d4118c17de717b0b90c326f8f52f87b5fff8678f513edd2ae575a55175954::farm::MockFarmEntity',
  },
  mainnet: {
    packageId: '', // TBD
    registryId: '', // TBD
    farmPackageId: '', // TBD
    farmRegistryId: '', // TBD
    stablecoinType: '', // TBD
    usdcType: '', // TBD
    usdbType: '', // TBD
    mockFarmEntityType: '', // TBD — mainnet may use a real entity type
  },
} as const

export type StableLayerNetwork = keyof typeof STABLELAYER_CONFIG
