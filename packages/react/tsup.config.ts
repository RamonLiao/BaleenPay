import { defineConfig } from 'tsup'

export default defineConfig({
  entry: ['src/index.ts'],
  format: ['esm', 'cjs'],
  dts: true,
  clean: true,
  sourcemap: true,
  external: [
    'react',
    'react-dom',
    '@tanstack/react-query',
    '@mysten/dapp-kit-react',
    '@mysten/dapp-kit-core',
    '@mysten/sui',
    '@floatsync/sdk',
  ],
})
