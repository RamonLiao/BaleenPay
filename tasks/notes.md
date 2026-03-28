# BaleenPay Notes

## 2026-03-25: Stripe-like SDK Architecture Decision

### 選定方案：C (Progressive Platform)
- Phase 1: `@baleenpay/sdk` + `@baleenpay/react` + 合約 order_id 升級
- Phase 2: `@baleenpay/server` (webhook + server-side idempotency)
- Phase 3: BaleenPay Cloud (REST API + Hosted Checkout + metering)

### 未來擴展：方案 B (Full Platform) 備忘
當團隊和資金到位時，Phase 3 展開為完整平台：
- REST API Gateway（/v1/payments, /v1/merchants...）
- Webhook Service（indexer → HTTP POST）
- API Key Management（pk_/sk_/whsec_ 三層）
- Hosted Checkout Page（pay.baleenpay.io）
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

## 2026-03-25: Phase 2 Backlog（SDK Review 期間識別）

以下功能在 Phase 1 SDK 實作/Review 過程中被識別為需要但延後處理：

| 項目 | 說明 | 優先級 |
|------|------|--------|
| `processSubscription` automation | 需要 cron/keeper pattern 自動呼叫到期 subscription 的 `process_subscription`。目前為手動或由任意人觸發。 | HIGH — Phase 2 server package |
| gRPC event stream migration | SUI JSON-RPC `subscribeEvent` 預計 2026-04 前被 GraphQL subscription 取代。EventStream 類需遷移。 | HIGH — 時效性 |
| `min_payment_amount` per merchant | 合約層新增每商家最低收款門檻，防止 dust payment。SDK 需對應驗證。 | MEDIUM |
| Tombstone pattern for `remove_order_record` | 目前 `remove_order_record` 是 hard delete（dynamic field 移除）+ audit event。考慮改為 soft delete（標記 tombstone）以便鏈上查詢歷史。 | LOW — 需評估 storage cost tradeoff |

## 2026-03-26: Demo App 未來升級方向

以下功能在 demo app brainstorming 中識別為有價值但不在 MVP scope：

| 項目 | 說明 | 優先級 |
|------|------|--------|
| Mobile responsive | 目前 desktop-first，未來需 responsive breakpoints（tablet + mobile）| MEDIUM |
| i18n / 多語系 | Landing page + checkout 支援中英文切換，擴大受眾 | MEDIUM |
| Hosted Checkout 模式 | 獨立 checkout URL（類似 Stripe Payment Links），商家只需分享連結 | HIGH — Phase 3 |
| Real-time event feed | Dashboard 即時顯示鏈上 payment/subscription events（WebSocket or polling）| MEDIUM |
| Multi-merchant 切換 | Dashboard 支援多個 MerchantAccount 切換，不只綁定一個 | LOW |
| Analytics / Charts | Dashboard 加入收款趨勢圖、訂閱留存率、yield 累積曲線 | MEDIUM |
| Testnet faucet 整合 | Demo 內建 SUI testnet faucet button，降低新用戶體驗門檻 | HIGH — UX |
| Dark mode toggle | Ocean palette 天然適合 dark mode，加 toggle 切換 | LOW |
| Interactive playground | Developers 頁面從 static snippets 升級為 live code editor + 即時預覽 | LOW — 可能獨立為 docs site |
| StableLayer yield 視覺化 | Dashboard 顯示 yield 來源、APY 歷史、compound 選項（待 StableLayer API 就緒）| HIGH — 依賴 StableLayer |
| Webhook 模擬器 | Developers 頁面加入 webhook event 模擬（類似 Stripe webhook tester）| MEDIUM — Phase 2 server |
| zkLogin / Passkey 登入 | 降低 Web2 用戶門檻，不需安裝錢包即可體驗 | HIGH — 殺手級 UX |

## 2026-03-26: Demo App 實作決策紀錄

### dapp-kit-react v2 API 變更（重要）
- Plan 原假設 v1 API：`createNetworkConfig` + `SuiClientProvider` + `WalletProvider`
- 實際 v2 API：`createDAppKit()` from `@mysten/dapp-kit-core` + `DAppKitProvider` from `@mysten/dapp-kit-react`
- `ConnectButton` 移到 `@mysten/dapp-kit-react/ui` subpath export
- `signAndExecuteTransaction` 回傳 `TransactionResultWithEffects`（有 `effects`, `transaction`, `bcs`），不是 v1 的 `{ Transaction, FailedTransaction }` wrapper
- **已知問題**：`@baleenpay/react` hooks（usePayment, useSubscription）內部 `txResult.FailedTransaction` / `txResult.Transaction.digest` 是 v1 pattern，需要更新以匹配 v2 DAppKit 結果格式。目前不阻擋 demo UI 開發，但影響實際交易流程。

### Provider Stack（最終版）
```
QueryClientProvider
  └── DAppKitProvider (dAppKit instance)
      └── BaleenPayProvider (config)
          └── Nav + main + Footer
```

### 依賴新增
- `@mysten/dapp-kit-core: ^1.2.0`（dapp-kit-react 的 peer dep，需要 explicit 安裝才能 import `createDAppKit`）

### Tailwind 4 Setup
- CSS-first config：`globals.css` 用 `@import 'tailwindcss'` + `@config '../tailwind.config.ts'`
- Ocean palette 定義在 `tailwind.config.ts` 的 `theme.extend.colors.ocean`

### 進度
- Task 1 (scaffold) + Task 2 (Nav/Footer/format) 完成
- Task 3-8 待做（shared components → pages）
- Plan：`docs/superpowers/plans/2026-03-26-baleenpay-demo-app.md`
