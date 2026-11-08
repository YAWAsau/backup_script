//! Remote connection policy. Transport/payload execution remains with existing adapters.
use std::{
    collections::BTreeMap,
    io::{self, Read},
    path::Path,
    process::{Command, Stdio},
};
pub fn endpoint(protocol: &str, url: &str) -> io::Result<(String, u16)> {
    let (scheme, rest) = url
        .split_once("://")
        .ok_or_else(|| io::Error::other("invalid remote URL"))?;
    if !matches!(
        (protocol, scheme),
        ("smb", "smb") | ("webdav", "http") | ("webdav", "https")
    ) || url.len() > 4096
        || url.chars().any(|c| c.is_control())
    {
        return Err(io::Error::other("invalid remote protocol"));
    }
    let authority = rest.split('/').next().unwrap_or("");
    if authority.is_empty() || authority.contains(['@', '?', '#', '\\']) {
        return Err(io::Error::other("invalid remote authority"));
    }
    let default = match scheme {
        "https" => 443,
        "http" => 80,
        _ => 445,
    };
    let (host, port) = if let Some(v) = authority.strip_prefix('[') {
        let (h, t) = v
            .split_once(']')
            .ok_or_else(|| io::Error::other("invalid IPv6 authority"))?;
        h.parse::<std::net::Ipv6Addr>()
            .map_err(|_| io::Error::other("invalid IPv6 host"))?;
        (
            h,
            if t.is_empty() {
                None
            } else {
                Some(
                    t.strip_prefix(':')
                        .ok_or_else(|| io::Error::other("invalid port"))?,
                )
            },
        )
    } else {
        if authority.matches(':').count() > 1 {
            return Err(io::Error::other("IPv6 requires brackets"));
        }
        authority
            .split_once(':')
            .map_or((authority, None), |(h, p)| (h, Some(p)))
    };
    let port = match port {
        Some(p) => p
            .parse::<u16>()
            .ok()
            .filter(|p| *p > 0)
            .ok_or_else(|| io::Error::other("invalid port"))?,
        None => default,
    };
    if host.is_empty() || host.chars().any(char::is_whitespace) {
        return Err(io::Error::other("invalid host"));
    }
    Ok((host.into(), port))
}
fn settings(path: &Path) -> io::Result<BTreeMap<String, String>> {
    Ok(
        super::web_settings::parse_runtime(&super::runtime_conf::read(path)?)?
            .into_iter()
            .map(|f| (f.key, f.value))
            .collect(),
    )
}
fn editor(conf: &Path, root: &Path, user: &str, kind: &str) -> io::Result<bool> {
    let mode = if conf
        .file_name()
        .is_some_and(|n| n == "restore_settings.conf")
    {
        "restore"
    } else {
        "backup"
    };
    let status = Command::new(std::env::current_exe()?)
        .args(["speedscan", "applist-web"])
        .arg(root.join("appList.txt"))
        .args(["--open", user])
        .arg(root)
        .args([mode, "settings"])
        // This child edits connection settings, not the parent's selection.
        // Inherited flow would reject /api/finish and keep retry stuck.
        .env_remove("SPEEDBACKUP_SELECTION_FLOW")
        .env_remove("SPEEDBACKUP_SELECTION_REPORT")
        .env_remove("SPEEDBACKUP_AUTH_SETUP")
        .env_remove("SPEEDBACKUP_DISCOVERY_SETUP")
        .env(kind, "1")
        .stdout(Stdio::null())
        .status()?;
    Ok(status.code() == Some(10))
}
fn notice(text: &str) {
    eprintln!("{}", super::applist_web::terminal_text(text));
}
pub fn auth(args: &[String]) -> i32 {
    if args.len() != 4 {
        return 2;
    }
    if matches!(args[3].as_str(), "1" | "true" | "True" | "TRUE") {
        notice("認證失敗，請前往設定修正帳密後重試");
        return 1;
    }
    match editor(
        Path::new(&args[0]),
        Path::new(&args[1]),
        &args[2],
        "SPEEDBACKUP_AUTH_SETUP",
    ) {
        Ok(true) => 10,
        Ok(false) => 130,
        Err(e) => {
            eprintln!("REMOTE_AUTH_FAILED {e}");
            1
        }
    }
}
pub fn address(args: &[String]) -> i32 {
    if args.len() != 3 {
        return 2;
    }
    let operation = || -> io::Result<String> {
        let conf = Path::new(&args[0]);
        let root = Path::new(&args[1]);
        let mut configured = false;
        loop {
            let c = settings(conf)?;
            let get = |k: &str| c.get(k).map(String::as_str).unwrap_or("");
            let protocol = get("remote_type");
            if protocol.is_empty() {
                return Ok(String::new());
            }
            if !matches!(protocol, "smb" | "webdav") {
                return Err(io::Error::other("invalid remote type"));
            }
            let url = get(if protocol == "smb" {
                "smb_url"
            } else {
                "webdav_url"
            });
            if get("remote_address_mode") != "auto" {
                endpoint(protocol, url)?;
                return Ok(url.into());
            }
            let id = get(if protocol == "smb" {
                "remote_smb_identity"
            } else {
                "remote_webdav_identity"
            });
            if !id.is_empty() && endpoint(protocol, url).is_ok() {
                notice("正在尋找原先選定的設備…");
                let out = Command::new(std::env::current_exe()?)
                    .args(["speedscan", "remote-resolve", id, url, &args[0], protocol])
                    .output()?;
                if out.status.success() {
                    let next = String::from_utf8(out.stdout)
                        .map_err(|_| io::Error::other("remote resolution encoding"))?
                        .trim()
                        .to_string();
                    endpoint(protocol, &next)?;
                    if next != url {
                        eprintln!(
                            "{}{next}",
                            super::applist_web::terminal_text("已找到原設備，地址已更新：")
                        );
                    }
                    return Ok(next);
                }
            }
            if configured {
                return Err(io::Error::other("未找到原設備，已停止本次操作"));
            }
            notice(if id.is_empty() {
                "首次使用自動地址：請選擇設備並填寫連線資料"
            } else {
                "未找到原設備，請選擇要使用的設備"
            });
            if !editor(conf, root, &args[2], "SPEEDBACKUP_DISCOVERY_SETUP")? {
                return Err(io::Error::other("連線設定未完成，已取消本次操作"));
            }
            configured = true;
        }
    };
    match operation() {
        Ok(url) => {
            println!("{url}");
            0
        }
        Err(e) => {
            eprintln!(
                "REMOTE_ADDRESS_FAILED {}",
                super::applist_web::terminal_text(&e.to_string())
            );
            1
        }
    }
}
pub fn smb_class(text: &str) -> (&'static str, &'static str, &'static str) {
    let t = text.to_ascii_lowercase();
    let has = |words: &[&str]| words.iter().any(|w| t.contains(w));
    if has(&["nt_status_logon_failure", "nt_status_wrong_password"]) {
        (
            "1",
            "已連上 445 port，但 SMB 認證失敗",
            "請在設定頁檢查 SMB 用戶名與密碼；若要匿名，請清空帳密並確認伺服器允許 Guest/匿名存取",
        )
    } else if has(&[
        "nt_status_bad_network_name",
        "tree connect failed",
        "bad_network_name",
        "object_name_not_found",
        "object_path_not_found",
        "errbadpath",
        "does not exist",
    ]) || t.lines().any(|line| {
        line.split_once("cd ")
            .is_some_and(|(_, after)| after.contains("failed"))
    }) {
        (
            "0",
            "SMB 認證可嘗試，但共享名稱或路徑不存在",
            "請在設定頁檢查 SMB 地址的共享名稱與後續路徑，例如 smb://IP/共享名稱/路徑",
        )
    } else if has(&["nt_status_access_denied", "access_denied", "denied"]) {
        (
            "0",
            "SMB 共享拒絕目前帳號存取",
            "請檢查共享權限與 Windows/NAS 檔案系統權限；能登入不代表能讀寫該 share",
        )
    } else if has(&[
        "connection refused",
        "unable to connect",
        "no route to host",
        "timed out",
        "timeout",
        "protocol negotiation failed",
    ]) {
        (
            "0",
            "SMB 伺服器不可連線或協議協商失敗",
            "請確認伺服器已開啟 SMB2/SMB3、445 port 未被防火牆阻擋，且手機與伺服器在可互通網段",
        )
    } else {
        (
            "0",
            "SMB 目標連線失敗",
            "請檢查 SMB 位址、帳號密碼、共享名稱與伺服器狀態",
        )
    }
}
fn guard_owner() -> io::Result<()> {
    unsafe extern "C" {
        fn getppid() -> i32;
        fn prctl(
            option: i32,
            a: std::os::raw::c_ulong,
            b: std::os::raw::c_ulong,
            c: std::os::raw::c_ulong,
            d: std::os::raw::c_ulong,
        ) -> i32;
    }
    let parent = unsafe { getppid() };
    if parent <= 1 || unsafe { prctl(1, 9, 0, 0, 0) } != 0 || unsafe { getppid() } != parent {
        return Err(io::Error::other("remote owner unavailable"));
    }
    Ok(())
}
pub fn command(args: &[String]) -> i32 {
    if matches!(args.first().map(String::as_str), Some("auth" | "address"))
        && guard_owner().is_err()
    {
        return 1;
    }
    match args.first().map(String::as_str) {
        Some("endpoint") if args.len() == 3 => match endpoint(&args[1], &args[2]) {
            Ok((h, p)) => {
                println!("{h}\t{p}");
                0
            }
            Err(e) => {
                eprintln!("REMOTE_ENDPOINT_FAILED {e}");
                1
            }
        },
        Some("smb-error") if args.len() == 1 => {
            let mut text = String::new();
            if io::stdin().take(1048577).read_to_string(&mut text).is_err() || text.len() > 1048576
            {
                return 1;
            }
            let (a, b, c) = smb_class(&text);
            println!("{a}\n{b}\n{c}");
            0
        }
        Some("auth") => auth(&args[1..]),
        Some("address") => address(&args[1..]),
        _ => 2,
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn authorities() {
        assert_eq!(
            endpoint("webdav", "https://[::1]:8765/x").unwrap(),
            ("::1".into(), 8765)
        );
        assert_eq!(
            endpoint("smb", "smb://nas/share").unwrap(),
            ("nas".into(), 445)
        );
        for u in [
            "http://a:0/",
            "http://a:bad/",
            "http://user@a/",
            "http://::1/",
        ] {
            assert!(endpoint("webdav", u).is_err());
        }
    }
    #[test]
    fn auth_vs_permissions() {
        assert_eq!(smb_class("NT_STATUS_LOGON_FAILURE").0, "1");
        assert_eq!(smb_class("NT_STATUS_ACCESS_DENIED").0, "0");
        assert_eq!(smb_class("protocol negotiation failed").0, "0");
    }
}
