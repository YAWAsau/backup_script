//! Fixed JSON operations used by the shell. No filter language or external process.
use super::*;
include!("json_caps.rs");
#[path = "json_legacy.rs"]
mod legacy;
// Device-tree cells are big-endian. Limit optional reads and never propagate failures.
fn ram_cell(path: &str) -> Option<u32> {
    use std::io::Read;
    let mut file = std::fs::File::open(path).ok()?;
    let mut bytes = [0u8; 4];
    file.read_exact(&mut bytes).ok()?;
    let mut extra = [0u8; 1];
    if file.read(&mut extra).ok()? != 0 { return None; }
    Some(u32::from_be_bytes(bytes))
}
fn ram_vendor(id: Option<u32>) -> String {
    // Rockchip DDR Develop Guide, LPDDR MR5 manufacturer tables.
    match id {
        Some(1) => "Samsung".into(),
        Some(6) => "SK hynix".into(),
        Some(255) => "Micron".into(),
        Some(0x13) => "CXMT".into(),
        Some(0x1a) => "UniIC".into(),
        Some(0xe5) => "Dosilicon".into(),
        Some(id) => format!("未知 (ID:0x{:08x})", id),
        None => "未知".into(),
    }
}
fn device_property(key: &str) -> String {
    #[cfg(target_os = "android")]
    {
        unsafe extern "C" { fn __system_property_get(name: *const std::ffi::c_char, value: *mut std::ffi::c_char) -> i32; }
        let Ok(key) = std::ffi::CString::new(key) else { return String::new(); };
        let mut buf = [0u8; 92];
        let n = unsafe { __system_property_get(key.as_ptr(), buf.as_mut_ptr().cast()) };
        if n > 0 && (n as usize) < buf.len() { return String::from_utf8_lossy(&buf[..n as usize]).into_owned(); }
    }
    let _ = key;
    String::new()
}
fn ram_product() -> String { device_property("ro.product.device") }
fn usable_ram(text: &str) -> Option<u64> {
    let mut rows=text.lines().filter_map(|line|line.strip_prefix("MemTotal:"));
    let fields:Vec<_>=rows.next()?.split_whitespace().collect();
    if rows.next().is_some() || fields.len()!=2 || fields[1]!="kB" {return None;}
    let kb=fields[0].parse::<u64>().ok()?;
    (kb>0 && kb<=1024*1024*1024).then_some(kb)
}
fn soc_key(value:&str)->String {value.trim().to_ascii_lowercase()}
fn soc_resolve(table:&V,candidates:&[String])->(String,String) {
    let usable=|s:&str|!s.trim().is_empty()&&!matches!(soc_key(s).as_str(),"null"|"unknown"|"n/a"|"none");
    for candidate in candidates.iter().filter(|s|usable(s)) {
        let exact=g(table,candidate.trim());
        let d=if exact.object(){exact}else if let V::Object(rows)=table {
            let mut hits=rows.iter().filter(|(k,_)|soc_key(k)==soc_key(candidate));
            match (hits.next(),hits.next()){(Some((_,v)),None)=>v.clone(),_=>V::Object(Vec::new())}
        }else{V::Object(Vec::new())};
        let name=raw(&g(&d,"NAME"));
        if usable(&name) {
            let vendor=raw(&g(&d,"VENDOR"));
            let label=if usable(&vendor){format!("{} {}",vendor.trim(),name.trim())}else{name.trim().into()};
            return (label,raw(&alt(&d,"MEMORY",string(""))));
        }
    }
    (candidates.iter().find(|s|usable(s)).map(|s|format!("{}（系統回報）",s.trim())).unwrap_or_else(||"未知".into()),String::new())
}
// Only use an independently verified device/platform pair after exact SoC lookup fails.
// Xiaomi official 2025 interim report: REDMI K80 Ultra uses Dimensity 9400+.
// Device codename dali is confirmed by the reporter and DevCheck device catalogue.
fn soc_device_resolve(table: &V, candidates: &[String], brand: &str, product: &str) -> (String, String) {
    let resolved = soc_resolve(table, candidates);
    if !resolved.0.ends_with("（系統回報）") { return resolved; }
    let platform = candidates.iter().any(|s| soc_key(s) == "mt6991");
    // Conflicting platform/model properties must keep the system-reported fallback.
    let conflict = candidates.iter().any(|s| {
        let s = soc_key(s);
        !matches!(s.as_str(), "" | "null" | "unknown" | "n/a" | "none" | "mt6991")
    });
    if platform && !conflict && soc_key(product) == "dali"
        && matches!(soc_key(brand).as_str(), "redmi" | "xiaomi") {
        // Do not infer RAM technology/speed from the phone's marketing specification.
        return ("MediaTek Dimensity 9400+".into(), String::new());
    }
    resolved
}
fn ram_display(id: Option<u32>, size: Option<u32>, product: &str, spec: &str) -> String {
    // Only these boards' ddr_size units have been verified as nominal GB.
    // The procfs fallback reports capacity explicitly in G/GB; never use swap.
    let size = if matches!(product, "songyuan" | "fuxi") {
        size.filter(|n| matches!(n, 4 | 6 | 8 | 12 | 16 | 24 | 32 | 48 | 64))
    } else { None };
    let vendor = ram_vendor(id);
    let extra = if vendor.starts_with("未知") || size.is_none() { device_ram::fallback() } else { None };
    let mv = if extra.is_none() && (vendor.starts_with("未知") || size.is_none()) { device_ram::mv_fallback() } else { None };
    let extra = extra.or_else(|| mv.as_ref().and_then(|f|f.ram.as_ref()).map(|(v,n)|(v.as_str(),*n)));
    let (vendor, size) = device_ram::merge(vendor, size, extra);
    let mut parts = vec![vendor];
    if let Some(gb) = size { parts.push(format!("{} GB", gb)); }
    else if let Some(kb)=std::fs::read_to_string("/proc/meminfo").ok().as_deref().and_then(usable_ram) {
        parts.push(format!("系統可用實體容量 {:.2} GiB",kb as f64/1048576.0));
    }
    let spec = spec.trim();
    if !spec.is_empty() && spec != "null" { parts.push(spec.to_owned()); }
    parts.join(" ")
}
fn ram_info(spec: &str) -> String {
    ram_display(
        ram_cell("/sys/firmware/devicetree/base/memory/ddr_manufacturer_id"),
        ram_cell("/sys/firmware/devicetree/base/memory/ddr_size"),
        &ram_product(), spec,
    )
}

