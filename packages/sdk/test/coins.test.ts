import { describe, it, expect } from 'vitest'
import { resolveCoin } from '../src/coins/registry.js'
import { ORDER_ID_REGEX } from '../src/constants.js'

describe('resolveCoin', () => {
  it('resolves USDC on testnet', () => {
    const coin = resolveCoin('testnet', 'USDC')
    expect(coin.type).toContain('::usdc::USDC')
    expect(coin.decimals).toBe(6)
  })

  it('resolves SUI on any network', () => {
    const coin = resolveCoin('testnet', 'SUI')
    expect(coin.type).toBe('0x2::sui::SUI')
    expect(coin.decimals).toBe(9)
  })

  it('is case insensitive', () => {
    const coin = resolveCoin('testnet', 'usdc')
    expect(coin.type).toContain('::usdc::USDC')
  })

  it('passes through full type strings', () => {
    const fullType = '0xabc::my_coin::MY_COIN'
    const coin = resolveCoin('testnet', fullType)
    expect(coin.type).toBe(fullType)
    expect(coin.decimals).toBe(-1)
  })

  it('throws for unknown coin', () => {
    expect(() => resolveCoin('testnet', 'DOGE')).toThrow('Unknown coin')
  })

  it('throws for unknown network', () => {
    expect(() => resolveCoin('localnet', 'SUI')).toThrow('Unknown network')
  })
})

describe('ORDER_ID_REGEX', () => {
  it('accepts valid order IDs', () => {
    expect(ORDER_ID_REGEX.test('order_001')).toBe(true)
    expect(ORDER_ID_REGEX.test('a')).toBe(true)
    expect(ORDER_ID_REGEX.test('A'.repeat(64))).toBe(true)
    expect(ORDER_ID_REGEX.test('inv-2024-001!@#')).toBe(true)
  })

  it('rejects invalid order IDs', () => {
    expect(ORDER_ID_REGEX.test('')).toBe(false)
    expect(ORDER_ID_REGEX.test('has space')).toBe(false)
    expect(ORDER_ID_REGEX.test('A'.repeat(65))).toBe(false)
  })
})
