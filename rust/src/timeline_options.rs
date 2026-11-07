use super::*;
fn root()->io::Result<PathBuf>{
 let root=PathBuf::from(std::env::var_os("SPEEDBACKUP_SELECTION_REPORT").ok_or_else(||err("timeline selection unavailable"))?);
 let m=fs::symlink_metadata(&root)?;
 if !root.is_absolute()||root.canonicalize()?!=root||!m.is_dir()||m.uid()!=0||m.mode()&0o777!=0o700{return Err(err("timeline selection identity"));}Ok(root)
}
pub(super) fn catalog()->io::Result<String>{
 let root=root()?;
 if root.join("timeline-error").exists(){return Err(err(&read(&root.join("timeline-error"))?.0));}
 if !root.join("timeline.json").exists(){return Ok("{\"sources\":[],\"targets\":[]}".into());}
 read(&root.join("timeline.json")).map(|v|v.0)
}
fn ids(name:&str)->io::Result<BTreeSet<String>>{
 Ok(read(&root()?.join(name))?.0.lines().filter_map(|l|l.split_once('\t').map(|v|v.0.to_string())).collect())
}
pub(super) fn save(session:&Session,body:&str)->io::Result<()> {
 let mut app_lines=Vec::new();let mut choice=None;
 for line in body.lines(){if let Some(value)=line.strip_prefix("@timeline\t"){if choice.replace(value).is_some(){return Err(err("duplicate timeline options"));}}else{app_lines.push(line);}}
 let app_body=app_lines.join("\n");
 let Some(choice)=choice else{return selection_flow::save_confirmed(session,&app_body);};
 if !matches!(selection_flow::flow().as_str(),"restore"|"remote"){return Err(err("timeline options outside restore"));}
 let fields=choice.split('\t').collect::<Vec<_>>();
 if fields.len()!=3||!matches!(fields[0],"match"|"account"|"cross"|"merge"){return Err(err("timeline restore mode"));}
 let packages=icon_packages(session,false).0;
 let maps=session.rows.iter().find(|r|packages.get(&r.pkg).map(String::as_str).unwrap_or(&r.pkg)=="com.google.android.apps.maps");
 let selected=maps.is_some_and(|r|app_lines.iter().any(|l|{let f=l.split('\t').collect::<Vec<_>>();f.len()==3&&f[0]==r.pkg&&f[1]=="1"&&f[2]=="0"}));
 if !selected{return selection_flow::save_confirmed(session,&app_body);}
 let mode=fields[0];let target=fields[1];let sources=fields[2];
 if mode=="match" {if !target.is_empty()||!sources.is_empty(){return Err(err("timeline default options"));}}
 else {
   if !ids("timeline-targets")?.contains(target){return Err(err("目的 Google 帳號已變更，請重新開啟選單"));}
   if mode=="account"{if !sources.is_empty(){return Err(err("timeline same-account sources"));}}
   else {let available=ids("timeline-sources")?;let rows=sources.split(',').collect::<Vec<_>>();let unique=rows.iter().copied().collect::<BTreeSet<_>>();if rows.is_empty()||rows.len()>32||rows.len()!=unique.len()||(mode=="cross"&&rows.len()!=1)||rows.iter().any(|s|!available.contains(*s)){return Err(err("請選擇有效的時間軸來源帳號"));}}
 }
 let path=root()?.join("timeline-choice");
 let mut file=OpenOptions::new().write(true).create_new(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(&path)?;
 let result=(||{file.write_all(choice.as_bytes())?;file.write_all(b"\n")?;file.write_all(read(&root()?.join("timeline-context"))?.0.as_bytes())?;file.sync_all()?;selection_flow::save_confirmed(session,&app_body)})();
 if result.is_err(){let _=fs::remove_file(path);}result
}
