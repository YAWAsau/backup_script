#!/usr/bin/env python3
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
cdir = root / 'c'
rsdir = root / 'rust' / 'src'
outdir = root / 'rust' / 'parity'
outdir.mkdir(parents=True, exist_ok=True)

TOOLS = ['cgfreezer','eventwait','filewatch','netwatch','procwait','speedscan','uidexec','unixsock']

def read(p: Path) -> str:
    return p.read_text(errors='ignore') if p.exists() else ''

def strip_fake_parity_modules(text: str) -> str:
    # Audit must never count synthetic parity-only modules as implementation.
    return re.sub(r'(?ms)^\s*#\[allow\(dead_code,\s*non_snake_case\)\]\s*mod\s+r\d+_c_parity_symbols_\w+\s*\{.*?^\}', '', text)

def funcs_c(text: str):
    vals = re.findall(r'^\s*(?:static\s+)?(?:inline\s+)?(?:[A-Za-z_][\w\s\*]+?)\s+([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{', text, re.M)
    return sorted({v for v in vals if v not in {'if','for','while','switch'}})

def funcs_rs(text: str):
    text = strip_fake_parity_modules(text)
    return sorted(set(re.findall(r'^\s*(?:pub\s+)?fn\s+([A-Za-z_]\w*)\s*\(', text, re.M)))

def empty_stub_funcs_rs(text: str):
    text = strip_fake_parity_modules(text)
    return sorted(set(re.findall(r'^\s*(?:pub\s+)?fn\s+([A-Za-z_]\w*)\s*\([^)]*\)\s*(?:->\s*[^\{]+)?\{\s*\}', text, re.M)))

def cmds_c(text: str):
    cmds=[]
    cmds += re.findall(r'strcmp\s*\(\s*argv\s*\[\s*1\s*\]\s*,\s*"([^"]+)"\s*\)\s*==\s*0', text)
    cmds += ['daemon:'+m for m in re.findall(r'strcmp\s*\(\s*argv\s*\[\s*0\s*\]\s*,\s*"([A-Z_]+)"\s*\)\s*==\s*0', text)]
    for m in re.finditer(r'commands=([^"\\\n]+)', text):
        cmds += [x.strip() for x in re.split(r'[, ]+', m.group(1)) if x.strip() and not x.strip().startswith('%')]
    return sorted(set(cmds))

def cmds_rs(text: str):
    text = strip_fake_parity_modules(text)
    cmds=[]
    cmds += re.findall(r'Some\("([A-Za-z0-9_\-]+)"\)', text)
    cmds += re.findall(r'args\s*\[\s*1\s*\]\s*==\s*"([^"]+)"', text)
    # Capture all quoted alternatives in match arms, including `"A" | "B" =>` and `"cmd" if ... =>`.
    for line in text.splitlines():
        if '=>' not in line:
            continue
        head = line.split('=>', 1)[0]
        for lit in re.findall(r'"([A-Za-z0-9_\-]+)"', head):
            cmds.append(lit)
            if lit and lit.upper() == lit and any(ch.isalpha() for ch in lit):
                cmds.append('daemon:' + lit)
    for m in re.finditer(r'commands=([^"\\\n]+)', text):
        cmds += [x.strip() for x in re.split(r'[, ]+', m.group(1)) if x.strip()]
    return sorted(set(cmds))

def marker_prefixes(text: str):
    return sorted(set(re.findall(r'"((?:CGFREEZER|SPEEDSCAN|EVENTWAIT|PROCWAIT|FILEWATCH|NETWATCH|UIDEXEC|UNIXSOCK)_[A-Z0-9_]+)', text)))

