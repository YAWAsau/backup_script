# SpeedBackup r534 honest C → Rust parity audit

r534 禁止把空 stub 或 regex 命中當成完成。此 audit 會排除 `r*_c_parity_symbols_*` 類 synthetic module，並額外列出空函式。

| tool | C lines | Rust lines | C bytes | Rust bytes | missing cmds | missing markers | missing funcs | empty stubs |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| cgfreezer | 2874 | 2694 | 126231 | 132012 | 0 | 0 | 41 | 0 |
| eventwait | 1036 | 610 | 39137 | 29697 | 0 | 0 | 22 | 0 |
| filewatch | 205 | 357 | 7973 | 12898 | 0 | 0 | 1 | 0 |
| netwatch | 367 | 360 | 10261 | 12808 | 0 | 0 | 3 | 0 |
| procwait | 348 | 382 | 10740 | 13620 | 0 | 0 | 3 | 0 |
| speedscan | 2182 | 1119 | 90641 | 63592 | 0 | 0 | 49 | 0 |
| uidexec | 242 | 243 | 6273 | 8227 | 0 | 0 | 0 | 0 |
| unixsock | 479 | 455 | 15677 | 16886 | 0 | 0 | 8 | 0 |

## r534 判定

- r534 以 speedbackup_native_rust_handoff_v10.zip 為基準做新一輪逐字 C-source audit 修正：補 speedscan label-audit/backup-root-index/backup-prescan-summary/manifest-verify/run-tmpdir-facts/zst-file-facts 與 open-failure strerror 差異，補 eventwait pid-file comment skip，補 cgfreezer oom_score_adj/daemon THAW_UID/SUBSCRIBE 差異，並補 unixsock response body/chunk parser 的 C strtoll/strtoull 語意。
- `missing_commands=0` / `missing_markers=0` 只表示公開命令與 marker prefix 沒缺；`missing_functions` 仍需搭配實跑 diff 判讀，不可單獨宣稱 runtime 等價。
- `empty_stubs` 必須保持 0；若非 0，代表又回到假 parity。
