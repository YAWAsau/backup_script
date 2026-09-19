//! Run-scoped event model. Identity is archive-relative key, retries use monotonic attempts.
use super::payload_stats::{difference, metrics};
use std::collections::BTreeMap;
use std::{fs, io};

fn bad(s: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, s)
}
fn number(s: &str) -> io::Result<u128> {
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
        return Err(bad("invalid integer"));
    }
    s.parse().map_err(|_| bad("integer overflow"))
}
fn opt(s: &str) -> io::Result<Option<u128>> {
    if s == "-" {
        Ok(None)
    } else {
        number(s).map(Some)
    }
}
fn show(n: Option<u128>) -> String {
    n.map(|v| v.to_string()).unwrap_or_else(|| "-".into())
}
fn add(a: &mut u128, b: u128) -> io::Result<()> {
    *a = a.checked_add(b).ok_or_else(|| bad("total overflow"))?;
    Ok(())
}

#[derive(Clone, Debug)]
pub struct BackupEntry {
    pub key: String,
    pub app: String,
    pub kind: String,
    pub planned_input_bytes: Option<u128>,
    pub actual_input_bytes: Option<u128>,
    pub output_bytes: Option<u128>,
    pub state: String,
    pub elapsed_ms: Option<u128>,
    pub rc: Option<u128>,
    pub attempt: u128,
    pub failed_attempts: u128,
    pub codec: String,
    pub source: String,
    pub reason: String,
    began: Option<u128>,
    last_event: Option<String>,
}
impl BackupEntry {
    fn new(key: &str, app: &str, kind: &str, planned: Option<u128>) -> Self {
        Self {
            key: key.into(),
            app: app.into(),
            kind: kind.into(),
            planned_input_bytes: planned,
            actual_input_bytes: None,
            output_bytes: None,
            state: "pending".into(),
            elapsed_ms: None,
            rc: None,
            attempt: 0,
            failed_attempts: 0,
            codec: "unknown".into(),
            source: "unknown".into(),
            reason: "not_started".into(),
            began: None,
            last_event: None,
        }
    }
    fn mismatch(&self) -> bool {
        self.state == "success"
            && matches!((self.planned_input_bytes,self.actual_input_bytes),(Some(a),Some(b)) if a!=b)
    }
}
#[derive(Default, Debug)]
pub struct Totals {
    pub entries: usize,
    pub success: usize,
    pub failed: usize,
    pub skipped: usize,
    pub incomplete: usize,
    pub mismatch: usize,
    pub planned: u128,
    pub planned_unknown: usize,
    pub actual: u128,
    pub output: u128,
    pub input_unknown: usize,
    pub output_unknown: usize,
    pub pending_bytes: usize,
    pub elapsed: u128,
    pub elapsed_unknown: usize,
    pub failed_attempts: u128,
    pub tar: usize,
    pub zstd: usize,
}
impl Totals {
    pub fn accept(&mut self, e: &BackupEntry) -> io::Result<()> {
        self.entries += 1;
        if e.state == "skipped" {
            self.skipped += 1;
            return Ok(());
        }
        match e.planned_input_bytes {
            Some(n) => add(&mut self.planned, n)?,
            None => self.planned_unknown += 1,
        }
        add(&mut self.failed_attempts, e.failed_attempts)?;
        if e.state == "success" {
            self.success += 1;
            if e.mismatch() {
                self.mismatch += 1;
            }
            match e.actual_input_bytes {
                Some(n) => add(&mut self.actual, n)?,
                None => self.input_unknown += 1,
            }
            match e.output_bytes {
                Some(n) => add(&mut self.output, n)?,
                None => self.output_unknown += 1,
            }
            if e.actual_input_bytes.is_none() || e.output_bytes.is_none() {
                self.pending_bytes += 1;
            }
            if e.codec.eq_ignore_ascii_case("tar") {
                self.tar += 1;
            } else {
                self.zstd += 1;
            }
        } else if e.state == "failed" {
            self.failed += 1;
        } else {
            self.incomplete += 1;
        }
        match e.elapsed_ms {
            Some(n) => add(&mut self.elapsed, n)?,
            None => self.elapsed_unknown += 1,
        }
        Ok(())
    }
}
// The app planner does not cover custom Media. Compare the same planned keys
// on both sides and report uncovered entries separately, never as zero bytes.
#[derive(Default)]
struct PlanReconcile {
    totals: Totals,
    outside: usize,
}
impl PlanReconcile {
    fn accept(&mut self, e: &BackupEntry) -> io::Result<()> {
        if e.state == "skipped" {
            return Ok(());
        }
        if e.planned_input_bytes.is_some() {
            self.totals.accept(e)?;
        } else {
            self.outside += 1;
        }
        Ok(())
    }
    fn result(&self) -> (&'static str, &'static str) {
        let t = &self.totals;
        if t.entries == 0 {
            return ("unknown", "unknown");
        }
        if t.failed != 0 || t.incomplete != 0 || t.input_unknown != 0 {
            return ("partial", "unknown");
        }
        if t.mismatch != 0 || t.planned != t.actual {
            ("mismatch", "0")
        } else {
            ("ok", "1")
        }
    }
    fn receipt(&self) -> String {
        let (state, matched) = self.result();
        let t = &self.totals;
        format!("SBRESULT\t1\tbackup-plan\t{state}\tplanned-entries\t{}\t{}\t{matched}\t{}\t{}\t{}\t{}\t{}\t{}\n",
            t.planned, t.actual, t.entries, t.mismatch, t.input_unknown, t.failed, t.incomplete, self.outside)
    }
}

