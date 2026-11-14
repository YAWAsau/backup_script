//! A single receipt for the existing two-stage external repair. Each worker
//! retains its own timeout, lease, owner checks and process-group cancellation.
use std::io;
pub fn execute(args: &[String], mut run: impl FnMut(&[String])->io::Result<(i32,Vec<u8>)>) -> io::Result<(i32,Vec<u8>)> {
    if args.first().map(String::as_str)!=Some("external-policy-repair-selinux") {return run(args);}
    if args.len()!=4 {return Err(io::ErrorKind::InvalidInput.into());}
    let mut first=args.to_vec();first[0]="external-policy-repair".into();
    let (rc,mut output)=run(&first)?;
    if rc!=0 {return Ok((rc,output));}
    let second=vec!["selinux-restore".into(),args[1].clone(),"12".into()];
    match run(&second) {
        Ok((rc,body))=>{output.extend(body);Ok((rc,output))},
        // Stage one already mutated data: never report the whole request as
        // not-started or permit an automatic replay of its successful stage.
        Err(e)=>{output.extend(format!("FILE_RPC_STAGE_FAILED stage=selinux error={e}\n").bytes());Ok((125,output))}
    }
}
#[cfg(test)] mod tests {
    use super::*;
    fn args()->Vec<String>{["external-policy-repair-selinux","/test","10001","data"].map(str::to_owned).to_vec()}
    #[test] fn exact_order_and_arguments(){let mut calls=Vec::new();let result=execute(&args(),|a|{calls.push(a.to_vec());Ok((0,vec![calls.len() as u8]))}).unwrap();assert_eq!(result,(0,vec![1,2]));assert_eq!(calls[0],["external-policy-repair","/test","10001","data"]);assert_eq!(calls[1],["selinux-restore","/test","12"]);}
    #[test] fn first_failure_stops(){let mut n=0;assert_eq!(execute(&args(),|_|{n+=1;Ok((7,vec![3]))}).unwrap(),(7,vec![3]));assert_eq!(n,1);}
    #[test] fn second_spawn_failure_is_partial(){let mut n=0;let (rc,body)=execute(&args(),|_|{n+=1;if n==1{Ok((0,vec![1]))}else{Err(io::ErrorKind::BrokenPipe.into())}}).unwrap();assert_eq!(rc,125);assert_eq!(body[0],1);}
    #[test] fn first_spawn_failure_is_not_started(){assert!(execute(&args(),|_|Err(io::ErrorKind::PermissionDenied.into())).is_err());}
    #[test] fn ordinary_command_unchanged(){let a=vec!["selinux-restore".into(),"/test".into(),"12".into()];assert_eq!(execute(&a,|b|{assert_eq!(b,a);Ok((9,vec![2]))}).unwrap(),(9,vec![2]));}
}
