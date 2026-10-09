//! Ordered JSON transformations for persisted profiles. No Android operations.
use super::*;
#[derive(Clone, Debug)]
enum V {
    Object(Vec<(String, V)>),
    Array(Vec<V>),
    String(String),
    Atom(String),
}
fn decode(s: &str) -> Result<String, String> {
    let mut it = s[1..s.len() - 1].chars();
    let mut out = String::new();
    while let Some(c) = it.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        out.push(match it.next().ok_or("escape")? {
            '"' => '"',
            '\\' => '\\',
            '/' => '/',
            'b' => '\u{8}',
            'f' => '\u{c}',
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            'u' => {
                let mut hex = || -> Result<u32, String> {
                    let h: String = it.by_ref().take(4).collect();
                    if h.len() != 4 {
                        return Err("unicode".into());
                    }
                    u32::from_str_radix(&h, 16).map_err(|_| "unicode".into())
                };
                let a = hex()?;
                let cp = if (0xd800..=0xdbff).contains(&a) {
                    if it.next() != Some('\\') || it.next() != Some('u') {
                        return Err("surrogate".into());
                    }
                    let h: String = it.by_ref().take(4).collect();
                    let b = u32::from_str_radix(&h, 16).map_err(|_| "surrogate")?;
                    if !(0xdc00..=0xdfff).contains(&b) {
                        return Err("surrogate".into());
                    }
                    0x10000 + ((a - 0xd800) << 10) + (b - 0xdc00)
                } else {
                    a
                };
                char::from_u32(cp).ok_or("unicode scalar")?
            }
            _ => return Err("escape".into()),
        });
    }
    Ok(out)
}
fn quote(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            '\u{8}' => o.push_str("\\b"),
            '\u{c}' => o.push_str("\\f"),
            c if c < ' ' => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}
