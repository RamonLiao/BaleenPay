import { describe, it, expect } from 'vitest'
import {
  FloatSyncError,
  PaymentError,
  MerchantError,
  ValidationError,
  NetworkError,
  parseAbortCode,
} from '../src/errors.js'

describe('Error hierarchy', () => {
  it('PaymentError instanceof FloatSyncError', () => {
    const err = new PaymentError('TEST', 'test')
    expect(err).toBeInstanceOf(FloatSyncError)
    expect(err).toBeInstanceOf(Error)
    expect(err.name).toBe('PaymentError')
  })

  it('MerchantError instanceof FloatSyncError', () => {
    const err = new MerchantError('TEST', 'test')
    expect(err).toBeInstanceOf(FloatSyncError)
    expect(err.name).toBe('MerchantError')
  })

  it('ValidationError instanceof FloatSyncError', () => {
    const err = new ValidationError('TEST', 'test')
    expect(err).toBeInstanceOf(FloatSyncError)
    expect(err.name).toBe('ValidationError')
  })

  it('NetworkError instanceof FloatSyncError', () => {
    const err = new NetworkError('TEST', 'test')
    expect(err).toBeInstanceOf(FloatSyncError)
    expect(err.name).toBe('NetworkError')
  })

  it('FloatSyncError has code and message', () => {
    const err = new FloatSyncError('FOO', 'bar')
    expect(err.code).toBe('FOO')
    expect(err.message).toBe('bar')
    expect(err.name).toBe('FloatSyncError')
  })
})

describe('parseAbortCode', () => {
  it('returns PaymentError for code 18 (ORDER_ALREADY_PAID)', () => {
    const err = parseAbortCode(18)
    expect(err).toBeInstanceOf(PaymentError)
    expect(err.code).toBe('ORDER_ALREADY_PAID')
    expect(err.message).toBe('This order has already been paid')
  })

  it('returns PaymentError for code 10 (ZERO_AMOUNT)', () => {
    const err = parseAbortCode(10)
    expect(err).toBeInstanceOf(PaymentError)
    expect(err.code).toBe('ZERO_AMOUNT')
  })

  it('returns PaymentError for code 13 (INSUFFICIENT_PREPAID)', () => {
    const err = parseAbortCode(13)
    expect(err).toBeInstanceOf(PaymentError)
  })

  it('returns PaymentError for code 15 (INSUFFICIENT_BALANCE)', () => {
    const err = parseAbortCode(15)
    expect(err).toBeInstanceOf(PaymentError)
  })

  it('returns PaymentError for code 23 (OVERFLOW)', () => {
    const err = parseAbortCode(23)
    expect(err).toBeInstanceOf(PaymentError)
  })

  it('returns MerchantError for code 2 (MERCHANT_PAUSED)', () => {
    const err = parseAbortCode(2)
    expect(err).toBeInstanceOf(MerchantError)
    expect(err.code).toBe('MERCHANT_PAUSED')
    expect(err.message).toBe('Merchant is paused')
  })

  it('returns MerchantError for code 0 (NOT_MERCHANT_OWNER)', () => {
    const err = parseAbortCode(0)
    expect(err).toBeInstanceOf(MerchantError)
  })

  it('returns MerchantError for code 6 (ALREADY_REGISTERED)', () => {
    const err = parseAbortCode(6)
    expect(err).toBeInstanceOf(MerchantError)
  })

  it('returns MerchantError for code 7', () => {
    const err = parseAbortCode(7)
    expect(err).toBeInstanceOf(MerchantError)
  })

  it('returns MerchantError for code 8', () => {
    const err = parseAbortCode(8)
    expect(err).toBeInstanceOf(MerchantError)
  })

  it('returns MerchantError for code 12', () => {
    const err = parseAbortCode(12)
    expect(err).toBeInstanceOf(MerchantError)
  })

  it('returns ValidationError for code 19 (INVALID_ORDER_ID)', () => {
    const err = parseAbortCode(19)
    expect(err).toBeInstanceOf(ValidationError)
    expect(err.code).toBe('INVALID_ORDER_ID')
    expect(err.message).toBe('Order ID must be 1-64 ASCII printable characters')
  })

  it('returns ValidationError for code 14 (ZERO_PERIOD)', () => {
    const err = parseAbortCode(14)
    expect(err).toBeInstanceOf(ValidationError)
  })

  it('returns ValidationError for code 17', () => {
    const err = parseAbortCode(17)
    expect(err).toBeInstanceOf(ValidationError)
  })

  it('returns ValidationError for code 22', () => {
    const err = parseAbortCode(22)
    expect(err).toBeInstanceOf(ValidationError)
  })

  it('returns FloatSyncError for unmapped codes (3, 11, 16, 20, 21)', () => {
    for (const code of [3, 11, 16, 20, 21]) {
      const err = parseAbortCode(code)
      expect(err).toBeInstanceOf(FloatSyncError)
      expect(err).not.toBeInstanceOf(PaymentError)
      expect(err).not.toBeInstanceOf(MerchantError)
      expect(err).not.toBeInstanceOf(ValidationError)
    }
  })

  it('returns FloatSyncError with UNKNOWN code for unknown abort code', () => {
    const err = parseAbortCode(999)
    expect(err).toBeInstanceOf(FloatSyncError)
    expect(err.code).toBe('UNKNOWN')
    expect(err.message).toContain('999')
  })
})
