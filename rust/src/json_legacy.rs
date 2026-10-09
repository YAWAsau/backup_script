//! Conversion of existing schema-2 and legacy backup AppState records.
use super::*;
fn object(xs: Vec<(&str, V)>) -> V {
    V::Object(xs.into_iter().map(|(k, v)| (k.into(), v)).collect())
}
fn mode(v: &V) -> V {
    if null(v) {
        return atom("3");
    }
    if numeric(v) {
        return v.clone();
    }
    let s = raw(v).to_ascii_lowercase();
    if !s.is_empty() && s.bytes().all(|c| c.is_ascii_digit()) {
        return atom(s.trim_start_matches('0').to_string().as_str()).nonempty_number();
    }
    atom(match s.as_str() {
        "allow" | "allowed" | "true" => "0",
        "ignore" | "ignored" | "false" => "1",
        "deny" | "denied" | "error" | "errored" => "2",
        "foreground" => "4",
        _ => "3",
    })
}
impl V {
    fn nonempty_number(self) -> V {
        if matches!(&self,V::Atom(s)if s.is_empty()) {
            atom("0")
        } else {
            self
        }
    }
}
fn mode_name(v: &V) -> V {
    string(if eqnum(v, 0.) {
        "allow".into()
    } else if eqnum(v, 1.) {
        "ignored".into()
    } else if eqnum(v, 2.) {
        "errored".into()
    } else if eqnum(v, 3.) {
        "default".into()
    } else if eqnum(v, 4.) {
        "foreground".into()
    } else {
        format!("mode_{}", raw(v))
    })
}
fn num(v: &V, d: &str) -> V {
    let s = raw(v);
    let s = s.trim();
    if let Ok(n) = s.parse::<f64>() {
        if !n.is_finite() {
            return atom(d);
        }
        if s.trim_start_matches(['-', '+'])
            .bytes()
            .all(|c| c.is_ascii_digit())
        {
            let digits = s.trim_start_matches(['-', '+']).trim_start_matches('0');
            if digits.is_empty() {
                atom("0")
            } else {
                atom(&format!(
                    "{}{}",
                    if s.starts_with('-') { "-" } else { "" },
                    digits
                ))
            }
        } else if parse(s).is_ok() {
            atom(s)
        } else {
            atom(&n.to_string())
        }
    } else {
        atom(d)
    }
}
fn parts(v: &V) -> Vec<V> {
    raw(v).split(' ').map(string).collect()
}
fn at(xs: &[V], i: usize) -> V {
    xs.get(i).cloned().unwrap_or_else(|| atom("null"))
}
fn nonnegative(v: &V) -> bool {
    numeric(v) && raw(v).parse::<f64>().map(|x| x >= 0.).unwrap_or(false)
}
fn scoped(v: &V) -> V {
    let mut o = v.clone();
    if o.object() {
        for (k, val) in [
            ("packageMode", atom("null")),
            ("uidMode", atom("null")),
            ("scope", string("default")),
        ] {
            if o.get(k).is_none() {
                o.put(k, val)
            }
        }
    }
    o
}
fn normalize(s: &V, pkg: &str) -> Result<V, String> {
    if !s.object() {
        return Err("AppState must be object".into());
    }
    let mut o = s.clone();
    let p = alt(s, "permissions", V::Array(vec![]));
    if !array(&p) && !p.object() {
        return Err("invalid permissions".into());
    }
    o.put(
        "permissions",
        V::Array(
            values(&p)
                .iter()
                .map(|v| {
                    if nonnegative(&num(&alt(v, "appOp", atom("-1")), "-1")) {
                        scoped(v)
                    } else {
                        v.clone()
                    }
                })
                .collect(),
        ),
    );
    let sp = alt(s, "specialAccess", obj());
    if !sp.object() && !array(&sp) {
        return Err("invalid specialAccess".into());
    }
    o.put(
        "specialAccess",
        V::Object(
            entries(&sp)
                .into_iter()
                .map(|(k, v)| (k, scoped(&v)))
                .collect(),
        ),
    );
    let ops = alt(s, "otherAppOps", V::Array(vec![]));
    if !array(&ops) && !ops.object() {
        return Err("invalid otherAppOps".into());
    }
    o.put(
        "otherAppOps",
        V::Array(values(&ops).iter().map(scoped).collect()),
    );
    let mut b = alt(s, "batterySettings", obj());
    if !b.object() {
        return Err("invalid batterySettings".into());
    }
    for k in ["RUN_IN_BACKGROUND", "RUN_ANY_IN_BACKGROUND"] {
        if let Some(v) = b.get(k) {
            let v = scoped(v);
            b.put(k, v)
        }
    }
    o.put("batterySettings", b);
    o.put("schemaVersion", atom("2"));
    o.put("recordType", string("snapshot"));
    o.put("packageName", string(pkg));
    Ok(o)
}
const SPECIALS: &[(&str, &str, Option<&str>)] = &[
    (
        "SYSTEM_ALERT_WINDOW",
        "android:system_alert_window",
        Some("android.permission.SYSTEM_ALERT_WINDOW"),
    ),
    ("PICTURE_IN_PICTURE", "android:picture_in_picture", None),
    (
        "MANAGE_EXTERNAL_STORAGE",
        "android:manage_external_storage",
        Some("android.permission.MANAGE_EXTERNAL_STORAGE"),
    ),
    (
        "WRITE_SETTINGS",
        "android:write_settings",
        Some("android.permission.WRITE_SETTINGS"),
    ),
    (
        "REQUEST_INSTALL_PACKAGES",
        "android:request_install_packages",
        Some("android.permission.REQUEST_INSTALL_PACKAGES"),
    ),
    (
        "GET_USAGE_STATS",
        "android:get_usage_stats",
        Some("android.permission.PACKAGE_USAGE_STATS"),
    ),
    (
        "USE_FULL_SCREEN_INTENT",
        "android:use_full_screen_intent",
        Some("android.permission.USE_FULL_SCREEN_INTENT"),
    ),
    (
        "SCHEDULE_EXACT_ALARM",
        "android:schedule_exact_alarm",
        Some("android.permission.SCHEDULE_EXACT_ALARM"),
    ),
    (
        "ACCESS_NOTIFICATION_POLICY",
        "android:access_notification_policy",
        Some("android.permission.ACCESS_NOTIFICATION_POLICY"),
    ),
];
fn special(k: &str, v: &V) -> Option<usize> {
    let n = raw(&alt(v, "publicName", string("")));
    let u = k.to_ascii_uppercase();
    SPECIALS
        .iter()
        .position(|(key, name, _)| *key == u || *name == n)
}
fn canonical(i: usize, x: &V) -> V {
    let (_, public, permission) = SPECIALS[i];
    let m = mode(&fallback(&[
        g(x, "mode"),
        g(x, "effectiveMode"),
        g(x, "packageMode"),
        atom("3"),
    ]));
    let op = num(&alt(x, "op", atom("-1")), "-1");
    object(vec![
        (
            "publicName",
            string(raw(&alt(x, "publicName", string(public)))),
        ),
        (
            "manifestPermission",
            fallback(&[
                g(x, "manifestPermission"),
                g(x, "permission"),
                permission.map(string).unwrap_or_else(|| atom("null")),
            ]),
        ),
        ("requested", alt(x, "requested", boolean(true))),
        ("supported", alt(x, "supported", boolean(nonnegative(&op)))),
        ("op", op),
        ("source", string("legacy-migrated")),
        (
            "packageMode",
            if null(&g(x, "packageMode")) {
                m.clone()
            } else {
                mode(&g(x, "packageMode"))
            },
        ),
        (
            "uidMode",
            if null(&g(x, "uidMode")) {
                atom("null")
            } else {
                mode(&g(x, "uidMode"))
            },
        ),
        ("scope", alt(x, "scope", string("package"))),
        ("mode", m.clone()),
        ("modeName", mode_name(&m)),
        ("allowed", boolean(eqnum(&m, 0.) || eqnum(&m, 4.))),
    ])
}
fn legacy_permissions(p: &V) -> V {
    V::Array(
        entries(p)
            .iter()
            .filter(|(k, _)| k.starts_with("android.permission."))
            .map(|(k, v)| {
                let xs = parts(v);
                let flags = xs
                    .iter()
                    .map(raw)
                    .find(|s| s.starts_with("pflags="))
                    .unwrap_or_else(|| "pflags=0".into());
                let flags = num(&string(&flags[7..]), "0");
                let m = if xs.len() >= 3 {
                    mode(&at(&xs, 2))
                } else {
                    atom("3")
                };
                object(vec![
                    ("name", string(k)),
                    ("granted", boolean(at(&xs, 0).text() == Some("true"))),
                    ("flags", flags),
                    ("runtime", boolean(true)),
                    ("development", boolean(false)),
                    (
                        "appOp",
                        if xs.len() >= 3 {
                            num(&at(&xs, 1), "-1")
                        } else {
                            atom("-1")
                        },
                    ),
                    ("appOpMode", m.clone()),
                    ("appOpModeName", mode_name(&m)),
                    ("packageMode", if xs.len() >= 3 { m } else { atom("null") }),
                    ("uidMode", atom("null")),
                    ("scope", string("package")),
                ])
            })
            .collect(),
    )
}
fn special_permissions(p: &V) -> V {
    let mut o = obj();
    for (k, v) in entries(p) {
        if let Some(i) = special(&k, &object(vec![("publicName", string(&k))])) {
            let xs = parts(&v);
            let op = num(&at(&xs, 1), "-1");
            let m = mode(&fallback(&[at(&xs, 2), atom("3")]));
            let x = object(vec![
                ("publicName", string(k)),
                ("op", op.clone()),
                ("mode", m.clone()),
                ("packageMode", m),
                ("requested", boolean(true)),
                ("supported", boolean(nonnegative(&op))),
            ]);
            o.put(SPECIALS[i].0, canonical(i, &x))
        }
    }
    o
}
fn normalize_special(p: &V) -> V {
    let mut o = obj();
    for (k, v) in entries(p) {
        if let Some(i) = special(&k, &v) {
            o.put(SPECIALS[i].0, canonical(i, &v))
        }
    }
    o
}
fn battery(b: &V, bo: &V) -> V {
    fn opstate(b: &V, k: &str) -> V {
        let xs = parts(&alt(b, k, string("")));
        let yes = xs.len() >= 2;
        let m = if yes { mode(&at(&xs, 1)) } else { atom("3") };
        object(vec![
            ("supported", boolean(yes)),
            (
                "op",
                if yes {
                    num(&at(&xs, 0), "-1")
                } else {
                    atom("-1")
                },
            ),
            ("mode", m.clone()),
            ("modeName", mode_name(&m)),
            ("packageMode", if yes { m } else { atom("null") }),
            ("uidMode", atom("null")),
            ("scope", string(if yes { "package" } else { "none" })),
        ])
    }
    let m = mode(bo);
    let any = if b.get("BATTERY:RUN_ANY_IN_BACKGROUND").is_some() {
        opstate(b, "BATTERY:RUN_ANY_IN_BACKGROUND")
    } else {
        object(vec![
            ("supported", boolean(!null(bo) && !raw(bo).is_empty())),
            ("op", atom("-1")),
            ("mode", m.clone()),
            ("modeName", mode_name(&m)),
            ("packageMode", atom("null")),
            ("uidMode", atom("null")),
            ("scope", string("legacy")),
        ])
    };
    object(vec![
        ("RUN_IN_BACKGROUND", opstate(b, "BATTERY:RUN_IN_BACKGROUND")),
        ("RUN_ANY_IN_BACKGROUND", any),
        (
            "deviceidleWhitelist",
            boolean(
                raw(&fallback(&[
                    g(b, "BATTERY:deviceidle_whitelist"),
                    g(b, "BATTERY:idle_whitelist"),
                    g(b, "BATTERY:doze_whitelist"),
                    boolean(false),
                ]))
                .eq_ignore_ascii_case("true"),
            ),
        ),
    ])
}
fn legacy_ops(p: &V, s: &V, b: &V) -> V {
    let handled: Vec<V> = values(s)
        .iter()
        .chain(values(b).iter())
        .filter(|v| v.object())
        .map(|v| g(v, "op"))
        .filter(nonnegative)
        .collect();
    let mut out = vec![];
    for (k, v) in entries(p) {
        if !k.starts_with("android:") && !k.starts_with("EXTRA_OP_") {
            continue;
        }
        let xs = parts(&v);
        let extra = k.starts_with("EXTRA_OP_");
        let op = num(&at(&xs, if extra { 0 } else { 1 }), "-1");
        if !nonnegative(&op) || handled.iter().any(|v| same(v, &op)) {
            continue;
        }
        let m = mode(&at(&xs, if extra { 1 } else { 2 }));
        out.push(object(vec![
            ("publicName", string(k)),
            ("op", op),
            ("mode", m.clone()),
            ("modeName", mode_name(&m)),
            ("allowed", boolean(eqnum(&m, 0.) || eqnum(&m, 4.))),
            ("packageMode", m),
            ("uidMode", atom("null")),
            ("scope", string("package")),
        ]))
    }
    out.sort_by(|a, b| {
        raw(&g(a, "op"))
            .parse::<f64>()
            .unwrap_or(-1.)
            .partial_cmp(&raw(&g(b, "op")).parse::<f64>().unwrap_or(-1.))
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    out.dedup_by(|a, b| same(&g(a, "op"), &g(b, "op")));
    V::Array(out)
}
pub(super) fn convert(v: &V, a: &Vars, fast: bool) -> Result<Vec<V>, String> {
    let entry = g(v, &var(a, "entry"));
    if !entry.object() && !null(&entry) {
        return Err("invalid metadata entry".into());
    }
    let pkg = var(a, "pkg");
    let state = fallback(&[
        path(v, &[&var(a, "entry"), "app_state"]),
        first(v, "app_state"),
        atom("null"),
    ]);
    if !null(&state) {
        return Ok(vec![normalize(&state, &pkg)?]);
    }
    if fast {
        return Ok(vec![]);
    }
    let os = objects(v);
    let meta = os
        .iter()
        .find(|v| is(v, "PackageName", &pkg))
        .or_else(|| os.first())
        .cloned()
        .unwrap_or_else(obj);
    let merged = |k: &str| -> V {
        os.iter()
            .map(|v| g(v, k))
            .filter(V::object)
            .fold(obj(), |a, b| merge(&a, &b))
    };
    let firstval = |k: &str| -> V {
        let x = os
            .iter()
            .map(|v| g(v, k))
            .find(|v| !null(v))
            .unwrap_or_else(|| atom("null"));
        if x.truth() {
            x
        } else {
            atom("null")
        }
    };
    let p = merged("permissions");
    let s = merge(
        &special_permissions(&p),
        &normalize_special(&merged("special_access")),
    );
    let b = battery(&merged("battery_settings"), &firstval("battery_opt"));
    let diag = firstval("install_diagnostics");
    Ok(vec![object(vec![
        ("schemaVersion", atom("2")),
        ("recordType", string("snapshot")),
        ("packageName", string(pkg)),
        (
            "userId",
            num(
                &fallback(&[
                    firstval("userId"),
                    firstval("user_id"),
                    string(var(a, "user")),
                ]),
                "0",
            ),
        ),
        (
            "package",
            object(vec![
                (
                    "installer",
                    fallback(&[
                        firstval("installer"),
                        g(&diag, "installer"),
                        g(&diag, "installing"),
                    ]),
                ),
                ("versionCode", alt(&meta, "apk_version", atom("null"))),
            ]),
        ),
        (
            "installDiagnostics",
            if diag.truth() { diag } else { obj() },
        ),
        ("permissions", legacy_permissions(&p)),
        ("specialAccess", s.clone()),
        ("otherAppOps", legacy_ops(&p, &s, &b)),
        ("batterySettings", b),
        ("ssaid", firstval("Ssaid")),
        ("sourceFormat", string("legacy-app-details-migrated")),
    ])])
}
