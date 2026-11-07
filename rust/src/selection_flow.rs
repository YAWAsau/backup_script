//! Selection preparation is read-only except for guarded list reconciliation.
//! Only the explicit save endpoint returns the execution receipt (20).
use super::*;

pub(super) fn flow() -> String {
    std::env::var("SPEEDBACKUP_SELECTION_FLOW").ok().filter(|v| matches!(v.as_str(),"backup"|"restore"|"remote"|"media")).unwrap_or_default()
}

fn parse_rows(text:&str,kind:&str)->io::Result<Vec<Row>>{if kind=="apps"{rows(text)}else{selection_rows(text,kind)}}

fn merge(old:&str,fresh:&str,kind:&str)->io::Result<String> {
    let previous=parse_rows(old,kind)?;
    let current=parse_rows(fresh,kind)?;
    let key=|r:&Row| if kind=="apps"{r.pkg.clone()}else{r.label.clone()};
    let live:BTreeMap<_,_>=current.iter().map(|r|(key(r),r)).collect();
    let prior:BTreeSet<_>=previous.iter().map(&key).collect();
    let indexed:BTreeMap<_,_>=previous.iter().map(|r|(r.line,r)).collect();
    let mut output=String::new();
    // Retain exact surviving rows, disabled markers, inline notes and prose.
    for (i,line) in old.split_inclusive('\n').enumerate() {
        match indexed.get(&i) {
            None=>output.push_str(line),
            Some(old)=>if let Some(new)=live.get(&key(old)) {
                if kind=="apps"&&old.label!=new.label {output.push_str(&line.replacen(&old.label,&new.label,1));}
                else {output.push_str(line);}
            }
        }
    }
    if !output.is_empty()&&!output.ends_with('\n'){output.push('\n');}
    let lines:Vec<_>=fresh.split_inclusive('\n').collect();
    for row in &current {if !prior.contains(&key(row)){output.push_str(lines[row.line]);if !output.ends_with('\n'){output.push('\n');}}}
    parse_rows(&output,kind)?;
    Ok(output)
}

pub(super) fn sync(args:&[String])->io::Result<()> {
    if args.len()!=4 || !matches!(args[3].as_str(),"remote"|"media"|"apps"){return Err(err("sync LIST FRESH KIND"));}
    let target=Path::new(&args[1]);let fresh=read(Path::new(&args[2]))?.0;
    if !target.is_absolute(){return Err(err("absolute list required"));}
    let _lock=editor_lock()?;
    match Session::new_kind(target,Some(&args[3])) {
        Ok(state)=>state.save_text(&merge(&state.original,&fresh,&args[3])?),
        Err(e) if e.kind()==io::ErrorKind::NotFound=>{
            parse_rows(&fresh,&args[3])?;
            super::super::publish_file::publish_bytes_guarded(fresh.as_bytes(),target,Some(0o644),super::super::publish_file::auto_preserve(target)?,&mut ||{
                match fs::symlink_metadata(target){Err(e) if e.kind()==io::ErrorKind::NotFound=>Ok(()),_=>Err(err("list appeared during synchronization"))}
            }).map(|_|())
        },
        Err(e)=>Err(e)
    }
}

// Project the explicit remote receipt onto downloaded local lists. Old payloads
// may coexist in the destination; they must never become implicit selections.
pub(super) fn project(args:&[String])->io::Result<()> {
    if args.len()!=3{return Err(err("project REMOTE_LIST LOCAL_ROOT"));}
    let _lock=editor_lock()?;
    let remote=Session::new_kind(Path::new(&args[1]),Some("remote"))?;
    let selected:BTreeSet<_>=remote.rows.iter().filter(|r|r.enabled).map(|r|r.label.as_str()).collect();
    let media_all=selected.contains("Media")&&!selected.iter().any(|n|n.ends_with(".tar")||n.ends_with(".tar.zst"));
    // The new remote catalog always lists exact media payloads. A legacy all marker
    // cannot prove which files in an existing download directory came from this run.
    if media_all{return Err(err("請重新同步遠端清單並選擇具體媒體項目"));}
    let root=Path::new(&args[2]);
    if !root.is_absolute()||!fs::symlink_metadata(root)?.is_dir(){return Err(err("download destination"));}
    let mut plans=Vec::new();
    for (name,kind) in [("appList.txt","apps"),("mediaList.txt","media")] {
        let path=root.join(name);
        if !path.exists(){continue;}
        let state=Session::new_kind(&path,Some(kind))?;
        let body=state.rows.iter().map(|r|format!("{}\t{}\t{}",r.pkg,usize::from(selected.contains(r.label.as_str())||(kind=="media"&&media_all)),usize::from(kind=="apps"&&r.data_only))).collect::<Vec<_>>().join("\n");
        let output=edit(&state.original,&state.rows,&body,state.selection_kind.as_deref())?;
        plans.push((state,output));
    }
    // Validate every selected app against the downloaded list before writing.
    let available:BTreeSet<_>=plans.iter().flat_map(|(s,_)|s.rows.iter().map(|r|r.label.as_str())).collect();
    for name in &selected {
        if !matches!(*name,"wifi"|"Media"|"@telephony:messages"|"@telephony:calls")&&!available.contains(name){return Err(err("selected download missing from local lists"));}
    }
    if selected.contains("Media")&&!plans.iter().any(|(s,_)|s.selection_kind.as_deref()==Some("media")&&!s.rows.is_empty()){return Err(err("selected Media has no downloaded items"));}
    remote.unchanged()?;
    for (state,_) in &plans{state.unchanged()?;}
    for (state,output) in plans{state.save_text(&output)?;}
    Ok(())
}

