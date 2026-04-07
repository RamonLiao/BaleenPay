# BaleenPay: SaaS White-Label Stablecoin Checkout Widget (MVP)

> **BaleenPay**: Like the baleen of a whale filtering plankton, it focuses on intercepting and activating the Payment Float of SaaS platforms, allowing idle cash flows to automatically generate yield in the underlying protocol.

## Project Overview
This is a demonstration system for subscription payments, combining "automatic deposit to the merchant's wallet on StableLayer upon receipt". From the user's perspective, they pay in BrandUSD; from the platform's perspective, the received funds automatically enter a "yield pool" that continuously accumulates returns.

## User Flow
1. Users connect their Sui wallet to make a payment on a SaaS website (e.g., a 10 BrandUSD monthly subscription).
2. The actual payment is made in USDC, which is then minted into BrandUSD via StableLayer.
3. The received USDC is automatically routed to the StableLayer USDC Yield Aggregator.
4. The platform can claim baseline yield from the dashboard as a revenue source, and monitor idle capital (principal) and accumulated yield at any time.

## Architecture Design

### Smart Contracts
- **Checkout Contract**: Manages the accounting functionality for subscriptions or one-off payments.
- **Routing Contract**: Integrates with StableLayer, routes USDC to the yield pool, and manages the ledger.

### Frontend Interface
- **Checkout Widget**: An embeddable checkout flow that can be integrated into any SaaS platform.
- **Merchant Dashboard**: Displays "Total Received", "Idle Capital Principal", and "Accumulated Yield", whilst providing a feature to claim yield.

## Commercial Narrative
Enabling the platform's incoming cash flow to "automatically earn interest whilst lying idle", intuitively solving the pain point of platform treasury floats failing to generate value. It has the potential to become the white-label Stripe/Paddle within the Sui ecosystem.
