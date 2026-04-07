import { describe, it, expect, vi, beforeEach } from 'vitest'
import {
  mockGetObject,
  mockListCoins,
  mockGetMoveFunction,
  mockGraphQLQuery,
  setupGrpcMock,
  setupGraphQLMock,
  mockV2Available,
  makeGraphQLEventsResponse,
} from './_mocks.js'
import { BaleenPay } from '../src/client.js'
import { AdminClient } from '../src/admin.js'
import { ValidationError } from '../src/errors.js'

// Hoist mocks before any imports that use them
setupGrpcMock()
setupGraphQLMock()

const baseConfig = {
  network: 'testnet' as const,
  packageId: '0xpkg123',
  merchantId: '0xmerchant456',
  registryId: '0xregistry789',
  routerConfigId: '0xrouter',
}

beforeEach(() => {
  vi.clearAllMocks()
})

describe('BaleenPay client', () => {
  describe('construction', () => {
    it('creates client with valid config', () => {
      const client = new BaleenPay(baseConfig)
      expect(client.config).toEqual(baseConfig)
      expect(client.rawClient).toBeDefined()
    })

    it('throws on missing packageId', () => {
      expect(() => new BaleenPay({ ...baseConfig, packageId: '' })).toThrow(ValidationError)
    })

    it('throws on missing merchantId', () => {
      expect(() => new BaleenPay({ ...baseConfig, merchantId: '' })).toThrow(ValidationError)
    })

    it('throws on missing network', () => {
      expect(() => new BaleenPay({ ...baseConfig, network: '' as 'testnet' })).toThrow(ValidationError)
    })

    it('uses custom grpcUrl when provided', () => {
      const client = new BaleenPay({ ...baseConfig, grpcUrl: 'https://custom.grpc' })
      expect(client.rawClient.baseUrl).toBe('https://custom.grpc')
    })
  })

  describe('synchronous methods return TransactionResult', () => {
    let client: BaleenPay

    beforeEach(() => {
      client = new BaleenPay(baseConfig)
    })

    it('registerMerchant returns tx', () => {
      const result = client.registerMerchant({ brandName: 'TestBrand' })
      expect(result.tx).toBeDefined()
    })

    it('claimYield returns tx', () => {
      const c = new BaleenPay({ ...baseConfig, yieldVaultId: '0xYV' })
      const result = c.claimYield('0xcap', 'USDC')
      expect(result.tx).toBeDefined()
    })

    it('claimYieldPartial returns tx', () => {
      const c = new BaleenPay({ ...baseConfig, yieldVaultId: '0xYV' })
      const result = c.claimYieldPartial('0xcap', 'USDC', 100n)
      expect(result.tx).toBeDefined()
    })

    it('claimYieldPartial throws on zero amount', () => {
      const c = new BaleenPay({ ...baseConfig, yieldVaultId: '0xYV' })
      expect(() => c.claimYieldPartial('0xcap', 'USDC', 0n)).toThrow('amount must be > 0')
    })

    it('claimYieldPartial throws on negative amount', () => {
      const c = new BaleenPay({ ...baseConfig, yieldVaultId: '0xYV' })
      expect(() => c.claimYieldPartial('0xcap', 'USDC', -1n)).toThrow('amount must be > 0')
    })

    it('claimYieldPartial throws without yieldVaultId', () => {
      const c = new BaleenPay(baseConfig)
      expect(() => c.claimYieldPartial('0xcap', 'USDC', 100n)).toThrow('yieldVaultId is required')
    })

    it('selfPause returns tx', () => {
      const result = client.selfPause('0xcap')
      expect(result.tx).toBeDefined()
    })

    it('selfUnpause returns tx', () => {
      const result = client.selfUnpause('0xcap')
      expect(result.tx).toBeDefined()
    })

    it('processSubscription returns tx', () => {
      const result = client.processSubscription('0xsub', '0x2::sui::SUI')
      expect(result.tx).toBeDefined()
    })

    it('cancelSubscription returns tx', () => {
      const result = client.cancelSubscription('0xsub', '0x2::sui::SUI')
      expect(result.tx).toBeDefined()
    })
  })

  describe('idempotency guard integration', () => {
    it('exposes idempotencyGuard', () => {
      const client = new BaleenPay(baseConfig)
      expect(client.idempotencyGuard).toBeDefined()
      expect(client.idempotencyGuard.size).toBe(0)
    })
  })

  describe('event delegation', () => {
    it('on() returns unsubscribe function', () => {
      const client = new BaleenPay(baseConfig)
      const unsub = client.on('payment.received', () => {})
      expect(typeof unsub).toBe('function')
    })
  })

  describe('getMerchant', () => {
    it('throws MERCHANT_NOT_FOUND when object not found', async () => {
      const client = new BaleenPay(baseConfig)
      mockGetObject.mockResolvedValue({ object: null })
      await expect(client.getMerchant()).rejects.toThrow('not found')
    })

    it('deserializes merchant fields', async () => {
      const client = new BaleenPay(baseConfig)
      mockGetObject.mockResolvedValue({
        object: {
          json: {
            owner: '0xowner',
            brand_name: 'TestBrand',
            total_received: '1000000',
            idle_principal: '500000',
            accrued_yield: '50000',
            active_subscriptions: 3,
            paused_by_admin: false,
            paused_by_self: false,
          },
        },
      })

      const info = await client.getMerchant()
      expect(info.merchantId).toBe(baseConfig.merchantId)
      expect(info.owner).toBe('0xowner')
      expect(info.brandName).toBe('TestBrand')
      expect(info.totalReceived).toBe(1000000n)
      expect(info.idlePrincipal).toBe(500000n)
      expect(info.accruedYield).toBe(50000n)
      expect(info.activeSubscriptions).toBe(3)
      expect(info.pausedByAdmin).toBe(false)
      expect(info.pausedBySelf).toBe(false)
    })

    it('queries custom merchantId', async () => {
      const client = new BaleenPay(baseConfig)
      mockGetObject.mockResolvedValue({
        object: {
          json: {
            owner: '0x1', brand_name: 'X', total_received: '0',
            idle_principal: '0', accrued_yield: '0', active_subscriptions: 0, paused_by_admin: false, paused_by_self: false,
          },
        },
      })

      await client.getMerchant('0xcustom')
      expect(mockGetObject).toHaveBeenCalledWith({ objectId: '0xcustom', include: { json: true } })
    })
  })

  describe('getSubscription', () => {
    it('throws when not found', async () => {
      const client = new BaleenPay(baseConfig)
      mockGetObject.mockResolvedValue({ object: null })
      await expect(client.getSubscription('0xsub')).rejects.toThrow('not found')
    })

    it('deserializes subscription fields', async () => {
      const client = new BaleenPay(baseConfig)
      mockGetObject.mockResolvedValue({
        object: {
          json: {
            merchant_id: '0xmerchant',
            payer: '0xpayer',
            amount_per_period: '100000',
            period_ms: 86400000,
            next_due: 1711324800000,
            balance: '300000',
          },
        },
      })

      const info = await client.getSubscription('0xsub')
      expect(info.subscriptionId).toBe('0xsub')
      expect(info.merchantId).toBe('0xmerchant')
      expect(info.payer).toBe('0xpayer')
      expect(info.amountPerPeriod).toBe(100000n)
      expect(info.periodMs).toBe(86400000)
      expect(info.nextDue).toBe(1711324800000)
      expect(info.balance).toBe(300000n)
    })
  })

  describe('getPaymentHistory', () => {
    it('returns normalized events with pagination', async () => {
      const client = new BaleenPay(baseConfig)
      mockGraphQLQuery.mockResolvedValue(
        makeGraphQLEventsResponse(
          [{
            type: `${baseConfig.packageId}::events::PaymentReceivedV2`,
            json: {
              merchant_id: '0xmerchant',
              payer: '0xpayer',
              amount: '500000',
              payment_type: 0,
              timestamp: 1711324800000,
              order_id: 'order-1',
              coin_type: '0x2::sui::SUI',
            },
          }],
          { hasNextPage: true, endCursor: 'cursor123' },
        ),
      )

      const result = await client.getPaymentHistory({ limit: 10 })
      expect(result.events).toHaveLength(1)
      expect(result.events[0].type).toBe('payment.received')
      expect(result.events[0].orderId).toBe('order-1')
      expect(result.hasNextPage).toBe(true)
      expect(result.nextCursor).toBeDefined()
    })

    it('filters by payer client-side', async () => {
      const client = new BaleenPay(baseConfig)
      mockGraphQLQuery.mockResolvedValue(
        makeGraphQLEventsResponse([
          {
            type: `${baseConfig.packageId}::events::PaymentReceivedV2`,
            json: { merchant_id: '0xm', payer: '0xA', amount: '100', payment_type: 0, timestamp: 1000, order_id: 'o1', coin_type: 'SUI' },
          },
          {
            type: `${baseConfig.packageId}::events::PaymentReceivedV2`,
            json: { merchant_id: '0xm', payer: '0xB', amount: '200', payment_type: 0, timestamp: 2000, order_id: 'o2', coin_type: 'SUI' },
          },
        ]),
      )

      const result = await client.getPaymentHistory({ payer: '0xA' })
      expect(result.events).toHaveLength(1)
      expect(result.events[0].payer).toBe('0xA')
    })
  })
})

