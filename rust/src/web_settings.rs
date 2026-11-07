//! Literal conf form codec; no shell evaluation and no whole-file regeneration.
use super::applist_web::{err, json};
use std::{collections::BTreeSet, io};
pub struct Field {
    pub key: String,
    pub value: String,
    help: String,
    start: usize,
    end: usize,
}
fn internal_setting(key: &str) -> bool {
    matches!(key, "diagnostic_mode" | "webdav_stream_heartbeat_sec"
        | "webdav_stream_progress_step_mb" | "webdav_stream_idle_warn_sec"
        | "webdav_stream_stall_abort_sec" | "webdav_stream_verbose"
        | "webdav_stream_post_body_timeout_sec" | "webdav_stream_finalize_timeout_sec"
        | "stream_background_boost" | "stream_background_boost_mode"
        | "stream_background_boost_target" | "stream_background_boost_interval_sec"
        | "stream_background_boost_burst_interval_sec" | "stream_background_boost_burst_sec"
        | "stream_background_boost_idle_ms" | "stream_background_boost_verbose")
}
pub fn parse(text: &str) -> io::Result<Vec<Field>> {
    if text.len() > 262144 || text.contains('\0') || text.starts_with('\u{feff}') {
        return Err(err("設定檔格式或大小不支援"));
    }
    let b = text.as_bytes();
    let mut i = 0;
    let mut out = Vec::new();
    let mut seen = BTreeSet::new();
    let mut help = String::new();
    while i < b.len() {
        let line_end = text[i..].find('\n').map(|n| i + n).unwrap_or(b.len());
        let line = text[i..line_end]
            .strip_suffix('\r')
            .unwrap_or(&text[i..line_end]);
        let trimmed = line.trim_start();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            if trimmed.starts_with('#') && help.len() < 4096 {
                help.push_str(trimmed.trim_start_matches('#').trim());
                help.push('\n');
            }
            i = (line_end + 1).min(b.len());
            continue;
        }
        let eq = line
            .find('=')
            .ok_or_else(|| err("設定檔含非指定格式內容，請用文字入口確認"))?;
        let key = line[..eq].trim();
        if key.is_empty()
            || !key.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_')
            || key.as_bytes()[0].is_ascii_digit()
            || !seen.insert(key.to_string())
        {
            return Err(err("設定名稱無效或重複，未開放表單編輯"));
        }
        let start = i + eq + 1;
        let mut end = i + line.len();
        let value;
        if matches!(b.get(start), Some(b'"' | b'\'')) {
            let quote = b[start];
            let mut at = start + 1;
            let mut raw = Vec::new();
            let mut closed = false;
            while at < b.len() {
                if at == line_end && quote == b'"' && line.ends_with("\\\"") {
                    return Err(err(
                        "此多行引號與舊設定解碼規則衝突，請調整第一行或使用文字入口",
                    ));
                }
                // The shell strips CR from the first physical line only.
                if at + 1 == line_end && b[at] == b'\r' {
                    at += 1;
                    continue;
                }
                if b[at] == quote {
                    end = at + 1;
                    closed = true;
                    break;
                }
                if quote == b'"'
                    && b[at] == b'\\'
                    && at + 1 < b.len()
                    && b"\\\"$`".contains(&b[at + 1])
                {
                    at += 1;
                }
                raw.push(b[at]);
                at += 1;
            }
            if !closed {
                return Err(err("設定值引號未結束，請用文字入口確認"));
            }
            let tail_end = text[end..].find('\n').map(|n| end + n).unwrap_or(b.len());
            let tail = text[end..tail_end].trim_matches(|c:char|c.is_ascii_whitespace());
            if !tail.is_empty() && !tail.starts_with('#') {
                return Err(err("設定值後有非註解內容"));
            }
            value = String::from_utf8(raw).map_err(|_| err("設定值編碼錯誤"))?;
            i = (tail_end + 1).min(b.len());
        } else {
            value = text[start..end].to_string();
            i = (line_end + 1).min(b.len());
        }
        out.push(Field {
            key: key.to_string(),
            value,
            help: std::mem::take(&mut help),
            start,
            end,
        });
        if out.len() > 256 {
            return Err(err("設定欄位過多"));
        }
    }
    Ok(out)
}
pub fn data(text: &str) -> io::Result<String> {
    Ok(format!(
        "[{}]",
        parse(text)?
            .iter()
            .filter(|f| !internal_setting(&f.key))
            .map(|f| format!(
                "{{\"key\":{},\"value\":{},\"help\":{}}}",
                json(&f.key),
                json(&f.value),
                json(&f.help)
            ))
            .collect::<Vec<_>>()
            .join(",")
    ))
}
fn quote(value: &str) -> String {
    if value.contains('\n') && !value.contains('\'') {
        return format!("'{}'", value);
    }
    let mut out = String::from("\"");
    for c in value.chars() {
        if matches!(c, '\\' | '"' | '$' | '`') {
            out.push('\\');
        }
        out.push(c);
    }
    out.push('"');
    out
}
pub fn edit(text: &str, body: &str) -> io::Result<String> {
    let fields = parse(text)?;
    let mut values = std::collections::BTreeMap::new();
    for line in body.lines() {
        let (key, hex) = line
            .split_once('\t')
            .ok_or_else(|| err("設定請求格式錯誤"))?;
        if hex.len() % 2 != 0 || hex.len() > 524288 || !hex.bytes().all(|c| c.is_ascii_hexdigit()) {
            return Err(err("設定值編碼錯誤"));
        }
        let raw: Vec<u8> = (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect();
        let value = String::from_utf8(raw).map_err(|_| err("設定值不是UTF-8"))?;
        if value.contains('\0') || values.insert(key.to_string(), value).is_some() {
            return Err(err("設定值無效或重複"));
        }
    }
    let public: Vec<_> = fields.iter().filter(|f| !internal_setting(&f.key)).collect();
    if values.len() != public.len() || public.iter().any(|f| !values.contains_key(&f.key)) {
        return Err(err("設定欄位不完整或含未知名稱"));
    }
    let mut output = text.to_string();
    for f in fields.iter().rev() {
        if internal_setting(&f.key) { continue; }
        let v = &values[&f.key];
        if v != &f.value {
            if v.contains('\r') {
                return Err(err("新設定值不可含CR字元"));
            }
            output.replace_range(f.start..f.end, &quote(v));
        }
    }
    let check = parse(&output)?;
    if check.len() != fields.len()
        || check
            .iter()
            .zip(&fields)
            .any(|(a, b)| a.key != b.key || &a.value != if internal_setting(&a.key) { &b.value } else { &values[&a.key] })
    {
        return Err(err("設定寫回驗證不符"));
    }
    Ok(output)
}

pub fn language(text:&str, lang:&str)->io::Result<String>{
    let code=match lang {"zh-Hant"=>"0","zh-Hans"=>"1",_=>return Err(err("invalid language"))};
    let fields=parse(text)?;
    if !fields.iter().any(|f|f.key=="Shell_LANG"){return Err(err("設定缺少 Shell_LANG"));}
    let mut out=String::new();let mut at=0;
    for f in &fields {
        // User comments and disabled paths must remain byte-identical.
        out.push_str(&text[at..f.start]);
        if f.key=="Shell_LANG" {out.push_str(&quote(code));}else{out.push_str(&text[f.start..f.end]);}
        at=f.end;
    }
    out.push_str(&text[at..]);
    let checked=parse(&out)?;
    if checked.len()!=fields.len()||checked.iter().zip(fields.iter()).any(|(a,b)|a.key!=b.key||(a.key!="Shell_LANG"&&a.value!=b.value)||(a.key=="Shell_LANG"&&a.value!=code)){return Err(err("language conf verification"));}
    Ok(out)
}

#[cfg(test)] mod review_tests {
 use super::*;
 #[test] fn internal_fields_are_hidden_and_not_editable() {
  let text="# keep\nwebdav_stream_verbose=1\nShell_LANG=0\nCustom_path='/sdcard/a\n# /sdcard/disabled'\n";
  assert!(!data(text).unwrap().contains("webdav_stream_verbose"));
  let body="Shell_LANG\t30\nCustom_path\t2f7364636172642f610a23202f7364636172642f64697361626c6564";
  assert_eq!(edit(text,body).unwrap(),text);
  assert!(edit(text,&format!("{body}\nwebdav_stream_verbose\t30")).is_err());
  let changed=edit(text,&body.replace("Shell_LANG\t30","Shell_LANG\t31")).unwrap();
  assert_eq!(changed,text.replace("Shell_LANG=0","Shell_LANG=\"1\""));
 }
 #[test] fn non_ascii_tail_is_rejected(){assert!(parse("Key=\"x\"\u{3000}#comment\n").is_err());assert!(parse("Key=\"x\" \t#comment\n").is_ok());}
 #[test] fn language_keeps_user_comments_and_paths() {
  let text="# 使用者註釋 /sdcard/資料夾\nShell_LANG=\"0\" # 保留\nCustom_path=\"/sdcard/測試\"\n#Disabled=/sdcard/應用\n";
  assert_eq!(language(text,"zh-Hans").unwrap(),text.replacen("Shell_LANG=\"0\"","Shell_LANG=\"1\"",1));
 }
}
