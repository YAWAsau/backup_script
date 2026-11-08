//! One-session loopback list editor. No shell execution from HTTP input.
#[path = "lan_discovery.rs"]
pub(crate) mod lan_discovery;
#[path = "selection_flow.rs"]
mod selection_flow;
#[path = "selection_plan.rs"]
mod selection_plan;
#[path = "timeline_options.rs"]
mod timeline_options;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, File, Metadata, OpenOptions},
    io::{self, Read, Write},
    net::{TcpListener, TcpStream},
    os::{
        fd::AsRawFd,
        unix::fs::{MetadataExt, OpenOptionsExt},
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, Instant},
};
#[path = "web_language_map.rs"]
mod terminal_language_map;
pub(super) fn terminal_text(text: &str) -> String {
    let lang = std::env::var("SCRIPT_LANG").unwrap_or_default();
    let simplified = match lang.as_str() {
        "CN" | "cn" => true,
        "TW" | "tw" => false,
        _ => matches!(web_language(None).as_deref(), Ok("zh-Hans")),
    };
    if simplified { text.chars().map(terminal_language_map::simplify).collect() } else { text.to_owned() }
}
macro_rules! terminal_println { ($($arg:tt)*) => { println!("{}", terminal_text(&format!($($arg)*))) }; }
macro_rules! terminal_eprintln { ($($arg:tt)*) => { eprintln!("{}", terminal_text(&format!($($arg)*))) }; }
const LIMIT: usize = 4 * 1024 * 1024;
// Read-only, token-authenticated picker. Never execute a path as a command.
fn picker_directory(base: &Path, value: &str) -> io::Result<PathBuf> {
    if value.len() > 4096 || value.chars().any(|c| c.is_control()) {
        return Err(err("路徑含不支援的字元或過長"));
    }
    let p = if value.is_empty() { base.to_path_buf() } else if Path::new(value).is_absolute() {
        PathBuf::from(value)
    } else { base.join(value) };
    let mut p = fs::canonicalize(p)?;
    if ["/proc", "/sys", "/dev"].iter().any(|root| p.starts_with(root)) {
        return Err(err("此系統虛擬目錄不提供瀏覽"));
    }
    if p.is_file() { p.pop(); }
    if !p.is_dir() { return Err(err("不是可瀏覽的資料夾")); }
    Ok(p)
}
fn picker_listing(base: &Path, value: &str, offset: usize) -> io::Result<String> {
    if offset > 100_000 { return Err(err("目錄項目過多，請輸入更精確的路徑")); }
    let dir = picker_directory(base, value)?;
    let mut entries = fs::read_dir(&dir)?.skip(offset);
    let mut rows = Vec::new();
    let mut consumed = 0;
    let mut more = true;
    // Bounded response and per-page work; no recursion, file reads or icon extraction.
    while consumed < 200 {
        let Some(entry) = entries.next() else { more = false; break; };
        consumed += 1;
        let entry = entry?;
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue; };
        if name.chars().any(|c| c.is_control()) { continue; }
        let kind = entry.file_type()?;
        // Do not follow arbitrary symlinks or device nodes while enumerating.
        if !kind.is_dir() && !kind.is_file() { continue; }
        let path = entry.path();
        let Some(path) = path.to_str() else { continue; };
        rows.push((!kind.is_dir(), name.to_owned(), format!("{{\"name\":{},\"path\":{},\"directory\":{}}}", json(name), json(path), kind.is_dir())));
    }
    rows.sort_by(|a,b| (&a.0,&a.1).cmp(&(&b.0,&b.1)));
    let path = dir.to_str().ok_or_else(|| err("路徑編碼不支援"))?;
    let parent = dir.parent().and_then(Path::to_str).unwrap_or(path);
    Ok(format!("{{\"path\":{},\"parent\":{},\"next\":{},\"entries\":[{}]}}", json(path), json(parent),
        if more { (offset + consumed).to_string() } else { "null".into() },
        rows.into_iter().map(|v|v.2).collect::<Vec<_>>().join(",")))
}
pub(super) fn err(s: &str) -> io::Error {
    io::Error::other(s)
}
fn random_hex() -> io::Result<String> {
    let mut bytes = [0u8; 32];
    File::open("/dev/urandom")?.read_exact(&mut bytes)?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}
