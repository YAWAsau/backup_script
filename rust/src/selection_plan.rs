//! Batch-only selection transforms. All parsers are shared with the editor.
use super::*;
fn input(path:&str)->io::Result<(PathBuf,String,Metadata)>{let p=PathBuf::from(path);if !p.is_absolute(){return Err(err("absolute input required"));}let(t,m)=read(&p)?;Ok((p,t,m))}
fn unchanged(items:&[(PathBuf,String,Metadata)])->io::Result<()> {for(p,t,m)in items{let(now,n)=read(p)?;if now!=*t||stamp(&n)!=stamp(m){return Err(err("selection inputs changed"));}}Ok(())}
fn publish(path:&str,text:&str,inputs:&[(PathBuf,String,Metadata)])->io::Result<()> {
 let p=Path::new(path);if !p.is_absolute(){return Err(err("absolute output required"));}
 super::super::publish_file::publish_bytes_guarded(text.as_bytes(),p,Some(0o600),false,&mut||unchanged(inputs)).map(|_|())
}
fn selected_details(list:&str,index:&str)->io::Result<String>{
 let selected:BTreeSet<_>=rows(list)?.into_iter().filter(|r|r.enabled).map(|r|r.label).collect();
 let mut out=String::new();
 for line in index.lines(){
  if line.is_empty(){continue;}if line.chars().any(char::is_control){return Err(err("metadata path control"));}
  let p=Path::new(line);if !p.is_absolute()||p.file_name().and_then(|x|x.to_str())!=Some("app_details.json"){return Err(err("metadata index path"));}
  if p.parent().and_then(Path::file_name).and_then(|x|x.to_str()).is_some_and(|n|selected.contains(n)){out.push_str(line);out.push('\n');}
 }
 if out.is_empty(){return Err(err("selected applications have no SSAID metadata"));}Ok(out)
}
fn selected_ssaid_rows(list:&str,generated:&str)->io::Result<String>{
 let current=rows(list)?;let selected:BTreeMap<_,_>=current.iter().filter(|r|r.enabled).map(|r|(r.pkg.as_str(),r)).collect();
 let lines:Vec<_>=list.split_inclusive('\n').collect();let mut out=String::new();
 for row in rows(generated)? {if let Some(old)=selected.get(row.pkg.as_str()) {if old.label!=row.label{return Err(err("SSAID selected identity mismatch"));}out.push_str(lines[old.line]);if !out.ends_with('\n'){out.push('\n');}}}
 Ok(out)
}
fn payload(name:&str)->bool {
 let exact=selection_rows(&format!("{name}\n"),"media").is_ok_and(|r|r.len()==1&&r[0].enabled&&r[0].label==name);
 exact&&!name.is_empty()&&!name.contains(['/', '\\'])&&!name.chars().any(char::is_control)
 &&(name.ends_with(".tar")||name.ends_with(".tar.zst"))
}
fn media_plan(keys:&str,remote:&str,selected:Option<&str>)->io::Result<String>{
 let keys:BTreeSet<_>=keys.lines().filter(|l|!l.is_empty()).collect();
 let selected=selected.map(|s|selection_rows(s,"remote")).transpose()?;
 let wanted:BTreeSet<_>=selected.as_ref().into_iter().flatten().filter(|r|r.enabled).map(|r|r.label.as_str()).collect();
 let all=selected.is_none()||(wanted.contains("Media")&&!wanted.iter().any(|s|payload(s)));let mut result=BTreeSet::new();
 for raw in remote.lines(){let name=raw.trim_end_matches('\r');if !payload(name){continue;}
  let stem=name.strip_suffix(".tar.zst").or_else(||name.strip_suffix(".tar")).unwrap();
  if keys.contains(stem)&&(all||wanted.contains(name)){result.insert(name);}
 }
 Ok(result.into_iter().map(|s|format!("{s}\n")).collect())
}
fn remote_catalog(listing:&str,fallback:Option<&str>,media:&str)->io::Result<String>{
 let payload_apps:BTreeSet<_>=fallback.into_iter().flat_map(str::lines).filter_map(|l|l.split_once('/')).filter(|(_,p)|matches!(p.trim_end_matches(".zst"),"apk.tar"|"data.tar"|"user.tar"|"user_de.tar"|"obb.tar"|"hma.tar"|"thanox.tar")).map(|(a,_)|a).collect();
 let mut apps=BTreeSet::new();let mut wifi=false;let mut comm=false;
 for line in listing.lines(){if line.is_empty(){continue;}let (kind,name)=line.split_once(char::is_whitespace).ok_or_else(||err("remote listing row"))?;
  if !matches!(kind,"D"|"N"){return Err(err("remote listing type"));}if kind!="D"{continue;}
  match name {"tools"|"Media"=>continue,"wifi"=>{wifi=true;continue;},"communications"=>{comm=true;continue;},_=>{}}
  if fallback.is_none()||payload_apps.contains(name){let parsed=selection_rows(&format!("{name}\n"),"remote")?;if parsed.len()!=1||!parsed[0].enabled||parsed[0].label!=name{return Err(err("remote name cannot round-trip"));}apps.insert(name);}
 }
 let mut out=String::from("# 遠端備份選擇清單；勾選與註釋會保留\n");for name in apps{out.push_str(name);out.push('\n');}
 for row in selection_rows(media,"media")? {if row.enabled {out.push_str(&row.label);out.push('\n');}}
 if wifi{out.push_str("wifi\n");}if comm{out.push_str("#@telephony:messages # 簡訊與 MMS\n#@telephony:calls # 通話紀錄\n");}
 selection_rows(&out,"remote")?;Ok(out)
}
pub(super) fn command(args:&[String])->Option<io::Result<()>> {
 let action=args.first()?.as_str();if !matches!(action,"--ssaid-filter"|"--ssaid-rows"|"--items"|"--media-plan"|"--media-candidates"|"--remote-catalog"|"--selected-media"|"--has-media-all"|"--module-map"){return None;}
 Some((||{
  let _lock=editor_lock()?;
  match action {
   "--ssaid-filter"|"--ssaid-rows" if args.len()==4=>{
    let inputs=vec![input(&args[1])?,input(&args[2])?];
    let out=if action=="--ssaid-filter"{selected_details(&inputs[0].1,&inputs[1].1)?}else{selected_ssaid_rows(&inputs[0].1,&inputs[1].1)?};publish(&args[3],&out,&inputs)
   },
   "--items" if args.len()==2=>{let src=input(&args[1])?;let selected=selection_rows(&src.1,"remote")?;unchanged(std::slice::from_ref(&src))?;for row in selected.into_iter().filter(|r|r.enabled){println!("{}",row.label);}Ok(())},
   "--module-map" if args.len()==3=>{
    let src=input(&args[1])?;let dir=Path::new(&args[2]);let m=fs::symlink_metadata(dir)?;
    if !dir.is_absolute()||!m.is_dir()||m.uid()!=0||m.mode()&0o777!=0o700{return Err(err("module cache directory"));}
    let mut facts=BTreeMap::new();
    for line in src.1.lines(){let f=line.split_whitespace().collect::<Vec<_>>();if f.len()==3&&package(f[1]){let value=f[2].split('|').any(|s|s=="xposed");if facts.insert(f[1],value).is_some_and(|old|old!=value){return Err(err("conflicting module facts"));}}}
    for (pkg,value) in facts {let mut out=OpenOptions::new().create_new(true).write(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(dir.join(pkg))?;out.write_all(if value{b"1"}else{b"0"})?;}
    unchanged(std::slice::from_ref(&src))?;
    let mut marker=OpenOptions::new().create_new(true).write(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(dir.join("READY"))?;marker.write_all(b"1")?;marker.sync_all()

   },
   "--has-media-all" if args.len()==2=>{let src=input(&args[1])?;let rows=selection_rows(&src.1,"remote")?;if rows.iter().any(|r|r.enabled&&r.label=="Media")&&!rows.iter().any(|r|r.enabled&&payload(&r.label)){Ok(())}else{Err(err("no Media marker"))}},
   "--selected-media" if args.len()==3=>{let src=input(&args[1])?;let out=selection_rows(&src.1,"remote")?.into_iter().filter(|r|r.enabled&&payload(&r.label)).map(|r|r.label).collect::<BTreeSet<_>>().into_iter().map(|s|format!("{s}\n")).collect::<String>();publish(&args[2],&out,std::slice::from_ref(&src))},
   "--media-candidates" if args.len()==3=>{let src=input(&args[1])?;let out=src.1.lines().filter(|l|payload(l)).collect::<BTreeSet<_>>().into_iter().map(|l|format!("{l}\n")).collect::<String>();publish(&args[2],&out,std::slice::from_ref(&src))},
   "--remote-catalog" if args.len()==5=>{let mut inputs=vec![input(&args[1])?,input(&args[3])?];if args[2]!="-"{inputs.push(input(&args[2])?);}let out=remote_catalog(&inputs[0].1,inputs.get(2).map(|x|x.1.as_str()),&inputs[1].1)?;publish(&args[4],&out,&inputs)},
   "--media-plan" if args.len()==5=>{let mut inputs=vec![input(&args[1])?,input(&args[2])?];if args[3]!="-"{inputs.push(input(&args[3])?);}let out=media_plan(&inputs[0].1,&inputs[1].1,inputs.get(2).map(|i|i.1.as_str()))?;publish(&args[4],&out,&inputs)},
   _=>Err(err("selection plan arguments"))
  }
 })())
}
#[cfg(test)]mod tests{
 use super::*;
 #[test]fn ssaid_respects_both_apk_markers_and_disabled(){let list="!A org.test.a\n！Ｂ org.test.b\n#C org.test.c\n";let index="/tmp/A/app_details.json\n/tmp/Ｂ/app_details.json\n/tmp/C/app_details.json\n";assert_eq!(selected_details(list,index).unwrap(),"/tmp/A/app_details.json\n/tmp/Ｂ/app_details.json\n");assert_eq!(selected_ssaid_rows(list,"A org.test.a\nＢ org.test.b\nC org.test.c\n").unwrap(),list.lines().take(2).map(|l|format!("{l}\n")).collect::<String>());}
 #[test]fn media_unicode_notes_and_exact_payloads(){assert_eq!(media_plan("相片\nＡ\nmissing\n","相片.tar.zst\nＡ.tar\napk.tar\nsub/相片.tar\nmissing.json\n",Some("#相片.tar.zst # disabled\nＡ.tar # selected\n")).unwrap(),"Ａ.tar\n");}
 #[test]fn remote_names_must_roundtrip(){assert!(remote_catalog("D  Leading\n",None,"").is_err());assert!(remote_catalog("D Trailing \n",None,"").is_err());assert!(remote_catalog("D #Disabled\n",None,"").is_err());assert!(remote_catalog("D App # comment\n",None,"").is_err());assert!(!payload("#Photos.tar"));assert!(!payload("Photos # personal.tar"));}
 #[test]fn malformed_selection_fails(){assert!(media_plan("A\n","A.tar\n",Some("../A.tar\n")).is_err());}
 #[test]fn media_namespace_allows_app_like_names(){assert_eq!(media_plan("data\napk\n","data.tar\napk.tar.zst\nuser.tar\n",Some("data.tar\n#apk.tar.zst\n")).unwrap(),"data.tar\n");}
}