// ── AdminClient ──

describe('AdminClient', () => {
  describe('construction', () => {
    it('creates with valid config', () => {
      const admin = new AdminClient(baseConfig)
      expect(admin.config).toEqual(baseConfig)
    })

    it('throws on missing packageId', () => {
      expect(() => new AdminClient({ ...baseConfig, packageId: '' })).toThrow(ValidationError)
    })
  })

  describe('pause', () => {
    it('returns tx with admin cap and merchant', () => {
      const admin = new AdminClient(baseConfig)
      const result = admin.pause('0xadminCap')
      expect(result.tx).toBeDefined()
    })

    it('uses custom merchantId', () => {
      const admin = new AdminClient(baseConfig)
      const result = admin.pause('0xadminCap', '0xcustomMerchant')
      expect(result.tx).toBeDefined()
    })
  })

  describe('unpause', () => {
    it('returns tx', () => {
      const admin = new AdminClient(baseConfig)
      const result = admin.unpause('0xadminCap')
      expect(result.tx).toBeDefined()
    })
  })

  describe('setRouterMode', () => {
    it('returns tx for valid mode', () => {
      const admin = new AdminClient(baseConfig)
      const result = admin.setRouterMode('0xadminCap', '0xrouter', 0)
      expect(result.tx).toBeDefined()
    })

    it('throws for negative mode', () => {
      const admin = new AdminClient(baseConfig)
      expect(() => admin.setRouterMode('0xadminCap', '0xrouter', -1)).toThrow('non-negative')
    })

    it('throws for non-integer mode', () => {
      const admin = new AdminClient(baseConfig)
      expect(() => admin.setRouterMode('0xadminCap', '0xrouter', 1.5)).toThrow('non-negative')
    })
  })
})