type Vars = HashMap<String, String>;
fn string(s: impl Into<String>) -> V {
    V::String(s.into())
}
fn boolean(b: bool) -> V {
    atom(if b { "true" } else { "false" })
}
fn number(n: usize) -> V {
    atom(&n.to_string())
}
fn null(v: &V) -> bool {
    matches!(v,V::Atom(s) if s=="null")
}
fn g(v: &V, k: &str) -> V {
    v.get(k).cloned().unwrap_or_else(|| atom("null"))
}
fn path(v: &V, keys: &[&str]) -> V {
    keys.iter().fold(v.clone(), |v, k| g(&v, k))
}
fn fallback(xs: &[V]) -> V {
    xs.iter()
        .find(|v| v.truth())
        .cloned()
        .or_else(|| xs.last().cloned())
        .unwrap_or_else(|| atom("null"))
}
fn raw(v: &V) -> String {
    v.text()
        .map(str::to_owned)
        .unwrap_or_else(|| v.emit(false, 0))
}
fn entries(v: &V) -> Vec<(String, V)> {
    match v {
        V::Object(xs) => xs.clone(),
        V::Array(xs) => xs
            .iter()
            .enumerate()
            .map(|(i, v)| (i.to_string(), v.clone()))
            .collect(),
        _ => vec![],
    }
}
fn values(v: &V) -> Vec<V> {
    entries(v).into_iter().map(|(_, v)| v).collect()
}
fn objects(v: &V) -> Vec<V> {
    values(v).into_iter().filter(V::object).collect()
}
fn array(v: &V) -> bool {
    matches!(v, V::Array(_))
}
fn numeric(v: &V) -> bool {
    matches!(v,V::Atom(s) if s.parse::<f64>().is_ok())
}
fn isbool(v: &V) -> bool {
    matches!(v,V::Atom(s) if s=="true"||s=="false")
}
fn eqnum(v: &V, n: f64) -> bool {
    numeric(v) && raw(v).parse::<f64>().ok() == Some(n)
}
fn is(v: &V, k: &str, s: &str) -> bool {
    g(v, k).text() == Some(s)
}
// Compare JSON decimals without converting persisted 64-bit values to f64.
fn decimal_key(v: &V) -> Option<(bool, String, i64)> {
    let V::Atom(s) = v else { return None };
    if !numeric(v) {
        return None;
    }
    let negative = s.starts_with('-');
    let s = s.trim_start_matches('-');
    let (mantissa, exponent) = s.split_once(['e', 'E']).unwrap_or((s, "0"));
    let exponent = exponent.parse::<i64>().ok()?;
    let fraction = mantissa.split_once('.').map(|(_, f)| f.len()).unwrap_or(0);
    let mut digits = mantissa
        .replace('.', "")
        .trim_start_matches('0')
        .to_string();
    if digits.is_empty() {
        return Some((false, "0".into(), 0));
    }
    let mut scale = exponent.checked_sub(i64::try_from(fraction).ok()?)?;
    while digits.ends_with('0') {
        digits.pop();
        scale = scale.checked_add(1)?
    }
    Some((negative, digits, scale))
}
fn same(a: &V, b: &V) -> bool {
    match (a, b) {
        (V::Object(a), V::Object(b)) => {
            a.len() == b.len()
                && a.iter().all(|(k, v)| {
                    b.iter()
                        .find(|(n, _)| n == k)
                        .map(|(_, w)| same(v, w))
                        .unwrap_or(false)
                })
        }
        (V::Array(a), V::Array(b)) => {
            a.len() == b.len() && a.iter().zip(b).all(|(v, w)| same(v, w))
        }
        _ => {
            a.emit(false, 0) == b.emit(false, 0)
                || (decimal_key(a).is_some() && decimal_key(a) == decimal_key(b))
        }
    }
}
fn var(a: &Vars, k: &str) -> String {
    a.get(k).cloned().unwrap_or_default()
}
fn tsv(xs: &[V]) -> Result<V, String> {
    let mut parts = Vec::new();
    for v in xs {
        if v.object() || array(v) {
            return Err("TSV field must be scalar".into());
        }
        parts.push(if null(v) {
            String::new()
        } else {
            raw(v)
                .replace('\\', "\\\\")
                .replace('\t', "\\t")
                .replace('\r', "\\r")
                .replace('\n', "\\n")
        });
    }
    Ok(string(parts.join("\t")))
}
fn merge(a: &V, b: &V) -> V {
    if a.object() && b.object() {
        let mut o = a.clone();
        for (k, v) in entries(b) {
            let old = g(&o, &k);
            o.put(&k, merge(&old, &v))
        }
        o
    } else {
        b.clone()
    }
}
fn put_path(v: &mut V, keys: &[&str], x: V) -> Result<(), String> {
    if null(v) {
        *v = obj()
    }
    if !v.object() {
        return Err("cannot update field of non-object".into());
    }
    if keys.len() == 1 {
        v.put(keys[0], x)
    } else {
        let mut e = g(v, keys[0]);
        put_path(&mut e, &keys[1..], x)?;
        v.put(keys[0], e)
    }
    Ok(())
}
fn remove(v: &mut V, k: &str) {
    if let V::Object(xs) = v {
        xs.retain(|(n, _)| n != k)
    }
}
fn first(v: &V, k: &str) -> V {
    objects(v)
        .iter()
        .map(|v| g(v, k))
        .find(|v| !null(v))
        .unwrap_or_else(|| atom("null"))
}
fn state_schema(v: &V) -> bool {
    if !v.object() && !array(v) {
        return false;
    }
    objects(v)
        .iter()
        .map(|v| g(v, "app_state"))
        .filter(|v| !null(v))
        .all(|s| {
            s.object()
                && eqnum(&g(&s, "schemaVersion"), 2.0)
                && is(&s, "recordType", "snapshot")
                && alt(&s, "packageName", string("")).text().is_some()
                && array(&g(&s, "permissions"))
                && g(&s, "specialAccess").object()
                && array(&g(&s, "otherAppOps"))
                && g(&s, "batterySettings").object()
        })
}
fn state_items(v: &V) -> bool {
    if !v.object() && !array(v) {
        return false;
    }
    if objects(v)
        .iter()
        .map(|v| g(v, "app_state"))
        .any(|s| !null(&s) && !s.object())
    {
        return false;
    }
    objects(v)
        .iter()
        .map(|v| g(v, "app_state"))
        .filter(|v| !null(v))
        .all(|s| {
            values(&g(&s, "permissions")).iter().all(|p| {
                g(p, "name").text().is_some() && isbool(&g(p, "granted")) && numeric(&g(p, "flags"))
            }) && values(&g(&s, "otherAppOps"))
                .iter()
                .all(|p| numeric(&g(p, "op")) && numeric(&g(p, "mode")))
        })
}
fn state_nullable(v: &V) -> bool {
    (v.object() || array(v))
        && objects(v)
            .iter()
            .map(|v| g(v, "app_state"))
            .filter(|v| !null(v))
            .all(|s| s.get("installer").is_some() && s.get("ssaid").is_some())
}
fn ad(v: &V, op: &str) -> Result<V, String> {
    let objs = objects(v);
    let empty = string("");
    if matches!(
        op,
        "ad_first_ssaid" | "ad_appstate_ssaid_count" | "ad_any_ssaid_count"
    ) && objs
        .iter()
        .map(|v| g(v, "app_state"))
        .any(|s| !null(&s) && !s.object())
    {
        return Ok(if op == "ad_first_ssaid" {
            string("")
        } else {
            number(0)
        });
    }
    Ok(match op {
        "ad_first_pkg" => string(raw(&fallback(&[first(v, "PackageName"), empty]))),
        "ad_first_apk_version" => fallback(&[first(v, "apk_version"), empty]),
        "ad_first_entry_name" => string(
            entries(v)
                .iter()
                .find(|(_, v)| v.object() && !null(&g(v, "PackageName")))
                .or(None)
                .map(|(k, _)| k.clone())
                .or_else(|| entries(v).first().map(|(k, _)| k.clone()))
                .unwrap_or_default(),
        ),
        "ad_first_ssaid" => {
            if !v.object() && !array(v) {
                string("")
            } else {
                objs.iter()
                    .map(|v| fallback(&[path(v, &["app_state", "ssaid"]), g(v, "Ssaid")]))
                    .find(V::truth)
                    .unwrap_or_else(|| atom("null"))
            }
        }
        "ad_state_count" => number(objs.iter().filter(|v| !null(&g(v, "app_state"))).count()),
        "ad_legacy_state_count" => number(
            objs.iter()
                .filter(|v| {
                    ["permissions", "special_access", "battery_settings", "Ssaid"]
                        .iter()
                        .any(|k| !null(&g(v, k)))
                })
                .count(),
        ),
        "ad_appstate_ssaid_count" => number(
            objs.iter()
                .filter(|v| !null(&path(v, &["app_state", "ssaid"])))
                .count(),
        ),
        "ad_any_ssaid_count" => number(
            objs.iter()
                .filter(|v| {
                    !null(&fallback(&[
                        path(v, &["app_state", "ssaid"]),
                        g(v, "Ssaid"),
                    ]))
                })
                .count(),
        ),
        "ad_required_meta_ok" => boolean(
            v.object()
                && objs
                    .iter()
                    .any(|v| !null(&g(v, "PackageName")) && !null(&g(v, "apk_version"))),
        ),
        _ => return Err(format!("unknown metadata operation: {op}")),
    })
}
fn caps(v: &V, names: &[&str]) -> Vec<String> {
    names
        .iter()
        .filter(|name| {
            !values(&g(v, "capabilities"))
                .iter()
                .any(|c| is(c, "name", name) && matches!(g(c,"enabled"),V::Atom(s) if s=="true"))
        })
        .map(|s| s.to_string())
        .collect()
}
fn snapshot_ok(v: &V) -> bool {
    is(v, "recordType", "snapshot")
        && matches!(path(v, &["result", "name"]).text(), Some("OK" | "PARTIAL"))
        && alt(v, "packageName", string("")).text() != Some("")
}
fn snapshot_error(v: &V) -> bool {
    (is(v, "recordType", "snapshot") && path(v, &["result", "name"]).text() != Some("OK"))
        || is(v, "recordType", "error")
}
fn summary_ok(v: &V) -> bool {
    is(v, "recordType", "summary")
        && is(v, "command", "snapshotAppStateBatch")
        && eqnum(&g(v, "schemaVersion"), 2.0)
        && matches!(path(v, &["result", "name"]).text(), Some("OK" | "PARTIAL"))
}
fn execute(op: &str, v: &V, a: &Vars, file: &str) -> Result<Vec<V>, String> {
    let one = |v| Ok(vec![v]);
    let empty = string("");
    // Match the consumers' field-indexing errors instead of silently treating
    // a scalar/array response as an empty API object.
    if !v.object()
        && !null(v)
        && matches!(
            op,
            "webdav-contract"
                | "release-tag"
                | "release-body"
                | "release-assets"
                | "release-digest"
                | "soc-info"
                | "root-field"
                | "device-log"
                | "device-names"
                | "dex-version"
                | "caps-enabled"
                | "caps-missing"
                | "foreground-active"
                | "foreground-packages"
                | "foreground-count"
                | "foreground-first"
                | "queue-label"
                | "snapshot-states"
                | "snapshot-errors"
                | "snapshot-reduce"
                | "snapshot-ssaid"
                | "home-package"
                | "home-label"
                | "home-source"
                | "home-resolver"
                | "ime-package"
                | "ime-label"
                | "ime-source"
                | "ensure-package"
        )
    {
        return Err("expected JSON object or null".into());
    }
    if !v.object() && matches!(op, "state-v2" | "state-migrate" | "protected-signature") {
        return Err("expected metadata object".into());
    }
    if !v.object()
        && !null(v)
        && matches!(
            op,
            "device-schema"
                | "device-diagnostic"
                | "inventory-schema"
                | "caps-contract"
                | "caps-diagnostic"
                | "caps-direct"
                | "caps-single"
                | "caps-telemetry"
                | "caps-observer"
                | "caps-session"
        )
    {
        return Err("expected JSON object or null".into());
    }
    if !v.object()
        && !array(v)
        && matches!(op, "media-keys" | "media-payload-keys" | "apk-input-size")
    {
        return Err("expected JSON collection".into());
    }
    match op {
        "home-fields" | "ime-fields" | "foreground-packages-count" => {
            let V::Array(docs) = v else { return Err("requires slurp".into()); };
            let ops: &[&str] = match op {
                "home-fields" => &["home-package", "home-label", "home-source", "home-resolver"],
                "ime-fields" => &["ime-package", "ime-label", "ime-source"],
                _ => &["foreground-packages"],
            };
            let mut fields = Vec::new();
            for field_op in ops {
                let mut stream = String::new();
                for doc in docs {
                    for value in execute(field_op, doc, a, file)? {
                        stream.push_str(&if value.text().is_some() { raw(&value) } else { value.emit(true, 0) });
                        stream.push('\n');
                    }
                }
                // Shell cannot represent NUL; keep its legacy pipeline for these inputs.
                if stream.contains('\0') { return Err("legacy NUL path".into()); }
                let lines = stream.split('\n').filter(|s| !s.trim_matches([' ', '\t']).is_empty());
                if op == "foreground-packages-count" {
                    let mut seen = std::collections::HashSet::new();
                    let rows: Vec<_> = lines.filter(|s| seen.insert((*s).to_string())).collect();
                    fields.push(number(rows.len()));
                    fields.extend(rows.into_iter().map(string));
                } else {
                    fields.push(string(lines.into_iter().next().unwrap_or_default()));
                }
            }
            Ok(fields)
        }
        "identity" => one(v.clone()),
        "length" => one(match v {
            V::Object(xs) => number(xs.len()),
            V::Array(xs) => number(xs.len()),
            V::String(s) => number(s.chars().count()),
            V::Atom(s) if s == "null" => number(0),
            V::Atom(s) if s.parse::<f64>().is_ok() => atom(s.trim_start_matches('-')),
            _ => return Err("invalid length input".into()),
        }),
        "merge" => {
            let xs = values(v);
            if xs.len() < 2 || !xs[0].object() || !xs[1].object() {
                return Err("merge needs two objects".into());
            }
            one(merge(&xs[0], &xs[1]))
        }
        // Merge only payload entries actually downloaded in this transaction.
        "media-download-merge" => {
            let xs = values(v);
            if xs.len() != 2 || !xs[0].object() || !xs[1].object() {
                return Err("media download merge needs two objects".into());
            }
            let mut out = xs[0].clone();
            let selection = std::fs::read_to_string(var(a, "items"))
                .map_err(|e| format!("read media selection: {e}"))?;
            if selection.lines().any(|s| s == "Media") {
                for (key, value) in entries(&xs[1]) { out.put(&key, value); }
            } else {
                for item in selection.lines() {
                    let Some(key) = item.strip_suffix(".tar.zst")
                        .or_else(|| item.strip_suffix(".tar")) else { continue };
                    if item.contains('/') { continue; }
                    let value = xs[1].get(key).filter(|x| x.object())
                        .ok_or_else(|| format!("missing selected media metadata: {key}"))?;
                    out.put(key, value.clone());
                }
            }
            one(out)
        }
        "release-tag" => one(alt(v, "tag_name", empty)),
        "release-body" => one(alt(v, "body", empty)),
        "release-assets" => Ok(values(&g(v, "assets"))
            .iter()
            .map(|v| g(v, "browser_download_url"))
            .filter(V::truth)
            .collect()),
        "release-digest" => Ok(values(&g(v, "assets"))
            .iter()
            .filter(|v| is(v, "browser_download_url", &var(a, "url")))
            .map(|v| alt(v, "digest", string("")))
            .collect()),
        "soc-info" => {
            let mut candidates=vec![var(a,"device")];
            for key in ["ro.soc.model","ro.vendor.soc.model","ro.mediatek.platform","ro.board.platform","ro.hardware"] {candidates.push(device_property(key));}
            let (name,spec)=soc_device_resolve(v,&candidates,&device_property("ro.product.brand"),&ram_product());
            Ok(vec![string(format!("DEVICE\t{}",name.replace(['\t','\r','\n']," "))),string(format!("RAM\t{}",ram_info(&spec)))])
        }
        "webdav-contract" => {
            let mut xs = vec![raw(&g(v, "serverProfile"))];
            for k in [
                "supportsChunkedPut",
                "supportsFixedPut",
                "supportsGetStream",
                "supportsMove",
                "supportsCopy",
                "supportsStat",
                "supportsRemoteSize",
                "supportsAtomicPublish",
                "supportsOverwriteMove",
                "supportsMkcol",
                "supportsDelete",
                "supportsDepthInfinity",
                "supportsDepth1",
                "supportsRecursiveWalkFallback",
                "supportsQuota",
                "supportsPacerRetryBackoff",
                "supportsDirectoryCache",
                "bodyCompareOk",
                "copyStatOk",
                "cleanupOk",
            ] {
                xs.push((g(v, k).truth() as u8).to_string())
            }
            one(string(xs.join(" ")))
        }
        "restore-mask" => {
            let xs = values(v);
            if xs.len() != 1 || !xs[0].object() {
                return Err("fallback".into());
            }
            let mut ks = vec![];
            for k in ["user", "data", "obb", "media", "user_de", "thanox", "hma"] {
                let val = fallback(&[path(&xs[0], &[k, "Size"]), string("")]);
                if val.object() || array(&val) || raw(&val).contains(['\0', '\r']) {
                    return Err("fallback".into());
                }
                let s = raw(&val);
                let s = s.trim_end_matches('\n');
                if !s.is_empty() && s != "null" {
                    ks.push(k)
                }
            }
            one(string(format!("|{}|", ks.join("|"))))
        }
        x if x.starts_with("ad_") => one(ad(v, x)?),
        "entry-field" => one(fallback(&[path(v, &[&var(a, "e"), &var(a, "k")]), empty])),
        "entry-has" => one(boolean(!null(&path(v, &[&var(a, "e"), &var(a, "k")])))),
        "state-schema" => one(boolean(state_schema(v))),
        "state-items" => one(boolean(state_items(v))),
        "state-nullable" => one(boolean(state_nullable(v))),
        "metadata-valid" => one(boolean(
            v.truth() && ad(v, "ad_required_meta_ok")?.truth() && state_schema(v) && state_items(v),
        )),
        "metadata-identity" => Ok(vec![ad(v, "ad_first_pkg")?, ad(v, "ad_first_apk_version")?]),
        "restore-ssaid-identity" => {
            let V::Array(docs) = v else { return Err("requires slurp".into()); };
            if docs.len() != 1 { return Err("legacy multi-document identity".into()); }
            let entry = raw(&ad(&docs[0], "ad_first_entry_name")?);
            let package = raw(&ad(&docs[0], "ad_first_pkg")?);
            if entry.contains(['\t', '\r', '\n', '\0']) || package.contains(['\t', '\r', '\n', '\0']) {
                return Err("legacy identity bytes".into());
            }
            one(string(format!("SBSSID1\t{entry}\t{package}")))
        }
        "restore-ssaid-package" => {
            let V::Array(docs) = v else { return Err("requires slurp".into()); };
            if docs.len() != 1 { return Err("legacy multi-document path".into()); }
            let ssaid = raw(&ad(&docs[0], "ad_first_ssaid")?);
            let package = raw(&ad(&docs[0], "ad_first_pkg")?);
            if ssaid.contains(['\n', '\0']) || package.contains(['\n', '\0']) {
                return Err("legacy multiline path".into());
            }
            one(string(if matches!(ssaid.as_str(), "" | "null" | "false") { "N".into() } else { format!("Y\n{package}") }))
        }
        "health-flags" => {
            let V::Array(docs)=v else { return Err("health-flags requires slurp".into()); };
            let last=docs.last().filter(|v| v.truth()).ok_or("invalid health document")?;
            let present=|key: &str| -> Result<bool,String> {
                let values=docs.iter().map(|v| ad(v,key).map(|v| raw(&v))).collect::<Result<Vec<_>,_>>()?;
                Ok(!values.join("\n").trim_end_matches('\n').is_empty())
            };
            let count=|key: &str| -> Result<V,String> {
                if docs.len()==1 { ad(last,key) } else { Ok(number(0)) }
            };
            one(tsv(&[
                number(usize::from(present("ad_first_pkg")?)),
                number(usize::from(present("ad_first_apk_version")?)),
                count("ad_state_count")?,count("ad_legacy_state_count")?,count("ad_appstate_ssaid_count")?,
                number(usize::from(state_schema(last))),number(usize::from(state_items(last))),number(usize::from(state_nullable(last))),
            ])?)
        }
        "restore-metadata-plan" => restore_metadata_plan(v, a),
        "health-row" => {
            let app = Path::new(file)
                .parent()
                .and_then(Path::file_name)
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            let mut xs = vec![string(app)];
            for k in [
                "ad_first_pkg",
                "ad_first_apk_version",
                "ad_state_count",
                "ad_legacy_state_count",
                "ad_appstate_ssaid_count",
            ] {
                xs.push(ad(v, k)?)
            }
            xs.extend([
                boolean(state_schema(v)),
                boolean(state_items(v)),
                boolean(state_nullable(v)),
            ]);
            one(tsv(&xs)?)
        }
        "payload-comparison" => one(tsv(&[
            fallback(&[path(v, &[&var(a, "e"), "Size"]), string("")]),
            fallback(&[path(v, &[&var(a, "e"), "change_fingerprint"]), string("")]),
        ])?),
        // Match the existing -e required-metadata check (last document wins),
        // then emit exactly the existing summary stream. The shell still checks
        // 13 lines, so multiple documents and embedded newlines remain rejected.
        "backup-required-summary" => {
            let V::Array(docs) = v else { return Err("summary requires slurp".into()); };
            let last = docs.last().ok_or("missing metadata")?;
            if !ad(last, "ad_required_meta_ok")?.truth() {
                return Err("required metadata missing".into());
            }
            let mut rows = Vec::new();
            for doc in docs {
                rows.extend(execute("metadata-summary", doc, a, file)?);
            }
            Ok(rows)
        }
        "metadata-summary" => {
            let mut xs = vec![
                fallback(&[first(v, "apk_version"), empty.clone()]),
                fallback(&[first(v, "PackageName"), empty.clone()]),
                fallback(&[path(v, &["Backup time", "date"]), empty.clone()]),
            ];
            for k in ["user", "data", "obb", "user_de", "media"] {
                xs.push(fallback(&[path(v, &[k, "Size"]), empty.clone()]))
            }
            for entry in ["user", "data", "obb", "user_de", "media"] {
                xs.push(fallback(&[
                    path(v, &[entry, "change_fingerprint"]),
                    string(""),
                ]));
            }
            Ok(xs)
        }
        "payload-summary" => Ok(vec![
            fallback(&[path(v, &[&var(a, "e"), "Size"]), empty.clone()]),
            fallback(&[first(v, "keystore"), empty.clone()]),
            fallback(&[path(v, &[&var(a, "e"), "path"]), empty.clone()]),
            fallback(&[path(v, &[&var(a, "e"), "archive_input_bytes"]), empty]),
        ]),
        "installer-state" => {
            let s = first(v, "app_state");
            one(fallback(&[
                g(&s, "installer"),
                path(&s, &["package", "installer"]),
                path(&s, &["installDiagnostics", "installing"]),
                empty,
            ]))
        }
        "installer-legacy" => one(fallback(&[first(v, "installer"), empty])),
        "installer-diagnostics" => {
            let d = first(v, "install_diagnostics");
            one(fallback(&[g(&d, "installer"), g(&d, "installing"), empty]))
        }
        "edit-batch" => {
            if !v.object() {
                return Err("expected metadata object".into());
            }
            let bytes = fs::read(var(a, "edits")).map_err(|_| "edit journal unavailable")?;
            let text = std::str::from_utf8(&bytes).map_err(|_| "invalid edit journal encoding")?;
            if !text.is_empty() && !text.ends_with('\0') {
                return Err("truncated edit journal".into());
            }
            let fields: Vec<_> = text.split_terminator('\0').collect();
            let mut p = 0;
            let mut value = v.clone();
            let mut count = 0;
            while p < fields.len() {
                let n: usize = fields[p]
                    .parse()
                    .map_err(|_| "invalid edit argument count")?;
                p += 1;
                if n == 0 || n > 128 || p + n > fields.len() {
                    return Err("truncated edit record".into());
                }
                let end = p + n;
                let mut args = Vars::new();
                let mut op = None;
                while p < end {
                    if fields[p] == "--arg" && p + 2 < end {
                        args.insert(fields[p + 1].into(), fields[p + 2].into());
                        p += 3;
                    } else if op.is_none() {
                        op = Some(fields[p]);
                        p += 1;
                    } else {
                        return Err("invalid edit arguments".into());
                    }
                }
                let op = op.ok_or("missing edit operation")?;
                if !matches!(
                    op,
                    "set-field"
                        | "set-payload-path"
                        | "set-payload"
                        | "set-apk"
                        | "ensure-package"
                        | "sync-package"
                ) {
                    return Err("unsupported edit operation".into());
                }
                value = execute(op, &value, &args, file)?
                    .into_iter()
                    .next()
                    .ok_or("empty edit result")?;
                count += 1;
            }
            let info = format!("JSON_BATCH edits={count}");
            let logged = std::env::var_os("SPEEDBACKUP_INFO_LOG")
                .filter(|p| !p.is_empty())
                .and_then(|p| std::fs::OpenOptions::new().create(true).append(true).open(p).ok())
                .map(|mut f| std::io::Write::write_all(&mut f, format!("{info}\n").as_bytes()).is_ok())
                .unwrap_or(false);
            if !logged { eprintln!("{info}"); }
            one(value)
        }
        "set-field" | "set-payload-path" | "set-payload" | "set-apk" | "ensure-package"
        | "sync-package" => {
            let mut o = v.clone();
            match op {
                "set-field" => put_path(
                    &mut o,
                    &[&var(a, "entry"), &var(a, "key")],
                    string(var(a, "value")),
                )?,
                "ensure-package" => {
                    let k = var(a, "software");
                    if g(&o, &k).truth() {
                        put_path(&mut o, &[&k, "PackageName"], string(var(a, "pkg")))?
                    }
                }
                "sync-package" => {
                    fn walk(v: &mut V, p: &str) {
                        match v {
                            V::Object(xs) => {
                                for (_, v) in xs.iter_mut() {
                                    walk(v, p)
                                }
                                if g(v, "PackageName").truth() {
                                    v.put("PackageName", string(p))
                                }
                            }
                            V::Array(xs) => {
                                for v in xs {
                                    walk(v, p)
                                }
                            }
                            _ => (),
                        }
                    }
                    walk(&mut o, &var(a, "name2"))
                }
                _ => {
                    let k = var(a, if op == "set-apk" { "software" } else { "e" });
                    if op == "set-apk" {
                        put_path(&mut o, &[&k, "PackageName"], string(var(a, "pkg")))?;
                        put_path(&mut o, &[&k, "apk_version"], string(var(a, "apk_version")))?
                    } else {
                        if op == "set-payload-path" {
                            put_path(&mut o, &[&k, "path"], string(var(a, "p")))?
                        }
                        put_path(&mut o, &[&k, "Size"], string(var(a, "s")))?;
                        put_path(
                            &mut o,
                            &[&k, "change_fingerprint"],
                            string(var(a, "fingerprint")),
                        )?;
                        put_path(&mut o, &["Backup time", "date"], string(var(a, "d")))?
                    }
                    let input = var(a, "input");
                    if !input.is_empty()
                        && !input.starts_with('0')
                        && input.bytes().all(|c| c.is_ascii_digit())
                    {
                        put_path(&mut o, &[&k, "archive_input_bytes"], string(input))?
                    } else {
                        let mut e = g(&o, &k);
                        remove(&mut e, "archive_input_bytes");
                        o.put(&k, e)
                    }
                }
            }
            one(o)
        }
        "schema2" => one(boolean(v.object() && eqnum(&g(v, "schemaVersion"), 2.0))),
        "snapshot-schema" => one(boolean(
            v.object() && eqnum(&g(v, "schemaVersion"), 2.0) && is(v, "recordType", "snapshot"),
        )),
        "status-schema" => one(boolean(v.object() && is(v, "recordType", "packageStatus"))),
        "device-schema" => one(boolean(is(v, "schema", "speedbackup.device_facts.v1"))),
        "root-field" => Ok(vec![g(v, &var(a, "k"))]
            .into_iter()
            .filter(V::truth)
            .collect()),
        "device-names" => Ok(["model", "marketNameZh", "marketName", "modelNameSource"]
            .iter()
            .map(|k| {
                string(
                    raw(&alt(v, k, string("")))
                        .split('\n')
                        .next()
                        .unwrap_or_default(),
                )
            })
            .collect()),
        "device-log" => {
            let keys = [
                ("marketZh", "marketNameZh"),
                ("rawModel", "model"),
                ("source", "modelNameSource"),
                ("confidence", "modelNameConfidence"),
                ("matchedField", "matchedField"),
                ("matchedKey", "matchedKey"),
                ("dbEntries", "modelDbEntryCount"),
                ("dbLines", "modelDbSourceLines"),
            ];
            one(string(
                keys.iter()
                    .map(|(n, k)| {
                        format!(
                            "{}={}",
                            n,
                            raw(&alt(v, k, string("")))
                                .split('\n')
                                .next()
                                .unwrap_or_default()
                        )
                    })
                    .collect::<Vec<_>>()
                    .join(" "),
            ))
        }
        "caps-missing" => one(string(caps(v, CAPS_MISSING).join(","))),
        "caps-contract" | "caps-diagnostic" => one(boolean(
            eqnum(&g(v, "schemaVersion"), 2.0)
                && raw(&alt(v, "daemonProtocolVersion", atom("0")))
                    .parse::<f64>()
                    .map(|n| n >= 1.0)
                    .unwrap_or(false)
                && caps(
                    v,
                    if op == "caps-contract" {
                        CAPS_CONTRACT
                    } else {
                        CAPS_DIAGNOSTIC
                    },
                )
                .is_empty(),
        )),
        "caps-direct" | "caps-single" | "caps-telemetry" | "caps-observer" | "caps-session" => {
            one(boolean(
                caps(
                    v,
                    match op {
                        "caps-direct" => CAPS_DIRECT,
                        "caps-single" => CAPS_SINGLE,
                        "caps-telemetry" => CAPS_TELEMETRY,
                        "caps-observer" => CAPS_OBSERVER,
                        _ => CAPS_SESSION,
                    },
                )
                .is_empty(),
            ))
        }
        "dex-version" => one(alt(v, "dexVersion", string("unknown"))),
        "caps-enabled" => one(string(
            values(&g(v, "capabilities"))
                .iter()
                .filter(|c| same(&g(c, "enabled"), &boolean(true)))
                .map(|c| {
                    if null(&g(c, "name")) {
                        String::new()
                    } else {
                        raw(&g(c, "name"))
                    }
                })
                .collect::<Vec<_>>()
                .join(","),
        )),
        "snapshot-summary" | "settings-fallback" => {
            for row in values(v) {
                if !row.object() && !null(&row) {
                    return Err("expected record object".into());
                }
                if if op == "snapshot-summary" {
                    summary_ok(&row)
                } else {
                    is(&row, "recordType", "settingsGet") && is(&row, "source", "exec_settings")
                } {
                    return one(boolean(true));
                }
            }
            one(boolean(false))
        }
        "snapshot-ssaid" => Ok(if valid(&g(v, "ssaid")) {
            vec![v.clone()]
        } else {
            vec![]
        }),
        "snapshot-states" | "snapshot-errors" | "snapshot-reduce" => {
            let mut out = vec![];
            if op != "snapshot-errors" && snapshot_ok(v) {
                let prefix = if op == "snapshot-reduce" { "STATE\t" } else { "" };
                // Compact JSON has no raw tabs/newlines; preserve its own escapes.
                out.push(string(format!("{}{}\t{}", prefix,
                    tsv_sanitize(g(v, "packageName").text().unwrap_or("")), v.emit(false, 0))));
            }
            if op != "snapshot-states" && snapshot_error(v) {
                let mut xs = vec![
                    alt(v, "packageName", string("-")),
                    fallback(&[path(v, &["result", "name"]), string("UNKNOWN")]),
                    fallback(&[path(v, &["result", "message"]), string("")]),
                    string(alt(v, "errors", V::Array(vec![])).emit(false, 0)),
                ];
                if op == "snapshot-reduce" {
                    xs.insert(0, string("ERROR"))
                }
                out.push(tsv(&xs)?)
            }
            if op == "snapshot-reduce" && summary_ok(v) {
                let mut xs = vec![string("SUMMARY")];
                for k in [
                    "batchWorkers",
                    "batchElapsedMs",
                    "batchWorkerPolicy",
                    "batchOrder",
                ] {
                    xs.push(alt(v, k, string("unknown")))
                }
                xs.push(fallback(&[path(v, &["result", "name"]), string("unknown")]));
                out.push(tsv(&xs)?)
            }
            Ok(out)
        }
        "foreground-active" => Ok(
            if is(v, "recordType", "foregroundState") && is(v, "packageName", &var(a, "p")) {
                vec![g(v, "active")]
            } else {
                vec![]
            },
        ),
        "foreground-packages" => Ok(
            if is(v, "recordType", "foregroundState") && same(&g(v, "active"), &boolean(true)) {
                vec![g(v, "packageName")]
            } else {
                vec![]
            },
        ),
        "queue-label" => Ok(if is(v, "packageName", &var(a, "p")) {
            vec![path(v, &["package", "label"])]
                .into_iter()
                .filter(V::truth)
                .collect()
        } else {
            vec![]
        }),
        "foreground-count" => one(fallback(&[path(v, &["counts", "shown"]), atom("0")])),
        "foreground-first" => {
            for k in [
                "top",
                "foreground",
                "active",
                "foreground_service",
                "background",
            ] {
                if let Some(x) = values(&g(v, k)).first() {
                    if !x.truth() {
                        return Ok(vec![]);
                    }
                    return one(tsv(&[
                        alt(x, "label", string("")),
                        alt(x, "packageName", string("")),
                    ])?);
                }
            }
            Ok(vec![])
        }
        "home-package" | "home-label" | "home-source" | "home-resolver" | "ime-package"
        | "ime-label" | "ime-source" => {
            if !is(
                v,
                "recordType",
                if op.starts_with("home-") {
                    "defaultHome"
                } else {
                    "defaultIme"
                },
            ) {
                return Ok(vec![]);
            }
            let k = op.split('-').nth(1).unwrap();
            if k == "package" {
                // Preserve the prior // true expression: even explicit false selects true.
                if path(v, &["result", "name"]).text() != Some("OK")
                    || (op == "home-package"
                        && !same(&alt(v, "isResolver", boolean(true)), &boolean(false)))
                {
                    return Ok(vec![]);
                }
                Ok(vec![g(v, "packageName")]
                    .into_iter()
                    .filter(V::truth)
                    .collect())
            } else if k == "resolver" {
                one(alt(v, "isResolver", boolean(false)))
            } else {
                Ok(vec![g(v, k)].into_iter().filter(V::truth).collect())
            }
        }
        "media-keys" | "media-payload-keys" => Ok(entries(v)
            .iter()
            .filter(|(k, x)| {
                !matches!(k.as_str(), "Backup time" | "PackageName" | "app_state")
                    && x.object()
                    && (op == "media-keys"
                        || !raw(&fallback(&[
                            g(x, "Size"),
                            g(x, "size"),
                            g(x, "path"),
                            string(""),
                        ]))
                        .is_empty())
            })
            .map(|(k, _)| string(k))
            .collect()),
        "apk-input-size" => {
            let x = objects(v)
                .iter()
                .filter(|v| !null(&g(v, "PackageName")))
                .map(|v| fallback(&[g(v, "archive_input_bytes"), g(v, "apk_size"), g(v, "Size")]))
                .find(V::truth);
            Ok(x.into_iter().collect())
        }
        "protected-signature" | "entry-packages" => {
            if op == "protected-signature"
                && objects(v)
                    .iter()
                    .map(|v| g(v, "app_state"))
                    .any(|s| !null(&s) && !s.object())
            {
                return Err("invalid app_state object".into());
            }
            let mut es = vec![];
            let mut ps = vec![];
            let mut lines = vec![];
            for (k, x) in entries(v) {
                if k == "Backup time" || !x.object() {
                    continue;
                }
                let p = path(&x, &["app_state", "packageName"]);
                let pkg = fallback(&[g(&x, "PackageName"), p.clone(), string("")]);
                let mut protected = pick(&x, REFRESH, true);
                if !null(&g(&x, "PackageName")) || !null(&p) {
                    lines.push(tsv(&[string(&k), pkg.clone()])?);
                    let ss = fallback(&[path(&x, &["app_state", "ssaid"]), g(&x, "Ssaid")]);
                    if ss.truth() {
                        protected.put("ssaid", ss)
                    }
                    let mut e = obj();
                    e.put("key", string(k));
                    e.put("packageName", pkg);
                    e.put("protected", protected);
                    es.push(e)
                } else if payload(&x) {
                    let mut e = obj();
                    e.put("key", string(k));
                    e.put("protected", protected);
                    ps.push(e)
                }
            }
            if op == "entry-packages" {
                Ok(lines)
            } else {
                let mut o = obj();
                o.put("backup_time", alt(v, "Backup time", atom("null")));
                o.put("entries", V::Array(es));
                o.put("payloads", V::Array(ps));
                one(o)
            }
        }
        "state-v2" | "state-migrate" => legacy::convert(v, a, op == "state-v2"),
        "state-diff" => state_diff(v),
        "inventory-schema" => one(boolean(
            is(v, "schema", "speedbackup.app_inventory.status.v1")
                || is(v, "schema", "speedbackup.app_inventory.v1")
                || v.get("packageName").is_some(),
        )),
        "device-diagnostic" => one(boolean(
            is(v, "schema", "speedbackup.device_facts.v1")
                && !raw(&g(v, "modelNameSource")).is_empty()
                && !null(&g(v, "modelNameSource"))
                && !raw(&g(v, "marketNameZh")).is_empty()
                && !null(&g(v, "marketNameZh"))
                && ["modelDbEntryCount", "modelDbSourceLines"].iter().all(|k| {
                    raw(&g(v, k))
                        .parse::<f64>()
                        .map(|n| n >= 4000.0)
                        .unwrap_or(false)
                })
                && raw(&g(v, "modelDbSourceSha256")).chars().count() == 64,
        )),
        _ => Err(format!("unknown JSON operation: {op}")),
    }
}
fn state_diff(v: &V) -> Result<Vec<V>, String> {
    let mut xs = values(v);
    while xs.len() < 2 {
        xs.push(atom("null"))
    }
    let (old, new) = (&xs[0], &xs[1]);
    if [old, new].iter().any(|v| !v.object() && !null(v)) {
        return Err("diff needs objects or null".into());
    }
    let mut out = vec![];
    fn index(v: &V, k: &str) -> V {
        let mut o = obj();
        for v in objects(v) {
            o.put(&raw(&g(&v, k)), v)
        }
        o
    }
    let op = index(&g(old, "permissions"), "name");
    let np = index(&g(new, "permissions"), "name");
    for (k, n) in entries(&np) {
        let o = g(&op, &k);
        if null(&o) {
            continue;
        }
        if ["granted", "appOpMode", "flags"].iter().any(|key| {
            !same(
                &alt(&o, key, atom(if *key == "flags" { "0" } else { "null" })),
                &alt(&n, key, atom(if *key == "flags" { "0" } else { "null" })),
            )
        }) {
            out.push(tsv(&[
                string("PERMISSION"),
                string(k),
                string(raw(&g(&o, "granted"))),
                string(raw(&g(&n, "granted"))),
                string(raw(&g(&o, "appOpMode"))),
                string(raw(&g(&n, "appOpMode"))),
                string(raw(&alt(&o, "flags", atom("0")))),
                string(raw(&alt(&n, "flags", atom("0")))),
            ])?)
        }
    }
    for (k, o) in entries(&op) {
        if null(&g(&np, &k)) {
            out.push(tsv(&[
                string("PERMISSION"),
                string(k),
                string(raw(&g(&o, "granted"))),
                string("missing"),
                string(raw(&g(&o, "appOpMode"))),
                string("missing"),
                string(raw(&alt(&o, "flags", atom("0")))),
                string("missing"),
            ])?)
        }
    }
    for (tag, os, ns) in [
        ("SPECIAL", g(old, "specialAccess"), g(new, "specialAccess")),
        (
            "APPOP",
            index(&g(old, "otherAppOps"), "publicName"),
            index(&g(new, "otherAppOps"), "publicName"),
        ),
        (
            "BATTERY",
            pick(
                &g(old, "batterySettings"),
                &["RUN_IN_BACKGROUND", "RUN_ANY_IN_BACKGROUND"],
                true,
            ),
            pick(
                &g(new, "batterySettings"),
                &["RUN_IN_BACKGROUND", "RUN_ANY_IN_BACKGROUND"],
                true,
            ),
        ),
    ] {
        for (k, n) in entries(&ns) {
            let o = g(&os, &k);
            if !null(&o)
                && !null(&n)
                && !same(
                    &alt(&o, "mode", atom("null")),
                    &alt(&n, "mode", atom("null")),
                )
            {
                out.push(tsv(&[
                    string(tag),
                    string(k),
                    string(raw(&g(&o, "mode"))),
                    string(raw(&g(&n, "mode"))),
                    string(""),
                    string(""),
                    string(""),
                    string(""),
                ])?)
            }
        }
    }
    let o = path(old, &["batterySettings", "deviceidleWhitelist"]);
    let n = path(new, &["batterySettings", "deviceidleWhitelist"]);
    if !same(
        &fallback(&[o.clone(), atom("null")]),
        &fallback(&[n.clone(), atom("null")]),
    ) {
        out.push(tsv(&[
            string("BATTERY"),
            string("deviceidleWhitelist"),
            string(raw(&o)),
            string(raw(&n)),
            string(""),
            string(""),
            string(""),
            string(""),
        ])?)
    }
    if !same(
        &alt(old, "ssaid", atom("null")),
        &alt(new, "ssaid", atom("null")),
    ) {
        out.push(tsv(&[
            string("SSAID"),
            string("value"),
            string("changed"),
            string("changed"),
            string(""),
            string(""),
            string(""),
            string(""),
        ])?)
    }
    Ok(out)
}
// Private fixed-line protocol for one immutable Restore App scope. Keep the
// existing JSON operations as the authority; unusual values use their original
// shell consumers instead of inventing escaping/flattening rules here.
fn restore_metadata_plan(v: &V, a: &Vars) -> Result<Vec<V>, String> {
    let V::Array(docs) = v else { return Err("plan requires slurp".into()) };
    if docs.len() != 1 || !docs[0].object() {
        return Err("fallback".into());
    }
    let doc = &docs[0];
    let scalar = |v: &V| -> Result<String, String> {
        if v.object() || array(v) || raw(v).contains(['\0', '\r', '\n']) {
            return Err("fallback".into());
        }
        Ok(raw(v))
    };
    let pkg = scalar(&ad(doc, "ad_first_pkg")?)?;
    if pkg.is_empty() { return Err("fallback".into()); }
    let version = scalar(&ad(doc, "ad_first_apk_version")?)?;
    let mut installer = String::new();
    for op in ["installer-state", "installer-legacy", "installer-diagnostics"] {
        installer = scalar(&execute(op, doc, a, "")?[0])?;
        if !installer.is_empty() && installer != "null" { break; }
    }
    let mask = scalar(&execute("restore-mask", v, a, "")?[0])?;
    let mut out = vec![string("RESTORE_METADATA_PLAN_1"), string(&pkg),
        string(version), string(installer), string(mask)];
    for entry in ["user", "data", "obb", "media", "user_de", "thanox", "hma"] {
        let vars = Vars::from([("e".into(), entry.into())]);
        for field in execute("payload-summary", doc, &vars, "")? {
            out.push(string(scalar(&field)?));
        }
    }
    // Only reuse the exact modern converter output, scoped by entry + package.
    // Missing/invalid modern state still goes through the existing migration.
    let state_vars = Vars::from([("entry".into(), var(a, "entry")), ("pkg".into(), pkg)]);
    let state = legacy::convert(doc, &state_vars, true).ok()
        .filter(|rows| rows.len() == 1)
        .map(|rows| rows[0].emit(false, 0)).unwrap_or_default();
    out.push(string(state));
    out.push(string("END_RESTORE_METADATA_PLAN_1"));
    Ok(out)
}

