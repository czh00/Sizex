# Sizex 視窗位置記憶與自訂熱鍵工具

[![AutoHotkey](https://img.shields.io/badge/AutoHotkey-v2.0+-green.svg)](https://www.autohotkey.com/)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)](https://www.microsoft.com/windows/)
[![License](https://img.shields.io/badge/License-MIT-orange.svg)](LICENSE)

專為 Windows 打造的高效能視窗位置記憶、自動定位與智慧熱鍵管理工具（基於 AutoHotkey v2 開發）。

---

## ✨ 主要特色

- 📌 **焦點視窗即時記憶**：一鍵記住當前焦點視窗的精確座標 (X, Y) 與尺寸 (W, H)。
- 🎯 **自訂熱鍵即時錄製**：內建按鍵錄製介面，按下鍵盤組合鍵（支援 `Ctrl`、`Alt`、`Shift`、`Win` 等）或滑鼠按鍵（支援中鍵 `MButton`、側鍵 `XButton1/2`、滾輪 `WheelUp/Down`、右鍵等）即可自動偵測轉換並即時套用。
- ⚙️ **多功能設定中心**：
  - **⌨️ 熱鍵設定**：錄製自訂熱鍵、動態綁定、一鍵還原預設值。
  - **📋 視窗紀錄管理**：表格清單檢視所有儲存視窗，支援刪除單筆紀錄與清空所有紀錄。
  - **📂 匯入 / 匯出**：支援 INI 設定檔備份匯出、外部設定檔合併匯入，以及直接編輯。
- 🪟 **100% 純事件驅動（零輪詢、零背景 CPU 佔用）**：
  - 🔄 **啟動單次復原**：僅在腳本啟動時執行單次掃描，將目前已存在的記錄視窗還原至記憶位置。
  - ⚡ **新開視窗事件觸發**：僅在 Windows 底層產生 `EVENT_OBJECT_SHOW` 事件時單次觸發定位，**絕不進行任何持續輪詢或背景迴圈**，閒置 CPU 佔用率為 0%。
  - 📏 原生事件監聽拖拉視窗時即時提示座標與尺寸。
- 零輸入法衝突，極致輕量無負擔。
- 托盤右鍵選單極簡設計（僅保留「設定」與「離開」）。

---

## 🚀 系統需求與安裝

1. 下載並安裝 [AutoHotkey v2.0+](https://www.autohotkey.com/).
2. 下載本專案所有檔案至任意資料夾。
3. 雙擊執行 `Sizex.ahk` 即可啟動。

---

## ⌨️ 預設熱鍵與操作

- **預設呼叫選單熱鍵**：`Ctrl + Win + Z` (`^#z`)
- **呼叫選單後**：
  - 點擊「📌 記住當前焦點視窗位置」以儲存目前選中的視窗。
  - 點擊「⚙️ 設定」開啟設定視窗（自訂熱鍵、管理視窗紀錄、匯入匯出）。
  - 點擊清單中的視窗名稱即可立即將該視窗移動至記憶位置。

---

## 📄 授權條款

本專案採用 [MIT License](LICENSE) 授權。
