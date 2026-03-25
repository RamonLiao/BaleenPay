// packages/sdk/src/errors.ts

import { ABORT_CODE_MAP } from './constants.js'

export class FloatSyncError extends Error {
  code: string
  constructor(code: string, message: string) {
    super(message)
    this.name = 'FloatSyncError'
    this.code = code
  }
}

export class PaymentError extends FloatSyncError {
  constructor(code: string, message: string) {
    super(code, message)
    this.name = 'PaymentError'
  }
}

export class MerchantError extends FloatSyncError {
  constructor(code: string, message: string) {
    super(code, message)
    this.name = 'MerchantError'
  }
}

export class ValidationError extends FloatSyncError {
  constructor(code: string, message: string) {
    super(code, message)
    this.name = 'ValidationError'
  }
}

export class NetworkError extends FloatSyncError {
  constructor(code: string, message: string) {
    super(code, message)
    this.name = 'NetworkError'
  }
}

const PAYMENT_CODES = new Set([10, 13, 15, 18, 23])
const MERCHANT_CODES = new Set([0, 2, 6, 7, 8, 12])
const VALIDATION_CODES = new Set([14, 17, 19, 22])

export function parseAbortCode(status: number): FloatSyncError {
  const entry = ABORT_CODE_MAP[status]

  if (!entry) {
    return new FloatSyncError('UNKNOWN', `Unknown abort code: ${status}`)
  }

  const { code, message } = entry

  if (PAYMENT_CODES.has(status)) return new PaymentError(code, message)
  if (MERCHANT_CODES.has(status)) return new MerchantError(code, message)
  if (VALIDATION_CODES.has(status)) return new ValidationError(code, message)

  return new FloatSyncError(code, message)
}
