# Rust JSON 操作介面

v793 起，執行期 JSON 處理由 `speednative speedscan json` 負責，僅提供固定操作，不接受任意查詢表達式。Shell 的 `_json_cmd` 使用既有 speedscan 路徑解析；Dex 仍負責 Android framework 存取。

介面：`speednative speedscan json [選項] 操作 [輸入檔案 ...]`。沒有輸入檔案或指定 `-` 時讀取 stdin。

- `-r`：字串直接輸出，其他值仍輸出 JSON。
- `-c`：緊湊 JSON；預設為兩格縮排。
- `-s`：收集輸入文件後交給合併、差異及摘要操作。
- `-e`：最後輸出為 true／非 null 非 false 值時回傳 0，false／null 回傳 1，沒有輸出回傳 4。
- `--arg 名稱 值`：傳入固定操作所需的字串參數。

輸入可以包含多筆 JSON 文件。會先解析完整輸入，再輸出結果，避免損壞的後續文件留下部分結果。IO／參數錯誤回傳 2；JSON 解析或操作型態錯誤回傳 5。一般操作成功回傳 0，即使其選取結果為空。

主要操作群組：

| 操作 | 用途 |
|---|---|
| `identity`、`length`、`merge` | 驗證、長度及遞迴物件合併 |
| `metadata-identity`、`metadata-valid`、`metadata-summary` | 一次取得版本與套件名稱、一次檢查 metadata、讀取摘要 |
| `set-field`、`set-payload`、`set-payload-path`、`set-apk` | 固定欄位更新，保留未修改欄位 |
| `ad_*`、`entry-field`、`entry-has`、`payload-summary` | 既有 metadata 規則 |
| `state-v2`、`state-migrate`、`state-diff` | AppState 欄位補齊、舊格式轉換、備份差異 |
| `snapshot-*`、`foreground-*`、`home-*`、`ime-*` | Dex JSON／NDJSON 結果解析 |
| `caps-*`、`device-*`、`inventory-schema` | 固定能力契約與診斷 |
| `webdav-contract`、`release-*`、`soc-info` | WebDAV、更新 API 與處理器資訊 |
| `protected-signature`、`entry-packages`、`media-*` | JSON 重建保護欄位與媒體清單 |

實作在 `rust/src/json_ops.rs`、`json_legacy.rs`、`json_caps.rs`，共用 `profile.rs` 的有序 JSON 值模型與既有嚴格解析器。數字原文、物件欄位順序、null 與 false 均保留；數值相等比較避免將大型整數轉成浮點數。固定 capability 清單保留各消費端原有要求。

最終檔案替換仍由 Shell 的暫存檔、驗證與 `_json_cat_replace` 處理，沿用 FUSE／掛載相容行為。新操作需要加入明確 Rust 分支與對應測試，不應引入執行期任意表達式求值。

升級須配套更新 `tools.sh`、`speednative`、`dex_check.sh`。日後交付以乾淨整包為準，僅包含目前源碼、建置輸入與必要執行檔。

JSON 歸併耗時日誌使用 `jsonMs` 與 `reduceJsonMs`。對應 schema 為 `speedbackup.appstate_snapshot_reduce_onepass.v4` 與 `speedbackup.appstate_prescan_wrapper_timing.v8`；解析日誌的外部工具須按 schema 讀取欄位。

## v795 批次修改契約

`speedscan json --arg edits JOURNAL edit-batch FILE` 一次解析 metadata，依序套用固定修改後才輸出結果。journal 每筆由十進位參數數量及該筆參數組成，各欄位以 NUL 結尾；參數支援 `--arg NAME VALUE`，不執行 Shell 或任意查詢語言。允許的操作為 `set-field`、`set-payload`、`set-payload-path`、`set-apk`、`ensure-package`、`sync-package`。截斷、未知操作或不合法參數會使整批失敗，沒有部分 JSON 輸出。

Shell 只在逐 App 資料備份階段收集修改；同檔原生讀取前的屏障及階段結束會提交，後續發布沿用既有檔案替換驗證。失敗保留原檔並停止本輪，journal 不跨備份輪次重用。

## 核驗與通訊傳輸

`speedscan payload-presence MODE EXPECTED REMOTE RECEIPTS ROOT v1 EXT` 的 MODE 為 `local`、`remote` 或 `restore`；EXT 為 `.tar` 或 `.tar.zst`。EXPECTED 是不帶封裝副檔名的相對路徑，REMOTE 與 RECEIPTS 是帶副檔名的路徑清單，均使用 LF。`-` 表示空清單。輸出缺失路徑，格式或 I/O 錯誤回傳非零。local 模式接受本地檔案，或同時存在於成功收據及新遠端清單的檔案。集合規則實作位於 `rust/src/workflow.rs`。

`speedscan frame-stream` 將 stdin 轉為有界資料塊：四位元組大端長度、最多 65536 位元組內容，零長度結束。TelephonyUtil 的 `restore-session` 消費兩個資料流；先驗證第一份封裝及附件雜湊，才處理第二份的合併匯入。維持兩次下載及既有不可變 generation 索引，不暫存整份封裝，不省略任何驗證。非主用戶的事前 Provider 探測保留獨立呼叫。

v795 需配套更新 `tools.sh`、`speednative`、`classes.dex` 及 `dex_check.sh`。
