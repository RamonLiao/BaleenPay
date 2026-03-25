# FloatSync Notes

## 2026-03-25: Stripe-like SDK Architecture Decision

### 選定方案：C (Progressive Platform)
- Phase 1: `@floatsync/sdk` + `@floatsync/react` + 合約 order_id 升級
- Phase 2: `@floatsync/server` (webhook + server-side idempotency)
- Phase 3: FloatSync Cloud (REST API + Hosted Checkout + metering)

### 未來擴展：方案 B (Full Platform) 備忘
當團隊和資金到位時，Phase 3 展開為完整平台：
- REST API Gateway（/v1/payments, /v1/merchants...）
- Webhook Service（indexer → HTTP POST）
- API Key Management（pk_/sk_/whsec_ 三層）
- Hosted Checkout Page（pay.floatsync.io）
- Dashboard API
- Usage Metering + Billing
- Protocol fee module（合約層抽成）

### 關鍵設計決策
| 決策 | 選擇 | 原因 |
|------|------|------|
| 客群 | 混合 Web2 + Web3 | 兩層接入面，共用底層 |
| 收費 | 合約免費 + yield spread + Hosted API 付費 | 零門檻進入 + Web3 文化契合 |
| SDK 範圍 | 全操作覆蓋 | register, pay, subscribe, claim, pause 全包 |
| 升級策略 | 合約 additive-first + SDK 版本適配 | SUI compatible 升級政策天然支持 |
| Event/Webhook | 鏈上 event 訂閱 + Hosted webhook | Web3 用 event stream, Web2 用 webhook |
| 幣種 | 白名單 shorthand + 自訂 coin type + SDK 驗證 | CoinMetadata RPC check 做 DX 防護 |
| 冪等性 | 合約層 Order ID + SDK/API 層 idempotency key | Order ID 精確防重複，SDK 做 UX 層 |
| 發布形態 | SDK → React 元件 → Hosted Checkout | 分階段，金字塔結構 |
| 安全 | pk_/sk_/whsec_ 三層 key + PII 不上鏈 | yield 策略放 off-chain 保護商業機密 |
