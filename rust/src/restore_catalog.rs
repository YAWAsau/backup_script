//! Restore catalog work shared by Shell entry points. Android APK probing stays in Dex.
use std::{collections::BTreeMap, fs, io, path::Path};
fn error(s:&str)->io::Error{io::Error::other(s)}
fn token(s:&str)->bool{!s.contains(['\0','\t','\r','\n'])}
fn publish(path:&Path,body:&str)->io::Result<()> {
    super::publish_file::publish_bytes_guarded(body.as_bytes(),path,Some(0o644),super::publish_file::auto_preserve(path)?,&mut ||Ok(())).map(|_|())
}
pub(super) fn safe_name(raw:&str,fallback:&str)->String {
    let raw=if matches!(raw.to_ascii_lowercase().as_str(),"media"|"log"|"tools"|"wifi"|"communications"){format!("app_{raw}")}else{raw.to_owned()};
    let clean=|s:&str| {let v=s.chars().map(|c|if "/\\ :\t\r\n\"`$;|&()<>!*?[]{}'=#~^".contains(c){'_'}else{c}).collect::<String>().replace("..","__");if !v.is_empty()&&v.chars().all(|c|c=='.'){"_".into()}else{v}};
    let mut value=clean(&raw);if value.is_empty(){value=clean(fallback);}if value.is_empty(){value="app".into();}value
}
fn scan(root:&Path,out:&Path,installed:&Path)->io::Result<()> {
    let installed=fs::read_to_string(installed)?;let installed:std::collections::BTreeSet<_>=installed.lines().filter_map(|l|l.split_whitespace().next()).collect();
    let mut paths=Vec::new();
    for entry in fs::read_dir(root)? {
        let entry=entry?;let ty=entry.file_type()?;
        if ty.is_file()&&entry.file_name().to_string_lossy().starts_with("apk."){paths.push(entry.path());}
        if ty.is_dir(){for child in fs::read_dir(entry.path())?{let child=child?;if child.file_type()?.is_file()&&child.file_name().to_string_lossy().starts_with("apk."){paths.push(child.path());}}}
    }
    use std::os::unix::ffi::OsStrExt;
    paths.sort_by(|a,b|a.as_os_str().as_bytes().cmp(b.as_os_str().as_bytes()));let mut cache=BTreeMap::new();let mut body=String::new();
    for path in paths {
        let folder=path.parent().ok_or_else(||error("archive parent"))?;
        let identity=cache.entry(folder.to_path_buf()).or_insert_with(||fs::read_to_string(folder.join("app_details.json")).ok().and_then(|s|super::profile::regen_identity(&s).ok()).unwrap_or_default());
        let (name,pkg)=identity;let path=path.to_str().ok_or_else(||error("archive encoding"))?;
        if !token(path){return Err(error("archive path contains control characters"));}
        let valid=!name.is_empty()&&!pkg.is_empty()&&token(pkg);
        body.push_str(&format!("{}\t{}\t{}\t{}\n",path,if valid{safe_name(name.lines().next().unwrap_or(""),pkg)}else{"-".into()},if valid{pkg.as_str()}else{"-"},usize::from(valid&&installed.contains(pkg.as_str()))));
    }
    publish(out,&body)
}
// Return the exact label byte range without touching disabled/APK markers or notes.
fn label_span(line:&str)->Option<(usize,usize,&str)> {
    let mut at=0;
    loop {
        let rest=&line[at..];let n=rest.len()-rest.trim_start_matches([' ','\t']).len();if n>0{at+=n;continue;}
        if let Some(c)=rest.chars().next().filter(|c|matches!(c,'#'|'＃')){at+=c.len_utf8();continue;}
        let mut advanced=false;
        for prefix in ["!play","！play"] {if rest.starts_with(prefix)&&rest[prefix.len()..].starts_with([' ','\t']){at+=prefix.len();advanced=true;break;}}
        if !advanced{break;}
    }
    let rest=&line[at..];let end=rest.find([' ','\t']).unwrap_or(rest.len());if end==0{return None;}
    let pkg=rest[end..].split_whitespace().next()?;
    let word=&rest[..end];let lead=word.len()-word.trim_start_matches(['!','！']).len();let tail=word.trim_end_matches(['!','！']).len();
    if lead>=tail{return None;}Some((at+lead,at+tail,pkg))
}
fn retarget(map:&Path,list:&Path)->io::Result<()> {
    let mapping=fs::read_to_string(map)?;if mapping.is_empty(){return Ok(());}
    let mut exact=BTreeMap::new();let mut packages:BTreeMap<&str,Vec<&str>>=BTreeMap::new();let mut fresh=String::new();
    for line in mapping.lines(){let f:Vec<_>=line.split('\t').collect();if f.len()!=3{return Err(error("rename map"));}exact.insert((f[0],f[2]),f[1]);packages.entry(f[2]).or_default().push(f[1]);fresh.push_str(&format!("{} {}\n",f[1],f[2]));}
    let original=match fs::read_to_string(list){Ok(s)=>s,Err(e) if e.kind()==io::ErrorKind::NotFound=>return publish(list,&fresh),Err(e)=>return Err(e)};
    let mut output=String::new();
    for line in original.split_inclusive('\n'){
        if let Some((start,end,pkg))=label_span(line){let replacement=exact.get(&(&line[start..end],pkg)).copied().or_else(||packages.get(pkg).filter(|v|v.len()==1).map(|v|v[0]));if let Some(value)=replacement{output.push_str(&line[..start]);output.push_str(value);output.push_str(&line[end..]);continue;}}
        output.push_str(line);
    }
    // Recheck the source snapshot before committing a rename's list changes.
    super::publish_file::publish_bytes_guarded(output.as_bytes(),list,None,super::publish_file::auto_preserve(list)?,&mut ||if fs::read_to_string(list)?==original{Ok(())}else{Err(error("list changed during retarget"))}).map(|_|())
}
fn legacy_rename(folder:&Path,target:&Path)->io::Result<()> {
    // Some older FUSE/sdcardfs implementations lack rename flags. Retain the
    // legacy rename operation, but recheck all destination types, including links.
    match fs::symlink_metadata(target){Err(e) if e.kind()==io::ErrorKind::NotFound=>fs::rename(folder,target),Ok(_)=>Err(error("rename destination appeared")),Err(e)=>Err(e)}
}
fn rename(folder:&Path,name:&str,pkg:&str)->io::Result<()> {
    if !token(name)||!token(pkg)||pkg.is_empty()||!pkg.bytes().all(|c|c.is_ascii_alphanumeric()||c==b'_'||c==b'.')||pkg.contains(".."){return Err(error("rename identity"));}
    let old=folder.file_name().and_then(|x|x.to_str()).ok_or_else(||error("folder name"))?;
    if !fs::symlink_metadata(folder)?.is_dir(){return Err(error("not a directory"));}
    let base=if old==pkg{safe_name(name.lines().next().unwrap_or(""),pkg)}else{pkg.to_owned()};let parent=folder.parent().ok_or_else(||error("folder parent"))?;
    let mut target=parent.join(&base);if target==folder{return Ok(());}
    let mut i=1;while target.is_dir(){target=parent.join(format!("{base}_{i}"));i+=1;}
    // renameat2 refuses a concurrent destination creation instead of overwriting it.
    use std::os::unix::ffi::OsStrExt;
    let from=std::ffi::CString::new(folder.as_os_str().as_bytes())?;let to=std::ffi::CString::new(target.as_os_str().as_bytes())?;
    unsafe extern "C" {fn syscall(number:std::ffi::c_long,...)->std::ffi::c_long;}
    #[cfg(target_arch="aarch64")] let number=276 as std::ffi::c_long;
    #[cfg(target_arch="x86_64")] let number=316 as std::ffi::c_long;
    #[cfg(not(any(target_arch="aarch64",target_arch="x86_64")))] let number=-1 as std::ffi::c_long;
    if number<0{legacy_rename(folder,&target)?;}
    else if unsafe{syscall(number,-100i32,from.as_ptr(),-100i32,to.as_ptr(),1u32)}!=0{
        let e=io::Error::last_os_error();
        if matches!(e.raw_os_error(),Some(22|38|95)){legacy_rename(folder,&target)?;}else{return Err(e);}
    }
    println!("{}\t{}\t{}",old,target.file_name().unwrap().to_string_lossy(),pkg);Ok(())
}
fn media(root:&Path,out:&Path,reset:bool)->io::Result<()> {
    if !reset&&!root.join("Media").is_dir(){return Ok(());}
    let mut body=if reset{String::new()}else{match fs::read_to_string(out){Ok(s)=>s,Err(e) if e.kind()==io::ErrorKind::NotFound=>String::new(),Err(e)=>return Err(e)}};
    let dir=root.join("Media");if dir.is_dir(){if !reset&&!out.exists(){body.push_str("#不需要恢復的資料夾請在開頭使用#注釋 比如：#Download\n");}for entry in fs::read_dir(dir)?{let entry=entry?;let name=entry.file_name();let name=name.to_str().ok_or_else(||error("media encoding"))?;if entry.file_type()?.is_file()&&name.contains(".tar"){if !token(name){return Err(error("media name"));}body.push_str(name);body.push('\n');}}}
    publish(out,&body)
}
fn apps(manifest:&Path,out:&Path)->io::Result<()> {
    let input=fs::read_to_string(manifest)?;let mut body=String::new();
    for line in input.lines(){let f:Vec<_>=line.split('\t').collect();if f.len()!=2||f.iter().any(|s|s.is_empty()||!token(s)){return Err(error("application catalog row"));}
        if body.is_empty(){body.push_str("#不需要恢復還原的應用請在開頭使用#注釋 比如：#酷安 com.coolapk.market\n");}
        body.push_str(f[0]);body.push(' ');body.push_str(f[1]);body.push('\n');
    }
    publish(out,&body)
}
pub(super) fn run(args:&[String])->i32 {
    let result=match args.first().map(String::as_str){
        Some("scan") if args.len()==4=>scan(Path::new(&args[1]),Path::new(&args[2]),Path::new(&args[3])),
        Some("retarget") if args.len()==3=>retarget(Path::new(&args[1]),Path::new(&args[2])),
        Some("rename") if args.len()==4=>rename(Path::new(&args[1]),&args[2],&args[3]),
        Some("media") if args.len()==4&&matches!(args[3].as_str(),"reset"|"append")=>media(Path::new(&args[1]),Path::new(&args[2]),args[3]=="reset"),
        Some("apps") if args.len()==3=>apps(Path::new(&args[1]),Path::new(&args[2])),
        Some("folders") if args.len()==2=>(||{for line in fs::read_to_string(&args[1])?.lines(){if let Some((a,b,pkg))=label_span(line){if !pkg.is_empty()&&pkg.split('.').all(|p|!p.is_empty()&&p.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'_')){println!("{}",line[a..b].replace(['!','！'],""));}}}Ok(())})(),
        _=>Err(error("restore-catalog arguments")),
    };
    match result{Ok(())=>0,Err(e)=>{eprintln!("RESTORE_CATALOG_ERROR {e}");1}}
}
#[cfg(test)] mod tests {
    use super::*;
    #[test] fn safe_names_match_shell(){assert_eq!(safe_name("Media","pkg"),"app_Media");assert_eq!(safe_name("a../b c$","pkg"),"a___b_c_");assert_eq!(safe_name("","org.test.app"),"org.test.app");}
    #[test] fn label_markers_and_notes(){let s=" #＃ !play ！Old！ org.test.app # note\n";let (a,b,p)=label_span(s).unwrap();assert_eq!(&s[a..b],"Old");assert_eq!(p,"org.test.app");}
}