fn documents(s: &str) -> Result<Vec<V>, String> {
    // Fully collect before emitting: an invalid later document cannot publish a prefix.
    serde_json::Deserializer::from_str(s).into_iter::<&serde_json::value::RawValue>()
        .map(|r| r.map_err(|e| e.to_string()).and_then(|r| parse(r.get())))
        .collect()
}

// Batch the common update-check path. Any non-canonical input returns to the
// unchanged Shell loop before publishing rows, including version-map misses
// that require an inventory refresh. Read the map anew for each entry.
pub(super) fn backup_update_plan(args: &[String]) -> i32 {
    let work = (|| -> Result<String, String> {
        if args.len() != 3 { return Err("args".into()); }
        let input = fs::read_to_string(&args[0]).map_err(|_| "input")?;
        let mut output = String::from("UPDATE_PLAN_1\n");
        let mut count = 0;
        for row in input.lines() {
            let cells: Vec<_> = row.split('\t').collect();
            if cells.len() != 3 { return Err("row".into()); }
            let (label, pkg, safe) = (cells[0], cells[1], cells[2]);
            if label.is_empty() || safe.is_empty() || safe.contains(['/', '\\', '\r', '\n']) || safe == "." || safe.contains("..")
                || !pkg.as_bytes().first().is_some_and(u8::is_ascii_alphabetic)
                || !pkg.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'.' || c == b'_') {
                return Err("legacy input".into());
            }
            let file = Path::new(&args[1]).join(safe).join("app_details.json");
            let absent = match fs::metadata(&file) {
                Ok(m) if m.is_file() => m.len() == 0,
                Err(e) if e.kind() == io::ErrorKind::NotFound => true,
                _ => return Err("legacy file".into()),
            };
            if absent {
                output.push_str(&format!("M\t{label}\t{pkg}\t{safe}\t-\t-\n"));
            } else {
                let text = fs::read_to_string(&file).map_err(|_| "json read")?;
                let docs = documents(&text)?;
                if docs.len() != 1 { return Err("legacy document stream".into()); }
                let record_pkg = raw(&ad(&docs[0], "ad_first_pkg")?);
                let version = ad(&docs[0], "ad_first_apk_version")?;
                let old = if version.text().is_some() { raw(&version) } else { version.emit(true, 0) };
                let clean = |v: &str| v.chars().filter(|c| !matches!(c, ' ' | '\t' | '\r' | '\n')).collect::<String>();
                let old = clean(&old);
                // Original code queries current version before rejecting old version
                // or package mismatch. Defer those cases to preserve that ordering.
                if record_pkg != pkg || old.is_empty() || !old.bytes().all(|c| c.is_ascii_digit()) { return Err("legacy identity".into()); }
                let map = fs::read_to_string(&args[2]).map_err(|_| "map read")?;
                if map.contains('\0') { return Err("legacy map".into()); }
                let current = map.split('\n').find_map(|line| {
                    let mut fields = line.split('\t');
                    if fields.next() == Some(pkg) { Some(clean(fields.next().unwrap_or_default())) } else { None }
                }).ok_or("refresh needed")?;
                if current.is_empty() || !current.bytes().all(|c| c.is_ascii_digit()) { return Err("refresh or legacy version".into()); }
                output.push_str(&format!("V\t{label}\t{pkg}\t{safe}\t{old}\t{current}\n"));
            }
            count += 1;
        }
        output.push_str(&format!("END_UPDATE_PLAN_1\t{count}\n"));
        Ok(output)
    })();
    match work {
        Ok(output) => if io::stdout().write_all(output.as_bytes()).is_ok() { 0 } else { 1 },
        Err(_) => 1,
    }
}

