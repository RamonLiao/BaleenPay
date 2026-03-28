# BaleenPay Project Plan & Notes

## 本次工作重點 (Latest Update)
- **做了什麼**:
  - 將專案命名為 **BaleenPay**。
  - 將原本的 `StableLayer-SaaS-Widget` 專案目錄重新命名為 `BaleenPay`。
  - 更新了 `README.md` 的標題與簡要敘述，加入 BaleenPay 的品牌設計理念。
  - 建立了本文件 (`plan.md`) 來記錄專案目標與未來決策。
- **更動了哪些檔案**:
  - 目錄名稱變更
  - `README.md` (標題與簡介更新)
  - `plan.md` (NEW)
- **決策原因**:
  - **BaleenPay** 這個名稱精準點出 SaaS 平台的 Payment Float (在途資金) 痛點，並具有與底層生息網路自動同步 (Sync) 的專業科技感與極簡商務風格。經調查，Web3/Fintech 領域目前無同名專案，且 GitHub 名稱亦為空缺，具有高可塑性。
- **尚未完成的 TODO**:
  - 初始化前端結構（例如 Next.js + shadcn/ui）作為 Demo Widget。
  - 規劃前端與 Move 智能合約（整合 StableLayer）的對接設計。
  - 註冊網域與 GitHub 組織。

## 專案目標與 Milestone
- **核心目標**: 開發一個供 SaaS 平台使用的「白牌穩定幣收款 Widget」。從用戶端看，支付的是 BrandUSD；從平台方看，收款後資金會自動進入 StableLayer 的收益池，實現閒置資金（payment float）自動生息。
- **MVP Milestone 1**: 完成基礎結帳金流 Demo（模擬 SaaS 付費流程）與商家後台。
- **MVP Milestone 2**: 實作並整合基礎 Sui 合約，測試 USDC 自動路由至 StableLayer 的流程。
