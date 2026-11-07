//! Per-loop queries and private temporary-file allocation. Live inputs are
//! reopened for every query; parsed rows are reused only for identical bytes.
use std::{fs::{self,File,OpenOptions},io::{self,BufRead,BufReader,Read,Write,Seek,SeekFrom},os::{fd::{AsRawFd,FromRawFd},unix::{process::CommandExt,fs::{MetadataExt,OpenOptionsExt}}},process::{Command,Stdio}};
use std::os::raw::{c_int,c_long,c_ulong};
#[repr(C)] struct PollFd{fd:c_int,events:i16,revents:i16}
extern "C"{fn syscall(n:c_long,...)->c_long;fn poll(p:*mut PollFd,n:usize,ms:c_int)->c_int;fn getppid()->c_int;fn dup(fd:c_int)->c_int;fn prctl(op:c_int,a:c_ulong,b:c_ulong,c:c_ulong,d:c_ulong)->c_int;fn _exit(rc:c_int)->!;fn snprintf(out:*mut u8,size:usize,format:*const u8,...)->c_int;fn strtod(input:*const u8,end:*mut *mut u8)->f64;}
const EXACT:&str="$0==k{f=1;exit} END{exit f?0:1}";
const PREFIX:&str="index($0,p)==1{f=1;exit} END{exit f?0:1}";
const ANY:&str="$0==a||$0==b{f=1;exit} END{exit f?0:1}";
const SIZE:&str=r###"
		function clean_path(x) {
			gsub(/\r/, "", x)
			sub(/^https?:\/\/[^\/]*\/?/, "", x)
			gsub(/^\/+/, "", x)
			return x
		}
		function is_suffix_path(p, r) {
			if (p == r) return 1
			if (length(p) > length(r) && substr(p, length(p)-length(r)+1) == r && substr(p, length(p)-length(r), 1) == "/") return 1
			return 0
		}
		BEGIN { r=clean_path(rel) }
		{
			for (i=1; i<=NF; i++) gsub(/\r/, "", $i)
			p=""; sz=""; typ=""
			if (($1 == "F" || $1 == "FILE") && NF >= 3) { typ=$1; sz=$2; p=$3 }
			else if (($1 == "D" || $1 == "DIR") && NF >= 3) { next }
			else if (NF >= 2) { p=$1; sz=$2; typ=$3 }
			else next
			if (typ == "D" || typ == "DIR") next
			if (sz !~ /^[0-9]+$/) next
			p=clean_path(p)
			if (is_suffix_path(p, r)) { print sz; found=1; exit }
		}
		END { if (!found) exit 1 }
	"###;
const ROW:&str="!/^[[:space:]]*[#＃]/ && NF{c++} c==n{print $0; exit}";
fn awk(executable:&str, inherited:&Option<File>,vars:&[(&str,&str)],program:&str,path:&str,err:&str)->io::Result<(i32,String)>{
    let mut c=Command::new(executable);
    for (k,v) in vars{c.arg("-v").arg(format!("{k}={v}"));}
    c.arg(program).arg(path).stdin(Stdio::null()).stdout(Stdio::piped())
        .stderr(if err=="@stderr"{Stdio::from(inherited.as_ref().ok_or_else(||io::Error::other("query stderr"))?.try_clone()?)}else{Stdio::from(OpenOptions::new().create(true).append(true).open(err)?)});
    let parent=std::process::id() as i32;
    unsafe{c.pre_exec(move||{if prctl(1,9,0,0,0)!=0||getppid()!=parent{return Err(io::Error::last_os_error());}Ok(())});}
    let mut child=c.spawn()?;let mut out=Vec::new();
    child.stdout.take().unwrap().take(1048577).read_to_end(&mut out)?;
    if out.len()>1048576{let _=child.kill();let _=child.wait();return Err(io::Error::other("query output limit"));}
    let rc=child.wait()?.code().ok_or_else(||io::Error::other("query signal"))?;
    while out.last()==Some(&b'\n'){out.pop();}
    if out.contains(&0)||out.contains(&b'\n'){return Err(io::Error::other("query framing"));}
    let text=String::from_utf8(out).map_err(|_|io::Error::other("query encoding"))?;
    Ok((rc,text))
}