// Shared pure conversion for the immutable batch plan and single-state command.
// Keep modern-to-legacy fallback and the compact JSON serialization boundary.
// This helper returns bytes; it does not write metadata or scratch files.
// The batch caller publishes a complete plan before the shell uses any row.
// Live installed, user, cache, journal and scratch checks remain in the shell.
// Failed or invalidated plan rows retain the single-state compatibility path.
fn restore_ssaid_convert_doc(doc: &V, path: &str, entry: &str, pkg: &str, user: &str) -> Result<(String, String), String> {
    let vars = Vars::from([("entry".into(), entry.into()), ("pkg".into(), pkg.into()), ("user".into(), user.into())]);
    let mut states = execute("state-v2", doc, &vars, path).unwrap_or_default();
    if states.is_empty() { states = execute("state-migrate", doc, &vars, path)?; }
    if states.is_empty() { return Err("empty state".into()); }
    let mut record = String::new();
    for state in states { record.push_str(&state.emit(false, 0)); record.push('\n'); }
    let mut filtered = String::new();
    for state in documents(&record)? {
        for value in execute("snapshot-ssaid", &state, &Vars::new(), path)? {
            filtered.push_str(&value.emit(false, 0)); filtered.push('\n');
        }
    }
    Ok((record, filtered))
}

