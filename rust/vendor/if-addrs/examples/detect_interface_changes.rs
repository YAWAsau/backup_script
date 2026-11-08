//! Interface change notifier example.

#[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "illumos")))]
fn main() {
    let mut if_change_notifier = if_addrs::IfChangeNotifier::new().unwrap();
    println!("Waiting for interface changes...");
    loop {
        if let Ok(details) = if_change_notifier.wait(None) {
            println!("Network interfaces changed: {:#?}", details);
        }
    }
}

#[cfg(any(target_os = "macos", target_os = "ios", target_os = "illumos"))]
fn main() {
    panic!("Interface change API is not implemented for macOS or iOS");
}
