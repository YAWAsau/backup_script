//! Shared literal configuration loader and guarded atomic publication.
use std::{
    fs::{self, OpenOptions},
    io,
    os::unix::fs::{MetadataExt, OpenOptionsExt},
    path::Path,
};
const KNOWN:&str="Background_apps_ignore|Backup_Mode|Backup_obb_data|Backup_suffix|Backup_user_data|Compression_method|Custom_path|Output_path|Shell_LANG|Zstd_level|Zstd_size_hint|Zstd_small_max_bytes|Zstd_small_threads|Zstd_threads|background_execution|backup_calllogs|backup_media|backup_messages|blacklist|blacklist_mode|cdn|list_location|log_max_size_mb|low_battery_mode|media_recovery|mount_point|notification_enable|pc_auto_shutdown|recovery_mode|remote_keep_local|remote_stream|remote_address_mode|remote_smb_identity|remote_webdav_identity|remote_type|remote_upload_per_app|restore_allow_low_target_sdk|restore_calllogs|restore_messages|rgb_a|rgb_b|rgb_c|setDisplayPowerMode|smb_remote_pass|smb_remote_user|smb_url|system|update|user|webdav_remote_pass|webdav_remote_user|webdav_url|whitelist";
pub fn assignments(text: &str, only: &str) -> io::Result<String> {
    let mut out = String::new();
    for f in super::web_settings::parse_runtime(text)? {
        if !KNOWN.split('|').any(|k| k == f.key)
            || (!only.is_empty() && !only.split('|').any(|k| k == f.key))
        {
            continue;
        }
        out.push_str(&f.key);
        out.push_str("='");
        out.push_str(&f.value.replace('\'', "'\\''"));
        out.push_str("'\n");
    }
    Ok(out)
}
pub(super) fn read(path: &Path) -> io::Result<String> {
    use std::io::Read;
    let f = OpenOptions::new()
        .read(true)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
        .open(path)?;
    if !f.metadata()?.is_file() {
        return Err(io::Error::other("configuration must be regular"));
    }
    let mut s = String::new();
    f.take(262145).read_to_string(&mut s)?;
    if s.len() > 262144 {
        return Err(io::Error::other("configuration limit"));
    }
    Ok(s)
}
pub fn commit(source: &Path, target: &Path) -> io::Result<()> {
    let output = read(source)?;
    let before = read(target)?;
    publish(target, &before, &output)
}
fn publish(target: &Path, before: &str, output: &str) -> io::Result<()> {
    super::web_settings::parse_runtime(output)?;
    let m = fs::symlink_metadata(target)?;
    if before == output {
        return Ok(());
    }
    let preserve = super::publish_file::auto_preserve(target)?;
    super::publish_file::publish_bytes_guarded(
        output.as_bytes(),
        target,
        Some(m.mode() & 0o777),
        preserve,
        &mut || {
            let now = fs::symlink_metadata(target)?;
            if (now.dev(), now.ino(), now.mode(), now.uid(), now.gid())
                != (m.dev(), m.ino(), m.mode(), m.uid(), m.gid())
                || read(target)? != before
            {
                return Err(io::Error::other("configuration changed concurrently"));
            }
            Ok(())
        },
    )?;
    Ok(())
}
pub fn command(args: &[String]) -> i32 {
    let result = (|| -> io::Result<()> {
        match args.first().map(String::as_str) {
            Some("load") if matches!(args.len(), 2 | 3) => {
                print!(
                    "{}",
                    assignments(
                        &read(Path::new(&args[1]))?,
                        args.get(2).map(String::as_str).unwrap_or("")
                    )?
                );
                Ok(())
            }
            Some("commit") if args.len() == 3 => commit(Path::new(&args[1]), Path::new(&args[2])),
            Some("migrate") if args.len() == 2 => transform_file(Path::new(&args[1]), false),
            Some("sanitize") if args.len() == 2 => transform_file(Path::new(&args[1]), true),
            _ => Err(io::Error::other("conf command arguments")),
        }
    })();
    match result {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("CONF_FAILED {e}");
            1
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn literal_and_selection() {
        let a = assignments(
            "webdav_remote_pass=\"$(touch /bad)\"\nZstd_level=9\nPATH=/bad\n",
            "",
        )
        .unwrap();
        assert!(a.contains("webdav_remote_pass='$(touch /bad)'"));
        assert!(!a.contains("PATH="));
        assert_eq!(
            assignments("Zstd_level=9\nuser=0\n", "user").unwrap(),
            "user='0'\n"
        );
    }
    #[test]
    fn apostrophe() {
        assert_eq!(
            assignments("webdav_remote_pass=\"a'b\"\n", "").unwrap(),
            "webdav_remote_pass='a'\\''b'\n"
        );
    }
}

const BACKUP_INSERTS: &[(&str, &str, &str)] = &[
    (
        "background_execution",
        "notification_enable",
        "notification_enable=1",
    ),
    (
        "notification_enable",
        "pc_auto_shutdown",
        "pc_auto_shutdown=0",
    ),
    ("Compression_method", "Zstd_level", "Zstd_level=6"),
    ("Zstd_level", "Zstd_threads", "Zstd_threads=0"),
    (
        "Zstd_threads",
        "Zstd_small_max_bytes",
        "Zstd_small_max_bytes=1048576",
    ),
    (
        "Zstd_small_max_bytes",
        "Zstd_small_threads",
        "Zstd_small_threads=1",
    ),
    ("Zstd_small_threads", "Zstd_size_hint", "Zstd_size_hint=1"),
    ("Compression_method", "rgb_a", "rgb_a=220"),
    ("rgb_a", "rgb_b", "rgb_b=51"),
    ("rgb_b", "rgb_c", "rgb_c=213"),
    ("rgb_c", "remote_type", "remote_type="),
    (
        "remote_type",
        "remote_address_mode",
        "remote_address_mode=manual",
    ),
    (
        "remote_address_mode",
        "remote_smb_identity",
        "remote_smb_identity=",
    ),
    (
        "remote_smb_identity",
        "remote_webdav_identity",
        "remote_webdav_identity=",
    ),
    ("remote_type", "smb_url", "smb_url="),
    ("smb_url", "smb_remote_user", "smb_remote_user="),
    ("smb_remote_user", "smb_remote_pass", "smb_remote_pass=\"\""),
    ("smb_remote_pass", "webdav_url", "webdav_url="),
    ("webdav_url", "webdav_remote_user", "webdav_remote_user="),
    (
        "webdav_remote_user",
        "webdav_remote_pass",
        "webdav_remote_pass=\"\"",
    ),
    ("webdav_remote_pass", "remote_stream", "remote_stream=0"),
    ("remote_stream", "remote_keep_local", "remote_keep_local=0"),
    (
        "remote_keep_local",
        "remote_upload_per_app",
        "remote_upload_per_app=0",
    ),
    (
        "remote_upload_per_app",
        "log_max_size_mb",
        "log_max_size_mb=1",
    ),
];
const RESTORE_INSERTS: &[(&str, &str, &str)] = &[
    (
        "background_execution",
        "notification_enable",
        "notification_enable=1",
    ),
    (
        "notification_enable",
        "pc_auto_shutdown",
        "pc_auto_shutdown=0",
    ),
    (
        "notification_enable",
        "log_max_size_mb",
        "log_max_size_mb=1",
    ),
    ("Compression_method", "rgb_a", "rgb_a=220"),
    ("rgb_a", "rgb_b", "rgb_b=51"),
    ("rgb_b", "rgb_c", "rgb_c=213"),
];

fn sanitize(text: &str) -> String {
    text.split_inclusive('\n')
        .map(|line| {
            let mut line = line.to_string();
            if line.starts_with('#') {
                while line.contains("演演算法") {
                    line = line.replace("演演算法", "演算法");
                }
            }
            line
        })
        .collect()
}
fn migrate(text: &str, backup: bool) -> io::Result<String> {
    // Operate on parsed field spans, so multiline lists/passwords are never
    // mistaken for assignments or comments during legacy cleanup.
    let mut output = sanitize(text);
    let fields = super::web_settings::parse_runtime(&output)?;
    let common = [
        "webdav_stream_heartbeat_sec",
        "webdav_stream_progress_step_mb",
        "webdav_stream_idle_warn_sec",
        "webdav_stream_stall_abort_sec",
        "webdav_stream_verbose",
    ];
    let extra = [
        "smbd_share_path",
        "diagnostic_mode",
        "stream_background_boost",
        "stream_background_boost_mode",
        "stream_background_boost_target",
        "stream_background_boost_interval_sec",
        "stream_background_boost_burst_interval_sec",
        "stream_background_boost_burst_sec",
        "stream_background_boost_idle_ms",
        "stream_background_boost_verbose",
    ];
    let legacy = [
        ("hybrid_urls", "${hybrid_urls:-}"),
        ("hybrid_get_mode", "${hybrid_get_mode:-assist}"),
        ("hybrid_get_lead_chunks", "${hybrid_get_lead_chunks:-32}"),
        ("hybrid_get_assist_stride", "${hybrid_get_assist_stride:-5}"),
    ];
    for f in fields.iter().rev() {
        if common.contains(&f.key.as_str())
            || (backup && extra.contains(&f.key.as_str()))
            || legacy.iter().any(|(k, v)| *k == f.key && *v == f.value)
        {
            let start = output[..f.start].rfind('\n').map_or(0, |i| i + 1);
            let end = output[f.end..]
                .find('\n')
                .map_or(output.len(), |i| f.end + i + 1);
            output.replace_range(start..end, "");
        }
    }
    for &(anchor, key, line) in if backup {
        BACKUP_INSERTS
    } else {
        RESTORE_INSERTS
    } {
        let fields = super::web_settings::parse_runtime(&output)?;
        if fields.iter().any(|f| f.key == key) {
            continue;
        }
        if let Some(f) = fields.iter().find(|f| f.key == anchor) {
            let end = output[f.end..]
                .find('\n')
                .map_or(output.len(), |i| f.end + i + 1);
            let addition = if end > 0 && !output[..end].ends_with('\n') {
                format!("\n{line}\n")
            } else {
                format!("{line}\n")
            };
            output.insert_str(end, &addition);
        } else {
            if !output.ends_with('\n') {
                output.push('\n');
            }
            output.push('\n');
            output.push_str(line);
            output.push('\n');
        }
    }
    Ok(output)
}
fn transform_file(path: &Path, only_sanitize: bool) -> io::Result<()> {
    let before = read(path)?;
    let output = if only_sanitize {
        sanitize(&before)
    } else {
        match path.file_name().and_then(|n| n.to_str()) {
            Some("backup_settings.conf") => migrate(&before, true)?,
            Some("restore_settings.conf") => migrate(&before, false)?,
            _ => return Ok(()),
        }
    };
    publish(path, &before, &output)
}
