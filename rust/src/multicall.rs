use std::ffi::OsString;
use std::path::Path;
use std::sync::OnceLock;

pub const APPLETS: [&str; 8] = [
    "cgfreezer",
    "eventwait",
    "filewatch",
    "netwatch",
    "procwait",
    "speedscan",
    "uidexec",
    "unixsock",
];
static ARGS: OnceLock<Vec<OsString>> = OnceLock::new();

// Preserve OS argument bytes. speedscan owns its existing UTF-8 validation;
// no argument is reconstructed through shell text or lossy conversion.
pub fn select(mut argv: Vec<OsString>) -> Result<(String, Vec<OsString>), Vec<OsString>> {
    let name = argv
        .first()
        .and_then(|s| Path::new(s).file_name())
        .and_then(|s| s.to_str());
    if let Some(name) = name.filter(|s| APPLETS.contains(s)) {
        return Ok((name.to_owned(), argv));
    }
    let applet = argv
        .get(1)
        .and_then(|s| s.to_str())
        .filter(|s| APPLETS.contains(s));
    if let Some(applet) = applet {
        let name = applet.to_owned();
        argv.remove(0);
        return Ok((name, argv));
    }
    Err(argv)
}

pub fn initialize(argv: Vec<OsString>) {
    ARGS.set(argv).expect("applet arguments initialized twice");
}

pub fn args_os() -> std::vec::IntoIter<OsString> {
    ARGS.get()
        .expect("applet arguments not initialized")
        .clone()
        .into_iter()
}

pub fn args() -> std::vec::IntoIter<String> {
    args_os()
        .map(|s| s.into_string().expect("non-UTF-8 argument"))
        .collect::<Vec<_>>()
        .into_iter()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_symlink_name_keeps_argv() {
        for name in APPLETS {
            let input = vec![
                OsString::from(format!("/data/backup_tools/{name}")),
                "--version".into(),
            ];
            let (selected, argv) = select(input.clone()).unwrap();
            assert_eq!(selected, name);
            assert_eq!(argv, input);
        }
    }

    #[test]
    fn subcommand_removes_only_binary_argument() {
        let (name, argv) = select(vec![
            "speednative".into(),
            "unixsock".into(),
            "".into(),
            "a b\t\nc".into(),
        ])
        .unwrap();
        assert_eq!(name, "unixsock");
        assert_eq!(
            argv,
            vec![OsString::from("unixsock"), "".into(), "a b\t\nc".into()]
        );
    }

    #[test]
    fn symlink_dispatch_precedes_subcommand() {
        assert_eq!(
            select(vec!["uidexec".into(), "speedscan".into()])
                .unwrap()
                .0,
            "uidexec"
        );
    }

    #[test]
    fn unknown_names_and_prefixes_are_not_applets() {
        for command in ["speedscan-other", "../speedscan", "", "--list"] {
            assert!(select(vec!["speednative".into(), command.into()]).is_err());
        }
    }

    #[cfg(unix)]
    #[test]
    fn non_utf8_payload_is_preserved() {
        use std::os::unix::ffi::OsStringExt;
        let raw = OsString::from_vec(vec![0xff, b'\n']);
        let (_, argv) =
            select(vec!["speednative".into(), "speedscan".into(), raw.clone()]).unwrap();
        assert_eq!(argv[1], raw);
    }
}
