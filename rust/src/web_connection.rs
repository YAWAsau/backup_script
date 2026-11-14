//! Connection-only commits preserve unrelated settings and reject concurrent edits.
use super::*;
pub(super) fn save(path:&Path,body:&str)->io::Result<()> {
    let request:serde_json::Value=serde_json::from_str(body)?;
    let text=|key:&str|request[key].as_str().unwrap_or("");
    let protocol=text("protocol");
    if !matches!(protocol,"smb"|"webdav"){return Err(err("連線類型無效"));}
    let state=Session::new(path,false)?;
    if text("revision")!=super::super::sha256_reader_hex(state.original.as_bytes())? {return Err(err("設定已變更，請重新開啟連線設定"));}
    let mut fields:serde_json::Value=serde_json::from_str(&super::super::web_settings::data(&state.original)?)?;
    let identity=text("identity");
    let auto=if protocol=="smb" {identity.strip_prefix("smb:").is_some_and(|s|s.len()==32&&s.bytes().all(|b|b.is_ascii_hexdigit()))} else {super::lan_discovery::valid_webdav_identity(identity,text("url"))};
    for field in fields.as_array_mut().ok_or_else(||err("設定格式無效"))? {
        let key=field["key"].as_str().unwrap_or("");
        let value=if key=="remote_type"{Some(protocol)}else if key=="remote_address_mode"{Some(if auto{"auto"}else{"manual"})}
            else if key==format!("{protocol}_url"){Some(text("url"))}
            else if key==format!("{protocol}_remote_user"){Some(text("user"))}
            else if key==format!("{protocol}_remote_pass"){Some(text("password"))}
            else if key==format!("remote_{protocol}_identity"){Some(identity)}else{None};
        if let Some(value)=value{field["value"]=serde_json::json!(value);}
    }
    let body=fields.as_array().unwrap().iter().map(|f|format!("{}\t{}",f["key"].as_str().unwrap(),f["value"].as_str().unwrap().as_bytes().iter().map(|b|format!("{b:02x}")).collect::<String>())).collect::<Vec<_>>().join("\n");
    let output=super::super::web_settings::edit(&state.original,&body)?;
    state.save_text(&output)
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn connection_commit_preserves_other_fields_and_rejects_stale_revision(){
        let dir=PathBuf::from(format!("/data/local/tmp/sb-connection-{}",random_hex().unwrap()));fs::create_dir(&dir).unwrap();
        let path=dir.join("backup_settings.conf");
        let original="remote_type=webdav\nremote_address_mode=auto\nwebdav_url=''\nwebdav_remote_user=''\nwebdav_remote_pass=''\nuser=0\n# preserved\n";
        fs::write(&path,original).unwrap();
        let revision=super::super::super::sha256_reader_hex(original.as_bytes()).unwrap();
        let body=serde_json::json!({"protocol":"webdav","url":"http://192.168.1.2:8080/dav/","identity":"","user":"fixture","password":"testpass","revision":revision}).to_string();
        save(&path,&body).unwrap();
        let saved=fs::read_to_string(&path).unwrap();assert!(saved.contains("# preserved")&&saved.contains("user=0"));
        let values=super::super::super::web_settings::parse_runtime(&saved).unwrap();
        assert!(values.iter().any(|f|f.key=="remote_address_mode"&&f.value=="manual"));
        assert!(values.iter().any(|f|f.key=="webdav_remote_pass"&&f.value=="testpass"));
        assert!(save(&path,&body).is_err());assert_eq!(fs::read_to_string(&path).unwrap(),saved);
        fs::remove_dir_all(&dir).unwrap();
    }
}