pub(super) fn restore_ssaid_state(args: &[String]) -> i32 {
    if args.len() != 6 || args[2].is_empty() || args[4].is_empty() || args[5].is_empty() { return 1; }
    let work = (|| -> Result<(), String> {
        let metadata = fs::metadata(&args[0]).map_err(|e| e.to_string())?;
        if !metadata.is_file() || metadata.len() == 0 { return Err("legacy source".into()); }
        let body = fs::read_to_string(&args[0]).map_err(|e| e.to_string())?;
        let docs = documents(&body)?;
        if docs.len() != 1 { return Err("legacy multi-document path".into()); }
        let (record, filtered) = restore_ssaid_convert_doc(&docs[0], &args[0], &args[1], &args[2], &args[3])?;
        fs::write(&args[4], record.as_bytes()).map_err(|e| e.to_string())?;
        fs::write(&args[5], filtered.as_bytes()).map_err(|e| e.to_string())?;
        Ok(())
    })();
    if work.is_ok() { 0 } else { 1 }
}

// One immutable metadata scan, no writes. Live installed and scratch-path checks
// remain in the shell loop; a failed conversion only declines that row's state.
pub(super) fn restore_ssaid_plan(list: &str, user: &str) -> i32 {
    let work = (|| -> Result<String, String> {
        let paths = fs::read_to_string(list).map_err(|e| e.to_string())?;
        if paths.contains('\0') { return Err("binary list".into()); }
        let mut out = String::from("SBSSID_PLAN1\n");
        for line in paths.split_inclusive('\n') {
            if !line.ends_with('\n') { break; }
            let path = line[..line.len()-1].trim_matches([' ', '\t']);
            let metadata = match fs::metadata(path) { Ok(m) if m.len() > 0 => m, _ => { out.push_str("N\n"); continue; } };
            if !metadata.is_file() { return Err("nonregular input".into()); }
            let body = fs::read_to_string(path).map_err(|e| e.to_string())?;
            let docs = documents(&body)?;
            let result = execute("restore-ssaid-identity", &V::Array(docs.clone()), &Vars::new(), path)?;
            let value = raw(result.first().ok_or("missing identity")?);
            let fields = value.strip_prefix("SBSSID1\t").ok_or("invalid identity")?;
            let (entry, pkg) = fields.split_once('\t').ok_or("missing identity field")?;
            let converted = if entry.is_empty() || pkg.is_empty() { None } else { restore_ssaid_convert_doc(&docs[0], path, entry, pkg, user).ok() };
            out.push_str("Y\t"); out.push_str(fields);
            if let Some((record, filtered)) = converted {
                if let Some(compact) = record.strip_suffix('\n') {
                    if !compact.contains(['\n', '\r', '\t', '\0']) && compact.starts_with('{') && compact.ends_with('}') && (filtered.is_empty() || filtered == record) {
                        out.push_str(if filtered.is_empty() { "\tR\t0\t" } else { "\tR\t1\t" });
                        out.push_str(compact); out.push('\n'); continue;
                    }
                }
            }
            out.push_str("\tF\t0\t\n");
        }
        out.push_str("END\n"); Ok(out)
    })();
    match work { Ok(out) => if io::stdout().write_all(out.as_bytes()).is_ok() { 0 } else { 1 }, Err(_) => 1 }
}