pub fn reduce(plan: &str, events: &str, sizes: &str) -> io::Result<BTreeMap<String, BackupEntry>> {
    let mut rows = BTreeMap::new();
    for line in plan.lines().filter(|l| !l.is_empty()) {
        let f: Vec<_> = line.split('\t').collect();
        if f.len() != 5 || !matches!(f[0], "APK" | "DIR") || f[1].is_empty() || f[3].is_empty() {
            return Err(bad("invalid plan"));
        }
        let key = format!("{}/{}", f[1], f[3]);
        let entry = BackupEntry::new(&key, f[1], f[3], Some(number(f[4])?));
        if rows.insert(key, entry).is_some() {
            return Err(bad("duplicate planned entry"));
        }
    }
    for line in events.lines().filter(|l| !l.is_empty()) {
        let f: Vec<_> = line.split('\t').collect();
        if f.len() != 12
            || f[..3].iter().any(|v| v.is_empty())
            || !matches!(
                f[4],
                "consider" | "begin" | "success" | "failed" | "skipped"
            )
        {
            return Err(bad("invalid entry event"));
        }
        let attempt = number(f[3])?;
        let at = number(f[9])?;
        let rc = opt(f[10])?;
        let input = opt(f[5])?;
        let output = opt(f[6])?;
        let e = rows
            .entry(f[0].into())
            .or_insert_with(|| BackupEntry::new(f[0], f[1], f[2], None));
        if e.app != f[1] || e.kind != f[2] {
            return Err(bad("entry identity changed"));
        }
        if f[0] != format!("{}/{}", f[1], f[2]) {
            return Err(bad("entry key mismatch"));
        }
        if e.last_event.as_deref() == Some(line) {
            continue;
        }
        if f[4] == "consider" {
            continue;
        }
        if attempt < e.attempt {
            return Err(bad("out-of-order attempt"));
        }
        if f[4] == "begin" {
            if attempt == 0 || e.state == "running" {
                return Err(bad("missing previous terminal event"));
            }
            if attempt <= e.attempt && e.began.is_some() {
                return Err(bad("duplicate begin"));
            }
            e.began = Some(at);
            e.state = "running".into();
            e.rc = None;
            e.actual_input_bytes = None;
            e.output_bytes = None;
            if e.attempt == 0 {
                e.elapsed_ms = Some(0);
            }
        } else if f[4] == "skipped" {
            if e.began.is_some() {
                return Err(bad("attempt cannot become skipped"));
            }
            if rc != Some(0) {
                return Err(bad("skipped rc"));
            }
            e.state = "skipped".into();
            e.elapsed_ms = Some(0);
            e.rc = rc;
        } else {
            if attempt != e.attempt || e.began.is_none() {
                return Err(bad("terminal event without begin"));
            }
            if (f[4] == "success" && rc != Some(0))
                || (f[4] == "failed" && (rc.is_none() || rc == Some(0)))
            {
                return Err(bad("terminal rc mismatch"));
            }
            if e.state != "running" {
                return Err(bad("conflicting terminal event"));
            }
            e.elapsed_ms = match (e.elapsed_ms, at.checked_sub(e.began.unwrap())) {
                (Some(total), Some(elapsed)) => Some(
                    total
                        .checked_add(elapsed)
                        .ok_or_else(|| bad("elapsed overflow"))?,
                ),
                _ => None,
            };
            e.state = f[4].into();
            e.rc = rc;
            e.actual_input_bytes = input;
            e.output_bytes = output;
            if f[4] == "failed" {
                add(&mut e.failed_attempts, 1)?;
            }
        }
        e.attempt = attempt;
        e.codec = f[7].into();
        e.source = f[8].into();
        e.reason = f[11].into();
        e.last_event = Some(line.into());
    }
    let mut map = BTreeMap::new();
    for l in sizes.lines().filter(|l| !l.is_empty()) {
        let f: Vec<_> = l.split('\t').collect();
        if f.len() != 2 {
            return Err(bad("size map columns"));
        }
        let n = number(f[1])?;
        if map.insert(f[0], n).is_some_and(|v| v != n) {
            return Err(bad("size map conflict"));
        }
    }
    for e in rows.values_mut() {
        if e.state == "success" && e.source == "smb" && e.output_bytes.is_none() {
            let ext = if e.codec.eq_ignore_ascii_case("tar") {
                ".tar"
            } else {
                ".tar.zst"
            };
            e.output_bytes = map.get(format!("{}{ext}", e.key).as_str()).copied();
            if ext == ".tar" && e.actual_input_bytes.is_none() {
                e.actual_input_bytes = e.output_bytes;
            }
        }
    }
    Ok(rows)
}
fn read_optional(path: &str) -> io::Result<String> {
    match fs::read_to_string(path) {
        Ok(s) => Ok(s),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(String::new()),
        Err(e) => Err(e),
    }
}
pub fn command(a: &[String]) -> i32 {
    let run = || -> io::Result<()> {
        if a.len() != 8 {
            return Err(bad(
                "backup-run-summary PLAN EVENTS SMB_MAP PREFIX EXPECTED PLAN_TOTAL",
            ));
        }
        match fs::remove_file(format!("{}.summary", a[5])) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e),
        }
        let rows = reduce(
            &read_optional(&a[2])?,
            &fs::read_to_string(&a[3])?,
            &read_optional(&a[4])?,
        )?;
        let mut totals = Totals::default();
        let mut reconcile = PlanReconcile::default();
        let mut apps = BTreeMap::<String, Totals>::new();
        let mut detail=String::from("#schema\tspeedbackup.backup_entries.v1\nkey\tapp\tkind\tplanned\tactual\toutput\tstate\tattempt\telapsedMs\trc\tfailedAttempts\tmismatch\tsavedPercent\treason\n");
        for e in rows.values() {
            totals.accept(e)?;
            reconcile.accept(e)?;
            apps.entry(e.app.clone()).or_default().accept(e)?;
            let rate = match (e.actual_input_bytes, e.output_bytes) {
                (Some(i), Some(o)) if e.state == "success" => metrics(i, o)?.0,
                _ => "-".into(),
            };
            detail.push_str(&format!(
                "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
                e.key,
                e.app,
                e.kind,
                show(e.planned_input_bytes),
                show(e.actual_input_bytes),
                show(e.output_bytes),
                e.state,
                e.attempt,
                show(e.elapsed_ms),
                show(e.rc),
                e.failed_attempts,
                u8::from(e.mismatch()),
                rate,
                e.reason
            ));
        }
        let mut appout=String::from("#schema\tspeedbackup.backup_apps.v1\napp\tentries\tsuccess\tfailed\tskipped\tincomplete\tplanned\tactual\toutput\tmismatch\telapsedMs\tunknownPlanned\tunknownInput\tunknownOutput\tsavedPercent\tratio\tfailedAttempts\tunknownElapsed\n");
        for (app, t) in &apps {
            let (rate, ratio) =
                if t.pending_bytes == 0 && t.failed == 0 && t.incomplete == 0 && t.actual > 0 {
                    metrics(t.actual, t.output)?
                } else {
                    ("-".into(), "-".into())
                };
            appout.push_str(&format!(
                "{app}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{rate}\t{ratio}\t{}\t{}\n",
                t.entries,
                t.success,
                t.failed,
                t.skipped,
                t.incomplete,
                t.planned,
                t.actual,
                t.output,
                t.mismatch,
                t.elapsed,
                t.planned_unknown,
                t.input_unknown,
                t.output_unknown,
                t.failed_attempts,
                t.elapsed_unknown
            ));
        }
        let t = &totals;
        let expected = number(&a[6])?;
        let plan = opt(&a[7])?;
        let complete = t.pending_bytes == 0 && t.failed == 0 && t.incomplete == 0;
        let (rate, ratio) = if complete && t.actual > 0 {
            metrics(t.actual, t.output)?
        } else {
            ("-".into(), "-".into())
        };
        let matched = match plan {
            Some(p)
                if t.planned_unknown == 0
                    && t.input_unknown == 0
                    && t.failed == 0
                    && t.incomplete == 0 =>
            {
                if p == t.actual && t.mismatch == 0 {
                    "1"
                } else {
                    "0"
                }
            }
            _ => "unknown",
        };
        let state = if t.failed > 0 {
            "failed"
        } else if !complete || t.mismatch > 0 {
            "partial"
        } else {
            "ok"
        };
        // First 21 fields retain the UI receipt order; append run model counters.
        let summary=format!("SBRESULT\t1\tbackup-run\t{state}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{rate}\t{ratio}\t{}\t{matched}\t{}\t{}\t{expected}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",t.success,t.success-t.pending_bytes,t.pending_bytes,t.input_unknown,t.output_unknown,t.actual,t.output,t.tar,t.zstd,difference(t.actual,t.output),difference(t.actual,expected),t.entries-t.skipped,t.failed_attempts,apps.len(),t.entries,t.skipped,t.failed,t.incomplete,t.mismatch,t.planned,t.planned_unknown);
        fs::write(format!("{}.entries.tsv", a[5]), detail)?;
        fs::write(format!("{}.apps.tsv", a[5]), appout)?;
        fs::write(format!("{}.reconcile", a[5]), reconcile.receipt())?;
        fs::write(format!("{}.totals.tsv",a[5]),format!("#schema\tspeedbackup.backup_totals.v1\napps\t{}\nentries\t{}\nsuccess\t{}\nfailed\t{}\nskipped\t{}\nincomplete\t{}\nmismatch\t{}\nplanned\t{}\nactual\t{}\noutput\t{}\nelapsedMs\t{}\nunknownElapsed\t{}\nfailedAttempts\t{}\nsavedPercent\t{rate}\nratio\t{ratio}\n",apps.len(),t.entries,t.success,t.failed,t.skipped,t.incomplete,t.mismatch,t.planned,t.actual,t.output,t.elapsed,t.elapsed_unknown,t.failed_attempts))?;
        fs::write(format!("{}.summary.tmp", a[5]), &summary)?;
        fs::rename(format!("{}.summary.tmp", a[5]), format!("{}.summary", a[5]))?;
        print!("{summary}");
        Ok(())
    };
    match run() {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("backup run: {e}");
            2
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn reconcile(plan: &str, events: &str) -> PlanReconcile {
        let mut result = PlanReconcile::default();
        for e in reduce(plan, events, "").unwrap().values() {
            result.accept(e).unwrap();
        }
        result
    }
    #[test]
    fn media_does_not_invalidate_app_comparison_or_claim_global_coverage() {
        let app = event(1, "begin", 1, "-") + &event(1, "success", 2, "0");
        let media = app.replace("App/user\tApp\tuser", "Media/DCIM\tMedia\tDCIM");
        let r = reconcile("DIR\tApp\tpkg\tuser\t100\n", &(app + &media));
        assert_eq!(r.result(), ("ok", "1"));
        assert_eq!(
            (r.totals.planned, r.totals.actual, r.outside),
            (100, 100, 1)
        );
    }
    #[test]
    fn no_plan_does_not_turn_zero_mismatches_into_success() {
        let r = reconcile(
            "",
            &(event(1, "begin", 1, "-") + &event(1, "success", 2, "0")),
        );
        assert_eq!(r.result(), ("unknown", "unknown"));
        assert_eq!(r.outside, 1);
    }
    #[test]
    fn scoped_comparison_preserves_unknown_failed_and_pending() {
        for events in [
            event(1, "begin", 1, "-"),
            event(1, "begin", 1, "-") + &event(1, "failed", 2, "1"),
            (event(1, "begin", 1, "-") + &event(1, "success", 2, "0")).replace("\t100\t", "\t-\t"),
        ] {
            assert_eq!(
                reconcile("DIR\tApp\tpkg\tuser\t100\n", &events).result(),
                ("partial", "unknown")
            );
        }
    }
    #[test]
    fn skipped_apk_is_excluded_and_offsets_do_not_hide_entry_mismatches() {
        let events = event(1, "begin", 1, "-") + &event(1, "success", 2, "0");
        let mut all =
            events.clone() + &events.replace("App/user\tApp\tuser", "App/data\tApp\tdata");
        all += "App/apk\tApp\tapk\t0\tskipped\t-\t-\tzstd\tlocal\t3\t0\tnot_repacked\n";
        let r = reconcile(
            "DIR\tApp\tpkg\tuser\t99\nDIR\tApp\tpkg\tdata\t101\nAPK\tApp\tpkg\tapk\t5000\n",
            &all,
        );
        assert_eq!(r.result(), ("mismatch", "0"));
        assert_eq!(
            (r.totals.planned, r.totals.actual, r.totals.mismatch),
            (200, 200, 2)
        );
    }
    fn event(attempt: u8, state: &str, time: u8, rc: &str) -> String {
        format!(
            "App/user\tApp\tuser\t{attempt}\t{state}\t100\t50\tzstd\tlocal\t{time}\t{rc}\ttest\n"
        )
    }
    #[test]
    fn retry_replaces_failure_and_keeps_failure_count() {
        let events = event(1, "begin", 1, "-")
            + &event(1, "failed", 2, "1")
            + &event(2, "begin", 3, "-")
            + &event(2, "success", 8, "0");
        let r = reduce("DIR\tApp\tpkg\tuser\t100\n", &events, "").unwrap();
        let e = &r["App/user"];
        assert_eq!(
            (e.failed_attempts, e.elapsed_ms, e.output_bytes),
            (1, Some(6), Some(50))
        );
        let mut t = Totals::default();
        t.accept(e).unwrap();
        assert_eq!((t.success, t.failed, t.actual), (1, 0, 100));
    }
    #[test]
    fn skipped_apk_never_counts_payload() {
        let r = reduce(
            "APK\tApp\tpkg\tuser\t100\n",
            &event(0, "skipped", 1, "0"),
            "",
        )
        .unwrap();
        let mut t = Totals::default();
        t.accept(&r["App/user"]).unwrap();
        assert_eq!((t.skipped, t.actual, t.planned), (1, 0, 0));
    }
    #[test]
    fn missing_end_remains_incomplete() {
        let r = reduce("", &event(1, "begin", 1, "-"), "").unwrap();
        let mut t = Totals::default();
        t.accept(&r["App/user"]).unwrap();
        assert_eq!(t.incomplete, 1);
    }
    #[test]
    fn malformed_order_and_rc_rejected() {
        assert!(reduce("", &event(1, "success", 1, "0"), "").is_err());
        assert!(reduce(
            "",
            &(event(1, "begin", 1, "-") + &event(1, "success", 2, "3")),
            ""
        )
        .is_err());
    }
    #[test]
    fn mismatch_and_unknown_are_distinct() {
        let r = reduce(
            "DIR\tApp\tpkg\tuser\t101\n",
            &(event(1, "begin", 1, "-") + &event(1, "success", 2, "0")),
            "",
        )
        .unwrap();
        assert!(r["App/user"].mismatch());
        let r = reduce(
            "",
            &(event(1, "begin", 1, "-") + &event(1, "success", 2, "0")),
            "",
        )
        .unwrap();
        assert!(!r["App/user"].mismatch());
        assert_eq!(r["App/user"].planned_input_bytes, None);
    }
    #[test]
    fn smb_unknown_size_is_resolved_without_fabricating_zero() {
        let events = (event(1, "begin", 1, "-") + &event(1, "success", 2, "0"))
            .replace("\t50\tzstd\tlocal", "\t-\tzstd\tsmb");
        let a = reduce("", &events, "").unwrap();
        assert_eq!(a["App/user"].output_bytes, None);
        let a = reduce("", &events, "App/user.tar.zst\t71\n").unwrap();
        assert_eq!(a["App/user"].output_bytes, Some(71));
        assert!(reduce("", &events, "App/user.tar.zst\t71\nApp/user.tar.zst\t72\n").is_err());
    }
    #[test]
    fn later_failure_supersedes_success_and_duplicate_terminal_is_idempotent() {
        let done = event(1, "success", 2, "0");
        let events = event(1, "begin", 1, "-") + &done + &done;
        let rows = reduce("", &events, "").unwrap();
        assert_eq!(rows["App/user"].state, "success");
        let rows = reduce(
            "",
            &(events + &event(2, "begin", 3, "-") + &event(2, "failed", 4, "2")),
            "",
        )
        .unwrap();
        let mut t = Totals::default();
        t.accept(&rows["App/user"]).unwrap();
        assert_eq!((t.success, t.failed, t.actual, t.output), (0, 1, 0, 0));
    }
    #[test]
    fn backwards_clock_is_unknown_and_unclosed_retry_rejected() {
        let a = reduce(
            "",
            &(event(1, "begin", 9, "-") + &event(1, "success", 2, "0")),
            "",
        )
        .unwrap();
        assert_eq!(a["App/user"].elapsed_ms, None);
        assert!(reduce(
            "",
            &(event(1, "begin", 1, "-") + &event(2, "begin", 2, "-")),
            ""
        )
        .is_err());
    }
    #[test]
    fn totals_overflow_is_reported() {
        let events = (event(1, "begin", 1, "-") + &event(1, "success", 2, "0"))
            .replace("\t100\t", &format!("\t{}\t", u128::MAX));
        let a = reduce("", &events, "").unwrap();
        let mut t = Totals::default();
        t.accept(&a["App/user"]).unwrap();
        assert!(t.accept(&a["App/user"]).is_err());
    }
}