#[derive(Default)]
struct QueryState { self_identity:Option<String>, rows: Option<(String,Vec<u8>,Vec<String>)>, root:String, seq:u64, awk_path:String, awk_identity:String, stderr:Option<File> }
fn row_query(state:&mut QueryState,path:&str,index:&str,err:&str)->io::Result<(i32,String)>{
    let bad=||io::Error::other("row fallback");
    let n=index.parse::<usize>().map_err(|_|bad())?;
    if n==0||n.to_string()!=index{return Err(bad());}
    // Always reopen and read CURRENT bytes; same size/mtime/inode is not proof.
    let mut raw=Vec::new();File::open(path)?.take(1048577).read_to_end(&mut raw)?;
    if raw.len()>1048576||raw.contains(&0){return Err(bad());}
    if let Some((cached_path,cached_bytes,rows))=&state.rows{
        if cached_path==path&&cached_bytes==&raw{return Ok((0,rows.get(n-1).cloned().unwrap_or_default()));}
    }
    #[cfg(target_arch="aarch64")] const MEMFD:c_long=279;
    #[cfg(target_arch="x86_64")] const MEMFD:c_long=319;
    #[cfg(not(any(target_arch="aarch64",target_arch="x86_64")))] const MEMFD:c_long=-1;
    let name=b"speedbackup-query\0";
    let fd=unsafe{syscall(MEMFD,name.as_ptr(),1u32)} as i32;
    if fd<0{return Err(bad());}
    let mut snapshot=unsafe{File::from_raw_fd(fd)};
    snapshot.write_all(&raw)?;snapshot.seek(SeekFrom::Start(0))?;
    // Awk still owns comment/locale/NF semantics. It parses the exact bytes
    // compared above, not a second read of a potentially replaced pathname.
    let mut c=Command::new(&state.awk_path);
    c.arg("!/^[[:space:]]*[#＃]/ && NF").stdin(Stdio::from(snapshot)).stdout(Stdio::piped())
        .stderr(Stdio::from(OpenOptions::new().create(true).append(true).open(err)?));
    let parent=std::process::id() as i32;
    unsafe{c.pre_exec(move||{if prctl(1,9,0,0,0)!=0||getppid()!=parent{return Err(io::Error::last_os_error());}Ok(())});}
    let mut child=c.spawn()?;let mut out=Vec::new();
    child.stdout.take().unwrap().take(2097153).read_to_end(&mut out)?;
    if out.len()>2097152{let _=child.kill();let _=child.wait();return Err(bad());}
    if !child.wait()?.success(){return Err(bad());}
    if out.last()==Some(&b'\n'){out.pop();}
    let rows=if out.is_empty(){Vec::new()}else{
        out.split(|b|*b==b'\n').map(|line|String::from_utf8(line.to_vec()).map_err(|_|bad())).collect::<io::Result<Vec<_>>>()?
    };
    let answer=rows.get(n-1).cloned().unwrap_or_default();
    state.rows=Some((path.into(),raw,rows));
    Ok((0,answer))
}
fn native_key(k:&str)->bool{
    !k.contains(['\\','\n','\0']) && (k.contains('/')||k.contains('_'))
}
fn native_match(path:&str, matches:impl Fn(&[u8])->bool)->io::Result<bool>{
    let mut reader=BufReader::new(File::open(path)?);let mut row=Vec::new();
    loop{row.clear();let n=Read::by_ref(&mut reader).take(65537).read_until(b'\n',&mut row)?;
        if n==0{return Ok(false);}
        if n>65536||row.contains(&0){return Err(io::Error::other("prefix fallback"));}
        if row.last()==Some(&b'\n'){row.pop();}
        if matches(&row){return Ok(true);}
    }
}

