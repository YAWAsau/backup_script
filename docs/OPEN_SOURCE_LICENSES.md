# 開源許可清單

「功能 → 開源許可」使用 Rust 內嵌的 `rust/src/open_source_licenses.json`。受保護的 `/api/licenses` 提供資料；APK 使用 Compose 原生卡片顯示，外部瀏覽器開啟項目網址。一般瀏覽器使用相同資料。

v1033 共 156 筆：134 個實際解析的 Maven 模組，以及 22 筆來源引用、設計參照與原生工具。涵蓋 APK/WebUI、Dex 的直接及間接依賴，編譯／註解處理項目另外標示。Rust 目前沒有外部 Cargo 套件，標準函式庫單獨列出。設計參照不代表將對方完整程式庫打包。

原有 cmd/keycheck 未附原作者與授權資料，介面明確標示「未記錄」，並連到本專案的分發來源。部分原生工具未保留版本資訊，不能將這些條目視為已補齊上游來源。現有授權原文與 NOTICE 仍保留於原有路徑；此清單不取代它們。

## 更新依賴

1. 使用各專案原有 JDK／Android SDK，分別在 `webview` 與 `dex` 執行 Gradle：`gradlew -I <絕對路徑>/ci/export_licenses.gradle exportLicenseCoordinates -PcatalogOut=<絕對輸出路徑>`。Dex 在非 ASCII 路徑仍須 `-Pandroid.overridePathCheck=true`。
2. 執行 `python ci/generate_licenses.py --import-metadata <webview輸出.json> <dex輸出.json>`，從實際解析模組與 POM 產生 `third_party/licenses/resolved.json`。匯出暫存含本機 POM 路徑，不加入發行包。
3. 檢查新增項目的作者、版本、授權與 HTTPS 項目網址；原始碼引用與原生工具更新 `third_party/licenses/references.json`，再執行 `python ci/generate_licenses.py`。
4. 執行 `python ci/generate_licenses.py --check`、完整建置與倉庫檢查。依賴宣告的 SHA-256 若改變，建置會要求重新匯出，避免清單悄悄過期。

來源快照與產生器隨乾淨原始碼包交付。執行時不需連線下載許可清單。
