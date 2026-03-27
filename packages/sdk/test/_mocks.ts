// packages/sdk/test/_mocks.ts
// Shared mock helpers for gRPC + GraphQL migration

import { vi } from 'vitest'

export const mockGetObject = vi.fn()
export const mockListCoins = vi.fn()
export const mockGetMoveFunction = vi.fn()
export const mockGetCoinMetadata = vi.fn()
export const mockGraphQLQuery = vi.fn()

export function setupGrpcMock() {
  vi.mock('@mysten/sui/grpc', () => {
    class MockSuiGrpcClient {
      baseUrl: string
      network: string
      constructor(opts: { baseUrl: string; network: string }) {
        this.baseUrl = opts.baseUrl
        this.network = opts.network
      }
      getObject = mockGetObject
      listCoins = mockListCoins
      getMoveFunction = mockGetMoveFunction
      getCoinMetadata = mockGetCoinMetadata
    }
    return { SuiGrpcClient: MockSuiGrpcClient }
  })
}

export function setupGraphQLMock() {
  vi.mock('@mysten/sui/graphql', () => {
    class MockSuiGraphQLClient {
      url: string
      network: string
      constructor(opts: { url: string; network: string }) {
        this.url = opts.url
        this.network = opts.network
      }
      query = mockGraphQLQuery
    }
    return { SuiGraphQLClient: MockSuiGraphQLClient }
  })
}

/** Setup v2 version detection mock (getMoveFunction succeeds) */
export function mockV2Available() {
  mockGetMoveFunction.mockResolvedValue({
    function: { packageId: '0x', moduleName: 'payment', name: 'pay_once_v2' },
  })
}

/** Setup v1-only version detection mock (getMoveFunction throws) */
export function mockV1Only() {
  mockGetMoveFunction.mockRejectedValue(new Error('Function not found'))
}

/** Setup default coin mock for SUI-based tests */
export function mockDefaultCoins() {
  mockListCoins.mockResolvedValue({
    objects: [{ objectId: '0xcoin1', balance: '999999999999', version: '1', digest: 'abc' }],
    hasNextPage: false,
    cursor: null,
  })
}

/** Helper to build a GraphQL events response */
export function makeGraphQLEventsResponse(
  nodes: Array<{
    type: string
    json: Record<string, unknown>
    sender?: string
  }>,
  pageInfo?: { hasNextPage: boolean; endCursor: string | null },
) {
  return {
    data: {
      events: {
        nodes: nodes.map((n) => ({
          type: { repr: n.type },
          contents: { json: n.json },
          sender: n.sender ? { address: n.sender } : null,
        })),
        pageInfo: pageInfo ?? { hasNextPage: false, endCursor: null },
      },
    },
  }
}