fn reserve_pair(state:&mut QueryState,path:&str)->io::Result<(i32,String)>{
    let bad=||io::Error::other("temporary-file fallback");
    if path!=state.root||path.contains(['|','\n','\r','\t']){return Err(bad());}
    let meta=fs::symlink_metadata(path)?;
    if !meta.is_dir()||meta.uid()!=0||meta.mode()&0o777!=0o700||fs::canonicalize(path)?.as_os_str()!=std::ffi::OsStr::new(path){return Err(bad());}
    for _ in 0..4{
        state.seq=state.seq.checked_add(1).ok_or_else(bad)?;
        let status=format!("{path}/.webdav_daemon_status_Q{}_{}",std::process::id(),state.seq);
        let errors=format!("{path}/.webdav_relay_err_Q{}_{}",std::process::id(),state.seq);
        let first=match OpenOptions::new().write(true).create_new(true).mode(0o600).open(&status){Ok(f)=>f,Err(e) if e.kind()==io::ErrorKind::AlreadyExists=>continue,Err(e)=>return Err(e)};
        match OpenOptions::new().write(true).create_new(true).mode(0o600).open(&errors){
            Ok(_)=>return Ok((0,format!("{status}|{errors}"))),
            Err(e)=>{
                let own=first.metadata()?;
                if fs::symlink_metadata(&status).map(|m|m.dev()==own.dev()&&m.ino()==own.ino()).unwrap_or(false){let _=fs::remove_file(&status);}
                if e.kind()==io::ErrorKind::AlreadyExists{continue;}return Err(e);
            }
        }
    }
    Err(bad())
}
fn identity(path:&str)->io::Result<String>{
    let m=fs::metadata(path)?;
    if !m.is_file()||m.mode()&0o111==0{return Err(io::Error::other("query executable"));}
    Ok(format!("{}:{}:{}:{}:{}:{}:{}:{}",m.dev(),m.ino(),m.len(),m.mtime(),m.mtime_nsec(),m.ctime(),m.ctime_nsec(),m.mode()))
}
// Match BusyBox awk's libc numeric formatting for canonical decimal inputs.
// Other locales/large inputs still use the original awk implementation.
fn display_size_native(value:&str)->Option<String>{
    if value.len()>20{return None;}
    for name in ["LC_ALL","LC_NUMERIC","LANG"]{
        if let Some(locale)=std::env::var_os(name){
            if !matches!(locale.to_str(),Some(""|"C"|"POSIX")){return None;}
        }
    }
    let mut input=value.as_bytes().to_vec();input.push(0);
    let number=unsafe{strtod(input.as_ptr(),std::ptr::null_mut())};
    let mut out=[0u8;128];
    let written=unsafe{
        if number>=1073741824.0{snprintf(out.as_mut_ptr(),out.len(),b"%.2fGB\0".as_ptr(),number/1073741824.0)}
        else if number>=1048576.0{snprintf(out.as_mut_ptr(),out.len(),b"%.1fMB\0".as_ptr(),number/1048576.0)}
        else if number>=1024.0{snprintf(out.as_mut_ptr(),out.len(),b"%.0fKB\0".as_ptr(),number/1024.0)}
        else{snprintf(out.as_mut_ptr(),out.len(),b"%dB\0".as_ptr(),number as c_int)}
    };
    if written<0||written as usize>=out.len(){return None;}
    String::from_utf8(out[..written as usize].to_vec()).ok()
}
fn regular(path:&str)->bool{path.starts_with('/')&&fs::metadata(path).map(|m|m.is_file()).unwrap_or(false)}
fn query(a:&[String],state:&mut QueryState)->io::Result<(i32,String)>{
    let bad=||io::Error::other("query fallback");
    if identity(&state.awk_path)?!=state.awk_identity{return Err(bad());}
    let (op,p,k,b,extra,err)=(&a[0],&a[1],&a[2],&a[3],&a[4],&a[5]);
    if op=="temps"{return reserve_pair(state,p);}
    if op=="display-size"{
        if err!="@stderr"||k.is_empty()||!k.bytes().all(|x|x.is_ascii_digit())||(k.len()>1&&k.starts_with('0')){return Err(bad());}
        if let Some(text)=display_size_native(k){return Ok((0,text));}
        return awk(&state.awk_path,&state.stderr,&[("s",k)],"BEGIN{if(s>=1073741824)printf\"%.2fGB\",s/1073741824;else if(s>=1048576)printf\"%.1fMB\",s/1048576;else if(s>=1024)printf\"%.0fKB\",s/1024;else printf\"%dB\",s}","/dev/null",err);
    }
    if op=="file-metrics" {
        if state.self_identity.as_ref()!=Some(&identity(b)?) { return Err(bad()); }
        return super::payload_stats::file_transfer_value(p,k)
            .map(|text|(0,text)).ok_or_else(bad);
    }
    if !err.starts_with('/')||!regular(p){return Err(bad());}
    // The original shell redirection must succeed even on a native fast path.
    drop(OpenOptions::new().create(true).append(true).open(err)?);
    match op.as_str(){
        "entry"=>{let (kind,keep)=super::media_entry_plan_value(p,k)?;Ok((0,format!("M1:{kind}:{}",u8::from(keep))))},
        "size"=>{
            // The producer normally supplies names only. Without a TAB every
            // record has NF<2 under the original parser, so no size can match.
            // Still read current bytes each time; unusual escapes retain awk diagnostics.
            if !k.contains('\\'){
                let mut raw=Vec::new();
                if File::open(p).and_then(|f|f.take(1048577).read_to_end(&mut raw)).is_ok()
                    &&raw.len()<=1048576&&!raw.contains(&b'\t')&&!raw.contains(&0)&&std::str::from_utf8(&raw).is_ok(){
                    return Ok((1,String::new()));
                }
            }
            awk(&state.awk_path,&state.stderr,&[("FS","\t"),("rel",k)],SIZE,p,err)
        },
        "row"=>row_query(state,p,k,err).or_else(|_|awk(&state.awk_path,&state.stderr,&[("n",k)],ROW,p,err)),
        "exact"=>{
            if native_key(k){if let Ok(found)=super::media_list_has(p,k.as_bytes()){return Ok((if found{0}else{1},String::new()));}}
            awk(&state.awk_path,&state.stderr,&[("k",k)],EXACT,p,err)
        },
        "prefix"=>{
            if !k.is_empty() && !k.contains(['\\','\n','\0']){if let Ok(found)=native_match(p,|row|row.starts_with(k.as_bytes())){return Ok((if found{0}else{1},String::new()));}}
            awk(&state.awk_path,&state.stderr,&[("p",k)],PREFIX,p,err)
        },
        "any"=>{
            if native_key(k)&&native_key(b){
                if let Ok(found)=native_match(p,|row|row==k.as_bytes()||row==b.as_bytes()){
                    return Ok((if found{0}else{1},String::new()));
                }
            }
            awk(&state.awk_path,&state.stderr,&[("a",k),("b",b)],ANY,p,err)
        },
        "selected"=>{
            if k.is_empty(){return Err(bad());}
            if !extra.is_empty()&&!regular(extra){return Err(bad());}
            if fs::metadata(p)?.len()==0{return Ok((0,"K".into()));}
            let supported=|v:&str|v.as_bytes().first().map(|x|x.is_ascii_alphabetic()||*x==b'_').unwrap_or(false)
                &&v.bytes().all(|x|(32..=126).contains(&x)&&x!=92)&&!v.to_ascii_lowercase().starts_with("nan")&&!v.to_ascii_lowercase().starts_with("inf");
            let keys=if supported(k){super::media_list_has(p,k.as_bytes()).ok()}else{None};
            if !match keys{Some(v)=>v,None=>match awk(&state.awk_path,&state.stderr,&[("k",k)],EXACT,p,err)?.0{0=>true,1=>false,_=>return Err(bad())}}{return Ok((0,"K".into()));}
            if !extra.is_empty(){
                let found=if supported(b){super::media_list_has(extra,b.as_bytes()).ok()}else{None};
                if !match found{Some(v)=>v,None=>match awk(&state.awk_path,&state.stderr,&[("k",b)],EXACT,extra,err)?.0{0=>true,1=>false,_=>return Err(bad())}}{return Ok((0,"R".into()));}
            }
            Ok((0,"Y".into()))
        },
        _=>Err(bad()),
    }
}
pub fn run(args:&[String])->i32{
    let result=(||->io::Result<()>{
        if args.len()!=4{return Err(io::Error::other("query arguments"));}
        // FD3 is a duplicate of the caller's stderr, sharing its open-file
        // description. Formatting diagnostics must preserve offset and flags.
        let stderr_fd=unsafe{dup(3)};
        if stderr_fd<0{return Err(io::Error::last_os_error());}
        let stderr=Some(unsafe{File::from_raw_fd(stderr_fd)});
        let awk_identity=identity(&args[2])?;
        if super::sha256_file_hex(std::path::Path::new(&args[2]))?!=args[3] || identity(&args[2])?!=awk_identity{return Err(io::Error::other("query executable integrity"));}
        let owner=args[0].parse::<u32>().map_err(|_|io::Error::other("query owner"))?;
        if owner<=1{return Err(io::Error::other("query owner"));}
        let fd=unsafe{syscall(434,owner,0u32)} as i32;
        if fd<0{return Err(io::Error::last_os_error());}
        let ownerfd=unsafe{File::from_raw_fd(fd)};
        let parent=unsafe{getppid()};
        if unsafe{prctl(1,9,0,0,0)}!=0||unsafe{getppid()}!=parent{return Err(io::Error::other("query parent"));}
        std::thread::spawn(move||{let mut p=PollFd{fd:ownerfd.as_raw_fd(),events:1,revents:0};loop{let rc=unsafe{poll(&mut p,1,-1)};if rc<0&&io::Error::last_os_error().kind()==io::ErrorKind::Interrupted{continue;}unsafe{_exit(125);}}});
        let mut input=BufReader::new(io::stdin().lock());let mut output=io::stdout().lock();
        let self_identity=identity("/proc/self/exe").ok();
        writeln!(output,"Q1:READY")?;output.flush()?;
        let mut state=QueryState{self_identity,root:args[1].clone(),awk_path:args[2].clone(),awk_identity,stderr,..QueryState::default()};
        loop{
            let mut args=Vec::new();let mut invalid=false;
            for field in 0..6{
                let mut line=Vec::new();let n=Read::by_ref(&mut input).take(65537).read_until(b'\n',&mut line)?;
                if n==0&&field==0{return Ok(());}
                if n==0||n>65536||line.last()!=Some(&b'\n'){return Err(io::Error::other("query request"));}
                line.pop();if line.contains(&0){invalid=true;}
                let text=match String::from_utf8(line){Ok(s)=>s,Err(_)=>{invalid=true;String::new()}};
                if field==0&&text=="QUIT"{return Ok(());}
                args.push(text);
            }
            match if invalid{Err(io::Error::other("query encoding"))}else{query(&args,&mut state)}{Ok((rc,text))=>writeln!(output,"Q1:R:{rc}:{text}")?,Err(_)=>writeln!(output,"Q1:F")?,}
            output.flush()?;
        }
    })();
    if result.is_ok(){0}else{125}
}