fn parse(s: &str) -> Result<V, String> {
    let s = s.trim();
    if !json_document_parse_ok(s) {
        return Err("invalid JSON".into());
    }
    parse_valid(s)
}
fn parse_valid(s: &str) -> Result<V, String> {
    Ok(match s.as_bytes().first() {
        Some(b'{') => {
            let mut v = V::Object(vec![]);
            for (k, x) in json_object_entries_raw(s) {
                v.put(&decode(&k)?, parse_valid(&x)?)
            }
            v
        }
        Some(b'[') => V::Array(
            json_array_items_raw(s)
                .iter()
                .map(|x| parse_valid(x))
                .collect::<Result<_, _>>()?,
        ),
        Some(b'"') => V::String(decode(s)?),
        _ => V::Atom(s.to_string()),
    })
}
impl V {
    fn get(&self, k: &str) -> Option<&V> {
        if let V::Object(v) = self {
            v.iter().find(|(n, _)| n == k).map(|(_, x)| x)
        } else {
            None
        }
    }
    fn put(&mut self, k: &str, x: V) {
        if let V::Object(v) = self {
            if let Some((_, old)) = v.iter_mut().find(|(n, _)| n == k) {
                *old = x
            } else {
                v.push((k.into(), x))
            }
        }
    }
    fn truth(&self) -> bool {
        !matches!(self,V::Atom(x) if x=="null"||x=="false")
    }
    fn text(&self) -> Option<&str> {
        if let V::String(s) = self {
            Some(s)
        } else {
            None
        }
    }
    fn object(&self) -> bool {
        matches!(self, V::Object(_))
    }
    fn emit(&self, pretty: bool, depth: usize) -> String {
        match self {
            V::String(s) => quote(s),
            V::Atom(s) => s.clone(),
            V::Object(v) => {
                let parts: Vec<_> = v
                    .iter()
                    .map(|(k, x)| {
                        format!(
                            "{}{}{}",
                            quote(k),
                            if pretty { ": " } else { ":" },
                            x.emit(pretty, depth + 1)
                        )
                    })
                    .collect();
                container("{", "}", parts, pretty, depth)
            }
            V::Array(v) => container(
                "[",
                "]",
                v.iter().map(|x| x.emit(pretty, depth + 1)).collect(),
                pretty,
                depth,
            ),
        }
    }
}
fn container(a: &str, b: &str, p: Vec<String>, pretty: bool, d: usize) -> String {
    if p.is_empty() {
        return format!("{}{}", a, b);
    }
    if pretty {
        let pad = "  ".repeat(d + 1);
        format!(
            "{}\n{}{}\n{}{}",
            a,
            pad,
            p.join(&format!(",\n{}", pad)),
            "  ".repeat(d),
            b
        )
    } else {
        format!("{}{}{}", a, p.join(","), b)
    }
}
fn atom(s: &str) -> V {
    V::Atom(s.into())
}
fn obj() -> V {
    V::Object(vec![])
}
fn alt(v: &V, k: &str, d: V) -> V {
    v.get(k).filter(|x| x.truth()).cloned().unwrap_or(d)
}
fn pick(v: &V, keys: &[&str], nulls: bool) -> V {
    let mut o = obj();
    for k in keys {
        if let Some(x) = v.get(k) {
            if nulls || !matches!(x,V::Atom(s)if s=="null") {
                o.put(k, x.clone())
            }
        }
    }
    o
}
const PERM: &[&str] = &[
    "name",
    "nameCn",
    "granted",
    "flags",
    "runtime",
    "development",
    "appOp",
    "appOpName",
    "appOpNameCn",
    "packageMode",
    "uidMode",
    "scope",
    "appOpMode",
    "appOpModeName",
    "appOpModeCn",
    "appOpStoredMode",
    "appOpRestoreMode",
    "locationEnabled",
];
const SPECIAL: &[&str] = &[
    "keyCn",
    "publicName",
    "publicNameCn",
    "manifestPermission",
    "manifestPermissionCn",
    "requested",
    "supported",
    "op",
    "packageMode",
    "uidMode",
    "scope",
    "mode",
    "modeName",
    "modeCn",
];
const OP: &[&str] = &[
    "op",
    "publicName",
    "publicNameCn",
    "supported",
    "packageMode",
    "uidMode",
    "scope",
    "mode",
    "modeName",
    "modeCn",
];
const ENTRY: &[&str] = &[
    "keystore",
    "path",
    "Size",
    "size",
    "apk_size",
    "data_size",
    "obb_size",
    "media_size",
    "origin_size",
    "archive_input_bytes",
    "change_fingerprint",
    "timeline_archive",
    "apk_version",
    "versionCode",
    "PackageName",
];
const REFRESH: &[&str] = &[
    "Size",
    "size",
    "apk_size",
    "data_size",
    "obb_size",
    "media_size",
    "origin_size",
    "archive_input_bytes",
    "change_fingerprint",
    "timeline_archive",
    "path",
    "keystore",
    "apk_version",
    "versionCode",
];
fn payload(v: &V) -> bool {
    [
        "Size",
        "size",
        "path",
        "keystore",
        "apk_size",
        "data_size",
        "obb_size",
        "media_size",
        "origin_size",
    ]
    .iter()
    .any(|k| v.get(k).is_some())
}
fn compact(s: &V) -> Result<V, String> {
    if !s.object() {
        return Err("state must be object".into());
    }
    let mut o = obj();
    for (k, d) in [
        ("schemaVersion", atom("2")),
        ("recordType", V::String("snapshot".into())),
        ("userId", atom("0")),
        ("packageName", atom("null")),
    ] {
        o.put(k, alt(s, k, d))
    }
    let installer = alt(
        s,
        "installer",
        s.get("package")
            .map(|p| alt(p, "installer", atom("null")))
            .filter(V::truth)
            .unwrap_or_else(|| {
                s.get("installDiagnostics")
                    .map(|d| alt(d, "installer", alt(d, "installing", atom("null"))))
                    .unwrap_or(atom("null"))
            }),
    );
    o.put("installer", installer);
    for (k, keys) in [
        ("permissions", PERM),
        ("specialAccess", SPECIAL),
        ("batterySettings", OP),
        ("otherAppOps", OP),
    ] {
        let array = k == "permissions" || k == "otherAppOps";
        let v = alt(s, k, if array { V::Array(vec![]) } else { obj() });
        let converted = match v {
            V::Array(xs) if array => V::Array(xs.iter().map(|x| pick(x, keys, false)).collect()),
            V::Object(xs) if !array => V::Object(
                xs.into_iter()
                    .map(|(n, x)| {
                        let out = if k == "batterySettings" && !x.object() {
                            x
                        } else {
                            pick(&x, keys, false)
                        };
                        (n, out)
                    })
                    .collect(),
            ),
            _ => return Err(format!("invalid {}", k)),
        };
        o.put(k, converted);
    }
    o.put("ssaid", alt(s, "ssaid", atom("null")));
    Ok(o)
}
fn normalize(root: &V) -> Result<V, String> {
    let mut out = obj();
    if let Some(t) = root.get("Backup time") {
        out.put("Backup time", t.clone())
    }
    let fields = match root {
        V::Object(v) => v,
        _ => return Err("profile must be object".into()),
    };
    for (k, v) in fields {
        if k == "Backup time" {
            continue;
        }
        let st = v.get("app_state");
        let pkg = alt(
            v,
            "PackageName",
            st.map(|x| alt(x, "packageName", atom("null")))
                .unwrap_or(atom("null")),
        );
        let has_package = [v.get("PackageName"), st.and_then(|x| x.get("packageName"))]
            .iter()
            .any(|x| matches!(x, Some(x) if !matches!(x, V::Atom(s) if s == "null")));
        if v.object() && has_package {
            let mut e = pick(v, ENTRY, false);
            e.put("PackageName", pkg);
            if let Some(st) = st.filter(|s| s.object()) {
                e.put("app_state", compact(st)?)
            }
            if let V::Object(fields) = &mut e {
                fields.retain(|(_, value)| !matches!(value, V::Atom(s) if s == "null"));
            }
            out.put(k, e);
        } else if payload(v) {
            out.put(k, pick(v, ENTRY, false))
        }
    }
    Ok(out)
}
fn read(p: &str) -> Result<V, String> {
    parse(&fs::read_to_string(p).map_err(|e| e.to_string())?)
}
fn persistable(v: &V) -> bool {
    v.get("recordType").and_then(V::text) == Some("snapshot")
        && matches!(v.get("schemaVersion"),Some(V::Atom(n)) if n.parse::<f64>().ok()==Some(2.0))
        && v.get("packageName")
            .map(|x| !matches!(x,V::Atom(n)if n=="null"))
            .unwrap_or(false)
        && matches!(v.get("permissions"), Some(V::Array(_)))
        && matches!(v.get("otherAppOps"), Some(V::Array(_)))
        && v.get("specialAccess").map(V::object) == Some(true)
        && v.get("batterySettings").map(V::object) == Some(true)
}
fn valid(v: &V) -> bool {
    !matches!(v,V::Atom(s)if s=="null") && v.text() != Some("") && v.text() != Some("null")
}
fn backup(old: &V, entry: &str, state: &V, prefix: &str) -> Result<(), String> {
    if !persistable(state) {
        return Err("invalid snapshot".into());
    }
    let empty = obj();
    let oe = old.get(entry).unwrap_or(&empty);
    let missing =
        oe.get("app_state").is_none() || matches!(oe.get("app_state"),Some(V::Atom(s))if s=="null");
    let previous = alt(oe, "app_state", atom("null"));
    let previous = if !missing && persistable(&previous) {
        compact(&previous)?
    } else {
        previous
    };
    let current = compact(state)?;
    let changed = missing || previous.emit(false, 0) != current.emit(false, 0);
    write(&format!("{}.old", prefix), &previous, false)?;
    write(&format!("{}.new", prefix), &current, false)?;
    if changed {
        let mut merged = current;
        for (key, legacy) in [("ssaid", "Ssaid"), ("installer", "installer")] {
            let oldval = oe
                .get("app_state")
                .map(|s| alt(s, key, atom("null")))
                .filter(V::truth)
                .unwrap_or_else(|| alt(oe, legacy, atom("null")));
            if !valid(&alt(&merged, key, atom("null"))) && valid(&oldval) {
                merged.put(key, oldval)
            }
        }
        let mut out = old.clone();
        let mut e = oe.clone();
        if !e.object() {
            e = obj()
        }
        e.put("app_state", merged);
        out.put(entry, e);
        write(&format!("{}.out", prefix), &normalize(&out)?, true)?;
    }
    println!("{}\n{}", missing as u8, changed as u8);
    Ok(())
}
fn write(p: &str, v: &V, pretty: bool) -> Result<(), String> {
    fs::write(p, format!("{}\n", v.emit(pretty, 0))).map_err(|e| e.to_string())
}

