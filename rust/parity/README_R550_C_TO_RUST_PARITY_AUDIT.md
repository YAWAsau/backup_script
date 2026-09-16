# SpeedBackup r550 honest C → Rust parity audit

r550 禁止把空 stub 或 regex 命中當成完成。此 audit 會排除 `r*_c_parity_symbols_*` 類 synthetic module，並額外列出空函式。

## r550 dead-code cleanup / no-multicall 判定

- 本輪以 v25/r544 Rust source 為基準；不改 CLI/schema/capability，不做 multicall binary，不改 8 支同名工具模型。
- `Cargo.toml` release profile 保留：`opt-level = "z"`、`lto = true`、`codegen-units = 1`、`panic = "abort"`、`strip = "symbols"`。
- `build_android_ndk_r28c.sh` 保留 Android NDK `llvm-strip --strip-all`。
- Rust 清理只移除全文零引用的共用 helper/FFI declaration；不移除各 bin 內為 C parity 保留的專用 helper。
- tools.sh 只移除 `if false` 永久不可達的 Media/app_details.json 舊逐檔下載分支；不做高風險函式大刪。
- 未發現新的 command-level 或 marker-level 缺口；未發現 empty stub / TODO / unimplemented 類假遷移。
- `missing_funcs` 保留為 function-name inventory，不等同漏遷移；不可為了歸零補空 wrapper。
- 本環境沒有 cargo/Android NDK；r550 需使用者端重新編譯確認。


