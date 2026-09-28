//! Fixed JSON operations used by the shell. No filter language or external process.
use super::*;
include!("json_caps.rs");
#[path = "json_legacy.rs"]
mod legacy;
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
                .or_else(|| None)
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
            let d = g(v, &var(a, "device"));
            if d.object() {
                Ok(vec![
                    string(format!(
                        "DEVICE\t處理器:{} {}",
                        raw(&alt(&d, "VENDOR", string("null"))),
                        raw(&alt(&d, "NAME", string("null")))
                    )),
                    string(format!(
                        "RAM\tRAM:{} {}",
                        raw(&alt(&d, "MEMORY", string("null"))),
                        raw(&alt(&d, "CHANNELS", string("null")))
                    )),
                ])
            } else {
                Ok(vec![string("DEVICE\t處理器:null"), string("RAM\tRAM:null")])
            }
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
        "metadata-summary" => {
            let mut xs = vec![
                fallback(&[first(v, "apk_version"), empty.clone()]),
                fallback(&[first(v, "PackageName"), empty.clone()]),
                fallback(&[path(v, &["Backup time", "date"]), empty.clone()]),
            ];
            for k in ["user", "data", "obb", "user_de", "media"] {
                xs.push(fallback(&[path(v, &[k, "Size"]), empty.clone()]))
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
            if !v.object() { return Err("expected metadata object".into()); }
            let bytes = fs::read(var(a, "edits")).map_err(|_| "edit journal unavailable")?;
            let text = std::str::from_utf8(&bytes).map_err(|_| "invalid edit journal encoding")?;
            if !text.is_empty() && !text.ends_with('\0') { return Err("truncated edit journal".into()); }
            let fields: Vec<_> = text.split_terminator('\0').collect();
            let mut p=0; let mut value=v.clone(); let mut count=0;
            while p<fields.len() {
                let n:usize=fields[p].parse().map_err(|_| "invalid edit argument count")?;p+=1;
                if n==0 || n>128 || p+n>fields.len() { return Err("truncated edit record".into()); }
                let end=p+n; let mut args=Vars::new(); let mut op=None;
                while p<end {
                    if fields[p]=="--arg" && p+2<end { args.insert(fields[p+1].into(),fields[p+2].into());p+=3; }
                    else if op.is_none() { op=Some(fields[p]);p+=1; }
                    else { return Err("invalid edit arguments".into()); }
                }
                let op=op.ok_or("missing edit operation")?;
                if !matches!(op,"set-field"|"set-payload-path"|"set-payload"|"set-apk"|"ensure-package"|"sync-package") { return Err("unsupported edit operation".into()); }
                value=execute(op,&value,&args,file)?.into_iter().next().ok_or("empty edit result")?;
                count+=1;
            }
            eprintln!("JSON_BATCH edits={count}");
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
                let mut xs = vec![g(v, "packageName"), string(v.emit(false, 0))];
                if op == "snapshot-reduce" {
                    xs.insert(0, string("STATE"))
                }
                out.push(tsv(&xs)?)
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
                        || raw(&fallback(&[
                            g(x, "Size"),
                            g(x, "size"),
                            g(x, "path"),
                            string(""),
                        ])) != "")
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
                && raw(&g(v, "modelNameSource")).len() > 0
                && !null(&g(v, "modelNameSource"))
                && raw(&g(v, "marketNameZh")).len() > 0
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
fn documents(s: &str) -> Result<Vec<V>, String> {
    let mut p = 0;
    let mut out = vec![];
    while p < s.len() {
        p = json_skip_ws_bytes(s.as_bytes(), p);
        if p == s.len() {
            break;
        }
        let end = json_parse_value_end_bytes(s.as_bytes(), p, 0).ok_or("invalid JSON input")?;
        out.push(parse(&s[p..end])?);
        p = end
    }
    Ok(out)
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
}
