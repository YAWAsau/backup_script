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
    fn key_of<'a>(r:&'a Row,kind:&str)->&'a str {if kind=="apps"{&r.pkg}else{&r.label}}
    let key=|r|key_of(r,kind);
    let live:BTreeMap<_,_>=current.iter().map(|r|(key(r),r)).collect();
    let prior:BTreeSet<_>=previous.iter().map(&key).collect();
    let indexed:BTreeMap<_,_>=previous.iter().map(|r|(r.line,r)).collect();
    let mut output=String::new();
    // Retain exact surviving rows, disabled markers, inline notes and prose.
    for (i,line) in old.split_inclusive('\n').enumerate() {
        match indexed.get(&i) {
            None=>output.push_str(line),
            Some(old)=>if let Some(new)=live.get(key(old)) {
                if kind=="apps"&&old.label!=new.label {output.push_str(&line.replacen(&old.label,&new.label,1));}
                else {output.push_str(line);}
            }
        }
    }
    if !output.is_empty()&&!output.ends_with('\n'){output.push('\n');}
    let lines:Vec<_>=fresh.split_inclusive('\n').collect();
    for row in &current {if !prior.contains(key(row)){output.push_str(lines[row.line]);if !output.ends_with('\n'){output.push('\n');}}}
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
    let apk_modes:BTreeMap<_,_>=remote.rows.iter().filter(|r|r.enabled).map(|r|(r.label.as_str(),r.data_only)).collect();
    let selected:BTreeSet<_>=remote.rows.iter().filter(|r|r.enabled).map(|r|r.label.as_str()).collect();
    let media_all=selected.contains("Media")&&!selected.iter().any(|n|remote_item_kind(n)==RemoteItemKind::MediaArchive);
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
        let body=state.rows.iter().map(|r|format!("{}\t{}\t{}",r.pkg,usize::from(selected.contains(r.label.as_str())||(kind=="media"&&media_all)),usize::from(kind=="apps"&&apk_modes.get(r.label.as_str()).copied().unwrap_or(r.data_only)))).collect::<Vec<_>>().join("\n");
        let output=edit(&state.original,&state.rows,&body,state.selection_kind.as_deref())?;
        plans.push((state,output));
    }
    // Validate every selected app against the downloaded list before writing.
    let available:BTreeSet<_>=plans.iter().flat_map(|(s,_)|s.rows.iter().map(|r|r.label.as_str())).collect();
    for name in &selected {
        if matches!(remote_item_kind(name),RemoteItemKind::App|RemoteItemKind::MediaArchive)&&!available.contains(name){return Err(err("selected download missing from local lists"));}
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
    let output=edit(&session.original,&session.rows,body,session.selection_kind.as_deref())?;
    let selected=if let Some(k)=session.selection_kind.as_deref(){selection_rows(&output,k)?}else{rows(&output)?};
    if !selected.iter().any(|r|r.enabled){return Err(err("請至少選擇一個項目"));}
    let root=PathBuf::from(std::env::var_os("SPEEDBACKUP_SELECTION_REPORT").ok_or_else(||err("selection report missing"))?);
    let meta=fs::symlink_metadata(&root)?;
    if !root.is_absolute()||!meta.is_dir()||meta.uid()!=0||meta.mode()&0o777!=0o700||root.canonicalize()?!=root{return Err(err("selection report identity"));}
    let receipt:std::borrow::Cow<'_,str>=if session.selection_kind.as_deref()==Some("remote"){selected.iter().filter(|r|r.enabled).map(|r|format!("{}{}\n",if r.data_only{"!"}else{""},r.label)).collect::<String>().into()}else{output.as_str().into()};
    let target=root.join("approved");
    let mut file=OpenOptions::new().write(true).create_new(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(&target)?;
    let result=(||{file.write_all(receipt.as_bytes())?;file.sync_all()?;session.save_text(&output)})();
    if result.is_err(){let _=fs::remove_file(&target);}result
}

fn default_roles(inventory: &str) -> BTreeMap<String, Vec<&'static str>> {
    let mut installed = BTreeSet::new();
    let mut roles = BTreeMap::<String, Vec<&'static str>>::new();
    for line in inventory.lines() {
        let f = line.split('\t').collect::<Vec<_>>();
        if f.len() == 3 && f[0] == "#META" && f[1] == "installed" { installed.insert(f[2]); }
        if f.len() == 5 && f[0] == "#META" && package(f[2]) {
            let label = match f[1] { "defaultHome" => "預設桌面", "defaultIme" => "預設輸入法", _ => continue };
            let labels = roles.entry(f[2].into()).or_default();
            if !labels.contains(&label) { labels.push(label); }
        }
    }
    roles.retain(|pkg, _| installed.contains(pkg.as_str()));
    roles
}

