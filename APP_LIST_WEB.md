# 原生 APK 操作介面

v1079 將隱藏 WebView 與 JavaScript 操作層移除。APK 使用 Kotlin／Compose 呈現清單、設定、檔案選擇、主選單、授權頁與日誌，透過帶有工作權杖的本機 Rust API 交換資料。Rust 不再提供 HTML、CSS 或 JavaScript 頁面；瀏覽器不再是操作入口。

Rust 保留工作所有權、清單與設定檔快照核對、原子儲存、備份／恢復執行與停止。APK 保留未提交選擇、設定草稿、分頁及各畫面捲動位置；原工作接回不重新啟動備份。Java／Dex 仍負責 Android 系統能力與根權限橋接。

`webview/` 來源目錄、Android 套件名稱、既有 Binder 協定及 `applist-web`、`menu-web`、`console-web` 等命令名稱為升級相容識別，不代表仍包含 WebView 或瀏覽器介面。不要直接更名，否則可能破壞既有工作接回與 APK 簽章升級。

原生 HTTP 傳輸只接受 127.0.0.1、拒絕代理與重新導向，限制請求及回應大小。敏感輸入的本機接續狀態以 Android Keystore 加密，正常完成後清除。診斷事件不含帳號、路徑、權杖或輸入內容；錯誤與正常事件分流，沿用 speed_debug 蒐集流程。

建置方式見 BUILDING.md。發布前必須完成協定／草稿／衝突／停止／接回測試、備用機驗證與獨立審查；本文件不構成測試通過聲明。
