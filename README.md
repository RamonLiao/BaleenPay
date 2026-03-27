# BaleenPay: SaaS 白牌穩定幣收款 Widget (MVP)

> **BaleenPay**：像過濾浮游生物的鯨鬚 (Baleen) 一樣，專注於攔截並活化 SaaS 的 Payment Float (在途資金)，讓閒置水流自動在底層協議轉化為收益。

## 專案簡介
這是一個訂閱收款示範系統，結合「收款後自動存入 StableLayer 的商家錢包」。從用戶端看，支付的是 BrandUSD；從平台方看，收款後資金自動進入不斷累積收益的「收益池」。

## 使用流程
1. 用戶在 SaaS 網站 (例如每月 10 BrandUSD 訂閱) 連接 Sui 錢包付款。
2. 實際上是支付 USDC，透過 StableLayer 鑄造成 BrandUSD。
3. 收到的 USDC 自動路由至 StableLayer 的 USDC Yield Aggregator。
4. 平台可從後台領出 baseline yield 成為收入來源，並隨時查看閒置資金 (Idle 資金本金) 與累積收益。

## 架構設計

### 智能合約
- **收款合約**: 管理 subscription 或 one-time payment 的記帳功能。
- **路由合約**: 與 StableLayer 整合，路由 USDC 至收益池，並管理帳本。

### 前端介面
- **結帳 Widget**: 嵌入式結帳流程，可放在任何 SaaS 平台。
- **商家 Dashboard**: 顯示「已收款總額」、「Idle 資金本金」和「累積收益」，提供領取收益 (Claim Yield) 功能。

## 商業敘事
讓平台的收款現金流「在躺著的時候自動賺利息」，直觀解決平台 treasury float 無法產生價值的痛點，未來可成為 Sui 生態內的白牌 Stripe/Paddle。
