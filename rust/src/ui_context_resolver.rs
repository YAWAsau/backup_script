//! Executed only as a short-lived standalone process, before any worker threads.
use std::{ffi::{CString,CStr,c_char,c_void},io::{self,Write}};
const PACKAGE:&str="io.github.yawasau.speedbackup.webview";
unsafe extern "C" {fn getuid()->u32;fn geteuid()->u32;fn dlopen(n:*const c_char,f:i32)->*mut c_void;fn dlsym(h:*mut c_void,n:*const c_char)->*mut c_void;}
fn valid(uid:&str,seinfo:&str,package:&str)->bool {
    package==PACKAGE && !uid.is_empty() && uid.len()<=10 && uid.bytes().all(|b|b.is_ascii_digit())
        && uid.parse::<u32>().is_ok_and(|v|v%100000>=10000&&v%100000<20000)
        && !seinfo.is_empty()&&seinfo.len()<=1024&&seinfo.bytes().all(|b|b.is_ascii_alphanumeric()||b"_:=-.,".contains(&b))
}
pub fn run(args:&[String])->i32 {
    let result=(||->io::Result<()>{
        if unsafe{getuid()!=0||geteuid()!=0}||args.len()!=3||!valid(&args[0],&args[1],&args[2]){return Err(io::Error::other("resolver arguments"));}
        let seinfo=CString::new(args[1].as_str()).unwrap();let package=CString::new(PACKAGE).unwrap();
        unsafe {
            let lib=dlopen(c"libselinux.so".as_ptr(),2);
            if lib.is_null(){return Err(io::Error::other("resolver library"));}
            let set=dlsym(lib,c"selinux_android_setcontext".as_ptr());let get=dlsym(lib,c"getcon".as_ptr());let free=dlsym(lib,c"freecon".as_ptr());
            if set.is_null()||get.is_null()||free.is_null(){return Err(io::Error::other("resolver symbols"));}
            let set:unsafe extern "C" fn(u32,bool,*const c_char,*const c_char)->i32=std::mem::transmute(set);
            let get:unsafe extern "C" fn(*mut *mut c_char)->i32=std::mem::transmute(get);
            let free:unsafe extern "C" fn(*mut c_char)=std::mem::transmute(free);
            if set(args[0].parse().unwrap(),false,seinfo.as_ptr(),package.as_ptr())!=0{return Err(io::Error::last_os_error());}
            let mut label=std::ptr::null_mut();if get(&mut label)!=0||label.is_null(){return Err(io::Error::other("resolver context"));}
            let bytes=CStr::from_ptr(label).to_bytes().to_vec();free(label);
            if bytes.is_empty()||bytes.len()>4096||bytes.iter().any(|b|*b<=32||*b>=127)||bytes.split(|b|*b==b':').count()<4{return Err(io::Error::other("resolver output"));}
            let mut out=io::stdout().lock();out.write_all(&bytes)?;out.write_all(b"\n")?;out.flush()?;
        }
        Ok(())
    })();
    if result.is_ok(){0}else{1}
}
#[cfg(test)] mod tests {use super::*;#[test]fn restrict_inputs(){assert!(valid("10859","default:targetSdkVersion=36:complete",PACKAGE));for (u,s,p) in [("0","default",PACKAGE),("10859","default\n",PACKAGE),("10859","default","android"),("-1","default",PACKAGE)]{assert!(!valid(u,s,p));}}}
