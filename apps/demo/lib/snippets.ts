export interface Snippet {
  title: string
  description: string
  code: string
}

export const DEVELOPER_SNIPPETS: Snippet[] = [
  {
    title: 'Quick Start',
    description: 'Initialize the SDK with your testnet config',
    code: `import { FloatSync } from '@floatsync/sdk'

const fs = new FloatSync({
  network: 'testnet',
  packageId: '0xe0eb...306b32a',
  merchantId: '0x4db0...c17c24',
})`,
  },
  {
    title: 'Accept a Payment',
    description: 'Build and execute a one-time payment transaction',
    code: `const { tx } = await fs.pay({
  amount: 49_000_000n,   // 49 USDC (6 decimals)
  coin: 'USDC',
  orderId: 'order_001',  // dedup key
}, senderAddress)

// Sign with wallet adapter
const result = await wallet.signAndExecuteTransaction({ transaction: tx })`,
  },
  {
    title: 'Create a Subscription',
    description: 'Set up a recurring payment with prepaid periods',
    code: `const { tx } = await fs.subscribe({
  amountPerPeriod: 49_000_000n,
  periodMs: 30 * 24 * 60 * 60 * 1000, // 30 days
  prepaidPeriods: 3,
  coin: 'USDC',
  orderId: 'sub_001',
}, senderAddress)`,
  },
  {
    title: 'React Hook — usePayment',
    description: 'State-managed payment flow in a React component',
    code: `import { usePayment } from '@floatsync/react'

function CheckoutButton() {
  const { pay, status, error, result, reset } = usePayment()

  return (
    <button
      onClick={() => pay({ amount: 49_000_000n, coin: 'USDC', orderId: 'order_001' })}
      disabled={status !== 'idle'}
    >
      {status === 'signing' ? 'Confirm in wallet...' : 'Pay $49'}
    </button>
  )
}`,
  },
  {
    title: 'Drop-in Component',
    description: 'One-line checkout button with built-in state management',
    code: `import { CheckoutButton } from '@floatsync/react'

<CheckoutButton
  amount={49_000_000n}
  coin="USDC"
  orderId="order_001"
  onSuccess={(digest) => console.log('Paid!', digest)}
  onError={(err) => console.error(err)}
/>`,
  },
  {
    title: 'Query Merchant Data',
    description: 'Read on-chain merchant state and payment history',
    code: `// SDK client
const merchant = await fs.getMerchant()
console.log(merchant.totalReceived)  // bigint
console.log(merchant.accruedYield)   // bigint
console.log(merchant.paused)         // boolean

// React hook
const { merchant, isLoading } = useMerchant()
const { events, hasNextPage, fetchNextPage } = usePaymentHistory()`,
  },
]