// Publish a complete validated document beside its destination. Never truncate
// the existing document if writing the replacement fails.
fn publish_document(path: &str, body: &[u8]) -> Result<(), String> {
    let dst = std::path::Path::new(path);
    let parent = dst.parent().ok_or("missing parent")?;
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    if fs::symlink_metadata(dst).map(|m| m.file_type().is_symlink()).unwrap_or(false) {
        return Err("refuse symlink document".into());
    }
    let tmp = parent.join(format!(".profile-publish-{}-{}", std::process::id(),
        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|e| e.to_string())?.as_nanos()));
    let result = (|| {
        let mut f = std::fs::OpenOptions::new().write(true).create_new(true).open(&tmp).map_err(|e| e.to_string())?;
        if let Ok(m) = fs::metadata(dst) { f.set_permissions(m.permissions()).map_err(|e| e.to_string())?; }
        std::io::Write::write_all(&mut f, body).map_err(|e| e.to_string())?;
        drop(f);
        fs::rename(&tmp, dst).map_err(|e| e.to_string())
    })();
    if result.is_err() { let _ = fs::remove_file(&tmp); }
    result
}

fn finalize_stage(source: &str, target: &str) -> Result<(), String> {
    let original = read(source)?;
    if !original.object() { return Err("profile must be object".into()); }
    let normalized = normalize(&original)?;
    if matches!(&normalized, V::Object(fields) if fields.is_empty()) {
        println!("SBRESULT\t1\tprofile-stage\tempty\t0\t0");
        return Ok(());
    }
    let body = format!("{}\n", normalized.emit(true, 0));
    // Validate serialized bytes before either publication.
    parse(&body)?;
    let changed = fs::read(target).map(|v| v != body.as_bytes()).unwrap_or(true);
    if fs::read(source).map_err(|e| e.to_string())? != body.as_bytes() {
        publish_document(source, body.as_bytes())?;
    }
    if target != source && changed { publish_document(target, body.as_bytes())?; }
    println!("SBRESULT\t1\tprofile-stage\tok\t{}\t{}", body.len(), changed as u8);
    Ok(())
}
fn refresh(old: &V, entry: &str, pkg: &str, state: &V) -> Result<V, String> {
    let empty = obj();
    let oe = old.get(entry).unwrap_or(&empty);
    let mut out = obj();
    if let Some(t) = old.get("Backup time") {
        out.put("Backup time", t.clone())
    }
    if let V::Object(fields) = old {
        for (k, v) in fields {
            if k != entry && k != "Backup time" && payload(v) {
                out.put(k, pick(v, REFRESH, true))
            }
        }
    }
    let mut e = pick(oe, REFRESH, true);
    let mut s = compact(state)?;
    let prev = oe
        .get("app_state")
        .map(|x| alt(x, "ssaid", atom("null")))
        .filter(V::truth)
        .unwrap_or_else(|| alt(oe, "Ssaid", atom("null")));
    if prev.truth() && prev.text() != Some("") && prev.text() != Some("null") {
        s.put("ssaid", prev)
    }
    e.put("PackageName", alt(oe, "PackageName", V::String(pkg.into())));
    e.put("app_state", s);
    out.put(entry, e);
    normalize(&out)
}
fn queue(input: &str, output: &str) -> Result<(), String> {
    let f = File::open(input).map_err(|e| e.to_string())?;
    let mut rows = Vec::new();
    let mut last = HashMap::new();
    for line in BufReader::new(f).lines() {
        let line = line.map_err(|e| e.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        let v = parse(&line)?;
        let key = v
            .get("packageName")
            .and_then(V::text)
            .filter(|s| !s.is_empty())
            .ok_or("queue package missing")?
            .to_string();
        last.insert(key.clone(), rows.len());
        rows.push((key, v));
    }
    let mut out = String::new();
    for (i, (k, v)) in rows.iter().enumerate() {
        if last.get(k) == Some(&i) {
            out.push_str(&v.emit(false, 0));
            out.push('\n')
        }
    }
    fs::write(output, out).map_err(|e| e.to_string())
}
pub(super) fn run(args: &[String]) -> i32 {
    let r = (|| -> Result<(), String> {
        match args.get(2).map(String::as_str) {
            Some("queue") if args.len() == 5 => queue(&args[3], &args[4]),
            Some("compact") if args.len() == 3 => {
                let mut s = String::new();
                io::stdin()
                    .read_to_string(&mut s)
                    .map_err(|e| e.to_string())?;
                println!("{}", compact(&parse(&s)?)?.emit(false, 0));
                Ok(())
            }
            Some("normalize") if args.len() == 5 => {
                write(&args[4], &normalize(&read(&args[3])?)?, true)
            }
            Some("finalize-stage") if args.len() == 5 => finalize_stage(&args[3], &args[4]),
            Some("backup") if args.len() == 7 => {
                backup(&read(&args[3])?, &args[4], &read(&args[5])?, &args[6])
            }
            Some("refresh") if args.len() == 8 => write(
                &args[7],
                &refresh(&read(&args[3])?, &args[4], &args[5], &read(&args[6])?)?,
                true,
            ),
            _ => Err("profile: invalid arguments".into()),
        }
    })();
    match r {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("PROFILE_ERROR {}", e);
            1
        }
    }
}

