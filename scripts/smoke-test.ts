#!/usr/bin/env npx tsx
// Testnet smoke test — queries deployed contract state

import { SuiJsonRpcClient } from '@mysten/sui/jsonRpc'

const PKG = '0x1e9ce29bbdd4cd47f26fc3941d8210f09a7614d7bc4096987eeae7089c6149c0'
const MERCHANT = '0x6f7af565126812afd1ccae459ca04fc9f9051400775d5fdaf735a81072a2d22c'
const ROUTER = '0xbfad6d4cda2cd76f53cd1109e987e3027c3713a048109eb3b9c52dc9e8aff278'
const VAULT = '0x3bde158ccc14a682f5cb782467f4778a90d925233a99421a7d09b7a1fa03bc52'
const YIELD_VAULT = '0x44897b52ca5d383e45a9be83275ef858782213f40c17139f519955dcc0e7b837'

const client = new SuiJsonRpcClient({ url: 'https://fullnode.testnet.sui.io:443', network: 'testnet' })

let pass = 0
let fail = 0
function check(name: string, ok: boolean, detail?: string) {
  if (ok) { pass++; console.log(`  ✓ ${name}`) }
  else { fail++; console.log(`  ✗ ${name}${detail ? ': ' + detail : ''}`) }
}

async function main() {
  console.log('BaleenPay Testnet Smoke Test')
  console.log('============================\n')

  // 1. Merchant state
  console.log('--- MerchantAccount ---')
  const merchant = await client.getObject({ id: MERCHANT, options: { showContent: true } })
  const mFields = (merchant.data?.content as any)?.fields
  check('exists', !!mFields)
  check('brand_name = SmokeTestShop', mFields?.brand_name === 'SmokeTestShop')
  check('total_received > 0', BigInt(mFields?.total_received ?? 0) > 0n, `got ${mFields?.total_received}`)
  check('idle_principal > 0', BigInt(mFields?.idle_principal ?? 0) > 0n, `got ${mFields?.idle_principal}`)
  check('not paused', mFields?.paused_by_admin === false && mFields?.paused_by_self === false)
  console.log(`  -> total_received: ${mFields?.total_received}, idle_principal: ${mFields?.idle_principal}, accrued_yield: ${mFields?.accrued_yield}`)

  // 2. RouterConfig
  console.log('\n--- RouterConfig ---')
  const router = await client.getObject({ id: ROUTER, options: { showContent: true } })
  const rFields = (router.data?.content as any)?.fields
  check('exists', !!rFields)
  check('mode = 1 (StableLayer)', Number(rFields?.mode) === 1, `got ${rFields?.mode}`)

  // 3. Vault<USDC>
  console.log('\n--- Vault<USDC> ---')
  const vault = await client.getObject({ id: VAULT, options: { showContent: true } })
  const vFields = (vault.data?.content as any)?.fields
  check('exists', !!vFields)
  const vaultBalance = BigInt(String(vFields?.balance ?? 0))
  check('balance > 0 (routed payment landed)', vaultBalance > 0n, `got ${vaultBalance}`)
  console.log(`  -> balance: ${vaultBalance}, total_deposited: ${vFields?.total_deposited}`)

  // 4. YieldVault<USDB>
  console.log('\n--- YieldVault<USDB> ---')
  const yv = await client.getObject({ id: YIELD_VAULT, options: { showContent: true } })
  const yvFields = (yv.data?.content as any)?.fields
  check('exists', !!yvFields)
  check('balance = 0 (no yield yet)', BigInt(String(yvFields?.balance ?? 0)) === 0n)

  // 5. Events via JSON-RPC queryEvents
  console.log('\n--- Events (JSON-RPC) ---')
  const payEvents = await client.queryEvents({ query: { MoveEventType: `${PKG}::events::PaymentReceivedV2` }, limit: 5 })
  check('PaymentReceivedV2 events exist', payEvents.data.length > 0, `found ${payEvents.data.length}`)
  for (const e of payEvents.data) {
    const j = e.parsedJson as any
    console.log(`    order=${j?.order_id} amount=${j?.amount}`)
  }

  const vaultEvts = await client.queryEvents({ query: { MoveEventType: `${PKG}::events::VaultDeposited` }, limit: 5 })
  check('VaultDeposited events exist', vaultEvts.data.length > 0, `found ${vaultEvts.data.length}`)

  const modeEvts = await client.queryEvents({ query: { MoveEventType: `${PKG}::events::RouterModeChanged` }, limit: 5 })
  check('RouterModeChanged events exist', modeEvts.data.length > 0, `found ${modeEvts.data.length}`)

  const regEvts = await client.queryEvents({ query: { MoveEventType: `${PKG}::events::MerchantRegistered` }, limit: 5 })
  check('MerchantRegistered events exist', regEvts.data.length > 0, `found ${regEvts.data.length}`)

  // 6. Version detection (function exists check via JSON-RPC)
  console.log('\n--- Version Detection ---')
  try {
    await client.getNormalizedMoveFunction({ package: PKG, module: 'payment', function: 'pay_once_v2' })
    check('pay_once_v2 exists', true)
  } catch { check('pay_once_v2 exists', false) }

  try {
    await client.getNormalizedMoveFunction({ package: PKG, module: 'payment', function: 'pay_once_routed' })
    check('pay_once_routed exists', true)
  } catch { check('pay_once_routed exists', false) }

  try {
    await client.getNormalizedMoveFunction({ package: PKG, module: 'router', function: 'claim_yield_v2' })
    check('claim_yield_v2 exists', true)
  } catch { check('claim_yield_v2 exists', false) }

  // Summary
  console.log(`\n============================`)
  console.log(`Results: ${pass} passed, ${fail} failed`)
  if (fail > 0) process.exit(1)
}

main().catch((err) => {
  console.error('Smoke test crashed:', err)
  process.exit(1)
})
