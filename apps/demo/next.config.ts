import type { NextConfig } from 'next'

const config: NextConfig = {
  transpilePackages: ['@floatsync/sdk', '@floatsync/react'],
}

export default config
