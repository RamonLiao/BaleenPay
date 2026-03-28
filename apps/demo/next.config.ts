import type { NextConfig } from 'next'
import { resolve } from 'path'

const config: NextConfig = {
  transpilePackages: ['@floatsync/sdk', '@floatsync/react'],
  webpack: (config) => {
    // Force single instance of dapp-kit-react so Provider context matches hooks
    // (pnpm resolves different copies for React 18 vs 19 peer deps)
    config.resolve.alias = {
      ...config.resolve.alias,
      '@mysten/dapp-kit-react$': resolve(
        __dirname,
        'node_modules/@mysten/dapp-kit-react',
      ),
      '@mysten/dapp-kit-core$': resolve(
        __dirname,
        'node_modules/@mysten/dapp-kit-core',
      ),
      '@tanstack/react-query$': resolve(
        __dirname,
        'node_modules/@tanstack/react-query',
      ),
    }
    return config
  },
}

export default config