fn stamp(m: &Metadata) -> (u64, u64, u64, i64, i64, i64, i64) {
    (
        m.dev(),
        m.ino(),
        m.len(),
        m.mtime(),
        m.mtime_nsec(),
        m.ctime(),
        m.ctime_nsec(),
    )
}
fn open(p: &Path) -> io::Result<File> {
    let f = OpenOptions::new()
        .read(true)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE | speedbackup_native_rs::O_NONBLOCK)
        .open(p)?;
    if !f.metadata()?.is_file() {
        return Err(err("需要一般檔案"));
    }
    Ok(f)
}
pub(super) fn open_icon_file(p:&Path)->io::Result<File>{open(p)}
fn read(p: &Path) -> io::Result<(String, Metadata)> {
    // Shared-storage metadata can settle just after creation. Retry bounded
    // read-only snapshots; never relax the final saved snapshot comparison.
    for _ in 0..5 {
        let mut f = open(p)?;
        let before = f.metadata()?;
        if before.len() > LIMIT as u64 {
            return Err(err("清單過大"));
        }
        let mut bytes = Vec::new();
        Read::by_ref(&mut f)
            .take((LIMIT + 1) as u64)
            .read_to_end(&mut bytes)?;
        if bytes.len() > LIMIT || bytes.contains(&0) {
            return Err(err("清單格式不支援"));
        }
        let after = f.metadata()?;
        let visible = fs::symlink_metadata(p)?;
        if visible.is_file()
            && stamp(&before) == stamp(&after)
            && stamp(&after) == stamp(&visible)
            && bytes.len() as u64 == after.len()
        {
            return Ok((
                String::from_utf8(bytes).map_err(|_| err("清單必須是 UTF-8"))?,
                after,
            ));
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    Err(err("清單仍在變更，請稍後重試"))
}

fn package(s: &str) -> bool {
    s.len() <= 255
        && s.contains('.')
        && s.as_bytes().first().is_some_and(u8::is_ascii_alphabetic)
        && s.split('.')
            .all(|v| !v.is_empty() && v.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_'))
}
struct Row {
    line: usize,
    pkg: String,
    label: String,
    enabled: bool,
    data_only: bool,
    prefix: usize,
    marker: usize,
    apk_start: usize,
}
fn raw_rows(text: &str) -> io::Result<Vec<Row>> {
    if text.starts_with('\u{feff}') {
        return Err(err("清單含 UTF-8 BOM，請先以無 BOM 的 UTF-8 儲存"));
    }
    let mut rows = Vec::new();
    for (line, raw) in text.split_inclusive('\n').enumerate() {
        let trimmed = raw.trim_start_matches([' ', '\t']);
        let prefix = raw.len() - trimmed.len();
        let disabled = trimmed.starts_with(['#', '＃']);
        let marker = if disabled {
            trimmed.chars().next().unwrap().len_utf8()
        } else {
            0
        };
        let body = trimmed[marker..].trim_start_matches([' ', '\t']);
        let apk = body.starts_with(['!', '！']);
        let labelbody = if apk {
            &body[body.chars().next().unwrap().len_utf8()..]
        } else {
            body
        };
        let fields: Vec<_> = labelbody
            .trim_end_matches(['\r', '\n'])
            .split([' ', '\t'])
            .filter(|s| !s.is_empty())
            .collect();
        if fields.len() != 2 || !package(fields[1]) || fields[0].starts_with(['#', '＃', '!', '！'])
        {
            if !disabled && !trimmed.trim().is_empty() {
                return Err(err("有無法辨識的有效行，請先用文字編輯修正"));
            }
            continue;
        }
        if fields[1] == crate::applist::HOST_PACKAGE { continue; }
        // The production backup loop separates fields on one ASCII space.
        // Leading/trailing whitespace is stripped by its installed-list filter;
        // ! and full-width ! must remain attached to the label token.
        let canonical = format!(
            "{}{} {}",
            if apk {
                &body[..body.chars().next().unwrap().len_utf8()]
            } else {
                ""
            },
            fields[0],
            fields[1]
        );
        if body.trim_end_matches([' ', '\t', '\r', '\n']) != canonical {
            return Err(err(&format!(
                "第 {} 行不是標準「名稱 包名」格式，請先用文字編輯修正",
                line + 1
            )));
        }
        rows.push(Row {
            line,
            pkg: fields[1].into(),
            label: fields[0].into(),
            enabled: !disabled,
            data_only: apk,
            prefix,
            marker,
            apk_start: prefix + marker + trimmed[marker..].len() - body.len(),
        });
    }
    Ok(rows)
}
// Legacy lists can contain one disabled historical row plus the identical
// active row. Backup already uses the active row; preserve that effective state.
fn rows(text:&str)->io::Result<Vec<Row>> {
    let mut unique:BTreeMap<String,Row>=BTreeMap::new();
    for row in raw_rows(text)? {
        if let Some(old)=unique.get(&row.pkg) {
            if old.enabled==row.enabled || old.label!=row.label || old.data_only!=row.data_only {
                return Err(err("有衝突的重複套件，請先用文字編輯確認"));
            }
            if !row.enabled {continue;}
        }
        unique.insert(row.pkg.clone(),row);
    }
    let mut result:Vec<_>=unique.into_values().collect();
    result.sort_by_key(|row|row.line);
    Ok(result)
}
fn selection_rows(text:&str,kind:&str)->io::Result<Vec<Row>> {
    if kind=="remote-delete" {
        let mut out=Vec::new();
        for (line,raw) in text.split_inclusive('\n').enumerate() {
            let raw=raw.strip_suffix('\n').unwrap_or(raw);
            let disabled=raw.starts_with('#');
            let label=if disabled {&raw[1..]} else {raw};
            let prefix=format!("{}. ",line+1);
            if !label.starts_with(&prefix) || label.len()<=prefix.len() || label.chars().any(char::is_control) {
                return Err(err("刪除清單格式無效，未刪除任何備份"));
            }
            out.push(Row{line,pkg:format!("row-{line}"),label:label.into(),enabled:!disabled,data_only:false,prefix:0,marker:usize::from(disabled),apk_start:0});
        }
        return Ok(out);
    }

    if text.starts_with('\u{feff}') {return Err(err("清單含 BOM，請先轉為 UTF-8 無 BOM"));}
    let mut out=Vec::new();let mut seen=BTreeSet::new();
    for (line,raw) in text.split_inclusive('\n').enumerate(){
        let trimmed=raw.trim_start_matches([' ','\t']);let prefix=raw.len()-trimmed.len();
        let disabled=trimmed.starts_with(['#','＃']);let marker=if disabled {trimmed.chars().next().unwrap().len_utf8()} else {0};
        let rest=&trimmed[marker..];let body=rest.trim();
        if body.is_empty(){continue;}
        let name=body.split(" #").next().unwrap().trim_end();
        let telephony=matches!(name,"@telephony:messages"|"@telephony:calls");
        // Generated prose begins '# '; uncommented records and '#record' remain selectable.
        if disabled && rest.starts_with([' ','\t']) && !telephony {continue;}
        let safe=!name.is_empty() && name.len()<=1024 && !name.chars().any(|c|c.is_control()||matches!(c,'/'|'\\'|'#'|'＃')) && !matches!(name,"."|"..");
        let archive=[".tar",".tar.zst",".tar.gz",".tar.bz2",".tar.xz",".tar.lz4",".tar.lzma",".tar.lzo"].iter().any(|ext|name.ends_with(ext));
        let valid=safe && if kind=="media" {archive} else {telephony||(!name.contains(':')&&!name.starts_with('@'))};
        if !valid {if disabled {continue;}return Err(err("清單包含不支援的有效項目，未修改原檔"));}
        if !seen.insert(name.to_string()){return Err(err("清單有重複項目，請先確認原檔"));}
        out.push(Row{line,pkg:format!("row-{line}"),label:name.into(),enabled:!disabled,data_only:false,prefix,marker,apk_start:0});
    }
    Ok(out)
}

pub(super) fn json(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c < ' ' => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn edit(original: &str, rows: &[Row], body: &str, selection: Option<&str>) -> io::Result<String> {
    let mut states = BTreeMap::new();
    for line in body.lines() {
        let fields: Vec<_> = line.split('\t').collect();
        if fields.len() != 3 || !matches!(fields[1], "0" | "1") || !matches!(fields[2], "0" | "1") {
            return Err(err("選擇格式錯誤"));
        }
        let pkg = fields[0];
        if states
            .insert(pkg, (fields[1] == "1", fields[2] == "1"))
            .is_some()
        {
            return Err(err("選擇重複或無效"));
        }
    }
    if states.len() != rows.len() || rows.iter().any(|r| !states.contains_key(r.pkg.as_str())) {
        return Err(err("選擇清單不完整或套件不符"));
    }
    let changes: BTreeMap<_, _> = rows.iter().map(|r| (r.line, r)).collect();
    let mut output = String::new();
    let mut removed_host_lines = Vec::new();
    let redundant:BTreeSet<usize>=if selection.is_none() {
        let kept:BTreeSet<_>=rows.iter().map(|r|r.line).collect();
        raw_rows(original)?.into_iter().filter(|r|!kept.contains(&r.line)).map(|r|r.line).collect()
    } else {BTreeSet::new()};
    for (i, line) in original.split_inclusive('\n').enumerate() {
        if redundant.contains(&i) || (selection.is_none() && line.split_whitespace().last() == Some(crate::applist::HOST_PACKAGE)) { removed_host_lines.push(i); continue; }
        if let Some(r) = changes.get(&i) {
            let (selected, apk) = states[r.pkg.as_str()];
            if selected != r.enabled || apk != r.data_only {
                let mut changed = line.to_string();
                // Edit the later APK marker first, so the earlier comment offset remains valid.
                if apk != r.data_only {
                    if apk {
                        changed.insert(r.apk_start, '!');
                    } else {
                        let width = changed[r.apk_start..].chars().next().unwrap().len_utf8();
                        changed.replace_range(r.apk_start..r.apk_start + width, "");
                    }
                }
                if selected != r.enabled {
                    if selected {
                        changed.replace_range(r.prefix..r.prefix + r.marker, "");
                    } else {
                        changed.insert(r.prefix, '#');
                    }
                }
                output.push_str(&changed);
            } else {
                output.push_str(line);
            }
        } else {
            output.push_str(line);
        }
    }

    let verified = match selection { Some(kind)=>selection_rows(&output,kind)?,None=>self::rows(&output)? };
    if verified.len() != rows.len()
        || verified.iter().zip(rows).any(|(a, b)| {
            a.pkg != b.pkg
                || a.label != b.label
                || a.data_only != states[b.pkg.as_str()].1
                || a.line != b.line - removed_host_lines.iter().filter(|&&line| line < b.line).count()
                || a.enabled != states[b.pkg.as_str()].0
        })
    {
        return Err(err("輸出清單驗證不符，未儲存"));
    }
    Ok(output)
}
struct Request {
    method: String,
    path: String,
    headers: BTreeMap<String, String>,
    body: String,
}
fn request(stream: &mut TcpStream) -> io::Result<Request> {
    let result=request_inner(stream);
    if let Err(e)=&result {ui_transport_error("http-read", &format!("kind={:?} errno={:?}",e.kind(),e.raw_os_error()));}
    result
}
fn request_inner(stream: &mut TcpStream) -> io::Result<Request> {
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.set_write_timeout(Some(Duration::from_secs(2)))?;
    let deadline = Instant::now() + Duration::from_secs(3);
    let mut raw = Vec::new();
    let mut one = [0u8; 1];
    while !raw.ends_with(b"\r\n\r\n") {
        if raw.len() >= 8192 || Instant::now() > deadline {
            return Err(err("header limit"));
        }
        stream.read_exact(&mut one)?;
        raw.push(one[0]);
    }
    let header = std::str::from_utf8(&raw).map_err(|_| err("header encoding"))?;
    let mut lines = header.split("\r\n");
    let parts: Vec<_> = lines.next().unwrap_or("").split(' ').collect();
    if parts.len() != 3 || parts[2] != "HTTP/1.1" {
        return Err(err("HTTP/1.1 required"));
    }
    let mut headers = BTreeMap::new();
    for line in lines.filter(|l| !l.is_empty()) {
        let Some((k, v)) = line.split_once(':') else {
            return Err(err("header"));
        };
        if v.bytes().any(|c| c < 32 && c != b'\t' || c == 127)
            || k.is_empty()
            || !k.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
            || headers
                .insert(k.to_ascii_lowercase(), v.trim().to_owned())
                .is_some()
        {
            return Err(err("duplicate header"));
        }
    }
    if headers.contains_key("transfer-encoding") {
        return Err(err("chunked not supported"));
    }
    let n = match headers.get("content-length") {
        Some(v) => {
            if v.is_empty() || !v.bytes().all(|c| c.is_ascii_digit()) {
                return Err(err("length"));
            }
            v.parse::<usize>().map_err(|_| err("length"))?
        }
        None => 0,
    };
    if n > LIMIT {
        return Err(err("body limit"));
    }
    let mut body = vec![0u8; n];
    let mut got = 0;
    while got < n {
        if Instant::now() > deadline {
            return Err(err("body timeout"));
        }
        let count = stream.read(&mut body[got..])?;
        if count == 0 {
            return Err(err("short body"));
        }
        got += count;
    }
    Ok(Request {
        method: parts[0].into(),
        path: parts[1].into(),
        headers,
        body: String::from_utf8(body).map_err(|_| err("body encoding"))?,
    })
}
// Never log request bodies, tokens, URLs, application names or account identities.
fn ui_record(kind: &str, stage: &str, reason: &str) {
    let reason: String = reason.chars().take(1024).map(|c| if c.is_control() {' '} else {c}).collect();
    let line = format!("{kind} stage={stage} pid={} reason={reason}",std::process::id());
    // Normal lifecycle events belong only in the private diagnostic sink.
    if kind!="WEBUI_EVENT" { eprintln!("{line}"); }
    let result=(|| -> io::Result<()> {
        let path=std::env::var("SPEEDBACKUP_UI_ERROR_LOG").map_err(|_|err("sink_unset"))?;
        if path.is_empty(){return Err(err("sink_unset"));}
        let mut file=OpenOptions::new().append(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE | speedbackup_native_rs::O_NONBLOCK).open(path).map_err(|_|err("sink_open_failed"))?;
        let meta=file.metadata().map_err(|_|err("sink_stat_failed"))?;
        if !meta.is_file()||meta.uid()!=0||meta.nlink()!=1||meta.mode()&0o077!=0{return Err(err("sink_identity_rejected"));}
        if meta.len()>=if kind=="WEBUI_EVENT"{512*1024}else{1024*1024}{return Err(err("sink_limit"));}
        writeln!(file,"{line}").map_err(|_|err("sink_write_failed"))
    })();
    if let Err(e)=result {
        static WARNED:std::sync::atomic::AtomicBool=std::sync::atomic::AtomicBool::new(false);
        if !WARNED.swap(true,std::sync::atomic::Ordering::Relaxed){eprintln!("WEBUI_LOG_UNAVAILABLE reason={e}");}
    }
}
fn ui_error(stage:&str,reason:&str){ui_record("WEBUI_ERROR",stage,reason);}
fn ui_event(stage:&str,reason:&str){ui_record("WEBUI_EVENT",stage,reason);}

// Transport diagnostics are bounded and contain no request or response content.
fn ui_transport_error(stage:&str,reason:&str) {
    static LAST:std::sync::Mutex<Option<BTreeMap<String,(Instant,u64)>>>=std::sync::Mutex::new(None);
    let key=format!("{stage}:{reason}");
    if let Ok(mut store)=LAST.lock(){
        let map=store.get_or_insert_with(BTreeMap::new);
        if let Some((last,suppressed))=map.get_mut(&key){
            if last.elapsed()<Duration::from_secs(1){*suppressed+=1;return;}
            if *suppressed>0{ui_event("diagnostic-suppressed",&format!("stage={stage} count={suppressed}"));}
            *last=Instant::now();*suppressed=0;
        }else if map.len()<64{map.insert(key,(Instant::now(),0));}
    }
    if stage=="browser-lifecycle"{ui_event(stage,reason);}else{ui_error(stage,reason);}
}
fn respond(s: &mut TcpStream, status: &str, kind: &str, body: &str) -> io::Result<()> {
    if !status.starts_with('2'){ui_transport_error("http-status",status);}
    let result=respond_inner(s,status,kind,body);
    if let Err(e)=&result{ui_transport_error("http-write",&format!("kind={:?} errno={:?}",e.kind(),e.raw_os_error()));}
    result
}
fn respond_inner(s: &mut TcpStream, status: &str, kind: &str, body: &str) -> io::Result<()> {
    write!(s,"HTTP/1.1 {status}\r\nContent-Type: {kind}; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src data:; font-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n\r\n{body}",body.len())
}
struct Session {
    parent: PathBuf,
    path: PathBuf,
    original: String,
    metadata: Metadata,
    rows: Vec<Row>,
    _dir: File,
    selection: bool,
    selection_kind: Option<String>,
}
impl Session {
    fn new(path: &Path, app_list: bool) -> io::Result<Self> {Self::new_kind(path,if app_list {Some("apps")} else {None})}
    fn new_kind(path:&Path,kind:Option<&str>)->io::Result<Self> {
        let parent = path.parent().ok_or_else(|| err("path"))?.canonicalize()?;
        let dir = OpenOptions::new()
            .read(true)
            .custom_flags(
                speedbackup_native_rs::O_NOFOLLOW_NATIVE
                    | speedbackup_native_rs::O_DIRECTORY_NATIVE,
            )
            .open(&parent)?;
        let visible = fs::symlink_metadata(&parent)?;
        let held = dir.metadata()?;
        if !visible.is_dir() || (visible.dev(), visible.ino()) != (held.dev(), held.ino()) {
            return Err(err("清單目錄已變更"));
        }
        if !dir.metadata()?.is_dir() {
            return Err(err("parent"));
        }
        let path = PathBuf::from(format!("/proc/self/fd/{}", dir.as_raw_fd()))
            .join(path.file_name().ok_or_else(|| err("filename"))?);
        let (original, metadata) = read(&path)?;
        let after = fs::symlink_metadata(&path)?;
        if stamp(&after) != stamp(&metadata) {
            return Err(err(&format!(
                "清單已變更 {:?} {:?}",
                stamp(&metadata),
                stamp(&after)
            )));
        }
        let rows=match kind {Some("apps")=>rows(&original)?,Some(k)=>selection_rows(&original,k)?,None=>{super::web_settings::parse(&original)?;Vec::new()}};
        Ok(Self {
            parent,
            path,
            original,
            metadata,
            rows,
            _dir: dir,
            selection:matches!(kind,Some("remote"|"media"|"remote-delete")),
            selection_kind:kind.filter(|k| matches!(*k,"remote"|"media"|"remote-delete")).map(str::to_owned),
        })
    }
    fn unchanged(&self) -> io::Result<()> {
        let parent = fs::symlink_metadata(&self.parent)?;
        let held = self._dir.metadata()?;
        if !parent.is_dir() || (parent.dev(), parent.ino()) != (held.dev(), held.ino()) {
            return Err(err("清單目錄已變更"));
        }
        let (text, m) = read(&self.path)?;
        // ctime alone is not an edit: Android shared-storage metadata can be
        // refreshed on resume. Keep full-content, identity, mtime and access checks.
        let before=&self.metadata;
        let access=(m.mode(),m.uid(),m.gid(),m.nlink())!=(before.mode(),before.uid(),before.gid(),before.nlink());
        let changed=text!=self.original || (m.dev(),m.ino(),m.len(),m.mtime(),m.mtime_nsec())
            !=(before.dev(),before.ino(),before.len(),before.mtime(),before.mtime_nsec()) || access;
        if changed {
            let before=&self.metadata;
            // Log only change categories; never list contents or app/account identifiers.
            let detail=format!("content={} identity={} size={} mtime={} ctime={} access={}",
                text!=self.original, (m.dev(),m.ino())!=(before.dev(),before.ino()),
                m.len()!=before.len(), (m.mtime(),m.mtime_nsec())!=(before.mtime(),before.mtime_nsec()),
                (m.ctime(),m.ctime_nsec())!=(before.ctime(),before.ctime_nsec()),access);
            ui_error("selection-conflict",&detail);
            let reason=if text!=self.original {"清單內容已被修改"}
                else if (m.dev(),m.ino())!=(before.dev(),before.ino()) {"清單檔案已被替換"}
                else {"清單檔案屬性已變更"};
            return Err(err(&format!("{reason}；未儲存，請關閉後重新開啟。")));
        }
        Ok(())
    }
    fn save(&self, body: &str) -> io::Result<()> {
        if self.selection && body.lines().any(|l|l.split('\t').nth(2)!=Some("0")){return Err(err("恢復清單只允許勾選，不支援 APK 模式"));}
        let output = edit(&self.original, &self.rows, body,self.selection_kind.as_deref())?;
        self.save_text(&output)
    }
    fn save_text(&self, output: &str) -> io::Result<()> {
        self.unchanged()?;
        if output == self.original {
            return Ok(());
        }
        let preserve = super::publish_file::auto_preserve(&self.path)?;
        super::publish_file::publish_bytes_guarded(
            output.as_bytes(),
            &self.path,
            Some(self.metadata.mode() & 0o777),
            preserve,
            &mut || self.unchanged(),
        )?;
        Ok(())
    }
}
// Persistent lists keep only selection text beside the script. Their icon map is run-local.
fn icon_map_path(list:&Path)->io::Result<PathBuf> {
    let name=list.file_name().ok_or_else(||err("icon list name"))?;
    let tmp=PathBuf::from(std::env::var_os("TMPDIR").ok_or_else(||err("icon TMPDIR missing"))?);
    let meta=fs::symlink_metadata(&tmp)?;
    if !tmp.is_absolute()||!meta.is_dir()||meta.uid()!=0||meta.mode()&0o077!=0||tmp.canonicalize()?!=tmp{return Err(err("icon TMPDIR must be private"));}
    use std::hash::{Hash,Hasher};
    let mut key=std::collections::hash_map::DefaultHasher::new();
    list.parent().ok_or_else(||err("icon parent"))?.canonicalize()?.hash(&mut key);
    name.hash(&mut key);
    Ok(tmp.join(format!(".remote-icons-{:016x}.tsv",key.finish())))
}
fn clear_icon_map(list:&Path)->io::Result<()> {
    let path=icon_map_path(list)?;
    match fs::remove_file(path){Ok(())=>{},Err(e) if e.kind()==io::ErrorKind::NotFound=>{},Err(e)=>return Err(e)}
    // Remove only the known legacy sidecar, never the list or JSON backup.
    if list.file_name().is_some_and(|n|n=="appList_network.txt") {
        let _=fs::remove_file(list.with_file_name("appList_network.txt.icons.tsv"));
    }
    Ok(())
}
// Display-only metadata. Selection IDs and destructive-operation snapshots never change.
fn icon_packages(session:&Session,restore:bool)->(BTreeMap<String,String>,BTreeMap<String,String>){
    if !session.selection {
        let packages=session.rows.iter().map(|r|(r.pkg.clone(),r.pkg.clone())).collect();let mut values=BTreeMap::new();let mut budget=0;
        if restore {for r in &session.rows {
            if r.label.contains(['/', '\\'])||matches!(r.label.as_str(),"."|"..") {continue;}
            let dir=session.parent.join(&r.label);
            if !fs::symlink_metadata(&dir).is_ok_and(|m|m.is_dir()){continue;}
            if let Ok((body,_))=read(&dir.join("app_details.json")){
                if let Some((pkg,icon))=super::profile::icon_metadata(&body){
                    if pkg==r.pkg&&!icon.is_empty()&&budget+icon.len()<=16*1024*1024{budget+=icon.len();values.insert(r.pkg.clone(),icon);}
                }
            }
        }}
        return (packages,values);
    }
    let Ok(path)=icon_map_path(&session.path) else{return (BTreeMap::new(),BTreeMap::new());};
    let mut names=BTreeMap::new();
    let text=(||->io::Result<String>{let mut f=open(&path)?;if f.metadata()?.len()>20*1024*1024{return Err(err("icon map limit"));}let mut text=String::new();Read::by_ref(&mut f).take(20*1024*1024+1).read_to_string(&mut text)?;if text.len()>20*1024*1024{return Err(err("icon map limit"));}Ok(text)})();
    if let Ok(text)=text{
        for line in text.lines(){if let Some((name,rest))=line.split_once('\t'){
            let (pkg,extra)=rest.split_once('\t').unwrap_or((rest,""));
            let icon=extra.split('\t').next().unwrap_or("");
            if package(pkg){names.insert(name.to_owned(),(pkg.to_owned(),if super::profile::valid_icon(icon){icon.to_owned()}else{String::new()}));}
        }}
    }
    let packages=session.rows.iter().filter_map(|r|names.get(&r.label).map(|(p,_)|(r.pkg.clone(),p.clone()))).collect();
    let mut budget=0;let values=session.rows.iter().filter_map(|r|names.get(&r.label).and_then(|(_,v)|{if !v.is_empty()&&budget+v.len()<=16*1024*1024{budget+=v.len();Some((r.pkg.clone(),v.clone()))}else{None}})).collect();
    (packages,values)
}
fn build_icon_map(args:&[String])->io::Result<()> {
    // Internal CLI: selection-web --icon-map LIST METADATA_ROOT. No HTTP file paths.
    let list=Path::new(&args[1]);let root=Path::new(&args[2]);
    if !root.is_absolute() || !fs::symlink_metadata(root)?.is_dir(){return Err(err("icon metadata root"));}
    let session=Session::new_kind(list,Some(if args.get(3).is_some_and(|v|v=="remote-delete"){"remote-delete"}else{"remote"}))?;let mut out=String::new();
    let (fallback,_) = icon_packages(&session,false);
    for row in &session.rows {
        let name=if session.selection_kind.as_deref()==Some("remote-delete"){row.label.strip_prefix(&format!("{}. ",row.line+1)).unwrap_or(&row.label)}else{&row.label};
        if name.contains(['/', '\\']) || matches!(name,"."|".."){continue;}
        let directory=root.join(name);
        let before=out.len();
        if fs::symlink_metadata(&directory).is_ok_and(|m|m.is_dir()) { if let Ok((body,_))=read(&directory.join("app_details.json")){
            if let Some((pkg,icon))=super::profile::icon_metadata(&body).filter(|(p,_)|package(p)){
                let icon=if out.len()+icon.len()<16*1024*1024{icon.as_str()}else{""};
                let module=super::profile::module_metadata(&body,&pkg);
                out.push_str(&format!("{}\t{pkg}\t{icon}\t{}\n",row.label,u8::from(module)));
            }
        }}
        if out.len()==before {if let Some(pkg)=fallback.get(&row.pkg){out.push_str(&format!("{}\t{pkg}\n",row.label));}}
    }
    let dest=icon_map_path(list)?;
    session.unchanged()?;
    super::publish_file::publish_bytes_guarded(out.as_bytes(),&dest,Some(0o600),false,&mut ||session.unchanged())?;
    if list.file_name().is_some_and(|n|n=="appList_network.txt") {let _=fs::remove_file(list.with_file_name("appList_network.txt.icons.tsv"));}
    Ok(())
}
struct Icons {
    values: BTreeMap<String, String>,
    bytes: usize,
    user: String,
    packages:BTreeMap<String,String>,
    attempted:BTreeSet<String>,
}
impl Icons {
    fn get(&mut self, body: &str, rows: &[Row], task: Option<&mut ReturnTask>) -> io::Result<String> {
        let wanted: Vec<_> = body.lines().collect();
        let allowed: BTreeSet<_> = rows.iter().map(|r| r.pkg.as_str()).collect();
        if wanted.is_empty()
            || wanted.len() > 100
            || wanted.iter().any(|p| !allowed.contains(p))
            || wanted.iter().collect::<BTreeSet<_>>().len() != wanted.len()
        {
            return Err(err("圖示請求不符清單"));
        }
        let missing: Vec<_> = wanted
            .iter()
            .filter(|p| !self.attempted.contains(**p) && self.values.get(**p).is_none_or(|v| v.is_empty() || super::profile::legacy_icon(v)))
            .copied()
            .collect();
        if !missing.is_empty() {
            for p in &missing {
                self.values.entry((*p).into()).or_default();
            }
            let packages:Vec<&str>=missing.iter().filter_map(|id|self.packages.get(*id).map(String::as_str)).collect::<BTreeSet<_>>().into_iter().collect();
            let batch=if packages.is_empty(){Ok(String::new())}else if web_console::managed(){web_console::icons(&self.user,&packages)}else{task.ok_or_else(||err("APK icon session unavailable"))
                .and_then(|t|t.icons(&self.user,&packages))};
            if let Ok(output) = batch {
                for p in &missing {self.attempted.insert((*p).into());}
                for line in output.lines() {
                    if let Some((pkg, value)) = line.split_once('\t') {
                        if packages.contains(&pkg)
                            && value.len() <= 43692
                            && value.starts_with("iVBORw0KGgo")
                            && value
                                .bytes()
                                .all(|b| b.is_ascii_alphanumeric() || b"+/=".contains(&b))
                            && super::profile::valid_icon(value)
                        {
                            for id in &missing {
                                if self.packages.get(*id).is_some_and(|p|p==pkg) && (self.values[*id].is_empty() || (super::profile::legacy_icon(&self.values[*id]) && !super::profile::legacy_icon(value))) && self.bytes-self.values[*id].len()+value.len()<=16*1024*1024 {
                                    self.bytes=self.bytes-self.values[*id].len()+value.len();self.values.insert((*id).into(),value.into());
                                }
                            }
                        }
                    }
                }
            }
        }
        Ok(format!(
            "{{{}}}",
            wanted
                .iter()
                .map(|p| format!("{}:{}", json(p), json(&self.values[*p])))
                .collect::<Vec<_>>()
                .join(",")
        ))
    }
}
// A bounded, read-only helper; only a fixed palette vocabulary crosses into HTTP.
fn read_theme() -> io::Result<String> {
    let dex = std::env::current_exe()?
        .parent()
        .ok_or_else(|| err("theme path"))?
        .join("classes.dex");
    let mut child = Command::new("/system/bin/app_process")
        .env("CLASSPATH", dex)
        .args(["/system/bin", "com.xayah.dex.AppListTheme"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()?;
    let stdout = child.stdout.take().expect("piped stdout");
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut bytes = Vec::new();
        let result = stdout.take(4097).read_to_end(&mut bytes);
        let _ = tx.send((result, bytes));
    });
    let result = rx.recv_timeout(Duration::from_secs(5));
    let _ = child.kill();
    let _ = child.wait();
    let (read, bytes) = result.map_err(|_| err("theme timeout"))?;
    read?;
    if bytes.len() > 4096 {
        return Err(err("theme limit"));
    }
    let text = String::from_utf8(bytes).map_err(|_| err("theme encoding"))?;
    let mut lines = text.lines();
    let source = match lines.next() {
        Some("source=system") => "system",
        Some("source=fallback") => "fallback",
        _ => return Err(err("theme source")),
    };
    let names = [
        "seed",
        "bg",
        "card",
        "field",
        "text",
        "muted",
        "line",
        "primary",
        "pressed",
        "footer",
        "danger",
        "selected",
        "on-primary",
        "accent",
    ];
    let mut modes = Vec::new();
    for mode in ["light", "dark"] {
        let mut colors = Vec::new();
        for name in names {
            let expected = format!("{mode}.{name}=");
            let value = lines
                .next()
                .and_then(|l| l.strip_prefix(&expected))
                .ok_or_else(|| err("theme role"))?;
            if value.len() != 7
                || !value.starts_with('#')
                || !value[1..].bytes().all(|b| b.is_ascii_hexdigit())
            {
                return Err(err("theme color"));
            }
            colors.push(format!("{}:{}", json(name), json(value)));
        }
        modes.push(format!("{}:{{{}}}", json(mode), colors.join(",")));
    }
    if lines.next().is_some() {
        return Err(err("theme extra output"));
    }
    Ok(format!(
        "{{\"source\":{},{} }}",
        json(source),
        modes.join(",")
    ))
}

fn device_users() -> io::Result<String> {
    let (status, text) = bounded_output(Command::new("/system/bin/pm").args(["list", "users"]), 3)?;
    if !status.success() { return Err(err("無法列出手機使用者")); }
    let mut users = std::collections::BTreeSet::new();
    for line in text.lines().map(str::trim) {
        if line.is_empty() || line == "Users:" { continue; }
        let id = line.strip_prefix("UserInfo{").and_then(|s| s.split_once(':')).map(|(id, _)| id)
            .filter(|s| !s.is_empty() && s.len() <= 5 && s.bytes().all(|b| b.is_ascii_digit()))
            .ok_or_else(|| err("無法辨識手機使用者清單"))?;
        users.insert(id.parse::<u32>().map_err(|_| err("使用者編號無效"))?);
    }
    if users.is_empty() { return Err(err("手機未回傳使用者清單")); }
    Ok(format!("[{}]", users.iter().map(u32::to_string).collect::<Vec<_>>().join(",")))
}

fn bounded_output(command: &mut Command, seconds: u64) -> io::Result<(std::process::ExitStatus, String)> {
    bounded_output_input(command,seconds,None)
}
fn bounded_output_input(command: &mut Command, seconds: u64, input: Option<&'static [u8]>) -> io::Result<(std::process::ExitStatus, String)> {
    let deadline = Instant::now() + Duration::from_secs(seconds);
    let rebind=command.get_args().any(|a|a=="--rebind-origin");
    let mut child = command.stdin(if input.is_some(){Stdio::piped()}else{Stdio::null()}).stdout(Stdio::piped()).stderr(if rebind{Stdio::inherit()}else{Stdio::null()}).spawn()?;
    let input_result=input.map(|bytes| {
        let mut stdin=child.stdin.take().expect("piped stdin");
        let(tx,rx)=std::sync::mpsc::channel();
        std::thread::spawn(move||{let result=stdin.write_all(bytes);drop(stdin);let _=tx.send(result);});rx
    });
    let result = (|| {
        let stdout = child.stdout.take().ok_or_else(|| err("helper stdout"))?;
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let mut out = Vec::new();
            let result = stdout.take(4097).read_to_end(&mut out);
            let _ = tx.send((result, out));
        });
        let (read, bytes) = rx.recv_timeout(deadline.saturating_duration_since(Instant::now()))
            .map_err(|_| err("helper timeout"))?;
        read?;
        if bytes.len() > 4096 { return Err(err("helper output limit")); }
        let text = String::from_utf8(bytes).map_err(|_| err("helper encoding"))?;
        if let Some(rx)=input_result {rx.recv_timeout(deadline.saturating_duration_since(Instant::now())).map_err(|_|err("helper input timeout"))??;}
        loop {
            if let Some(status) = child.try_wait()? { return Ok((status, text)); }
            if Instant::now() >= deadline { return Err(err("helper timeout")); }
            std::thread::sleep(Duration::from_millis(10));
        }
    })();
    if result.is_err() { let _ = child.kill(); let _ = child.wait(); }
    result
}
// Only the verified Dex handshake supplies user/SDK; no HTTP policy commands.
fn prepare_host_access(user:u32,sdk:u32) {
    const PACKAGE:&str="io.github.yawasau.speedbackup.webview";
    let user=user.to_string();
    let mut requests:Vec<(&str,Vec<&str>)>=Vec::new();
    if sdk>=33 {requests.push(("/system/bin/pm",vec!["grant","--user",&user,PACKAGE,"android.permission.POST_NOTIFICATIONS"]));}
    let whitelist=format!("+{PACKAGE}");
    requests.push(("/system/bin/cmd",vec!["deviceidle","whitelist",&whitelist]));
    requests.push(("/system/bin/cmd",vec!["appops","set","--user",&user,PACKAGE,"RUN_IN_BACKGROUND","allow"]));
    requests.push(("/system/bin/cmd",vec!["appops","set","--user",&user,PACKAGE,"RUN_ANY_IN_BACKGROUND","allow"]));
    // Separate bounded children: a rejected operation cannot mask an earlier failure.
    std::thread::scope(|scope| {for (program,args) in requests {scope.spawn(move || {
        if !bounded_output(Command::new(program).args(&args),4).is_ok_and(|(s,_)|s.success()) {
            terminal_eprintln!("HOST_ACCESS_SETUP unavailable operation={}",args.join(" "));
        }
    });}});
}
fn ensure_webview(dex: &Path) -> io::Result<()> {
    fn check(dex: &Path)->io::Result<(std::process::ExitStatus,String)>{bounded_output(Command::new("/system/bin/app_process").env("CLASSPATH",dex).args(["/system/bin","com.xayah.dex.AppListReturn","--check"]),8)}
    let (status,text)=check(dex)?;
    if status.success()&&text.trim()=="OK" {return Ok(());}
    if status.code()!=Some(10){return Err(err("WebView identity check failed"));}
    let user=text.trim().strip_prefix("INSTALL\t").filter(|s| !s.is_empty()&&s.bytes().all(|b|b.is_ascii_digit())).ok_or_else(||err("WebView install user"))?;
    let bytes=include_bytes!("../../webview/embedded/speedbackup-webview.apk");
    terminal_println!("正在安裝 SpeedBackup 原生介面…");
    // An anonymous pipe avoids mutable staging paths and SELinux file-label access.
    let (installed,_) = bounded_output_input(Command::new("/system/bin/pm").args(["install","-r","--user",user,"-S",&bytes.len().to_string()]),60,Some(bytes))?;
    if !installed.success(){return Err(err("WebView install failed"));}
    let (status,text)=check(dex)?;
    if !status.success()||text.trim()!="OK" {return Err(err("installed WebView identity verification"));}
    Ok(())
}

// This helper holds a Binder task token in memory for one editor session.
// HTTP clients cannot choose a package/task or request an arbitrary launch.
#[derive(PartialEq)]
enum Navigation { Ready, Retry, Closed }
struct ReturnTask {
    child: std::process::Child,
    lines: std::sync::mpsc::Receiver<String>,
    held: bool,
    icon_lines: std::sync::mpsc::Receiver<String>,
    icons_disabled: bool,
}
impl Drop for ReturnTask {
    fn drop(&mut self) {
        drop(self.child.stdin.take());
        if self.held { return; }
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
impl ReturnTask {
    fn capture(url: Option<&str>) -> Option<Self> { Self::capture_once(url, false, web_console::managed(),None) }
    fn capture_managed(url: &str,events:std::sync::mpsc::SyncSender<()>) -> Option<Self> {Self::capture_once(Some(url), false, true,Some(events))}
    fn capture_once(url: Option<&str>, installed_once: bool, managed:bool,events:Option<std::sync::mpsc::SyncSender<()>>) -> Option<Self> {
        let url=Some(url?); // no installation or helper for legacy return-only mode
        let dex = std::env::current_exe().ok()?.parent()?.join("classes.dex");
        let mut command = Command::new("/system/bin/app_process");
        command
            .env("CLASSPATH", &dex)
            .env("SPEEDBACKUP_UI_LANGUAGE",web_language(None).unwrap_or_else(|_|"zh-Hant".into()))
            .env("SPEEDBACKUP_WEBVIEW_FRESH_TASK", if installed_once { "1" } else { "0" })
            .args(["/system/bin", "com.xayah.dex.AppListReturn"]);
        if let Some(url) = url {
            command.arg(url);
        }
        // Do not retain shell relay/lock descriptors in the handoff controller.
        // Mark inherited descriptors CLOEXEC rather than closing Rust's exec-error pipe.
        let inherited: Vec<i32> = fs::read_dir("/proc/self/fd").ok()?.filter_map(|e|
            e.ok()?.file_name().to_str()?.parse::<i32>().ok().filter(|fd| *fd >= 3)).collect();
        use std::os::unix::process::CommandExt;
        unsafe {
            command.pre_exec(move || {
                unsafe extern "C" { fn fcntl(fd:i32,cmd:i32,...)->i32; fn setsid()->i32; }
                for &fd in &inherited { let flags=fcntl(fd,1); if flags>=0 && fcntl(fd,2,flags|1)<0 {return Err(io::Error::last_os_error());} }
                if setsid()<0 {return Err(io::Error::last_os_error());}
                Ok(())
            });
        }
        let child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .ok()?;
        let (tx, lines) = std::sync::mpsc::sync_channel(3);
        let (icon_tx, icon_lines)=std::sync::mpsc::sync_channel(1);
        let mut state = Self { child, lines, held: false, icon_lines, icons_disabled:false };
        let mut stdout = io::BufReader::new(state.child.stdout.take()?);
        let reader_events=events.clone();
        std::thread::spawn(move || {
            (||{loop {
                let mut line = Vec::new();
                loop {
                    let mut byte = [0];
                    if stdout.read_exact(&mut byte).is_err() {
                        return;
                    }
                    if byte[0] == b'\n' {
                        break;
                    }
                    if line.len() == 6*1024*1024 {
                        return;
                    }
                    line.push(byte[0]);
                }
                if line.starts_with(b"ICONS\t") {
                    let _=icon_tx.try_send(String::from_utf8_lossy(&line[6..]).into_owned());
                    if let Some(events)=&reader_events{let _=events.try_send(());}
                    continue;
                }
                if tx
                    .send(String::from_utf8_lossy(&line).into_owned())
                    .is_err()
                {
                    return;
                }
                if let Some(events)=&reader_events{let _=events.try_send(());}
            }})();
            // Disconnect channels before waking the consumer, avoiding an EOF race.
            drop(tx);drop(icon_tx);
            if let Some(events)=reader_events{let _=events.try_send(());}
        });
        let mut ready = state.lines.recv_timeout(Duration::from_secs(20)).ok()?;
        if ready.trim()=="WAIT_FOREGROUND" {
            terminal_println!("等待回到原終端或 SpeedBackup 卡片；不會搶走其他應用程式的前景。");
            ready=state.lines.recv_timeout(Duration::from_secs(if managed{2}else{920})).ok()?;
        }
        if !installed_once && ready.trim().strip_prefix("INSTALL\t").is_some_and(|s| !s.is_empty() && s.bytes().all(|b|b.is_ascii_digit())) {
            drop(state);
            ensure_webview(&dex).map_err(|e| terminal_eprintln!("WEBVIEW_INSTALL_ERROR {e}")).ok()?;
            return Self::capture_once(url, true, managed,events);
        }
        if let Some(access)=ready.strip_prefix("HOST_ACCESS\t") {
            let fields=access.trim().split('\t').collect::<Vec<_>>();
            if fields.len()!=2{return None;}
            let user=fields[0].parse::<u32>().ok()?;let sdk=fields[1].parse::<u32>().ok()?;
            prepare_host_access(user,sdk);
            state.child.stdin.as_mut()?.write_all(b"HOST_ACCESS_DONE\n").ok()?;
            ready=state.lines.recv_timeout(Duration::from_secs(20)).ok()?;
        }
        if ready.trim()=="WAIT_HOST_SETUP" {ready=state.lines.recv_timeout(Duration::from_secs(125)).ok()?;}
        match ready.trim() {
            "READY" | "READY_CUSTOM" => Some(state),
            _ => None,
        }
    }

    fn navigate(&mut self,url:&str)->Navigation {
        let Ok(id)=random_hex()else{return Navigation::Retry;};
        if self.child.stdin.as_mut().is_none_or(|s|s.write_all(format!("NAV\t{id}\t{url}\n").as_bytes()).is_err()){return Navigation::Closed;}
        let deadline=Instant::now()+Duration::from_millis(2300);
        loop{
            if self.child.try_wait().ok().flatten().is_some(){return Navigation::Closed;}
            match self.lines.recv_timeout(deadline.saturating_duration_since(Instant::now())){
                Ok(line)if line.trim()=="WINDOW_CLOSED"=>return Navigation::Closed,
                Ok(line)if line.trim()==format!("NAV_OK\t{id}")=>return Navigation::Ready,
                Ok(line)if line.trim()==format!("NAV_CLOSED\t{id}")=>return Navigation::Closed,
                Ok(line)if line.trim()==format!("NAV_FALLBACK\t{id}")=>return Navigation::Retry,
                Ok(_)=>{if Instant::now()>=deadline{return Navigation::Retry;}},
                Err(std::sync::mpsc::RecvTimeoutError::Disconnected)=>return Navigation::Closed,
                Err(_)=>return if self.child.try_wait().ok().flatten().is_some(){Navigation::Closed}else{Navigation::Retry},
            }
        }
    }
    fn begin_icons(&mut self,user:&str,packages:&[&str])->io::Result<()> {
        if self.icons_disabled || user.is_empty() || user.len()>5 || !user.bytes().all(|b|b.is_ascii_digit()){return Err(err("APK icon session unavailable"));}
        self.child.stdin.as_mut().ok_or_else(||err("icon channel"))?.write_all(format!("ICONS\t{}\t{}\n",user,packages.join("\t")).as_bytes())
    }
    fn poll_icons(&mut self)->io::Result<Option<String>> {
        match self.icon_lines.try_recv(){
            Ok(line)=>Ok(Some(line.split(';').filter_map(|row|row.split_once(':')).map(|(p,v)|format!("{p}\t{v}\n")).collect())),
            Err(std::sync::mpsc::TryRecvError::Empty)=>Ok(None),
            Err(_)=>{self.icons_disabled=true;Err(err("APK icon disconnected"))}
        }
    }
    fn icons(&mut self,user:&str,packages:&[&str])->io::Result<String>{
        if self.icons_disabled || user.is_empty() || user.len()>5 || !user.bytes().all(|b|b.is_ascii_digit()){
            return Err(err("APK icon session unavailable"));
        }
        let request=format!("ICONS\t{}\t{}\n",user,packages.join("\t"));
        let result=(||{
            self.child.stdin.as_mut().ok_or_else(||err("icon channel"))?.write_all(request.as_bytes())?;
            let line=self.icon_lines.recv_timeout(Duration::from_secs(8)).map_err(|_|err("APK icon timeout"))?;
            Ok(line.split(';').filter_map(|row|row.split_once(':')).map(|(p,v)|format!("{p}\t{v}\n")).collect())
        })();
        if result.is_err(){self.icons_disabled=true;}
        result
    }

    fn externally_closed(&mut self) -> bool {
        if controller_closed(&self.lines){return true;}
        // The APK is death-linked to this controller. If it dies without a final
        // callback, there is no usable window: never leave an invisible HTTP server.
        match self.child.try_wait() {
            Ok(None) => false,
            _ => { terminal_eprintln!("WEBVIEW_CONTROLLER_EXITED"); true }
        }
    }

    fn finish(mut self, handoff: bool, background: bool) -> bool {
        let result = (|| {
            let request: &[u8] = if handoff && std::env::var("SPEEDBACKUP_WEB_OWNER_PID").is_ok_and(|v| !v.is_empty() && v.bytes().all(|b|b.is_ascii_digit())) {
                if background { b"BACKGROUND\n" } else { b"HOLD\n" }
            } else { b"RETURN\n" };
            self.child.stdin.as_mut()?.write_all(request).ok()?;
            self.lines.recv_timeout(Duration::from_secs(10)).ok()
        })();
        if result.as_deref() == Some("HELD") {
            self.held = true;
            return true;
        }
        let text = match result.as_deref() {
            Some("FOCUS_FAILED") => "無法確認原終端已在前景；這次操作未執行。",
            Some("WINDOW_CLOSED") => "獨立編輯視窗已關閉。",
            Some("CLOSED_RETURNED") => "已關閉本次獨立編輯視窗並返回原終端。",
            Some("CLOSED_RETURN_UNCONFIRMED") => "已關閉本次編輯視窗；請手動返回原終端。",
            Some("SKIP_CLOSE_FAILED") => "未能關閉本次視窗；未操作其他分頁。",
            Some("RETURNED") => "已切回原終端任務。",
            Some("ALREADY_ORIGIN") => "目前已在原終端任務。",
            Some("SKIP_LOCKED") => "畫面已鎖定，未切回終端。",
            Some("SKIP_FOREGROUND_CHANGED") => "前景已變更，未切回終端。",
            Some("SKIP_ORIGIN_CHANGED") => "原終端任務已變更，未切換畫面。",
            Some("RETURN_UNCONFIRMED") => "已要求切回終端，尚未確認畫面。",
            Some("SKIP_UNAVAILABLE") => "系統不支援此切回操作，請手動返回終端。",
            _ => "未切換畫面；請手動返回終端。",
        };
        let _ = writeln!(io::stdout(), "{}", terminal_text(text));
        matches!(result.as_deref(),Some("CLOSED_RETURNED"|"RETURNED"|"ALREADY_ORIGIN"))
            || (!handoff && result.as_deref()==Some("WINDOW_CLOSED"))
    }
}
fn controller_closed(lines:&std::sync::mpsc::Receiver<String>)->bool{
    loop {match lines.try_recv(){
        Ok(line) if line.trim()=="WINDOW_CLOSED"=>return true,
        Ok(_)=>continue,
        Err(std::sync::mpsc::TryRecvError::Disconnected)=>return true,
        Err(std::sync::mpsc::TryRecvError::Empty)=>return false,
    }}
}
fn finish_return(task: &mut Option<ReturnTask>) -> bool {
    if let Some(task) = task.take() {return task.finish(true, std::env::var("SPEEDBACKUP_WEB_UI_ONLY").as_deref()!=Ok("1"));}
    true
}

fn editor_lock() -> io::Result<File> {
    // Shared-storage FUSE may not implement flock. Serialize editor sessions on
    // a root-owned regular file on /data, without truncating or chmodding an existing inode.
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE | speedbackup_native_rs::O_NONBLOCK)
        .open("/data/local/tmp/.speedbackup-applist-web.lock")?;
    let lock_meta = file.metadata()?;
    if !lock_meta.is_file()
        || lock_meta.uid() != 0
        || lock_meta.nlink() != 1
        || lock_meta.mode() & 0o777 != 0o600
    {
        return Err(err("編輯器鎖檔身分不符"));
    }
    unsafe extern "C" {
        fn flock(fd: i32, op: i32) -> i32;
    }
    if unsafe { flock(file.as_raw_fd(), 2 | 4) } != 0 {
        return Err(err("清單正在另一個編輯器使用中"));
    }
    Ok(file)
}

fn serve_kind(args: &[String], selection:Option<&str>) -> io::Result<i32> {
    unsafe extern "C" {
        fn getppid() -> i32;
    }
    let owner = unsafe { getppid() };
    if args.is_empty()
        || args.len() == 2
        || args.len() == 4
        || args.len() > 6
        || args.get(5).is_some_and(|s| !matches!(s.as_str(),"apps"|"settings"|"manager"))
        || args
            .get(4)
            .is_some_and(|s| !matches!(s.as_str(), "backup" | "restore"))
        || args
            .get(1)
            .is_some_and(|s| !matches!(s.as_str(), "--open" | "--return"))
        || args
            .get(2)
            .is_some_and(|s| s.is_empty() || s.len() > 5 || !s.bytes().all(|b| b.is_ascii_digit()))
    {
        return Err(err("Usage: applist-web ABSOLUTE_LIST [--open|--return USER_ID [CONFIG_DIR backup|restore]]"));
    }
    let path = Path::new(&args[0]);
    if !path.is_absolute() {
        return Err(err("需要絕對清單路徑"));
    }
    let _lock = editor_lock()?;
    let flow=selection_flow::flow();
    let session = if let Some(kind)=selection {Session::new_kind(path,Some(kind))} else {Session::new(path,true)};
    // Validate the same held snapshot used by the editor, before binding HTTP
    // or installing/launching the APK. Settings and archive selectors are independent.
    if flow.is_empty() && selection.is_none() && args.get(5).is_none_or(|panel| panel != "settings") {
        match &session {
            Ok(session) if session.rows.is_empty() => return Err(err("請先生成應用列表。")),
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Err(err("請先生成應用列表。")),
            Err(_) => return Err(session.err().unwrap()),
            _ => {}
        }
    }
    if args.len() < 4 && session.is_err() {
        return Err(session.err().unwrap());
    }
    let list_data=selection_flow::list_data(session.as_ref().ok(),selection)?;
    ui_event("selection-open",concat!("build=",env!("CARGO_PKG_VERSION")));
    let mut configs: BTreeMap<&str, Result<Session, io::Error>> = BTreeMap::new();
    if let Some(root) = args.get(3) {
        let root = Path::new(root);
        if !root.is_absolute() {
            return Err(err("設定目錄必須是絕對路徑"));
        }
        for (key, name) in [if args[4] == "restore" {
            ("restore", "restore_settings.conf")
        } else {
            ("backup", "backup_settings.conf")
        }] {
            configs.insert(key, Session::new(&root.join(name), false));
        }
    }
    let mut random = [0u8; 32];
    File::open("/dev/urandom")?.read_exact(&mut random)?;
    let token = random
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<String>();
    let listener = TcpListener::bind("127.0.0.1:0")?;
    listener.set_nonblocking(true)?;
    let host = listener.local_addr()?.to_string();
    let origin = format!("http://{host}");
    let url = format!("{origin}/#{token}");
    let mut _console_page=web_console::Page::register(&url,!std::env::var("SPEEDBACKUP_AUTH_SETUP").is_ok_and(|v|v=="1"))?;
    let mut return_task = if args.len() >= 2 && _console_page.is_none() {
        ReturnTask::capture(if args.get(1).is_some_and(|s| s == "--open") {
            Some(&url)
        } else {
            None
        })
    } else {
        None
    };
    if args.get(1).is_some_and(|s| s == "--open") && return_task.is_none() && _console_page.is_none() {
        return Err(err("無法安全啟動編輯視窗，已取消等待；請重試或使用終端編輯"));
    }
    if _console_page.is_none(){terminal_println!("正在開啟應用清單；儲存或取消後返回原畫面。");}
    io::stdout().flush()?;
    if args.len() >= 2 && _console_page.is_none() {
        terminal_println!(
            "{}",
            if return_task.is_some() {
                "已記錄原終端任務，完成後會嘗試切回。"
            } else {
                "無法記錄原終端任務，完成後請手動返回。"
            }
        );
    }
    let discovery = lan_discovery::Discovery::default();
    let auth_setup=std::env::var("SPEEDBACKUP_AUTH_SETUP").is_ok_and(|v|v=="1");
    let mut configs_saved = false;
    // Root worker owns this display-only draft. It never authorizes a save or
    // operation, and disappears with this editor session. A reconnect claims a
    // new lease so late requests from the previous WebView cannot overwrite it.
    let mut draft = String::from("{}");
    let mut draft_lease = 0u64;
    let mut theme_cache: Option<(Instant, io::Result<String>)> = None;
    let started = Instant::now();
    let mut last = started;
    let (icon_packages,icon_values)=session.as_ref().map(|s|icon_packages(s,args.get(4).is_some_and(|v|v=="restore"))).unwrap_or_default();
    let icon_bytes=icon_values.values().map(String::len).sum();
    let mut icons = Icons {
        values: icon_values,
        bytes: icon_bytes,
        user: args.get(2).cloned().unwrap_or_else(|| "0".into()),
        packages:icon_packages,
        attempted:BTreeSet::new(),
    };
    let (tx, rx) = std::sync::mpsc::sync_channel(8);
    let active = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
    loop {
        if return_task
            .as_mut()
            .is_some_and(ReturnTask::externally_closed)
        {
            ui_event("editor-close","external_close");
            terminal_println!(
                "獨立編輯視窗已關閉；未儲存的修改已取消。{}",
                if configs_saved {
                    "先前已儲存的設定仍保留，請重新執行入口套用。"
                } else {
                    ""
                }
            );
            return Ok(if selection.is_some()||!flow.is_empty()||auth_setup{130}else if configs_saved||auth_setup { 10 } else { 0 });
        }
        if unsafe { getppid() } != owner
            || (_console_page.is_none() && (last.elapsed() > Duration::from_secs(900)
            || started.elapsed() > Duration::from_secs(3600)))
        {
            ui_event("editor-close","owner_exit_or_timeout");
            terminal_println!(
                "{}",
                if configs_saved {
                    "清單編輯已結束；先前儲存的設定仍保留。"
                } else {
                    "清單編輯已結束，未儲存。"
                }
            );
            return Ok(if selection.is_some()||!flow.is_empty()||auth_setup{130}else if configs_saved||auth_setup { 10 } else { 0 });
        }
        use std::sync::atomic::Ordering;
        match listener.accept() {
            Ok((mut stream, _)) => {
                if active.load(Ordering::Relaxed) < 8 {
                    active.fetch_add(1, Ordering::Relaxed);
                    let active = active.clone();
                    let tx = tx.clone();
                    std::thread::spawn(move || {
                        let req = request(&mut stream);
                        let _ = tx.send((stream, req));
                        active.fetch_sub(1, Ordering::Relaxed);
                    });
                }
            }
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {}
            Err(e) => return Err(e),
        }
        let (mut stream, req) = match rx.recv_timeout(Duration::from_millis(10)) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let req = match req {
            Ok(v) => v,
            Err(_) => {
                let _ = respond(&mut stream, "400 Bad Request", "text/plain", "請求格式錯誤");
                continue;
            }
        };
        if req.headers.get("host") != Some(&host)
            || req.headers.get("origin").is_some_and(|o| o != &origin)
            || (req.path.starts_with("/api/")
                && req
                    .headers
                    .get("sec-fetch-site")
                    .is_some_and(|v| !matches!(v.as_str(), "same-origin" | "none")))
        {
            let _ = respond(&mut stream, "403 Forbidden", "text/plain", "來源不符");
            continue;
        }
        if req.headers.get("x-speedbackup-token") != Some(&token) {
            let _ = respond(&mut stream, "403 Forbidden", "text/plain", "編輯憑證無效");
            continue;
        }
    if req.method=="GET" && req.path=="/api/session" && req.body.is_empty() {
        let _=respond(&mut stream,"200 OK","application/json",r#"{"protocol":1,"kind":"editor","native":true}"#);continue;
    }
        if req.method=="POST" && req.path=="/api/discovery" {
            match stream.try_clone().and_then(|peer|discovery.start(peer,&req.body)) {
                Ok(())=>{}, Err(error)=>{let _=respond(&mut stream,"409 Conflict","text/plain",&error.to_string());}
            }
            continue;
        }
        if req.method=="POST" && req.path=="/api/discovery-stop" {
            discovery.stop(&req.body);let _=respond(&mut stream,"200 OK","text/plain","ok");continue;
        }
        let config_before=configs.values().find_map(|s|s.as_ref().ok()).map(|s|s.original.clone());
        if appearance_request(&mut stream, &req) { continue; }
        if language_request(&mut stream, &req, configs.values_mut().find_map(|s|s.as_mut().ok()), None).is_some() {
            configs_saved |= config_before!=configs.values().find_map(|s|s.as_ref().ok()).map(|s|s.original.clone());
            continue;
        }
        // Existing ping is sent only after recent user interaction; preserve that keepalive.
        if req.path != "/api/theme" && req.path != "/api/lifecycle" {
            last = Instant::now();
        }
        match (req.method.as_str(), req.path.as_str()) {
            ("POST", "/api/lifecycle") if req.headers.get("content-type").is_some_and(|v|v=="text/plain;charset=UTF-8") && matches!(req.body.as_str(),"hidden"|"visible"|"pageshow") => {
                ui_event("lifecycle",&req.body);
                let _=respond(&mut stream,"200 OK","text/plain","ok");
            }
            ("GET", "/api/timeline") if req.body.is_empty() => {
                match timeline_options::catalog(){Ok(value)=>{let _=respond(&mut stream,"200 OK","application/json",&value);},Err(e)=>{ui_error("timeline-catalog",&e.to_string());let _=respond(&mut stream,"409 Conflict","text/plain",&e.to_string());}}
            }
            ("GET", "/api/draft") if req.body.is_empty() => {
                draft_lease = draft_lease.saturating_add(1);
                ui_event("draft-open",if draft.is_empty(){"empty"}else{"restored"});
                let _ = respond(&mut stream,"200 OK","text/plain",&format!("{draft_lease}\n{draft}"));
            }
            ("POST", "/api/draft") if req.headers.get("content-type").is_some_and(|v|v=="text/plain;charset=UTF-8") => {
                if let Some((lease,body))=req.body.split_once('\n').filter(|(lease,body)|lease.parse::<u64>().ok()==Some(draft_lease)&&draft_lease!=0&&body.len()<=1024*1024) {
                    let _=lease;
                    draft=body.to_owned();
                    let _=respond(&mut stream,"200 OK","text/plain","ok");
                } else {let _=respond(&mut stream,"409 Conflict","text/plain","draft lease or size");}
            }
            ("POST", "/api/browse-path") if req.headers.get("content-type").is_some_and(|v| v == "text/plain;charset=UTF-8") => {
                let result = (|| -> io::Result<String> {
                    let parts: Vec<_> = req.body.split('\n').collect();
                    if parts.len() != 4 || !matches!(parts[1], "Custom_path" | "Output_path" | "list_location") {
                        return Err(err("路徑選擇請求無效"));
                    }
                    let state = configs.get(parts[0]).and_then(|v|v.as_ref().ok()).ok_or_else(||err("設定檔無法編輯"))?;
                    if !super::web_settings::parse(&state.original)?.iter().any(|f|f.key == parts[1]) {
                        return Err(err("此設定沒有該路徑欄位"));
                    }
                    let offset = parts[2].parse::<usize>().map_err(|_|err("頁碼無效"))?;
                    picker_listing(state.path.parent().unwrap_or(Path::new("/")), parts[3], offset)
                })();
                match result {
                    Ok(body) => { let _ = respond(&mut stream, "200 OK", "application/json", &body); }
                    Err(e) => { ui_error("browse", &e.to_string()); let _ = respond(&mut stream, "400 Bad Request", "text/plain", &e.to_string()); }
                }
            }
            ("POST", "/api/icons") => match icons.get(
                &req.body,
                session.as_ref().map(|s| s.rows.as_slice()).unwrap_or(&[]),
                return_task.as_mut(),
            ) {
                Ok(body) => {
                    let _ = respond(&mut stream, "200 OK", "application/json", &body);
                }
                Err(e) => {
                    ui_error("icons", &e.to_string());
                    let _ = respond(&mut stream, "400 Bad Request", "text/plain", &e.to_string());
                }
            },
            ("GET", "/api/theme") => {
                if theme_cache
                    .as_ref()
                    .is_none_or(|(time, _)| time.elapsed() > Duration::from_secs(10))
                {
                    theme_cache = Some((Instant::now(), read_theme()));
                }
                match &theme_cache.as_ref().unwrap().1 {
                    Ok(body) => {
                        let _ = respond(&mut stream, "200 OK", "application/json", body);
                    }
                    Err(_) => {
                        let _ = respond(
                            &mut stream,
                            "503 Service Unavailable",
                            "text/plain",
                            "動態配色暫時無法取得",
                        );
                    }
                }
            }
            ("GET", "/api/ping") => {
                let _ = respond(&mut stream, "200 OK", "text/plain", "ok");
            }
            ("GET", "/api/users") => {
                match device_users() {
                    Ok(body) => { let _ = respond(&mut stream, "200 OK", "application/json", &body); }
                    Err(error) => { let _ = respond(&mut stream, "503 Service Unavailable", "text/plain", &error.to_string()); }
                }
            }
            ("GET", "/api/manager") => {
                let available = |k: &str| configs.get(k).is_some_and(|v| v.is_ok());
                let body = format!(
                    "{{\"apps\":{},\"backup\":{},\"restore\":{},\"panel\":{},\"managed\":{},\"flow\":{},\"mode\":{},\"discoverySetup\":{},\"authSetup\":{}}}",
                    session.is_ok(),
                    available("backup"),
                    available("restore"),
                    json(args.get(5).map(String::as_str).unwrap_or("manager")),
                    _console_page.is_some(),
                    json(&flow),
                    json(selection.unwrap_or_else(||args.get(4).map(String::as_str).unwrap_or("apps"))),
                    std::env::var("SPEEDBACKUP_DISCOVERY_SETUP").is_ok_and(|v|v=="1"),
                    std::env::var("SPEEDBACKUP_AUTH_SETUP").is_ok_and(|v|v=="1")
                );
                let _ = respond(&mut stream, "200 OK", "application/json", &body);
            }
            ("GET", "/api/backup" | "/api/restore") => {
                let key = req.path.trim_start_matches("/api/");
                match configs
                    .get(key)
                    .and_then(|v| v.as_ref().ok())
                    .and_then(|s| super::web_settings::data(&s.original).ok())
                {
                    Some(body) => {
                        let _ = respond(&mut stream, "200 OK", "application/json", &body);
                    }
                    None => {
                        let _ = respond(
                            &mut stream,
                            "409 Conflict",
                            "text/plain",
                            "設定檔不存在、不是一般檔案，或格式無法安全編輯；請用終端確認",
                        );
                    }
                }
            }
            ("POST", "/api/save-backup" | "/api/save-restore")
                if req
                    .headers
                    .get("content-type")
                    .is_some_and(|v| v == "text/plain;charset=UTF-8") =>
            {
                let key = req.path.trim_start_matches("/api/save-");
                let result = (|| -> io::Result<()> {
                    let state = configs
                        .get_mut(key)
                        .and_then(|v| v.as_mut().ok())
                        .ok_or_else(|| err("此設定無法編輯"))?;
                    let output = super::web_settings::edit(&state.original, &req.body)?;
                    if std::env::var("SPEEDBACKUP_AUTH_SETUP").is_ok_and(|v|v=="1") {
                        let old=super::web_settings::parse(&state.original)?;
                        let protocol=old.iter().find(|f|f.key=="remote_type").map(|f|f.value.as_str()).unwrap_or("");
                        if !matches!(protocol,"smb"|"webdav"){return Err(err("invalid credential protocol"));}
                        let new=super::web_settings::parse(&output)?;
                        let allowed=[format!("{protocol}_remote_user"),format!("{protocol}_remote_pass")];
                        if old.len()!=new.len()||old.iter().zip(&new).any(|(a,b)|a.key!=b.key||(!allowed.contains(&a.key)&&a.value!=b.value)){return Err(err("帳密重填不能修改地址或其他設定"));}
                    }
                    state.save_text(&output)?;
                    configs_saved |= output != state.original;
                    // A successful publish is never rolled back if refreshing fails.
                    let (actual, metadata) = read(&state.path)
                        .map_err(|_| err("設定已寫入，但無法重新確認；請重新開啟管理頁"))?;
                    if actual != output {
                        return Err(err("設定已寫入，但隨後有其他寫入；請重新開啟管理頁"));
                    }
                    state.original = actual;
                    state.metadata = metadata;
                    Ok(())
                })();
                match result {
                    Ok(()) => {
                        let _ = respond(&mut stream, "200 OK", "text/plain", "設定已儲存");
                    }
                    Err(error) => {
                        ui_error("save-settings", &error.to_string());
                        let _ = respond(
                            &mut stream,
                            "409 Conflict",
                            "text/plain",
                            &error.to_string(),
                        );
                    }
                }
            }
            ("POST", "/api/finish") if flow.is_empty() && req.body.is_empty() => {
                let _ = respond(&mut stream, "200 OK", "text/plain", "管理已完成");
                if selection.is_none(){if let Some(page)=_console_page.as_mut(){page.return_to_menu();}}
                if !finish_return(&mut return_task) && (selection.is_some()||!flow.is_empty()||auth_setup){return Ok(130);}
                return Ok(if configs_saved||auth_setup { 10 } else { 0 });
            }
            ("GET", "/api/list") => {
                let _ = respond(
                    &mut stream,
                    "200 OK",
                    "application/json",
                    &list_data,
                );
            }
            ("POST", "/api/cancel") if req.body.is_empty() => {
                ui_event("selection-close","cancelled");
                let _ = respond(&mut stream, "200 OK", "text/plain", "已取消，原檔未修改");
                let _ = writeln!(io::stdout(), "{}", terminal_text("清單編輯取消，原檔未修改。"));
                if let Some(page)=_console_page.as_mut(){page.return_to_menu();}
                if !finish_return(&mut return_task) && (selection.is_some()||!flow.is_empty()||auth_setup){return Ok(130);}
                return Ok(if selection.is_some()||!flow.is_empty()||auth_setup{130}else if configs_saved||auth_setup { 10 } else { 0 });
            }
            ("POST", "/api/save")
                if req
                    .headers
                    .get("content-type")
                    .is_some_and(|v| v == "text/plain;charset=UTF-8") =>
            {
                match session
                    .as_ref()
                    .map_err(|_| err("應用清單無法編輯，請先生成或修正清單"))
                    .and_then(|s| {if !flow.is_empty()&&!req.body.lines().any(|l|l.split('\t').nth(1)==Some("1")){return Err(err("請至少選擇一個項目"));}timeline_options::save(s,&req.body)})
                {
                    Ok(()) => {
                        ui_event("selection-close","saved");
                        let _ = respond(&mut stream, "200 OK", "text/plain", "已儲存，可返回終端");
                        let _ = writeln!(io::stdout(), "{}", terminal_text("應用列表已儲存。"));
                if flow.is_empty()&&selection.is_none(){if let Some(page)=_console_page.as_mut(){page.return_to_menu();}}
                        if !finish_return(&mut return_task) && (selection.is_some()||!flow.is_empty()||auth_setup){return Ok(130);}
                        return Ok(if !flow.is_empty(){20}else if configs_saved||auth_setup { 10 } else { 0 });
                    }
                    Err(e) => {
                        ui_error("save-selection", &e.to_string());
                        let _ = respond(&mut stream, "409 Conflict", "text/plain", &e.to_string());
                    }
                }
            }
            _ => {
                let _ = respond(&mut stream, "404 Not Found", "text/plain", "無此操作");
            }
        }
    }
}
pub fn run(args: &[String]) -> i32 {
    match serve_kind(args,None) {
        Ok(rc) => rc,
        Err(e) if e.to_string() == "請先生成應用列表。" => 66,
        Err(e) => {
            ui_error("open-app-list", &e.to_string());
            1
        }
    }
}

pub fn selection(args:&[String])->i32 {
    if let Some(result)=selection_plan::command(args){return match result{Ok(())=>0,Err(e) if args.first().is_some_and(|s|s=="--has-media-all") && e.to_string()=="no Media marker"=>1,Err(e)=>{ui_error("selection-plan", &e.to_string());65}};}
    if args.len()==3&&args[0]=="--timeline-metadata"{return match selection_flow::timeline_metadata(args){Ok(())=>0,Err(e)=>{ui_error("timeline-metadata",&e.to_string());65}};}
    if args.len()==2&&args[0]=="--emit-selected"{return match selection_flow::emit_selected(Path::new(&args[1])){Ok(())=>0,Err(e)=>{ui_error("selection-emit", &e.to_string());65}};}
    if args.first().is_some_and(|v|v=="--project-local"){return match selection_flow::project(args){Ok(())=>0,Err(e)=>{ui_error("local-project", &e.to_string());65}};}
    if args.first().is_some_and(|v|v=="--sync"){return match selection_flow::sync(args){Ok(())=>0,Err(e)=>{ui_error("selection-sync", &e.to_string());65}};}
    if args.len()==2 && args[0]=="--has-icon-map" {return if icon_map_path(Path::new(&args[1])).ok().and_then(|p|fs::metadata(p).ok()).is_some_and(|m|m.is_file()&&m.len()>0){0}else{1};}

    if args.len()==2 && args[0]=="--clear-icon-map" {return match clear_icon_map(Path::new(&args[1])){Ok(())=>0,Err(_)=>1};}
    if matches!(args.len(),3|4) && args[0]=="--icon-map" {return match build_icon_map(args){Ok(())=>0,Err(e)=>{terminal_eprintln!("ICON_MAP_UNAVAILABLE: {e}");1}};}
    if args.len()!=4 || !matches!(args[3].as_str(),"remote"|"media"|"remote-delete") {return 64;}
    let expected=if args[3]=="remote" {"appList_network.txt"} else if args[3]=="remote-delete" {"remote_delete.txt"} else {"mediaList.txt"};
    if Path::new(&args[0]).file_name().and_then(|s|s.to_str())!=Some(expected){return 64;}
    match serve_kind(&args[..3],Some(&args[3])){Ok(code)=>code,Err(e)=>{ui_error("open-selection", &e.to_string());65}}
}

#[path = "web_menu.rs"]
mod web_menu;
#[path = "web_console.rs"]
mod web_console;
pub fn console(args:&[String])->i32 { web_console::run(args) }
pub fn menu(args: &[String]) -> i32 { web_menu::run(args) }

fn web_language(save: Option<&str>) -> io::Result<String> {
    web_preference("language", "zh-Hant", |v| matches!(v,"zh-Hant"|"zh-Hans"), save)
}
fn valid_appearance(value: &str) -> bool {
    let fields:Vec<_>=value.split('\t').collect();
    fields.len()==2 && matches!(fields[0],"system"|"light"|"dark"|"space"|"night") && matches!(fields[1],"full"|"system"|"reduce")
}
fn web_preference(key: &str, default: &str, valid: fn(&str)->bool, save: Option<&str>) -> io::Result<String> {
    if save.is_some_and(|v| !valid(v)) { return Err(err("invalid web preference")); }
    let parent = Path::new("/data/local/tmp/.speedbackup-web-preferences");
    if save.is_some() {
        use std::os::unix::fs::DirBuilderExt;
        match fs::DirBuilder::new().mode(0o700).create(parent) { Ok(()) => {}, Err(e) if e.kind()==io::ErrorKind::AlreadyExists=>{},Err(e)=>return Err(e) }
    }
    let dir = match OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE | speedbackup_native_rs::O_DIRECTORY_NATIVE).open(parent) {
        Ok(f)=>f,Err(e) if save.is_none() && e.kind()==io::ErrorKind::NotFound=>return Ok(default.into()),Err(e)=>return Err(e),
    };
    let pm=dir.metadata()?;
    if pm.uid()!=0 || pm.mode()&0o777!=0o700 {return Err(err("web preferences directory identity"));}
    let path=parent.join(key);
    let old=match fs::symlink_metadata(&path) {
        Ok(m)=>{if !m.is_file() || m.uid()!=0 || m.nlink()!=1 || m.mode()&0o777!=0o600 {return Err(err("web preferences file identity"));}Some(stamp(&m))},
        Err(e) if e.kind()==io::ErrorKind::NotFound=>None,Err(e)=>return Err(e),
    };
    let mut guard=||->io::Result<()> {
        let m=fs::symlink_metadata(parent)?;
        if !m.is_dir() || (m.dev(),m.ino())!=(pm.dev(),pm.ino()) {return Err(err("web preferences directory changed"));}
        let now=match fs::symlink_metadata(&path){Ok(m)=>Some(stamp(&m)),Err(e) if e.kind()==io::ErrorKind::NotFound=>None,Err(e)=>return Err(e)};
        if now!=old {return Err(err("web preferences changed"));}Ok(())
    };
    if let Some(value)=save {
        super::publish_file::publish_bytes_guarded(value.as_bytes(), &path, Some(0o600), false, &mut guard)?;
        return Ok(value.into());
    }
    guard()?;
    let value=if old.is_some(){read(&path)?.0}else{default.into()};
    guard()?;
    if !valid(&value) {return Err(err("invalid saved web preference"));}
    Ok(value)
}

fn language_request(stream: &mut TcpStream, req: &Request, config: Option<&mut Session>, queue: Option<&Path>) -> Option<bool> {
    if req.path!="/api/language" {return None;}
    let result=match req.method.as_str(){
        "GET" if req.body.is_empty()=>web_language(None),
        "POST" if req.headers.get("content-type").is_some_and(|v|v=="text/plain;charset=UTF-8")=> (||->io::Result<String>{
            if !matches!(req.body.as_str(),"zh-Hant"|"zh-Hans"){return Err(err("invalid web language"));}
            if let Some(state)=config {
                let output=super::web_settings::language(&state.original,&req.body)?;
                state.save_text(&output)?;
                // Record the committed write even if a concurrent replacement prevents revalidation.
                state.original=output.clone();
                let (actual,metadata)=read(&state.path)?;
                if actual!=output{return Err(err("語言已寫入，但設定隨後變更，請重新開啟"));}
                state.original=actual;state.metadata=metadata;
            }
            if let Some(dir)=queue {web_console::queue_language(dir,&req.body)?;}
            web_language(Some(&req.body))
        })(),
        _=>Err(err("invalid language request")),
    };
    let success=result.is_ok();
    match result {Ok(text)=>{let _=respond(stream,"200 OK","text/plain",&text);},Err(e)=>{ui_error("preferences", &e.to_string());let _=respond(stream,"400 Bad Request","text/plain",&e.to_string());}}
    Some(success)
}

// Called by the shell only at idle/completion boundaries. Never executes a job.
pub fn language_reload(args:&[String])->i32 {
    let result=(||->io::Result<bool>{
        if args.len()!=2 || !matches!(args[1].as_str(),"zh-TW"|"zh-CN"){return Err(err("language-reload arguments"));}
        let mut state=Session::new(Path::new(&args[0]),false)?;
        if let Some((path,value,_lock))=web_console::pending_language()? {
            let output=super::web_settings::language(&state.original,&value)?;
            state.save_text(&output)?;state.original=output;
            fs::remove_file(path)?;
        }
        let fields=super::web_settings::parse(&state.original)?;
        let target=fields.iter().find(|f|f.key=="Shell_LANG").map(|f|f.value.as_str());
        Ok(matches!((target,args[1].as_str()),(Some("0"),"zh-CN")|(Some("1"),"zh-TW")))
    })();
    match result {Ok(true)=>10,Ok(false)=>0,Err(e)=>{eprintln!("language reload: {e}");1}}
}

// Used only by shell fallback after a web transport error. No HTTP dispatch.
pub fn focus_origin(args: &[String]) -> i32 {
    if !args.is_empty() { return 2; }
    let result=(|| -> io::Result<bool> {
        let dex=std::env::current_exe()?.parent().ok_or_else(||err("dex parent"))?.join("classes.dex");
        let (status,text)=bounded_output(Command::new("/system/bin/app_process").env("CLASSPATH",dex).args(["/system/bin","com.xayah.dex.AppListReturn","--focus-origin"]),10)?;
        Ok(status.success() && matches!(text.trim(),"RETURNED"|"ALREADY_ORIGIN"))
    })();
    if matches!(result,Ok(true)) {0} else {130}
}

pub fn prepare_origin(args: &[String]) -> i32 {
    if args.len()!=1 || !matches!(args[0].as_str(),"0"|"1") { return 2; }
    let result=(|| -> io::Result<bool> {
        let dex=std::env::current_exe()?.parent().ok_or_else(||err("dex parent"))?.join("classes.dex");
        let (status,text)=bounded_output(Command::new("/system/bin/app_process").env("CLASSPATH",dex).args(["/system/bin","com.xayah.dex.AppListReturn","--prepare-origin",&args[0]]),12)?;
        Ok(status.success() && text.trim()=="ORIGIN_OK")
    })();
    if matches!(result,Ok(true)) {0} else {130}
}

fn native_preference(key:&str,save:Option<&str>)->io::Result<String>{
    if key=="language" {return web_language(save);}
    // Compatibility endpoint only: obsolete saved styles cannot block startup.
    if key=="style" {
        if save.is_some_and(|v|v!="miuix") {return Err(err("unsupported component style"));}
        return Ok("miuix".into());
    }
    let (key,default,valid):(&str,&str,fn(&str)->bool)=if key=="scale" {
        ("scale","100",|v|matches!(v,"80"|"90"|"100"|"110"|"120"|"130"))
    }else if key=="monet"{("monet","on",|v|matches!(v,"on"|"off"))}
    else if key=="glass-blur"{("glass-blur","on",|v|matches!(v,"on"|"off"))}
    else if key=="glass-adaptive"{("glass-adaptive","off",|v|matches!(v,"on"|"off"))}
    else if matches!(key,"glass-blur-strength"|"glass-light"|"glass-transparency"|"glass-refraction"){
        (key,"100",|v|v.parse::<u8>().is_ok_and(|n|n<=100&&n.to_string()==v))
    }else{("appearance","system\tfull",valid_appearance)};
    web_preference(key,default,valid,save)
}

fn appearance_request(stream: &mut TcpStream, req: &Request) -> bool {
    // Called only after origin and session-token checks by all three controllers.
    if req.path=="/api/system-wallpaper" {
        let image=(||->io::Result<File>{
            if req.method!="POST" || req.body.is_empty() || req.body.len()>4 || !req.body.bytes().all(|b|b.is_ascii_digit()){return Err(err("invalid user"));}
            let user=req.body.parse::<u32>().map_err(|_|err("invalid user"))?;
            // Fixed home-wallpaper paths only. No shell or caller-supplied filesystem path.
            for path in [format!("/data/system/users/{user}/wallpaper"),format!("/data/system/users/{user}/wallpaper_orig"),format!("/data/system/users/{user}/wallpaper_desktop"),format!("/data/system/theme_magic/users/{user}/wallpaper")] {
                if let Ok(file)=OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE | speedbackup_native_rs::O_NONBLOCK).open(path){
                    let m=file.metadata()?;
                    if m.is_file() && m.len()>0 && m.len()<=32*1024*1024{return Ok(file);}
                }
            }
            Err(err("system wallpaper unavailable"))
        })();
        match image {
            Ok(file)=>{let _=(||->io::Result<()>{let size=file.metadata()?.len().min(32*1024*1024);write!(stream,"HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {size}\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n")?;io::copy(&mut file.take(size),stream)?;Ok(())})();}
            Err(_)=>{let _=respond(stream,"404 Not Found","text/plain","無法讀取系統靜態壁紙；原背景已保留。");}
        }
        return true;
    }
    if req.path=="/api/preferences" {
        let result=(||->io::Result<String>{
            if req.method!="GET" || !req.body.is_empty(){return Err(err("invalid preferences request"));}
            let mut fields=Vec::new();
            for key in ["appearance","scale","style","monet","glass-blur","glass-blur-strength","glass-light","glass-transparency","glass-refraction","glass-adaptive","language"] {
                fields.push(format!("{}:{}",json(key),json(&native_preference(key,None)?)));
            }
            Ok(format!("{{{}}}",fields.join(",")))
        })();
        match result {Ok(value)=>{let _=respond(stream,"200 OK","application/json",&value);},Err(e)=>{ui_error("preferences",&e.to_string());let _=respond(stream,"400 Bad Request","text/plain",&e.to_string());}}
        return true;
    }
    if req.path=="/api/diagnostic" {
        if req.method=="POST" && req.body.starts_with("native-") && req.body.len()<=128 && req.body.bytes().all(|b|b.is_ascii_alphanumeric()||matches!(b,b'-'|b':')) {
            let event=req.body.as_str();
            if matches!(event,"native-open"|"native-visible"|"native-hidden"|"native-close") {ui_event("native-lifecycle",event);}
            else {ui_transport_error("native-client",event);}
            let _=respond(stream,"200 OK","text/plain","OK");return true;
        }
        if req.method=="POST" && matches!(req.body.as_str(),"script-error"|"unhandled-rejection"|"network-failure"|"visible"|"hidden"|"pageshow") {
            ui_transport_error(if matches!(req.body.as_str(),"visible"|"hidden"|"pageshow"){"browser-lifecycle"}else{"browser"},&req.body);
            let _=respond(stream,"200 OK","text/plain","OK");
        } else {let _=respond(stream,"400 Bad Request","text/plain","無效診斷事件");}
        return true;
    }
    if !matches!(req.path.as_str(),"/api/appearance"|"/api/scale"|"/api/style"|"/api/monet"|"/api/glass-blur-strength"|"/api/glass-blur"|"/api/glass-light"|"/api/glass-transparency"|"/api/glass-refraction"|"/api/glass-adaptive") {return false;}
    let result=match req.method.as_str(){
        "GET" if req.body.is_empty()=>native_preference(req.path.trim_start_matches("/api/"),None),
        "POST" if req.headers.get("content-type").is_some_and(|v|v=="text/plain;charset=UTF-8")=>native_preference(req.path.trim_start_matches("/api/"),Some(&req.body)),
        _=>Err(err("invalid appearance request")),
    };
    match result {Ok(text)=>{let _=respond(stream,"200 OK","text/plain",&text);},Err(e)=>{ui_error("preferences", &e.to_string());let _=respond(stream,"400 Bad Request","text/plain",&e.to_string());}}
    true
}

#[cfg(test)]
mod metadata_resume_tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    #[test]
    fn ctime_only_resume_saves_but_permission_and_content_changes_conflict() {
        let dir=PathBuf::from(format!("/data/local/tmp/sb-ctime-{}",random_hex().unwrap()));
        fs::create_dir(&dir).unwrap();
        let path=dir.join("appList.txt");
        fs::write(&path,"# kept comment\nExample com.example.test\n").unwrap();
        fs::set_permissions(&path,fs::Permissions::from_mode(0o600)).unwrap();
        let session=Session::new_kind(&path,Some("apps")).unwrap();
        std::thread::sleep(Duration::from_millis(20));
        fs::set_permissions(&path,fs::Permissions::from_mode(0o600)).unwrap();
        assert_ne!((session.metadata.ctime(),session.metadata.ctime_nsec()),(fs::metadata(&path).unwrap().ctime(),fs::metadata(&path).unwrap().ctime_nsec()));
        session.save_text("# kept comment\n#Example com.example.test\n").unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(),"# kept comment\n#Example com.example.test\n");
        let session=Session::new_kind(&path,Some("apps")).unwrap();
        fs::set_permissions(&path,fs::Permissions::from_mode(0o640)).unwrap();
        assert!(session.unchanged().is_err());
        fs::set_permissions(&path,fs::Permissions::from_mode(0o600)).unwrap();
        fs::write(&path,"# external change\n").unwrap();
        assert!(session.save_text("overwrite").is_err());
        assert_eq!(fs::read_to_string(&path).unwrap(),"# external change\n");
        fs::remove_file(&path).unwrap();fs::remove_dir(&dir).unwrap();
    }
}
