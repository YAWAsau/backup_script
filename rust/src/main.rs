#[path = "bin/cgfreezer.rs"]
mod cgfreezer;
#[path = "bin/eventwait.rs"]
mod eventwait;
#[path = "bin/filewatch.rs"]
mod filewatch;
mod multicall;
#[path = "bin/netwatch.rs"]
mod netwatch;
#[path = "bin/procwait.rs"]
mod procwait;
#[path = "bin/speedscan.rs"]
mod speedscan;
#[path = "bin/uidexec.rs"]
mod uidexec;
#[path = "bin/unixsock.rs"]
mod unixsock;

fn main() {
    let (name, argv) = match multicall::select(std::env::args_os().collect()) {
        Ok(invocation) => invocation,
        Err(argv) => {
            let command = argv.get(1).and_then(|s| s.to_str());
            if argv.len() == 2 {
                match command {
                    Some("--list") => {
                        for name in multicall::APPLETS {
                            println!("{name}");
                        }
                        return;
                    }
                    Some("--capabilities") => {
                        println!("speednative.multicall.v1 speednative.argv0_dispatch.v1");
                        return;
                    }
                    Some("--versions") => {
                        for (name, version) in speedbackup_native_rs::APPLET_VERSIONS {
                            println!("{name} {version} build={}", speedbackup_native_rs::BUILD_VERSION);
                        }
                        return;
                    }
                    Some("--version") => {
                        println!("speednative build={}", speedbackup_native_rs::BUILD_VERSION);
                        return;
                    }
                    _ => {}
                }
            }
            eprintln!(
                "Usage: speednative APPLET [ARGS...]\nApplets: {}",
                multicall::APPLETS.join(" ")
            );
            std::process::exit(if command == Some("--help") { 0 } else { 127 });
        }
    };
    multicall::initialize(argv);
    // comm remains the applet name for existing diagnostics; argv[0] is already
    // the symlink name on the production path. Each invocation is its own process.
    #[cfg(any(target_os = "android", target_os = "linux"))]
    unsafe {
        extern "C" {
            fn prctl(
                option: i32,
                arg2: std::os::raw::c_ulong,
                arg3: std::os::raw::c_ulong,
                arg4: std::os::raw::c_ulong,
                arg5: std::os::raw::c_ulong,
            ) -> i32;
        }
        let comm = std::ffi::CString::new(name.as_str()).unwrap();
        prctl(15, comm.as_ptr() as std::os::raw::c_ulong, 0, 0, 0);
    }
    match name.as_str() {
        "cgfreezer" => cgfreezer::run(),
        "eventwait" => eventwait::run(),
        "filewatch" => filewatch::run(),
        "netwatch" => netwatch::run(),
        "procwait" => procwait::run(),
        "speedscan" => speedscan::run(),
        "uidexec" => uidexec::run(),
        "unixsock" => unixsock::run(),
        _ => unreachable!(),
    }
}