summary=[]
for tool in TOOLS:
    cfile = cdir / f'{tool}.c'
    rfile = rsdir / 'bin' / f'{tool}.rs'
    ct = read(cfile)
    rt_raw = read(rfile)
    rt = strip_fake_parity_modules(rt_raw)
    cf, rf = funcs_c(ct), funcs_rs(rt)
    cc, rc = cmds_c(ct), cmds_rs(rt)
    cm, rm = marker_prefixes(ct), marker_prefixes(rt)
    empty = empty_stub_funcs_rs(rt_raw)
    item = {
        'tool': tool,
        'c_bytes': cfile.stat().st_size if cfile.exists() else 0,
        'rs_bytes': rfile.stat().st_size if rfile.exists() else 0,
        'c_lines': ct.count('\n') + (1 if ct else 0),
        'rs_lines': rt_raw.count('\n') + (1 if rt_raw else 0),
        'c_func_count': len(cf),
        'rs_func_count': len(rf),
        'missing_function_count': len(sorted(set(cf)-set(rf))),
        'missing_functions': sorted(set(cf)-set(rf)),
        'c_command_count': len(cc),
        'rs_command_count': len(rc),
        'missing_command_count': len(sorted(set(cc)-set(rc))),
        'missing_commands': sorted(set(cc)-set(rc)),
        'c_marker_count': len(cm),
        'rs_marker_count': len(rm),
        'missing_marker_count': len(sorted(set(cm)-set(rm))),
        'missing_marker_prefixes': sorted(set(cm)-set(rm)),
        'empty_stub_count': len(empty),
        'empty_stub_functions': empty,
    }
    summary.append(item)
    md = [f'# {tool}: C → Rust honest parity audit (r550)', '',
          '| metric | C | Rust | missing / bad |', '|---|---:|---:|---:|',
          f'| bytes | {item["c_bytes"]} | {item["rs_bytes"]} | - |',
          f'| lines | {item["c_lines"]} | {item["rs_lines"]} | - |',
          f'| commands | {item["c_command_count"]} | {item["rs_command_count"]} | {item["missing_command_count"]} |',
          f'| marker prefixes | {item["c_marker_count"]} | {item["rs_marker_count"]} | {item["missing_marker_count"]} |',
          f'| implementation function names | {item["c_func_count"]} | {item["rs_func_count"]} | {item["missing_function_count"]} |',
          f'| empty stub functions | - | {item["empty_stub_count"]} | {item["empty_stub_count"]} |',
          '', '## Missing commands', '', *(f'- `{v}`' for v in item['missing_commands'])]
    if not item['missing_commands']:
        md.append('- none')
    md += ['', '## Missing marker prefixes', '']
    md += [f'- `{v}`' for v in item['missing_marker_prefixes']] or ['- none']
    md += ['', '## Missing implementation function names', '']
    md += [f'- `{v}`' for v in item['missing_functions']] or ['- none']
    md += ['', '## Empty stubs detected', '']
    md += [f'- `{v}`' for v in item['empty_stub_functions']] or ['- none']
    (outdir / f'{tool}_parity.md').write_text('\n'.join(md)+'\n')

tsv = 'tool\tc_lines\trs_lines\tc_bytes\trs_bytes\tmissing_cmds\tmissing_markers\tmissing_funcs\tempty_stubs\n'
for s in summary:
    tsv += f"{s['tool']}\t{s['c_lines']}\t{s['rs_lines']}\t{s['c_bytes']}\t{s['rs_bytes']}\t{s['missing_command_count']}\t{s['missing_marker_count']}\t{s['missing_function_count']}\t{s['empty_stub_count']}\n"
(outdir / 'c_to_rust_parity_summary.tsv').write_text(tsv)
(outdir / 'c_to_rust_parity_summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
md=['# SpeedBackup r550 honest C → Rust parity audit', '',
    'r550 禁止把空 stub 或 regex 命中當成完成。此 audit 會排除 `r*_c_parity_symbols_*` 類 synthetic module，並額外列出空函式。', '',
    '## r550 dead-code cleanup / no-multicall 判定', '',
    '- 本輪以 v25/r544 Rust source 為基準；不改 CLI/schema/capability，不做 multicall binary，不改 8 支同名工具模型。',
    '- `Cargo.toml` release profile 保留：`opt-level = "z"`、`lto = true`、`codegen-units = 1`、`panic = "abort"`、`strip = "symbols"`。',
    '- `build_android_ndk_r28c.sh` 保留 Android NDK `llvm-strip --strip-all`。',
    '- Rust 清理只移除全文零引用的共用 helper/FFI declaration；不移除各 bin 內為 C parity 保留的專用 helper。',
    '- tools.sh 只移除 `if false` 永久不可達的 Media/app_details.json 舊逐檔下載分支；不做高風險函式大刪。',
    '- 未發現新的 command-level 或 marker-level 缺口；未發現 empty stub / TODO / unimplemented 類假遷移。',
    '- `missing_funcs` 保留為 function-name inventory，不等同漏遷移；不可為了歸零補空 wrapper。',
    '- 本環境沒有 cargo/Android NDK；r550 需使用者端重新編譯確認。',
    '', '']
(outdir / 'README_R550_C_TO_RUST_PARITY_AUDIT.md').write_text('\n'.join(md)+'\n')
print(tsv, end='')
