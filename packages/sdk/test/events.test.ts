import { describe, it, expect, vi } from 'vitest'
import { EVENT_TYPE_MAP, normalizeEvent } from '../src/events/types.js'
import { EventStream } from '../src/events/stream.js'
import type { FloatSyncEventData } from '../src/types.js'

describe('EVENT_TYPE_MAP', () => {
  it('has entries for all event types', () => {
    const expected = [
      'PaymentReceived',
      'PaymentReceivedV2',
      'SubscriptionCreated',
      'SubscriptionCreatedV2',
      'SubscriptionProcessed',
      'SubscriptionCancelled',
      'SubscriptionFunded',
      'MerchantRegistered',
      'MerchantPaused',
      'MerchantUnpaused',
      'YieldClaimed',
      'RouterModeChanged',
      'OrderRecordRemoved',
    ]
    for (const name of expected) {
      expect(EVENT_TYPE_MAP[name]).toBeDefined()
    }
  })

  it('maps v1 and v2 payment events to same name', () => {
    expect(EVENT_TYPE_MAP.PaymentReceived).toBe('payment.received')
    expect(EVENT_TYPE_MAP.PaymentReceivedV2).toBe('payment.received')
  })

  it('maps v1 and v2 subscription events to same name', () => {
    expect(EVENT_TYPE_MAP.SubscriptionCreated).toBe('subscription.created')
    expect(EVENT_TYPE_MAP.SubscriptionCreatedV2).toBe('subscription.created')
  })
})

describe('normalizeEvent', () => {
  it('maps PaymentReceived (v1) → payment.received with orderId undefined', () => {
    const data = normalizeEvent('0xabc::events::PaymentReceived', {
      merchant_id: '0x111',
      payer: '0x222',
      amount: '1000000',
      payment_type: 0,
      timestamp: '1700000000',
    })

    expect(data.type).toBe('payment.received')
    expect(data.merchantId).toBe('0x111')
    expect(data.payer).toBe('0x222')
    expect(data.amount).toBe(1000000n)
    expect(data.orderId).toBeUndefined()
    expect(data.coinType).toBeUndefined()
    expect(data.timestamp).toBe(1700000000)
  })

  it('maps PaymentReceivedV2 → payment.received with orderId from parsedJson', () => {
    const data = normalizeEvent('0xabc::events::PaymentReceivedV2', {
      merchant_id: '0x111',
      payer: '0x222',
      amount: '5000000',
      payment_type: 0,
      timestamp: '1700000000',
      order_id: 'order-123',
      coin_type: '0xabc::usdc::USDC',
    })

    expect(data.type).toBe('payment.received')
    expect(data.orderId).toBe('order-123')
    expect(data.coinType).toBe('0xabc::usdc::USDC')
    expect(data.amount).toBe(5000000n)
  })

  it('maps SubscriptionCreatedV2 → subscription.created', () => {
    const data = normalizeEvent('0xabc::events::SubscriptionCreatedV2', {
      merchant_id: '0x111',
      payer: '0x222',
      amount_per_period: '2000000',
      period_ms: '86400000',
      prepaid_periods: '3',
      subscription_id: '0x333',
      order_id: 'sub-001',
    })

    expect(data.type).toBe('subscription.created')
    expect(data.amountPerPeriod).toBe(2000000n)
    expect(data.subscriptionId).toBe('0x333')
    expect(data.orderId).toBe('sub-001')
  })

  it('maps SubscriptionCreated (v1) with orderId undefined', () => {
    const data = normalizeEvent('0xabc::events::SubscriptionCreated', {
      merchant_id: '0x111',
      payer: '0x222',
      amount_per_period: '1000000',
      period_ms: '86400000',
      prepaid_periods: '5',
    })

    expect(data.type).toBe('subscription.created')
    expect(data.orderId).toBeUndefined()
  })

  it('handles unknown event struct gracefully', () => {
    const data = normalizeEvent('0xabc::events::SomeFutureEvent', { foo: 'bar' })
    expect(data.type).toBe('*')
  })
})

describe('EventStream', () => {
  it('on registers listener and returns unsubscribe function', () => {
    const stream = new EventStream('0xpkg')
    const cb = vi.fn()
    const unsub = stream.on('payment.received', cb)

    expect(typeof unsub).toBe('function')

    // Dispatch an event — should call the callback
    const event: FloatSyncEventData = { type: 'payment.received', amount: 100n }
    stream.dispatch(event)
    expect(cb).toHaveBeenCalledOnce()
    expect(cb).toHaveBeenCalledWith(event)

    // Unsubscribe — should no longer fire
    unsub()
    stream.dispatch(event)
    expect(cb).toHaveBeenCalledOnce()
  })

  it('wildcard * listener receives all events', () => {
    const stream = new EventStream('0xpkg')
    const cb = vi.fn()
    stream.on('*', cb)

    stream.dispatch({ type: 'payment.received' })
    stream.dispatch({ type: 'merchant.registered' })
    stream.dispatch({ type: 'subscription.created' })

    expect(cb).toHaveBeenCalledTimes(3)
  })

  it('dispatch with filter matches correctly', () => {
    const stream = new EventStream('0xpkg')
    const cb = vi.fn()
    stream.on('payment.received', cb, { payer: '0xalice' })

    // Should match
    stream.dispatch({ type: 'payment.received', payer: '0xalice', amount: 100n })
    expect(cb).toHaveBeenCalledOnce()

    // Should NOT match
    stream.dispatch({ type: 'payment.received', payer: '0xbob', amount: 200n })
    expect(cb).toHaveBeenCalledOnce()
  })

  it('filter with multiple fields requires all to match', () => {
    const stream = new EventStream('0xpkg')
    const cb = vi.fn()
    stream.on('payment.received', cb, { payer: '0xalice', merchantId: '0xmerchant' })

    // Only payer matches — should NOT fire
    stream.dispatch({ type: 'payment.received', payer: '0xalice', merchantId: '0xother' })
    expect(cb).not.toHaveBeenCalled()

    // Both match
    stream.dispatch({ type: 'payment.received', payer: '0xalice', merchantId: '0xmerchant' })
    expect(cb).toHaveBeenCalledOnce()
  })

  it('multiple listeners on same event', () => {
    const stream = new EventStream('0xpkg')
    const cb1 = vi.fn()
    const cb2 = vi.fn()
    stream.on('payment.received', cb1)
    stream.on('payment.received', cb2)

    stream.dispatch({ type: 'payment.received' })
    expect(cb1).toHaveBeenCalledOnce()
    expect(cb2).toHaveBeenCalledOnce()
  })

  it('does not fire listener for wrong event type', () => {
    const stream = new EventStream('0xpkg')
    const cb = vi.fn()
    stream.on('merchant.registered', cb)

    stream.dispatch({ type: 'payment.received' })
    expect(cb).not.toHaveBeenCalled()
  })
})
