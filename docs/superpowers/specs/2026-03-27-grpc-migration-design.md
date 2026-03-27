# FloatSync SDK: JSON-RPC → gRPC Migration

**Date**: 2026-03-27
**Status**: Approved
**Deadline**: April 2026 (JSON-RPC removal by Mysten)

## Motivation

`@mysten/sui` v2 deprecates JSON-RPC (`SuiJsonRpcClient`) in favor of gRPC (`SuiGrpcClient`). JSON-RPC endpoints will be removed in April 2026. The SDK currently uses the `@mysten/sui/jsonRpc` compat layer — this migration replaces it with gRPC before the deadline.

## Decisions

| Item | Decision | Rationale |
|---|---|---|
| Transport | gRPC primary, GraphQL for events | gRPC is Mysten's official direction; gRPC has no `queryEvents` equivalent |
| JSON-RPC fallback | None — full removal | 0.x stage, one consumer (demo app), JSON-RPC dies in ~1 month |
| Public API | `private grpcClient` + `rawClient` getter | Production-safe: hides transport detail, provides escape hatch without scary naming |
| Config | `network` required, `grpcUrl?` + `graphqlUrl?` optional | Supports self-hosted nodes while defaulting to Mysten public endpoints |
| Environment | Isomorphic (browser + Node.js) | `SuiGrpcClient` uses gRPC-Web transport, works in both |

## Architecture

```
FloatSync (client.ts)
├── SuiGrpcClient (@mysten/sui/grpc)
│   ├── getObject()      — merchant/subscription queries
│   ├── listCoins()      — coin preparation for PTBs
│   └── getMoveFunction() — version detection (v1 vs v2)
├── SuiGraphQLClient (@mysten/sui/graphql)
│   └── query()          — event queries (history + stream polling)
├── EventStream (events/stream.ts)
│   └── GraphQL polling with cursor tracking
└── rawClient getter     — escape hatch for advanced users
```

## API Changes

### FloatSyncConfig

```ts
// Before
interface FloatSyncConfig {
  packageId: string
  merchantId: string
  network: 'mainnet' | 'testnet' | 'devnet'
  rpcUrl?: string          // ← removed
}

// After
interface FloatSyncConfig {
  packageId: string
  merchantId: string
  network: 'mainnet' | 'testnet' | 'devnet'
  grpcUrl?: string         // ← optional gRPC endpoint override
  graphqlUrl?: string      // ← optional GraphQL endpoint override
}
```

### FloatSync class

```ts
class FloatSync {
  // Before
  readonly suiClient: SuiJsonRpcClient  // ← public, JSON-RPC

  // After
  private readonly grpcClient: SuiGrpcClient      // ← private
  private readonly graphqlClient: SuiGraphQLClient // ← private
  get rawClient(): SuiGrpcClient { ... }           // ← escape hatch
}
```

## Migration Map

### 1. `client.ts` — Constructor + Query Methods

**Constructor**:
```ts
// Before
import { SuiJsonRpcClient, getJsonRpcFullnodeUrl } from '@mysten/sui/jsonRpc'
this.suiClient = new SuiJsonRpcClient({
  url: config.rpcUrl ?? DEFAULT_RPC_URLS[config.network] ?? getJsonRpcFullnodeUrl(config.network),
  network: config.network,
})

// After
import { SuiGrpcClient } from '@mysten/sui/grpc'
import { SuiGraphQLClient } from '@mysten/sui/graphql'
this.grpcClient = new SuiGrpcClient({
  baseUrl: config.grpcUrl ?? DEFAULT_GRPC_URLS[config.network],
  network: config.network,
})
this.graphqlClient = new SuiGraphQLClient({
  url: config.graphqlUrl ?? DEFAULT_GRAPHQL_URLS[config.network],
  network: config.network,
})
```

**getMerchant / getSubscription**:
```ts
// Before
const obj = await this.suiClient.getObject({
  id,
  options: { showContent: true },
})
const fields = obj.data.content.fields as Record<string, unknown>

// After
const { object } = await this.grpcClient.getObject({
  objectId: id,
  include: { json: true },
})
const fields = object.json as Record<string, unknown>
```

**getPaymentHistory** — moves to GraphQL:
```ts
// Before
const result = await this.suiClient.queryEvents({
  query: { MoveEventType: eventType },
  cursor, limit, order,
})

// After
const result = await this.graphqlClient.query({
  query: QUERY_EVENTS,
  variables: { eventType, cursor, limit, order },
})
```

### 2. `version.ts` — Version Detection

```ts
// Before
import type { SuiJsonRpcClient } from '@mysten/sui/jsonRpc'
const mod = await client.getNormalizedMoveModule({ package: packageId, module: 'payment' })
const hasV2 = 'pay_once_v2' in mod.exposedFunctions

// After
import type { SuiGrpcClient } from '@mysten/sui/grpc'
try {
  await client.getMoveFunction({
    packageId,
    moduleName: 'payment',
    name: 'pay_once_v2',
  })
  return { hasV2: true }
} catch {
  return { hasV2: false }
}
```

