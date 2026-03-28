# BaleenPay Project Plan & Notes

## 本次工作重點 (Latest Update)
- **做了什麼**:
  - 歷經多次命名迭代，最終敲定專案名稱為 **BaleenPay**。
  - 將專案目錄由 `BaleenPay` 重新命名為 `BaleenPay`。
  - 更新了 `README.md`，加入了 Baleen (鯨鬚) 攔截水流中浮游生物 (截流 Yield) 的核心品牌隱喻。
- **更動了哪些檔案**:
  - 目錄名稱變更
  - `README.md` (標題與簡介更新)
  - `plan.md` (重建此記錄檔)
- **決策原因**:
  - **Baleen (鯨鬚)** 是絕佳的高級生物學隱喻，安靜且高效地過濾出龐大水流 (Payment Float) 中的高營養價值物 (Yield)。加上 Pay 後綴，在 B2B SaaS 領域定位清晰。最重要的是，`baleenpay.com` 網域與 GitHub 組織皆無人使用，非常適合 Hackathon 快速部署與日後商用。
- **尚未完成的 TODO**:
  - 初始化前端結構（例如 Next.js + shadcn/ui）作為 Demo Widget。
  - 規劃前端與 Move 智能合約（整合 StableLayer）的對接設計。
  - 註冊網域 (`baleenpay.com`) 與 GitHub 組織 (`github.com/baleenpay`)。

## 專案目標與 Milestone
- **核心目標**: 開發一個供 SaaS 平台使用的「白牌穩定幣收款 Widget」。從用戶端看，支付的是 BrandUSD（底層為 USDC）；從平台方看，收款後資金會自動進入 StableLayer 的收益池，實現閒置資金（payment float）自動生息。
- **MVP Milestone 1**: 完成基礎結帳金流 Demo（模擬 SaaS 付費流程）與商家後台。
- **MVP Milestone 2**: 實作並整合基礎 Sui 合約，測試 USDC 自動路由至 StableLayer 的流程。
