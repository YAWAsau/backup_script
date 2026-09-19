//! One reducer for successful payload receipts. Unknown bytes are never zero.
use std::collections::BTreeMap;
use std::{fs, io};

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}
fn uint(s: &str) -> io::Result<u128> {
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
        return Err(invalid("invalid unsigned decimal"));
    }
    s.parse().map_err(|_| invalid("decimal overflow"))
}
fn optional(s: &str) -> io::Result<Option<u128>> {
    if s == "-" {
        Ok(None)
    } else {
        uint(s).map(Some)
    }
}
fn add(a: u128, b: u128) -> io::Result<u128> {
    a.checked_add(b).ok_or_else(|| invalid("sum overflow"))
}
pub fn difference(a: u128, b: u128) -> String {
    if a >= b {
        (a - b).to_string()
    } else {
        format!("-{}", b - a)
    }
}
fn fixed(n: u128, d: u128) -> io::Result<String> {
    if d == 0 {
        return Ok("0.00".into());
    }
    let q = n
        .checked_mul(100)
        .ok_or_else(|| invalid("ratio overflow"))?;
    let value = add(q / d, u128::from(q % d >= d / 2 + d % 2))?;
    Ok(format!("{}.{:02}", value / 100, value % 100))
}
pub fn metrics(input: u128, output: u128) -> io::Result<(String, String)> {
    if input == 0 {
        return Ok(("0.00".into(), "0.00".into()));
    }
    let delta = input
        .abs_diff(output)
        .checked_mul(100)
        .ok_or_else(|| invalid("rate overflow"))?;
    let rate = fixed(delta, input)?;
    Ok((
        if output > input {
            format!("-{rate}")
        } else {
            rate
        },
        fixed(input, output)?,
    ))
}