### 3. `events/stream.ts` — Event Polling

```ts
// Before
import type { SuiJsonRpcClient } from '@mysten/sui/jsonRpc'
async start(client: SuiJsonRpcClient, intervalMs): Promise<void> {
  // polling via client.queryEvents()
}

// After
import type { SuiGraphQLClient } from '@mysten/sui/graphql'
async start(client: SuiGraphQLClient, intervalMs): Promise<void> {
  // polling via client.query({ query: QUERY_EVENTS, variables })
}
```

GraphQL query for events:
```graphql
query QueryEvents(
  $eventType: String!
  $after: String
  $first: Int
) {
  events(
    filter: { type: $eventType }
    after: $after
    first: $first
  ) {
    nodes {
      contents { json }
      sender { address }
      type { repr }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
```

### 4. `coins/helper.ts` — Coin Preparation

```ts
// Before
import type { SuiJsonRpcClient } from '@mysten/sui/jsonRpc'
const { data: coins } = await client.getCoins({ owner, coinType })

// After
import type { SuiGrpcClient } from '@mysten/sui/grpc'
const { objects: coins } = await client.listCoins({ owner, coinType })
// Coin shape: { objectId, balance, ... } — same fields, different wrapper
```

### 5. `coins/validator.ts`, `transactions/*.ts` — Type Updates

All files that import `SuiJsonRpcClient` type → change to `SuiGrpcClient`:
- `coins/validator.ts`
- `transactions/pay.ts`
- `transactions/subscribe.ts`
- `transactions/subscription.ts`

### 6. `constants.ts` — URL Constants

```ts
// Before
export const DEFAULT_RPC_URLS: Record<string, string> = {
  mainnet: 'https://fullnode.mainnet.sui.io:443',
  testnet: 'https://fullnode.testnet.sui.io:443',
  devnet: 'https://fullnode.devnet.sui.io:443',
}

// After
export const DEFAULT_GRPC_URLS: Record<string, string> = {
  mainnet: 'https://sui-mainnet.mystenlabs.com',
  testnet: 'https://sui-testnet.mystenlabs.com',
  devnet: 'https://sui-devnet.mystenlabs.com',
}

export const DEFAULT_GRAPHQL_URLS: Record<string, string> = {
  mainnet: 'https://sui-mainnet.mystenlabs.com/graphql',
  testnet: 'https://sui-testnet.mystenlabs.com/graphql',
  devnet: 'https://sui-devnet.mystenlabs.com/graphql',
}
```

### 7. `types.ts` — Config Type

Update `FloatSyncConfig` interface: remove `rpcUrl`, add `grpcUrl` + `graphqlUrl`.

### 8. Tests — Mock Updates

All test files mock `@mysten/sui/jsonRpc` → split into:
- `vi.mock('@mysten/sui/grpc')` — for `SuiGrpcClient`
- `vi.mock('@mysten/sui/graphql')` — for `SuiGraphQLClient`

Affected files:
- `test/client.test.ts`
- `test/integration.test.ts`
- `test/monkey.test.ts`

### 9. React Package

`packages/react/src/provider.tsx` — no direct changes needed. The `FloatSync` constructor internally creates the clients. Provider just passes `FloatSyncConfig` through.

Config type change (`rpcUrl` → `grpcUrl`/`graphqlUrl`) propagates through `FloatSyncProviderProps`.

### 10. Demo App

Update config in demo app provider setup:
- Remove `rpcUrl` if used
- No other changes needed (demo uses SDK hooks, not raw client)

## New Dependencies

None. Both `@mysten/sui/grpc` and `@mysten/sui/graphql` are subpath exports of `@mysten/sui` which is already installed at `^2.8.0` (resolved: `2.11.0`).

## Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| GraphQL endpoint rate limits | Medium | Add configurable `graphqlUrl` for self-hosted; event polling already has 3s interval |
| gRPC-Web browser compat | Low | `SuiGrpcClient` uses `@protobuf-ts/grpcweb-transport`, proven in Mysten's own dApp Kit |
| `getObject` response shape change | Medium | `include: { json: true }` returns `Record<string, unknown>` via `object.json` instead of `obj.data.content.fields`. **Implementation must verify**: hit testnet with known merchantId via both gRPC and JSON-RPC, compare key mapping before finalizing deserializers |
| GraphQL event query field mapping | Medium | Need to verify GraphQL event `contents.json` matches JSON-RPC `parsedJson` structure — test with real testnet data |
| `getMoveFunction` error behavior | Low | gRPC throws on not-found vs JSON-RPC returns module with functions — version detection logic adapts with try/catch |

## Out of Scope

- gRPC streaming for real-time events (gRPC only has `subscribeCheckpoints`, too heavy for event filtering)
- BCS-first deserialization (keep JSON for now, BCS migration is a future optimization)
- Multi-client failover / retry logic