#[path = "json_ops.rs"]
mod json_ops;
pub(super) fn json_run(args: &[String]) -> i32 {
    json_ops::run(args)
}

pub(super) fn persistable_json(raw: &str) -> bool {
    parse(raw)
        .map(|v| {
            persistable(&v)
                && v.get("packageName")
                    .and_then(V::text)
                    .map(|s| !s.is_empty())
                    .unwrap_or(false)
        })
        .unwrap_or(false)
}

pub(super) fn entry_fingerprints(raw: &str) -> String {
    let value = parse(raw).ok();
    ["user", "user_de", "data", "obb", "media"]
        .iter()
        .map(|entry| {
            value
                .as_ref()
                .and_then(|v| v.get(entry))
                .and_then(|e| e.get("change_fingerprint"))
                .and_then(V::text)
                .unwrap_or("")
                .to_owned()
        })
        .collect::<Vec<_>>()
        .join("\t")
}

/// Decode a JSON string using the same validated Unicode parser as profiles.
pub fn string_value(raw: &str) -> Option<String> {
    match parse(raw).ok()? {
        V::String(s) => Some(s),
        _ => None,
    }
}

pub(super) fn top_string(body: &str, keys: &[&str]) -> Option<String> {
    let root = parse(body).ok()?;
    let direct = |value: &V| keys.iter().find_map(|key| match value.get(key) {
        Some(V::String(value)) => Some(value.clone()),
        _ => None,
    });
    direct(&root).or_else(|| match &root {
        V::Object(entries) => entries.iter().find_map(|(_, value)| match value {
            V::Object(_) => direct(value),
            _ => None,
        }),
        _ => None,
    })
}