pub(super) fn restore_ssaid_batch(list: &str) -> i32 {
    let work = (|| -> Result<String, String> {
        let paths = fs::read_to_string(list).map_err(|e| e.to_string())?;
        if paths.contains('\0') { return Err("binary list".into()); }
        let mut out = String::from("SBSSAID1\n");
        for line in paths.split_inclusive('\n') {
            // Match while read -r: an unterminated last record is not processed.
            if !line.ends_with('\n') { break; }
            let path = line[..line.len()-1].trim_matches([' ', '\t']);
            let metadata = match fs::metadata(path) { Ok(m) if m.len() > 0 => m, _ => { out.push_str("N\n"); continue; } };
            if !metadata.is_file() { return Err("nonregular input".into()); }
            let body = fs::read_to_string(path).map_err(|e| e.to_string())?;
            let docs = documents(&body)?;
            let result = execute("restore-ssaid-package", &V::Array(docs), &Vars::new(), path)?;
            let value = raw(result.first().ok_or("missing result")?);
            if value == "N" { out.push_str("N\n"); }
            else if let Some(pkg) = value.strip_prefix("Y\n") {
                if pkg.contains(['\t', '\r', '\n', '\0']) { return Err("legacy package".into()); }
                out.push_str("Y\t"); out.push_str(pkg); out.push('\n');
            } else { return Err("invalid result".into()); }
        }
        out.push_str("END\n"); Ok(out)
    })();
    match work { Ok(out) => if io::stdout().write_all(out.as_bytes()).is_ok() { 0 } else { 1 }, Err(_) => 1 }
}

