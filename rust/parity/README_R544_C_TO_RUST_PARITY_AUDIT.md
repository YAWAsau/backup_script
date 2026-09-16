# SpeedBackup r544 honest C → Rust parity audit

r544 禁止把空 stub 或 regex 命中當成完成。此 audit 會排除 `r*_c_parity_symbols_*` 類 synthetic module，並額外列出空函式。

## r544 size optimize / no-multicall 判定

- 本輪以 v23/r542 source 為基準，做 Rust binary size optimize；明確不做 multicall binary，不改 8 支同名工具模型。
- `Cargo.toml` release profile 保留/確認：`opt-level = "z"`、`lto = true`、`codegen-units = 1`、`panic = "abort"`、`strip = "symbols"`。
- `build_android_ndk_r28c.sh` 在複製 release binary 後追加 Android NDK `llvm-strip --strip-all`，讓遠端編譯產物實際剝離 symbols。
- 清理使用者真機 cargo build 回報的 unused import / unused mut / 明確 dead helper，但不新增 Rust-only CLI/schema/capability，也不修改 `tools.sh` 或 `c/` reference。
- 未發現新的 command-level 或 marker-level 缺口；未發現 empty stub / TODO / unimplemented 類假遷移。
- `missing_funcs` 保留為 function-name inventory，不等同漏遷移；不可為了歸零補空 wrapper。
- 本輪屬 size/metadata/cleanup 收斂版；使用者已完成 v23/r542 Android arm64 release 編譯與基礎 smoke，本環境仍只跑 source-level 檢查。