// One serializer owns every row variant; optional metadata remains optional.
struct SelectionViewRow<'a> {
    pkg:std::borrow::Cow<'a,str>,label:&'a str,selected:bool,apk:bool,display_package:&'a str,apk_supported:bool,
    badge:Option<String>,removed:Option<bool>,
}
impl<'a> SelectionViewRow<'a> {
    fn new(row:&'a Row,display_package:&'a str,kind:Option<&str>)->Self {
        Self{pkg:std::borrow::Cow::Borrowed(&row.pkg),label:&row.label,selected:row.enabled,apk:row.data_only,display_package,
            apk_supported:kind==Some("remote")&&remote_apk_supported(&row.label),badge:None,removed:None}
    }
}
impl serde::Serialize for SelectionViewRow<'_> {
    fn serialize<S:serde::Serializer>(&self,serializer:S)->Result<S::Ok,S::Error>{
        use serde::ser::SerializeStruct;
        let mut row=serializer.serialize_struct("SelectionViewRow",6+usize::from(self.badge.is_some())+usize::from(self.removed.is_some()))?;
        row.serialize_field("pkg",&self.pkg)?;row.serialize_field("label",self.label)?;
        row.serialize_field("selected",&self.selected)?;row.serialize_field("apk",&self.apk)?;
        row.serialize_field("displayPackage",&self.display_package)?;row.serialize_field("apkSupported",&self.apk_supported)?;
        if let Some(v)=&self.badge{row.serialize_field("badge",v)?;}if let Some(v)=self.removed{row.serialize_field("removed",&v)?;}row.end()
    }
}
fn serialize_rows(rows:&[SelectionViewRow<'_>])->io::Result<String>{serde_json::to_string(rows).map_err(io::Error::other)}

fn selection_key(row:&Row,by_label:bool)->&str {if by_label{&row.label}else{&row.pkg}}
fn display_package<'a>(row:&'a Row,packages:&'a BTreeMap<String,String>,kind:Option<&str>)->&'a str {
    packages.get(&row.pkg).map(String::as_str).unwrap_or_else(||if kind.is_none()&&package(&row.pkg){&row.pkg}else{""})
}
pub(super) fn list_data(session:Option<&Session>,kind:Option<&str>)->io::Result<String> {
    let current=session.map(|s|s.rows.as_slice()).unwrap_or(&[]);
    // Metadata is display-only: retain the synthetic selection IDs used by save/draft.
    let packages=session.map(|s|icon_packages(s,false).0).unwrap_or_default();
    let Some(root)=std::env::var_os("SPEEDBACKUP_SELECTION_REPORT") else{
        return serialize_rows(&current.iter().map(|r|SelectionViewRow::new(r,display_package(r,&packages,kind),kind)).collect::<Vec<_>>());
    };
    let root=PathBuf::from(root);
    if !root.is_absolute()||root.canonicalize()?!=root{return Err(err("selection report path"));}
    let meta=fs::symlink_metadata(&root)?;
    if !meta.is_dir()||meta.uid()!=0||meta.mode()&0o777!=0o700{return Err(err("selection report identity"));}
    let old=read(&root.join("old"))?.0;
    let previous=if let Some(k)=kind {selection_rows(&old,k)?} else {rows(&old)?};
    let prior:BTreeSet<_>=previous.iter().map(|r|selection_key(r,kind.is_some())).collect();
    let live:BTreeSet<_>=current.iter().map(|r|selection_key(r,kind.is_some())).collect();
    let mut xposed=BTreeSet::new();
    let mut roles=BTreeMap::new();
    if let Ok((inventory,_))=read(&root.join("inventory")) {
        roles=default_roles(&inventory);
        for line in inventory.lines(){let f:Vec<_>=line.split_whitespace().collect();if f.len()==3&&package(f[1])&&f[2].split('|').any(|v|v=="xposed"){xposed.insert(f[1].to_owned());}}
    }
    let by_label:BTreeMap<_,_>=current.iter().map(|r|(r.label.as_str(),r.pkg.as_str())).collect();
    let mut modules=BTreeSet::new();
    if let Some(session)=session {
        for row in current {if packages.get(&row.pkg).is_some_and(|p|xposed.contains(p)){modules.insert(row.pkg.as_str());}}
        if session.selection {
            if let Ok(path)=icon_map_path(&session.path){if let Ok((text,_))=read(&path){for line in text.lines(){let f=line.split('\t').collect::<Vec<_>>();if f.len()==4&&f[3]=="1"{if let Some(pkg)=by_label.get(f[0]){modules.insert(*pkg);}}}}}
        }else if flow()=="restore" {
            for row in current {if row.label.contains(['/', '\\'])||matches!(row.label.as_str(),"."|".."){continue;}let path=session.parent.join(&row.label).join("app_details.json");
                if let Ok((body,_))=read(&path){if super::super::profile::module_metadata(&body,&row.pkg){modules.insert(row.pkg.as_str());}}
            }
        }
    }
    let mut output=Vec::with_capacity(current.len()+previous.len().saturating_sub(live.len()));
    for r in current {
        let display=display_package(r,&packages,kind);
        let mut badge=roles.get(display).cloned().unwrap_or_default();if xposed.contains(&r.pkg)||modules.contains(r.pkg.as_str()){badge.push("Xposed");}if !prior.contains(&selection_key(r,kind.is_some())){badge.push(if kind.is_some(){"新增項目"}else{"新增應用"});}
        let mut row=SelectionViewRow::new(r,display,kind);row.badge=Some(badge.join(" · "));row.removed=Some(false);output.push(row);
    }
    for r in previous.iter().filter(|r|!live.contains(&selection_key(r,kind.is_some()))) {
        let mut row=SelectionViewRow::new(r,if kind.is_none()&&package(&r.pkg){r.pkg.as_str()}else{""},kind);row.pkg=std::borrow::Cow::Owned(format!("removed:{}",r.pkg));row.selected=false;row.apk=false;row.apk_supported=false;row.removed=Some(true);row.badge=Some(if kind.is_some(){"遠端已不存在 · 已移除列表"}else{"無此應用 · 已刪除列表"}.into());output.push(row);
    }
    serialize_rows(&output)
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn view_borrows_identity_and_display_and_removed_owns_only_override(){
        let rows=selection_rows("App\n","remote").unwrap();
        let packages=BTreeMap::from([(rows[0].pkg.clone(),"org.test.app".into())]);
        let mut view=SelectionViewRow::new(&rows[0],display_package(&rows[0],&packages,Some("remote")),Some("remote"));
        assert!(matches!(view.pkg,std::borrow::Cow::Borrowed(_)));
        assert_eq!(view.display_package,"org.test.app");
        assert_eq!(selection_key(&rows[0],true),"App");
        assert_eq!(selection_key(&rows[0],false),rows[0].pkg);
        view.pkg=std::borrow::Cow::Owned(format!("removed:{}",rows[0].pkg));
        view.removed=Some(true);view.selected=false;
        let json:serde_json::Value=serde_json::from_str(&serialize_rows(&[view]).unwrap()).unwrap();
        assert_eq!(json[0]["pkg"],format!("removed:{}",rows[0].pkg));assert_eq!(json[0]["removed"],true);
    }
    #[test] fn row_serialization_preserves_optional_fields_and_escaping(){
        let parsed=selection_rows("!測試應用\n","remote").unwrap();
        let mut row=SelectionViewRow::new(&parsed[0],"org.test.app",Some("remote"));
        let v:serde_json::Value=serde_json::from_str(&serialize_rows(std::slice::from_ref(&row)).unwrap()).unwrap();
        assert_eq!(v[0]["apk"],true);assert_eq!(v[0]["apkSupported"],true);assert!(v[0].get("badge").is_none());
        row.badge=Some("quoted \"value\"\nnext".into());row.removed=Some(false);
        let v:serde_json::Value=serde_json::from_str(&serialize_rows(&[row]).unwrap()).unwrap();
        assert_eq!(v[0]["badge"],"quoted \"value\"\nnext");assert_eq!(v[0]["removed"],false);
    }
    #[test] fn remote_apk_roundtrip_preserves_comments_and_identity(){
        let input="# note\n  #！應用 A # note\nApp B\nwifi\nDCIM.tar.zst\n#@telephony:calls\n";
        let rows=selection_rows(input,"remote").unwrap();
        assert!(rows[0].data_only);assert_eq!(rows[0].label,"應用 A");
        let body=rows.iter().map(|r|format!("{}\t1\t{}",r.pkg,usize::from(r.label=="App B"))).collect::<Vec<_>>().join("\n");
        let out=edit(input,&rows,&body,Some("remote")).unwrap();
        assert_eq!(out,"# note\n  應用 A # note\n!App B\nwifi\nDCIM.tar.zst\n@telephony:calls\n");
        assert_eq!(merge(&out,"應用 A\nApp B\nwifi\nDCIM.tar.zst\n@telephony:calls\nNew\n","remote").unwrap(),out+"New\n");
        assert!(selection_rows("!App\nApp\n","remote").is_err());
    }
    #[test] fn remote_non_app_rows_reject_apk_mode(){
        for name in ["wifi","Media","@telephony:messages","@telephony:calls","photo.tar.zst"] {
            assert!(selection_rows(&format!("!{name}\n"),"remote").is_err());
            let text=format!("{name}\n");let rows=selection_rows(&text,"remote").unwrap();
            assert!(edit(&text,&rows,"row-0\t1\t1",Some("remote")).is_err());
        }
        let rows=selection_rows("photo.tar\n","media").unwrap();
        assert!(edit("photo.tar\n",&rows,"row-0\t1\t1",Some("media")).is_err());
        let rows=selection_rows("1. App\n","remote-delete").unwrap();
        assert!(edit("1. App\n",&rows,"row-0\t1\t1",Some("remote-delete")).is_err());
    }
    #[test] fn default_badges_require_installed_package() {
        let data="#META\tinstalled\tcom.test.home\n#META\tdefaultHome\tcom.test.home\tHome\tpm\n#META\tdefaultIme\tcom.test.home\tHome\tsettings\n";
        assert_eq!(default_roles(data).get("com.test.home").unwrap(), &vec!["預設桌面", "預設輸入法"]);
        assert!(default_roles(&data.replace("installed\tcom.test.home", "installed\tcom.other.app")).is_empty());
    }
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
