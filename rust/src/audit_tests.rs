use super::*;

#[test]
fn package_string_reads_app_level_and_decodes_escapes() {
    assert_eq!(json_string_value(r#"{"nested":{"PackageName":"wrong"},"PackageName":"com.example.\u0061"}"#, &["PackageName"]), Some("com.example.a".into()));
    assert_eq!(json_string_value(r#"{"App":{"nested":{"PackageName":"wrong"}}}"#, &["PackageName"]), None);
    assert_eq!(json_string_value(r#"{"App":{"PackageName":"p"}}"#, &["PackageName"]), Some("p".into()));
    assert_eq!(json_string_value(r#"{"PackageName":"first","PackageName":"last"}"#, &["PackageName"]), Some("last".into()));
}

#[test]
fn unicode_strings_and_direct_numeric_version() {
    assert_eq!(
        json_unquote_simple(r#""中文\ud83d\ude00""#).as_deref(),
        Some("中文😀")
    );
    assert!(json_unquote_simple(r#""\ud83d""#).is_none());
    let values = json_top_object_values(
        r#"{"App":{"apk_version":4294967297,"nested":{"versionCode":"1"}}}"#,
    );
    assert_eq!(health_first_apk_version(&values), "4294967297");
}

#[test]
fn folder_names_share_one_policy() {
    for (name, expected) in [
        ("WiFi", "app_WiFi"),
        ("tools", "app_tools"),
        ("C#編輯器", "C_編輯器"),
        ("a/b..c", "a_b__c"),
        ("😀", "😀"),
    ] {
        assert_eq!(safe_name_for_backup(name, "com.example"), expected);
        assert_eq!(sanitize_app_folder_name(name, "com.example"), expected);
    }
    assert!(parse_app_line("😀 com.example").is_some());
    assert!(parse_app_line("＃comment com.example").is_none());
}

#[test]
fn sha256_block_and_read_boundaries() {
    let path = env::temp_dir().join(format!("audit-sha-{}", std::process::id()));
    for (data, expected) in [
        (
            Vec::new(),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ),
        (
            b"abc".to_vec(),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        ),
        (
            vec![b'a'; 1_000_000],
            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
        ),
    ] {
        fs::write(&path, data).unwrap();
        assert_eq!(sha256_file_hex(&path).unwrap(), expected);
    }
    fs::remove_file(path).unwrap();
}
#[test]
fn timeline_sidecar_is_an_app_payload_not_a_media_tar() {
    assert!(super::appdetails_is_payload_tail(
        "timeline_01234567-89ab-cdef-0123-456789abcdef.sbtimeline"
    ));
    assert!(!super::appdetails_is_payload_tail(
        "timeline_../../escape.sbtimeline"
    ));
    assert!(!super::appdetails_is_payload_tail(
        "timeline_------------------------------------.sbtimeline"
    ));
}
