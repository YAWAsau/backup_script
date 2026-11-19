//! Socket-only SELinux creation scope. Never changes task credentials or domain.
//!
//! The caller must authenticate the process identity before supplying its context.
//! This module deliberately does not accept a context from an HTTP request or an
//! environment variable. Publication is allowed only after `create` returns.
use std::{fs::OpenOptions,io::{self,Read,Write},marker::PhantomData,rc::Rc};

const ATTRIBUTE:&str="/proc/thread-self/attr/sockcreate";

fn context_bytes(context:&str)->io::Result<&[u8]> {
    if context.is_empty() || context.len()>4096 || context.bytes().any(|b|b<=32||b>=127)
        || context.split(':').count()<4 {
        return Err(io::Error::new(io::ErrorKind::InvalidInput,"invalid socket security context"));
    }
    Ok(context.as_bytes())
}

trait Attribute {
    fn read(&mut self)->io::Result<Vec<u8>>;
    fn set(&mut self,value:&[u8])->io::Result<()>;
}
struct ThreadAttribute;
impl Attribute for ThreadAttribute {
    fn read(&mut self)->io::Result<Vec<u8>> {
        let mut bytes=Vec::new();
        OpenOptions::new().read(true).open(ATTRIBUTE)?.take(4097).read_to_end(&mut bytes)?;
        if bytes.len()>4096{return Err(io::Error::new(io::ErrorKind::InvalidData,"socket attribute too large"));}
        Ok(bytes)
    }
    fn set(&mut self,value:&[u8])->io::Result<()> {
        // proc attributes consume one write, not a write_all retry of a suffix.
        // A NUL clears sockcreate; a zero-length write does not reset it.
        let mut file=OpenOptions::new().write(true).open(ATTRIBUTE)?;
        if file.write(value)?!=value.len(){return Err(io::Error::new(io::ErrorKind::WriteZero,"short socket attribute write"));}
        Ok(())
    }
}
struct Scope<'a,A:Attribute> {
    attribute:&'a mut A,
    armed:bool,
    // A scope cannot move to another OS thread: the proc path is thread-local.
    _thread:PhantomData<Rc<()>>,
}
impl<A:Attribute> Scope<'_,A> {
    fn reset(&mut self)->io::Result<()> {
        self.attribute.set(b"\0")?;
        if !self.attribute.read()?.is_empty(){return Err(io::Error::new(io::ErrorKind::PermissionDenied,"socket attribute reset not verified"));}
        self.armed=false;
        Ok(())
    }
}
impl<A:Attribute> Drop for Scope<'_,A> {
    fn drop(&mut self) {
        // Continuing on this thread could mislabel unrelated sockets. Even an
        // unwinding panic must not leave a contaminated thread in a worker pool.
        if self.armed && self.reset().is_err(){std::process::abort();}
    }
}
fn scoped<A:Attribute,T>(attribute:&mut A,context:&str,create:impl FnOnce()->io::Result<T>)->io::Result<T> {
    let bytes=context_bytes(context)?;
    // No nested override, and no silent destruction of somebody else's scope.
    if !attribute.read()?.is_empty(){return Err(io::Error::new(io::ErrorKind::PermissionDenied,"socket creation scope already active"));}
    let mut scope=Scope{attribute,armed:true,_thread:PhantomData};
    scope.attribute.set(bytes)?;
    let result=create();
    // Drop the socket before reporting a reset failure. Nothing is published.
    if let Err(error)=scope.reset(){drop(result);return Err(error);}
    result
}

/// Execute only socket creation here: no spawning threads, Binder, logging,
/// callbacks, bind/listen, or descriptor publication until this has returned.
/// A persistent reset failure aborts rather than allowing a contaminated thread
/// to create any further sockets. UID0 and the process SELinux domain are intact.
#[allow(dead_code)]
pub(super) fn create<T>(context:&str,create:impl FnOnce()->io::Result<T>)->io::Result<T> {
    scoped(&mut ThreadAttribute,context,create)
}

#[cfg(target_os="android")]
pub(super) fn bind_abstract(context:&str,name:&str)->io::Result<std::os::unix::net::UnixListener> {
    use std::os::fd::{FromRawFd,AsRawFd,OwnedFd};
    unsafe extern "C"{fn socket(domain:i32,kind:i32,protocol:i32)->i32;fn bind(fd:i32,addr:*const std::ffi::c_void,len:u32)->i32;fn listen(fd:i32,backlog:i32)->i32;}
    #[repr(C)] struct Address{family:u16,path:[u8;108]}
    if name.is_empty()||name.len()>107||name.as_bytes().contains(&0){return Err(io::Error::new(io::ErrorKind::InvalidInput,"abstract socket name"));}
    let fd=create(context,||{let fd=unsafe{socket(1,1|0x80000,0)};if fd<0{Err(io::Error::last_os_error())}else{Ok(unsafe{OwnedFd::from_raw_fd(fd)})}})?;
    // The override has been reset and verified before bind/listen publication.
    let mut addr=Address{family:1,path:[0;108]};addr.path[1..1+name.len()].copy_from_slice(name.as_bytes());
    if unsafe{bind(fd.as_raw_fd(),(&addr as *const Address).cast(),(3+name.len())as u32)}!=0||unsafe{listen(fd.as_raw_fd(),128)}!=0{return Err(io::Error::last_os_error());}
    Ok(fd.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[derive(Default)]
    struct Fake {value:Vec<u8>,writes:Vec<Vec<u8>>,fail_reset_once:bool}
    impl Attribute for Fake {
        fn read(&mut self)->io::Result<Vec<u8>>{Ok(self.value.clone())}
        fn set(&mut self,v:&[u8])->io::Result<()> {
            self.writes.push(v.to_vec());
            if v==b"\0"&&self.fail_reset_once{self.fail_reset_once=false;return Err(io::Error::other("reset failed"));}
            self.value=if v==b"\0"{Vec::new()}else{v.to_vec()};Ok(())
        }
    }
    const CONTEXT:&str="u:r:untrusted_app_34:s0:c1,c2";
    #[test] fn reset_before_return(){let mut a=Fake::default();assert_eq!(scoped(&mut a,CONTEXT,||Ok(42)).unwrap(),42);assert!(a.value.is_empty());assert_eq!(a.writes,vec![CONTEXT.as_bytes().to_vec(),vec![0]]);}
    #[test] fn creation_error_resets(){let mut a=Fake::default();assert!(scoped(&mut a,CONTEXT,||Err::<(),_>(io::Error::other("socket failed"))).is_err());assert!(a.value.is_empty());}
    #[test] fn nested_scope_rejected(){let mut a=Fake{value:CONTEXT.as_bytes().to_vec(),..Fake::default()};assert!(scoped(&mut a,CONTEXT,||Ok(())).is_err());assert!(a.writes.is_empty());}
    #[test] fn invalid_context_never_writes(){for c in ["","u:r:t:s0\n","u:r:t:s0\0","u:r:t"]{let mut a=Fake::default();assert!(scoped(&mut a,c,||Ok(())).is_err());assert!(a.writes.is_empty());}}
    #[test] fn reset_failure_does_not_publish(){let mut a=Fake{fail_reset_once:true,..Fake::default()};assert!(scoped(&mut a,CONTEXT,||Ok(42)).is_err());assert!(a.value.is_empty());assert_eq!(a.writes.len(),3);}
    #[test] fn panic_resets(){let mut a=Fake::default();let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{let _=scoped(&mut a,CONTEXT,||->io::Result<()>{panic!("creation panic")});}));assert!(result.is_err());assert!(a.value.is_empty());}
}
