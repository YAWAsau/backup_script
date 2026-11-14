//! Read-only resolution of a user-selected discovery result. Credentials are never
//! broadcast to discovered hosts; only this selected endpoint receives them.
use std::io;
use serde_json::{json,Value};

use super::super::super::remote_probe::{Scratch,execute,webdav_code,smb_command,smb_failed};
use super::super::super::command_lifecycle::CancelEvent;
fn shares(text:&str)->Vec<String>{
    let mut rows=std::collections::BTreeSet::new();
    for line in text.lines(){
        let mut fields=line.split('|');
        if fields.next()!=Some("Disk"){continue;}
        if let Some(name)=fields.next().filter(|s|!s.is_empty()&&s.len()<=255&&!s.ends_with('$')&&!s.chars().any(|c|c.is_control()||matches!(c,'/'|'\\'|'%'|'"'|'\''|';'|'!'|'`'|'|'))){rows.insert(name.to_owned());}
    }
    rows.into_iter().take(128).collect()
}
pub fn resolve(body:&str,cancel:Option<&CancelEvent>)->io::Result<Value>{
    if body.len()>16384{return Err(io::Error::other("地址資料過長"));}
    let request:Value=serde_json::from_str(body).map_err(|_|io::Error::other("地址資料無效"))?;
    let get=|key:&str|request[key].as_str().unwrap_or("");
    let protocol=get("protocol");let url=get("url");let user=get("user");let pass=get("password");
    let (host,port)=super::super::super::remote_control::endpoint(protocol,url)?;
    let ip:std::net::IpAddr=host.parse().map_err(|_|io::Error::other("搜尋地址必須是 IP"))?;
    if ip.is_unspecified()||ip.is_loopback()||ip.is_multicast()||url.contains(['?','#','\\']){return Err(io::Error::other("搜尋地址無效"));}
    if [user,pass].iter().any(|s|s.len()>4096||s.chars().any(char::is_control)){return Err(io::Error::other("帳密含不支援的控制字元"));}
    let scratch=Scratch::new()?;
    let exe=std::env::current_exe()?;let tools=exe.parent().ok_or_else(||io::Error::other("工具位置無效"))?;
    if protocol=="webdav" {
        return match webdav_code(tools,&scratch,body,cancel)? {
            207=>Ok(json!({"verified":true,"urls":[url]})),
            401=>Ok(json!({"verified":false,"reason":"auth_failed","error":if user.is_empty(){"WebDAV 未設定帳號或需要認證"}else{"WebDAV 帳號或密碼錯誤"}})),
            403=>Err(io::Error::other("WebDAV 拒絕存取，請檢查權限")),
            404=>Err(io::Error::other("WebDAV 公告路徑不存在，請手動設定完整路徑")),
            405|501=>Err(io::Error::other("此地址不支援 WebDAV 目錄存取")),
            _=>Err(io::Error::other("WebDAV 無法確認目錄，請檢查網路、憑證與服務路徑")),
        };
    }
    let (_,_,path)=super::authority(url)?;
    let path=path.trim_end_matches('/');
    // Samba receives a UNC argument, never a command constructed from a URL.
    // Discovery offers share roots only; an existing nested path stays editable.
    if path.contains('/')||path.contains('%')||path.chars().any(|c|matches!(c,'"'|'\''|';'|'!'|'`'|'|')){return Err(io::Error::other("請選擇共用根目錄；子目錄可於設定頁保留或修改"));}
    let cmd=smb_command(tools,&scratch,&host,port,user,pass,path)?;
    let (ok,output)=execute(cmd,&scratch,None,cancel)?;
    if smb_failed(ok,&output){
        let class=super::super::super::remote_control::smb_class(&output);
        if class.0=="1" {return Ok(json!({"verified":false,"reason":"auth_failed","error":class.1}));}
        return Err(io::Error::other(class.1));
    }
    if !path.is_empty(){return Ok(json!({"verified":true,"urls":[url]}));}
    let urls=shares(&output).into_iter().map(|name|format!("{}{name}",if url.ends_with('/'){url.to_owned()}else{format!("{url}/")})).collect::<Vec<_>>();
    if urls.is_empty(){return Err(io::Error::other("SMB 未提供可列出的共用資料夾；請確認分享及帳號權限，或手動填寫共用名稱"));}
    Ok(json!({"verified":false,"urls":urls}))
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn share_rows_only(){assert_eq!(shares("Disk|Backup|x\nIPC|IPC$|x\nDisk|C$|x\nDisk|Backup|duplicate\nDisk|bad/name|x\nDisk|照片 備份|x"),vec!["Backup","照片 備份"]);}
}