pub(super) fn emit_selected(path:&Path)->io::Result<()> {
    let _lock=editor_lock()?;
    let state=Session::new_kind(path,Some("remote"))?;
    let selected:Vec<_>=state.rows.iter().filter(|r|r.enabled).map(|r|r.label.as_str()).collect();
    if selected.is_empty(){return Err(err("empty selection"));}
    state.unchanged()?;
    for name in selected{println!("{name}");}
    Ok(())
}

// Receipt comes from the exact edited snapshot, never a reread after HTTP save.
pub(super) fn save_confirmed(session:&Session,body:&str)->io::Result<()> {
    if flow().is_empty(){return session.save(body);}
    if session.selection&&body.lines().any(|l|l.split('\t').nth(2)!=Some("0")){return Err(err("selection APK mode"));}
    let output=edit(&session.original,&session.rows,body,session.selection_kind.as_deref())?;
    let selected=if let Some(k)=session.selection_kind.as_deref(){selection_rows(&output,k)?}else{rows(&output)?};
    if !selected.iter().any(|r|r.enabled){return Err(err("請至少選擇一個項目"));}
    let root=PathBuf::from(std::env::var_os("SPEEDBACKUP_SELECTION_REPORT").ok_or_else(||err("selection report missing"))?);
    let meta=fs::symlink_metadata(&root)?;
    if !root.is_absolute()||!meta.is_dir()||meta.uid()!=0||meta.mode()&0o777!=0o700||root.canonicalize()?!=root{return Err(err("selection report identity"));}
    let receipt=if session.selection_kind.as_deref()==Some("remote"){selected.iter().filter(|r|r.enabled).map(|r|format!("{}\n",r.label)).collect::<String>()}else{output.clone()};
    let target=root.join("approved");
    let mut file=OpenOptions::new().write(true).create_new(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(&target)?;
    let result=(||{file.write_all(receipt.as_bytes())?;file.sync_all()?;session.save_text(&output)})();
    if result.is_err(){let _=fs::remove_file(&target);}result
}

pub(super) fn list_data(session:Option<&Session>,kind:Option<&str>)->io::Result<String> {
    let current=session.map(|s|s.rows.as_slice()).unwrap_or(&[]);
    // Metadata is display-only: retain the synthetic selection IDs used by save/draft.
    let packages=session.map(|s|icon_packages(s,false).0).unwrap_or_default();
    let display_package=|r:&Row| packages.get(&r.pkg).cloned().unwrap_or_else(||if kind.is_none()&&package(&r.pkg){r.pkg.clone()}else{String::new()});
    let Some(root)=std::env::var_os("SPEEDBACKUP_SELECTION_REPORT") else{
        return Ok(format!("[{}]",current.iter().map(|r|format!("{{\"pkg\":{},\"label\":{},\"selected\":{},\"apk\":{},\"displayPackage\":{}}}",json(&r.pkg),json(&r.label),r.enabled,r.data_only,json(&display_package(r)))).collect::<Vec<_>>().join(",")));
    };
    let root=PathBuf::from(root);
    if !root.is_absolute()||root.canonicalize()?!=root{return Err(err("selection report path"));}
    let meta=fs::symlink_metadata(&root)?;
    if !meta.is_dir()||meta.uid()!=0||meta.mode()&0o777!=0o700{return Err(err("selection report identity"));}
    let old=read(&root.join("old"))?.0;
    let previous=if let Some(k)=kind {selection_rows(&old,k)?} else {rows(&old)?};
    let key=|r:&Row| if kind.is_some(){r.label.clone()}else{r.pkg.clone()};
    let prior:BTreeSet<_>=previous.iter().map(&key).collect();
    let live:BTreeSet<_>=current.iter().map(&key).collect();
    let mut xposed=BTreeSet::new();
    if let Ok((inventory,_))=read(&root.join("inventory")) {
        for line in inventory.lines(){let f:Vec<_>=line.split_whitespace().collect();if f.len()==3&&package(f[1])&&f[2].split('|').any(|v|v=="xposed"){xposed.insert(f[1].to_owned());}}
    }
    let by_label:BTreeMap<_,_>=current.iter().map(|r|(r.label.as_str(),r.pkg.as_str())).collect();
    let mut modules=BTreeSet::new();
    if let Some(session)=session {
        for row in current {if packages.get(&row.pkg).is_some_and(|p|xposed.contains(p)){modules.insert(row.pkg.clone());}}
        if session.selection {
            if let Ok(path)=icon_map_path(&session.path){if let Ok((text,_))=read(&path){for line in text.lines(){let f=line.split('\t').collect::<Vec<_>>();if f.len()==4&&f[3]=="1"{if let Some(pkg)=by_label.get(f[0]){modules.insert((*pkg).to_owned());}}}}}
        }else if flow()=="restore" {
            for row in current {if row.label.contains(['/', '\\'])||matches!(row.label.as_str(),"."|".."){continue;}let path=session.parent.join(&row.label).join("app_details.json");
                if let Ok((body,_))=read(&path){if super::super::profile::module_metadata(&body,&row.pkg){modules.insert(row.pkg.clone());}}
            }
        }
    }
    let mut output=Vec::new();
    for r in current {
        let mut badge=Vec::new();if xposed.contains(&r.pkg)||modules.contains(&r.pkg){badge.push("Xposed");}if !prior.contains(&key(r)){badge.push(if kind.is_some(){"新增項目"}else{"新增應用"});}
        output.push(format!("{{\"pkg\":{},\"label\":{},\"selected\":{},\"apk\":{},\"badge\":{},\"removed\":false,\"displayPackage\":{}}}",json(&r.pkg),json(&r.label),r.enabled,r.data_only,json(&badge.join(" · ")),json(&display_package(r))));
    }
    for r in previous.iter().filter(|r|!live.contains(&key(r))) {
        output.push(format!("{{\"pkg\":{},\"label\":{},\"selected\":false,\"apk\":false,\"badge\":{},\"removed\":true,\"displayPackage\":{}}}",json(&format!("removed:{}",r.pkg)),json(&r.label),json(if kind.is_some(){"遠端已不存在 · 已移除列表"}else{"無此應用 · 已刪除列表"}),json(if kind.is_none()&&package(&r.pkg){&r.pkg}else{""})));
    }
    Ok(format!("[{}]",output.join(",")))
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn remote_sync_preserves_exact_choices_and_notes(){
        let old="# personal note\n#App A # keep disabled\nApp B # keep selected\n#Gone\n";
        let fresh="# server header\nApp A\nApp B\nNew\n";
        assert_eq!(merge(old,fresh,"remote").unwrap(),"# personal note\n#App A # keep disabled\nApp B # keep selected\nNew\n");
    }
    #[test] fn app_identity_survives_rename_without_reusing_another_package(){
        assert_eq!(merge("!Old org.test.same\n#Reuse org.test.gone\n","New org.test.same\nReuse org.test.new\n","apps").unwrap(),"!New org.test.same\nReuse org.test.new\n");
    }
    #[test] fn invalid_refresh_never_produces_output(){assert!(merge("App\n","../escape\n","remote").is_err());}
}

pub(super) fn timeline_metadata(args:&[String])->io::Result<()> {
    if args.len()!=3{return Err(err("timeline metadata arguments"));}
    let remote=args[2]=="remote";
    let kind=Some(if remote{"remote"}else{"apps"});
    let state=Session::new_kind(Path::new(&args[1]),kind)?;
    let packages=icon_packages(&state,false).0;
    for row in &state.rows {
        if packages.get(&row.pkg).map(String::as_str).unwrap_or(&row.pkg)!="com.google.android.apps.maps"{continue;}
        if row.label.contains(['/', '\\','\t','\n','\r'])||matches!(row.label.as_str(),"."|".."){return Err(err("Maps backup name"));}
        let root=if remote{PathBuf::from(std::env::var_os("TMPDIR").ok_or_else(||err("TMPDIR"))?).join(".stream_appdetails_bundle")}else{state.parent.clone()};
        let path=root.join(&row.label).join("app_details.json");
        println!("{}\t{}",row.label,path.display());return Ok(());
    }
    Ok(())
}