#[derive(Debug)]
pub struct Summary {
    pub rows: usize,
    pub origin_pending: usize,
    pub stored_pending: usize,
    pub pending: usize,
    pub input: u128,
    pub output: u128,
    pub tar: usize,
    pub zstd: usize,
    pub duplicates: usize,
}
pub fn reduce(ledger: &str, map: &str) -> io::Result<Summary> {
    let mut sizes = BTreeMap::new();
    for line in map.lines().filter(|s| !s.is_empty()) {
        let f: Vec<_> = line.split('\t').collect();
        if f.len() != 2 || f[0].is_empty() {
            return Err(invalid("invalid size map row"));
        }
        let size = uint(f[1])?;
        if sizes.insert(f[0], size).is_some_and(|old| old != size) {
            return Err(invalid("conflicting size map"));
        }
    }
    let mut entries = BTreeMap::new();
    let mut duplicates = 0;
    for line in ledger.lines().filter(|s| !s.is_empty()) {
        let f: Vec<_> = line.split('\t').collect();
        if f.len() != 6
            || f[0].is_empty()
            || f[5].is_empty()
            || !matches!(f[3], "local" | "webdav" | "smb" | "unknown")
        {
            return Err(invalid("invalid successful payload receipt"));
        }
        let (mut input, mut output) = (optional(f[1])?, optional(f[2])?);
        let tar = f[4].eq_ignore_ascii_case("tar");
        if !tar && !f[4].eq_ignore_ascii_case("zstd") {
            return Err(invalid("invalid codec"));
        }
        if f[3] == "smb" && output.is_none() {
            output = sizes.get(f[0]).copied();
            if tar && input.is_none() {
                input = output;
            }
        }
        // A later successful retry replaces the prior receipt for the same archive.
        if entries.insert(f[0], (input, output, tar)).is_some() {
            duplicates += 1;
        }
    }
    let mut s = Summary {
        rows: entries.len(),
        origin_pending: 0,
        stored_pending: 0,
        pending: 0,
        input: 0,
        output: 0,
        tar: 0,
        zstd: 0,
        duplicates,
    };
    for (_, (input, output, tar)) in entries {
        if let Some(n) = input {
            s.input = add(s.input, n)?;
        } else {
            s.origin_pending += 1;
        }
        if let Some(n) = output {
            s.output = add(s.output, n)?;
        } else {
            s.stored_pending += 1;
        }
        if input.is_none() || output.is_none() {
            s.pending += 1;
        }
        if tar {
            s.tar += 1;
        } else {
            s.zstd += 1;
        }
    }
    Ok(s)
}
pub fn command(args: &[String]) -> i32 {
    let run = || -> io::Result<()> {
        if args.get(1).map(String::as_str) == Some("payload-metrics") {
            if args.len() != 4 {
                return Err(invalid("payload-metrics INPUT OUTPUT"));
            }
            let (rate, ratio) = metrics(uint(&args[2])?, uint(&args[3])?)?;
            println!("{rate}\t{ratio}");
            return Ok(());
        }
        if args.len() != 7 {
            return Err(invalid("payload-stats LEDGER MAP EXPECTED PLAN ARCHIVES"));
        }
        let map = match fs::read_to_string(&args[3]) {
            Ok(s) => s,
            Err(e) if e.kind() == io::ErrorKind::NotFound => String::new(),
            Err(e) => return Err(e),
        };
        let s = reduce(&fs::read_to_string(&args[2])?, &map)?;
        let expected = uint(&args[4])?;
        let plan = optional(&args[5])?;
        let archives = uint(&args[6])?;
        let (rate, ratio) = if s.pending == 0 {
            metrics(s.input, s.output)?
        } else {
            ("-".into(), "-".into())
        };
        let matched = match plan {
            Some(n) if s.origin_pending == 0 => {
                if n == s.input {
                    "1"
                } else {
                    "0"
                }
            }
            _ => "unknown",
        };
        println!("SBRESULT\t1\tpayload-stats\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            if s.pending == 0 { "ok" } else { "partial" }, s.rows, s.rows-s.pending,
            s.pending, s.origin_pending, s.stored_pending, s.input, s.output, s.tar, s.zstd,
            difference(s.input, s.output), rate, ratio, difference(s.input, expected), matched,
            archives, s.duplicates, expected);
        Ok(())
    };
    match run() {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("payload stats: {e}");
            2
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_and_expansion() {
        let s = reduce(
            "a\t100\t50\tlocal\tzstd\tuser\nb\t20\t30\twebdav\ttar\tapk\n",
            "",
        )
        .unwrap();
        assert_eq!((s.input, s.output, s.rows, s.pending), (120, 80, 2, 0));
        assert_eq!(metrics(100, 125).unwrap(), ("-25.00".into(), "0.80".into()));
    }
    #[test]
    fn unknown_is_not_zero() {
        let s = reduce("a\t-\t0\tlocal\tzstd\tuser\n", "").unwrap();
        assert_eq!((s.pending, s.origin_pending, s.stored_pending), (1, 1, 0));
    }
    #[test]
    fn smb_and_retry() {
        let s = reduce(
            "a\t2\t1\tsmb\ttar\tuser\na\t-\t-\tsmb\ttar\tuser\n",
            "a\t10240\n",
        )
        .unwrap();
        assert_eq!(
            (s.input, s.output, s.rows, s.duplicates),
            (10240, 10240, 1, 1)
        );
    }
    #[test]
    fn malformed_and_overflow() {
        assert!(reduce("a\t-1\t0\tlocal\tzstd\tuser\n", "").is_err());
        assert!(reduce("a\t1\t1\tlocal\tzstd\tuser\n", "a\t2\na\t3\n").is_err());
        assert!(reduce(
            &format!(
                "a\t{}\t1\tlocal\tzstd\tuser\nb\t1\t0\tlocal\tzstd\tuser\n",
                u128::MAX
            ),
            ""
        )
        .is_err());
    }
    #[test]
    fn big_integer_and_empty() {
        let s = reduce(
            "a\t9007199254740993\t9007199254740992\tlocal\tzstd\tuser\n",
            "",
        )
        .unwrap();
        assert_eq!(difference(s.input, s.output), "1");
        assert_eq!(reduce("", "").unwrap().rows, 0);
    }
}
