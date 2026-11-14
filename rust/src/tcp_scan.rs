//! Shared bounded TCP discovery. Open ports are candidates, never authentication.
use std::{io,net::{Ipv4Addr,SocketAddr,TcpStream},sync::atomic::{AtomicBool,AtomicUsize,Ordering},time::{Duration,Instant}};
pub fn scan(hosts:&[Ipv4Addr],ports:&[u16],timeout:Duration,workers:usize,cancel:&AtomicBool,found:impl Fn(Ipv4Addr,u16,TcpStream,u128)+Sync) {
    let next=AtomicUsize::new(0);
    std::thread::scope(|scope|{
        for _ in 0..workers.clamp(1,192).min(hosts.len()*ports.len()) {
            let next=&next;let found=&found;
            scope.spawn(move||while !cancel.load(Ordering::Acquire){
                let i=next.fetch_add(1,Ordering::Relaxed);
                if i>=hosts.len()*ports.len(){break;}
                let ip=hosts[i/ports.len()];let port=ports[i%ports.len()];let begin=Instant::now();
                if let Ok(stream)=TcpStream::connect_timeout(&SocketAddr::from((ip,port)),timeout) {
                    if !cancel.load(Ordering::Acquire){found(ip,port,stream,begin.elapsed().as_millis().max(1));}
                }
            });
        }
    });
}
fn hosts(raw:&str)->io::Result<Vec<Ipv4Addr>> {
    let raw=raw.trim().trim_end_matches('/');
    let normalized=if raw.matches('.').count()==2{format!("{raw}.0/24")}else if !raw.contains('/'){format!("{raw}/32")}else{raw.to_owned()};
    let(ip,prefix)=normalized.split_once('/').ok_or_else(||io::Error::other("CIDR"))?;
    let ip=u32::from(ip.parse::<Ipv4Addr>().map_err(|_|io::Error::other("IPv4"))?);
    let prefix=prefix.parse::<u32>().ok().filter(|p|(16..=32).contains(p)).ok_or_else(||io::Error::other("prefix"))?;
    let mask=u32::MAX<<(32-prefix);let base=ip&mask;let end=base|!mask;
    let(start,end)=if prefix<=30{(base+1,end-1)}else{(base,end)};
    if end-start+1>16384{return Err(io::Error::other("scan range too large"));}
    Ok((start..=end).map(Ipv4Addr::from).collect())
}
pub fn command(args:&[String])->i32 {
    let run=||->io::Result<bool>{
        let raw=args.first().map(String::as_str).unwrap_or("auto");
        let raw=if raw=="auto" {
            let ip=if_addrs::get_if_addrs()?.into_iter().filter(|i|!i.is_loopback()&&!i.is_p2p&&i.is_oper_up()).find_map(|i|match i.addr {if_addrs::IfAddr::V4(v) if v.ip.is_private()=>Some(v.ip),_=>None}).ok_or_else(||io::Error::other("no LAN IPv4"))?;
            format!("{ip}/24")
        }else{raw.into()};
        let hosts=hosts(&raw)?;
        let ms=args.get(1).and_then(|s|s.parse::<u64>().ok()).unwrap_or(800).clamp(80,5000);
        let workers=args.get(2).and_then(|s|s.parse().ok()).unwrap_or(192);
        let first=args.get(3).is_some_and(|s|matches!(s.as_str(),"1"|"true"|"yes"|"y"));
        let ports=args.get(4).map(String::as_str).unwrap_or("445,139").split([',',';']).filter_map(|s|s.trim().parse::<u16>().ok()).filter(|p|*p>0).collect::<std::collections::BTreeSet<_>>().into_iter().collect::<Vec<_>>();
        if ports.is_empty()||hosts.len()*ports.len()>16384{return Err(io::Error::other("scan range/ports"));}
        let cancel=AtomicBool::new(false);let rows=std::sync::Mutex::new(Vec::new());
        let found=|ip,port,_stream,elapsed|{rows.lock().unwrap().push((ip,port,elapsed));if first{cancel.store(true,Ordering::Release);}};
        scan(&hosts,&ports,Duration::from_millis(ms),workers,&cancel,&found);
        if rows.lock().unwrap().is_empty()&&ms<1000{scan(&hosts,&ports,Duration::from_millis((ms*3).max(1000)),workers,&cancel,&found);}
        let mut rows=rows.into_inner().unwrap();rows.sort_unstable();rows.dedup_by_key(|r|(r.0,r.1));
        if first{rows.truncate(1);}
        for(ip,port,elapsed)in &rows{println!("{ip}\t{port}\topen\t{elapsed}ms");}
        Ok(!rows.is_empty())
    };
    match run(){Ok(true)=>0,Ok(false)=>1,Err(e)=>{eprintln!("SMB_SCAN_FAILED {e}");2}}
}
#[cfg(test)] mod tests {
 use super::*;
 #[test] fn cidr_limits(){assert_eq!(hosts("192.168.0").unwrap().len(),254);assert_eq!(hosts("192.168.0.4/31").unwrap().len(),2);assert_eq!(hosts("192.168.0.4").unwrap(),vec![Ipv4Addr::new(192,168,0,4)]);assert!(hosts("10.0.0.0/16").is_err());assert!(hosts("bad").is_err());}
 #[test] fn open_and_cancel(){let listener=std::net::TcpListener::bind("127.0.0.1:0").unwrap();let cancel=AtomicBool::new(false);let hits=AtomicUsize::new(0);scan(&[Ipv4Addr::LOCALHOST],&[listener.local_addr().unwrap().port()],Duration::from_millis(100),1,&cancel,|_,_,_,_|{hits.fetch_add(1,Ordering::Relaxed);});assert_eq!(hits.load(Ordering::Relaxed),1);cancel.store(true,Ordering::Release);scan(&[Ipv4Addr::LOCALHOST],&[listener.local_addr().unwrap().port()],Duration::from_millis(100),1,&cancel,|_,_,_,_|panic!("cancelled"));}
}
