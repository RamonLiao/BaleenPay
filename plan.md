# BaleenPay Project Plan & Notes

## 本次工作重點 (Latest Update)
- **做了什麼**:
  - 將專案原有的繁體中文 `README.md` 重新命名為 `README_zh.md`。
  - 根據需求，翻譯並生成了一份全新的英式英文版本 `README.md`，使專案的說明文件更佳國際化且符合英式英文字詞慣例。
- **更動了哪些檔案**:
  - `README.md` (NEW / Trnaslated to British English)
  - `README_zh.md` (Renamed from original README.md)
  - `plan.md` (Update)
- **決策原因**:
  - 為擴大專案受眾，並建立專業專案的雙語說明文件基礎。
- **尚未完成的 TODO**:
  - 初始化前端結構（例如 Next.js + shadcn/ui）作為 Demo Widget。
  - 規劃前端與 Move 智能合約（整合 StableLayer）的對接設計。
  - 註冊網域 (`baleenpay.com`) 與 GitHub 組織 (`github.com/baleenpay`)。

## 專案目標與 Milestone
- **核心目標**: 開發一個供 SaaS 平台使用的「白牌穩定幣收款 Widget」。從用戶端看，支付的是 BrandUSD（底層為 USDC）；從平台方看，收款後資金會自動進入 StableLayer 的收益池，實現閒置資金（payment float）自動生息。
- **MVP Milestone 1**: 完成基礎結帳金流 Demo（模擬 SaaS 付費流程）與商家後台。
- **MVP Milestone 2**: 實作並整合基礎 Sui 合約，測試 USDC 自動路由至 StableLayer 的流程。
