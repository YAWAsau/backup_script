//! Ordered JSON transformations for persisted profiles. No Android operations.
use super::*;
#[derive(Clone, Debug)]
enum V {
    Object(Vec<(String, V)>),
    Array(Vec<V>),
    String(String),
    Atom(String),
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
#[path = "json_parse.rs"]
mod json_parse;
fn parse(s: &str) -> Result<V, String> { json_parse::parse(s) }
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
            if *k=="icon_png_base64" && !x.text().is_some_and(valid_icon){continue;}
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
    "xposed",
    "icon_png_base64",
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
    "xposed",
    "icon_png_base64",
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
// Only bounded, checksum-valid 48/64/128-square RGBA PNGs can enter a persisted icon or WebUI.
pub(super) fn valid_icon(value:&str)->bool {
    if value.is_empty()||value.len()>43692||value.len()%4!=0{return false;}
    let mut bytes=Vec::with_capacity(value.len()/4*3);
    let digit=|b:u8|->Option<u32>{Some(match b{b'A'..=b'Z'=>(b-b'A') as u32,b'a'..=b'z'=>(b-b'a'+26) as u32,b'0'..=b'9'=>(b-b'0'+52) as u32,b'+'=>62,b'/'=>63,_=>return None})};
    for (i,c) in value.as_bytes().chunks_exact(4).enumerate(){
        let Some(a)=digit(c[0]) else{return false;};let Some(b)=digit(c[1]) else{return false;};
        let pad=if c[2]==b'=' {if c[3]!=b'='||b&15!=0{return false;}2}else if c[3]==b'=' {1}else{0};
        if pad>0 && (i+1)*4!=value.len(){return false;}
        let d=if pad==2{0}else{let Some(d)=digit(c[2]) else{return false;};d};
        if pad==1&&d&3!=0{return false;}
        let e=if pad>0{0}else{let Some(e)=digit(c[3]) else{return false;};e};
        let n=(a<<18)|(b<<12)|(d<<6)|e;bytes.push((n>>16)as u8);if pad<2{bytes.push((n>>8)as u8);}if pad==0{bytes.push(n as u8);}
    }
    if bytes.len()>32768||!bytes.starts_with(b"\x89PNG\r\n\x1a\n"){return false;}
    let mut pos=8;let mut first=true;let mut data=false;
    while pos+12<=bytes.len(){
        let n=u32::from_be_bytes(bytes[pos..pos+4].try_into().unwrap())as usize;
        if n>32768||pos+12+n>bytes.len(){return false;}
        let kind=&bytes[pos+4..pos+8];let body=&bytes[pos+8..pos+8+n];
        let mut crc=0xffffffffu32;for b in &bytes[pos+4..pos+8+n]{crc^=*b as u32;for _ in 0..8{crc=(crc>>1)^if crc&1!=0{0xedb88320}else{0};}}
        if (crc^0xffffffff)!=u32::from_be_bytes(bytes[pos+8+n..pos+12+n].try_into().unwrap()){return false;}
        if first {if kind!=b"IHDR"||!(body==[0,0,0,48,0,0,0,48,8,6,0,0,0]||body==[0,0,0,64,0,0,0,64,8,6,0,0,0]||body==[0,0,0,128,0,0,0,128,8,6,0,0,0]){return false;}first=false;}
        else if kind==b"IHDR"{return false;}
        if kind==b"IDAT"{data=true;}
        pos+=12+n;
        if kind==b"IEND"{return n==0&&data&&pos==bytes.len();}
    }
    false
}
pub(super) fn module_metadata(body:&str,pkg:&str)->bool {
    let Ok(root)=parse(body)else{return false;};
    let records=if root.get("PackageName").is_some(){vec![&root]}else{match &root{V::Object(fields)=>fields.iter().map(|(_,v)|v).collect(),_=>Vec::new()}};
    records.iter().any(|r|r.get("PackageName").and_then(V::text)==Some(pkg)&&matches!(r.get("xposed"),Some(V::Atom(v))if v=="true"))
}
fn attach_module_value(file:&str,entry:&str,pkg:&str)->Result<bool,String>{
    if !pkg.bytes().all(|b|b.is_ascii_alphanumeric()||matches!(b,b'.'|b'_'))||!pkg.contains('.'){return Err("module package".into());}
    let Some(cache)=std::env::var_os("SPEEDBACKUP_MODULE_FACTS")else{return Ok(false);};
    let path=std::path::PathBuf::from(cache);let meta=fs::symlink_metadata(&path).map_err(|e|e.to_string())?;
    if !meta.is_dir()||meta.uid()!=0||meta.mode()&0o777!=0o700{return Err("module cache identity".into());}
    if fs::read(path.join("READY")).ok().as_deref()!=Some(b"1"){return Err("module cache incomplete".into());}
    let Ok(value)=fs::read_to_string(path.join(pkg))else{return Ok(false);};
    let flag=match value.as_str(){"0"=>"false","1"=>"true",_=>return Err("module fact".into())};
    let mut root=read(file)?;let flat=root.get("PackageName").and_then(V::text)==Some(pkg);let mut record=if flat{root.clone()}else{root.get(entry).ok_or("module record")?.clone()};
    if record.get("PackageName").and_then(V::text)!=Some(pkg){return Err("module identity".into());}
    if matches!(record.get("xposed"),Some(V::Atom(v))if v==flag){return Ok(false);}
    record.put("xposed",V::Atom(flag.into()));if flat{root=record;}else{root.put(entry,record);}
    publish_document(file,format!("{}\n",root.emit(true,0)).as_bytes())?;Ok(true)
}
fn attach_module(file:&str,entry:&str,pkg:&str)->Result<(),String>{println!("{}",u8::from(attach_module_value(file,entry,pkg)?));Ok(())}
pub(super) fn icon_metadata(body:&str)->Option<(String,String)>{
    let root=parse(body).ok()?;
    let records:Vec<&V>=if root.get("PackageName").and_then(V::text).is_some(){vec![&root]}else{
        let V::Object(fields)=&root else{return None;};fields.iter().map(|(_,v)|v).collect()
    };
    let mut package:Option<String>=None;let mut icon=String::new();
    for record in records {
        if let Some(pkg)=record.get("PackageName").and_then(V::text){
            if package.as_deref().is_some_and(|p|p!=pkg){return None;}
            package=Some(pkg.to_owned());
            if icon.is_empty(){if let Some(value)=record.get("icon_png_base64").and_then(V::text).filter(|v|valid_icon(v)){icon=value.to_owned();}}
        }
    }
    Some((package?,icon))
}
fn attach_icon_value(file:&str,entry:&str,pkg:&str,icon:&str)->Result<bool,String>{
    let mut root=read(file)?;
    let key=if root.get(entry).and_then(|v|v.get("PackageName")).and_then(V::text)==Some(pkg){entry.to_owned()}
        else {match &root {V::Object(rows)=>{let keys:Vec<_>=rows.iter().filter(|(_,v)|v.get("PackageName").and_then(V::text)==Some(pkg)).map(|(k,_)|k.clone()).collect();if keys.len()!=1{return Err("icon package mismatch".into());}keys[0].clone()},_=>return Err("icon object".into())}};
    let mut input=super::applist_web::open_icon_file(std::path::Path::new(icon)).map_err(|e|e.to_string())?;
    let mut value=String::new();std::io::Read::take(&mut input,43693).read_to_string(&mut value).map_err(|e|e.to_string())?;
    if !valid_icon(&value){return Err("invalid optional icon".into());}
    let mut record=root.get(&key).unwrap().clone();
    if record.get("icon_png_base64").and_then(V::text)==Some(value.as_str()){return Ok(false);}
    record.put("icon_png_base64",V::String(value));root.put(&key,record);
    publish_document(file,format!("{}\n",root.emit(true,0)).as_bytes())?;Ok(true)
}
fn attach_icon(file:&str,entry:&str,pkg:&str,icon:&str)->Result<(),String>{
    println!("{}",if attach_icon_value(file,entry,pkg,icon)?{1}else{0});Ok(())
}
// A valid legacy 48-square PNG remains a fallback, but must not suppress an HD refresh.
pub(super) fn legacy_icon(value:&str)->bool {
    // First 24 PNG bytes include signature, IHDR type, width and height.
    value.starts_with("iVBORw0KGgoAAAANSUhEUgAAADAAAAAw") && valid_icon(value)
}
fn icon_records(root:&str)->Result<Vec<(String,String,String,bool)>,String>{
    let mut rows=Vec::new();
    let base=std::path::Path::new(root);
    if !fs::symlink_metadata(base).is_ok_and(|m|m.is_dir()){return Ok(rows);}
    for entry in fs::read_dir(base).map_err(|e|e.to_string())?.take(10000){
        let entry=entry.map_err(|e|e.to_string())?;
        if !entry.file_type().is_ok_and(|m|m.is_dir()){continue;}
        let name=entry.file_name().to_string_lossy().into_owned();
        if name.contains(['\t','\n','\r']){continue;}
        let file=entry.path().join("app_details.json");
        let Ok(mut input)=super::applist_web::open_icon_file(&file) else{continue;};
        let mut text=String::new();
        if std::io::Read::take(&mut input,4*1024*1024+1).read_to_string(&mut text).is_err()||text.len()>4*1024*1024{continue;}
        if let Some((pkg,icon))=icon_metadata(&text){
            if pkg.len()>255||!pkg.contains('.')||!pkg.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'.'||b==b'_'){continue;}
            rows.push((file.to_string_lossy().into_owned(),name,pkg,!icon.is_empty()&&!legacy_icon(&icon)));
        }
    }
    Ok(rows)
}
fn icons_plan(root:&str,packages:&str,out:&str)->Result<(),String>{
    let have:std::collections::BTreeSet<_>=icon_records(root)?.into_iter().filter(|r|r.3).map(|r|r.2).collect();
    let text=fs::read_to_string(packages).map_err(|e|e.to_string())?;
    let wanted:std::collections::BTreeSet<_>=text.lines().filter(|p|!have.contains(*p)).collect();
    publish_document(out,wanted.into_iter().collect::<Vec<_>>().join("\n").as_bytes())
}
fn icons_batch(root:&str,cache:&str,report:&str)->Result<(),String>{
    let mut out=String::new();
    for (file,name,pkg,_) in icon_records(root)? {
        let icon=std::path::Path::new(cache).join(format!("{pkg}.b64"));
        // Missing/truncated/unavailable optional icons are skips, never backup failures.
        let module_changed=attach_module_value(&file,&name,&pkg).unwrap_or(false);
        let changed=match attach_icon_value(&file,&name,&pkg,&icon.to_string_lossy()){Ok(true)=>1,_ if module_changed=>1,Ok(false)=>0,Err(_)=>2};
        let size=fs::metadata(&file).map(|m|m.len()).unwrap_or(0);
        out.push_str(&format!("{changed}\t{name}\t{pkg}\t{size}\n"));
    }
    publish_document(report,out.as_bytes())
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
// Consume the existing snapshot map in the same process as the transformation.
// Match the first TSV record, as the former awk helper did, but validate its
// package identity before writing any profile output.
fn snapshot_from_map(path: &str, package: &str) -> Result<V, String> {
    if package.is_empty() { return Err("snapshot package missing".into()); }
    let file = File::open(path).map_err(|e| e.to_string())?;
    for line in BufReader::new(file).lines() {
        let line = line.map_err(|e| e.to_string())?;
        let mut fields = line.split('\t');
        if fields.next() != Some(package) { continue; }
        let state = parse(fields.next().ok_or("snapshot record missing JSON")?)?;
        if state.get("packageName").and_then(V::text) != Some(package) {
            return Err("snapshot package mismatch".into());
        }
        return Ok(state);
    }
    Err("snapshot package not found".into())
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
fn require_complete_state(state: &V) -> Result<(), String> {
    if !persistable(state) {
        return Err("invalid snapshot".into());
    }
    // Diagnostic/installer failures are harmless to persisted sections; failed
    // state collection must never replace a valid previous subtree with empties.
    if let Some(V::Array(errors)) = state.get("errors") {
        if errors.is_empty() && state.get("result").and_then(|r| r.get("name")).and_then(V::text) == Some("PARTIAL") {
            return Err("partial snapshot without section diagnostics".into());
        }
        if errors.iter().any(|e| e.get("field").and_then(V::text).map(|field|
                ["permissions", "otherAppOps", "specialAccess", "batterySettings"].iter()
                    .any(|section| field == *section || field.starts_with(&format!("{section}."))))
                .unwrap_or(false)) {
            return Err("incomplete state snapshot; previous state retained".into());
        }
    } else if state.get("result").and_then(|r| r.get("name")).and_then(V::text) == Some("PARTIAL") {
        return Err("partial snapshot without section diagnostics".into());
    }
    Ok(())
}
fn backup(old: &V, entry: &str, state: &V, prefix: &str) -> Result<(), String> {
    require_complete_state(state)?;
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
    require_complete_state(state)?;
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
    // Refresh keeps the backup's identity, and must not erase installer metadata
    // merely because the current package-manager query could not provide it.
    if !valid(&alt(&s, "installer", atom("null"))) {
        let previous_installer = oe.get("app_state")
            .map(|x| alt(x, "installer", atom("null")))
            .filter(V::truth)
            .unwrap_or_else(|| alt(oe, "installer", atom("null")));
        if valid(&previous_installer) { s.put("installer", previous_installer); }
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
            Some("icons-plan") if args.len()==6 => icons_plan(&args[3],&args[4],&args[5]),
            Some("icons-batch") if args.len()==6 => icons_batch(&args[3],&args[4],&args[5]),
            Some("module-attach") if args.len()==6 => attach_module(&args[3],&args[4],&args[5]),
            Some("icon-attach") if args.len()==7 => attach_icon(&args[3],&args[4],&args[5],&args[6]),
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
            Some("backup-map") if args.len() == 8 => {
                let state = snapshot_from_map(&args[5], &args[6])?;
                backup(&read(&args[3])?, &args[4], &state, &args[7])
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
pub(super) fn backup_update_plan(args: &[String]) -> i32 {
    json_ops::backup_update_plan(args)
}
pub(super) fn json_run(args: &[String]) -> i32 {
    json_ops::run(args)
}

pub(super) fn restore_ssaid_state(args: &[String]) -> i32 {
    json_ops::restore_ssaid_state(args)
}

pub(super) fn restore_ssaid_plan(list: &str, user: &str) -> i32 {
    json_ops::restore_ssaid_plan(list, user)
}

pub(super) fn restore_ssaid_batch(list: &str) -> i32 {
    json_ops::restore_ssaid_batch(list)
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

pub(super) fn regen_identity(text:&str)->Result<(String,String),String>{json_ops::regen_identity(text)}