pub(super) fn run(args: &[String]) -> i32 {
    let result = (|| -> Result<i32, (i32, String)> {
        let (mut r, mut c, mut e, mut slurp) = (false, false, false, false);
        let mut vars = Vars::new();
        let mut p = 2;
        let mut op = None;
        let mut files = vec![];
        while p < args.len() {
            let t = &args[p];
            if op.is_none() && t.starts_with('-') {
                if t == "--arg" {
                    if p + 2 >= args.len() {
                        return Err((2, "missing argument".into()));
                    }
                    vars.insert(args[p + 1].clone(), args[p + 2].clone());
                    p += 3;
                    continue;
                }
                for ch in t.chars().skip(1) {
                    match ch {
                        'r' => r = true,
                        'c' => c = true,
                        'e' => e = true,
                        's' => slurp = true,
                        _ => return Err((2, format!("unsupported flag {t}"))),
                    }
                }
            } else if op.is_none() {
                op = Some(t.clone())
            } else {
                files.push(t.clone())
            }
            p += 1
        }
        let op = op.ok_or((2, "missing operation".into()))?;
        if files.is_empty() {
            files.push("-".into())
        }
        let mut docs = vec![];
        for file in files {
            let s = if file == "-" {
                let mut s = String::new();
                io::stdin()
                    .read_to_string(&mut s)
                    .map_err(|x| (2, x.to_string()))?;
                s
            } else {
                fs::read_to_string(&file).map_err(|x| (2, x.to_string()))?
            };
            for v in documents(&s).map_err(|x| (5, x))? {
                docs.push((file.clone(), v))
            }
        }
        if slurp {
            docs = vec![(
                "-".into(),
                V::Array(docs.into_iter().map(|(_, v)| v).collect()),
            )]
        }
        let mut output = String::new();
        let mut last = None;
        for (file, v) in docs {
            for v in execute(&op, &v, &vars, &file).map_err(|x| (5, x))? {
                output.push_str(&if r && v.text().is_some() {
                    raw(&v)
                } else {
                    v.emit(!c, 0)
                });
                output.push('\n');
                last = Some(v.truth())
            }
        }
        io::stdout()
            .write_all(output.as_bytes())
            .map_err(|x| (2, x.to_string()))?;
        Ok(if e {
            match last {
                Some(true) => 0,
                Some(false) => 1,
                None => 4,
            }
        } else {
            0
        })
    })();
    match result {
        Ok(rc) => rc,
        Err((rc, err)) => {
            eprintln!("JSON_ERROR {err}");
            rc
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn soc_board_fallback_requires_verified_identity_and_preserves_exact_sku() {
        let table=parse(r#"{"MT6991Z/CZB":{"VENDOR":"MediaTek","NAME":"Dimensity 9400"}}"#).unwrap();
        let base=vec!["null".into()," MT6991 ".into()];
        assert_eq!(soc_device_resolve(&table,&base,"Redmi","dali"),("MediaTek Dimensity 9400+".into(),String::new()));
        assert_eq!(soc_device_resolve(&table,&base,"XIAOMI","DALI").0,"MediaTek Dimensity 9400+");
        for (brand,board) in [("vivo","dali"),("Redmi","unknown"),("","dali")] {
            assert_eq!(soc_device_resolve(&table,&base,brand,board).0,"MT6991（系統回報）");
        }
        assert_eq!(soc_device_resolve(&table,&["MT6991".into(),"MT6991Z/CZB".into()],"Redmi","dali").0,"MediaTek Dimensity 9400");
        assert_eq!(soc_device_resolve(&table,&["MT6991".into(),"MT6991Z/NEW".into()],"Redmi","dali").0,"MT6991（系統回報）");
        assert_eq!(soc_device_resolve(&table,&["SM8550".into()],"Redmi","dali").0,"SM8550（系統回報）");
        assert_eq!(soc_device_resolve(&table,&[],"Redmi","dali").0,"未知");
        assert_eq!(soc_device_resolve(&table,&["MT6989".into(),"MT6991".into()],"Redmi","dali").0,"MT6989（系統回報）");
        let exact=parse(r#"{"MT6991":{"NAME":"Database model","MEMORY":"Verified memory"}}"#).unwrap();
        assert_eq!(soc_device_resolve(&exact,&base,"Redmi","dali"),("Database model".into(),"Verified memory".into()));
    }
    #[test]
    fn soc_fallback_exact_normalized_and_unknown() {
        let table=parse(r#"{"MT6991Z/TCZB":{"VENDOR":"MediaTek","NAME":"Dimensity 9400+","MEMORY":"LPDDR5X"}}"#).unwrap();
        assert_eq!(soc_resolve(&table,&[" mt6991z/tczb ".into()]),("MediaTek Dimensity 9400+".into(),"LPDDR5X".into()));
        assert_eq!(soc_resolve(&table,&["null".into(),"MT6991Z/TCZB".into()]).0,"MediaTek Dimensity 9400+");
        assert_eq!(soc_resolve(&table,&["MT6991".into()]).0,"MT6991（系統回報）");
        assert_eq!(soc_resolve(&table,&["null".into(),"".into()]).0,"未知");
        let bad=parse(r#"{"X":{"VENDOR":"bad","NAME":null}}"#).unwrap();
        assert_eq!(soc_resolve(&bad,&["X".into()]).0,"X（系統回報）");
    }
    #[test]
    fn memtotal_excludes_swap_and_rejects_invalid() {
        assert_eq!(usable_ram("MemTotal: 15600000 kB\nSwapTotal: 8000000 kB\n"),Some(15600000));
        for s in ["SwapTotal: 12000000 kB","MemTotal: 16 GB","MemTotal: 0 kB","MemTotal: 12 kB\nMemTotal: 24 kB","MemTotal: -1 kB"]{assert_eq!(usable_ram(s),None);}
    }
    #[test]
    fn reject_partial_document_stream() {
        assert!(documents("{\"ok\":1}\n{bad").is_err());
    }
    #[test]
    fn numeric_equality_preserves_large_integer_distinctions() {
        assert!(!same(&atom("9007199254740992"), &atom("9007199254740993")));
        assert!(same(&atom("12300"), &atom("1.2300e4")));
        assert!(same(&atom("-0.00"), &atom("0")));
    }
    #[test]
    fn preserve_integer_and_nullable_fields() {
        let v = parse(r#"{"App":{"n":18446744073709551615,"flag":false,"nil":null}}"#).unwrap();
        let a = Vars::from([
            ("entry".into(), "App".into()),
            ("key".into(), "Size".into()),
            ("value".into(), "2".into()),
        ]);
        let out = execute("set-field", &v, &a, "").unwrap();
        assert_eq!(
            out[0].emit(false, 0),
            r#"{"App":{"n":18446744073709551615,"flag":false,"nil":null,"Size":"2"}}"#
        );
    }
    #[test]
    fn recursive_merge_keeps_order_and_replaces_arrays() {
        let a = parse(r#"{"a":{"x":1,"keep":null},"b":[1,2]}"#).unwrap();
        let b = parse(r#"{"a":{"y":false},"b":[3]}"#).unwrap();
        assert_eq!(
            merge(&a, &b).emit(false, 0),
            r#"{"a":{"x":1,"keep":null,"y":false},"b":[3]}"#
        );
    }
    #[test]
    fn partial_snapshot_is_both_state_and_error() {
        let v=parse(r#"{"recordType":"snapshot","packageName":"pkg.test","result":{"name":"PARTIAL","message":"a\tb\nc"}}"#).unwrap();
        let out = execute("snapshot-reduce", &v, &Vars::new(), "").unwrap();
        assert_eq!(out.len(), 2);
        assert!(raw(&out[0]).starts_with("STATE\tpkg.test\t"));
        assert!(raw(&out[1]).contains("a\\tb\\nc"));
    }
    #[test]
    fn invalid_root_cannot_pass_schema() {
        for v in [atom("null"), boolean(false), string("bad")] {
            assert!(!state_schema(&v));
            assert!(!state_items(&v));
            assert!(!state_nullable(&v));
        }
    }
    #[test]
    fn missing_capability_fails_contract() {
        let v =
            parse(r#"{"schemaVersion":2,"daemonProtocolVersion":1,"capabilities":[]}"#).unwrap();
        assert!(!execute("caps-contract", &v, &Vars::new(), "").unwrap()[0].truth());
    }
    #[test]
    fn metadata_batch_matches_individual_operations() {
        let v = parse(r#"{"App":{"PackageName":"pkg.test","apk_version":"9"}}"#).unwrap();
        let out = execute("metadata-identity", &v, &Vars::new(), "").unwrap();
        assert_eq!(
            out[0].emit(false, 0),
            ad(&v, "ad_first_pkg").unwrap().emit(false, 0)
        );
        assert_eq!(
            out[1].emit(false, 0),
            ad(&v, "ad_first_apk_version").unwrap().emit(false, 0)
        );
        assert!(execute("metadata-valid", &v, &Vars::new(), "").unwrap()[0].truth());
    }
    #[test]
    fn restore_metadata_plan_matches_existing_readers() {
        let doc = parse(r#"{"Example":{"PackageName":"pkg.test","apk_version":9223372036854775807,"keystore":true,"app_state":{"installer":"store.state"}},"user":{"Size":"  12 KB\t","path":"/data/a b","archive_input_bytes":18446744073709551615},"data":{"Size":false,"path":null},"hma":{"Size":0}}"#).unwrap();
        let vars = Vars::from([("entry".into(), "Example".into())]);
        let slurp = V::Array(vec![doc.clone()]);
        let rows = execute("restore-metadata-plan", &slurp, &vars, "").unwrap();
        assert_eq!(rows.len(), 35);
        assert_eq!(raw(&rows[0]), "RESTORE_METADATA_PLAN_1");
        assert_eq!(raw(&rows[34]), "END_RESTORE_METADATA_PLAN_1");
        assert_eq!(raw(&rows[1]), raw(&ad(&doc, "ad_first_pkg").unwrap()));
        assert_eq!(raw(&rows[2]), raw(&ad(&doc, "ad_first_apk_version").unwrap()));
        assert_eq!(raw(&rows[3]), "store.state");
        assert_eq!(raw(&rows[4]), raw(&execute("restore-mask", &slurp, &vars, "").unwrap()[0]));
        for (i, entry) in ["user", "data", "obb", "media", "user_de", "thanox", "hma"].iter().enumerate() {
            let args = Vars::from([("e".into(), (*entry).into())]);
            let old = execute("payload-summary", &doc, &args, "").unwrap();
            for j in 0..4 { assert_eq!(raw(&rows[5 + i * 4 + j]), raw(&old[j])); }
        }
    }
    #[test]
    fn restore_metadata_plan_preserves_installer_precedence() {
        for (state, legacy, diag, expected) in [
            ("store.state", "store.legacy", "store.diag", "store.state"),
            ("", "store.legacy", "store.diag", "store.legacy"),
            ("null", "", "store.diag", "store.diag"),
            ("", "null", "", ""),
        ] {
            let doc = parse(&format!(r#"{{"Example":{{"PackageName":"pkg.test","app_state":{{"installer":"{state}"}},"installer":"{legacy}","install_diagnostics":{{"installer":"{diag}"}}}}}}"#)).unwrap();
            let rows = restore_metadata_plan(&V::Array(vec![doc]), &Vars::new()).unwrap();
            assert_eq!(raw(&rows[3]), expected);
        }
    }
    #[test]
    fn restore_metadata_plan_unusual_inputs_require_fallback() {
        for text in [r#"null"#, r#"false"#, r#"[]"#, r#"{}"#,
            r#"{"App":{"PackageName":"pkg.test","apk_version":"9\n"}}"#,
            r#"{"App":{"PackageName":"pkg.test","apk_version":{"n":9}}}"#,
            r#"{"App":{"PackageName":"pkg.test"},"user":{"Size":"1\r"}}"#,
            r#"{"App":{"PackageName":"pkg.test"},"user":{"path":"a\u0000b"}}"#,
            r#"{"App":{"PackageName":"pkg.test","installer":["store"]}}"#,
        ] {
            let doc = parse(text).unwrap();
            assert!(restore_metadata_plan(&V::Array(vec![doc]), &Vars::new()).is_err(), "{text}");
        }
        let doc = parse(r#"{"App":{"PackageName":"pkg.test"}}"#).unwrap();
        assert!(restore_metadata_plan(&doc, &Vars::new()).is_err());
        assert!(restore_metadata_plan(&V::Array(vec![doc.clone(), doc]), &Vars::new()).is_err());
    }
    #[test]
    fn restore_metadata_plan_modern_state_is_exact_converter_output() {
        let doc = parse(r#"{"Example":{"PackageName":"pkg.test","app_state":{"schemaVersion":2,"recordType":"snapshot","packageName":"old.pkg","permissions":[],"ssaid":"0123","package":{"label":"a\nb"}}}}"#).unwrap();
        let vars = Vars::from([("entry".into(), "Example".into()), ("pkg".into(), "pkg.test".into())]);
        let rows = restore_metadata_plan(&V::Array(vec![doc.clone()]), &vars).unwrap();
        let old = execute("state-v2", &doc, &vars, "").unwrap();
        assert_eq!(raw(&rows[33]), old[0].emit(false, 0));
        let legacy = parse(r#"{"Example":{"PackageName":"pkg.test","app_ops":[]}}"#).unwrap();
        let rows = restore_metadata_plan(&V::Array(vec![legacy]), &vars).unwrap();
        assert_eq!(raw(&rows[33]), "");
    }
}

pub(super) fn regen_identity(text:&str)->Result<(String,String),String>{let v=parse(text)?;Ok((raw(&ad(&v,"ad_first_entry_name")?),raw(&ad(&v,"ad_first_pkg")?)))}
