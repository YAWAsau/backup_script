# if-addrs
https://crates.io/crates/if-addrs

## Overview

Retrieve network interface info for all interfaces on the system:

```rust
// List all of the machine's network interfaces
for iface in if_addrs::get_if_addrs().unwrap() {
    println!("{:#?}", iface);
}
```

Get notifications for changes in network interfaces:

```rust
let mut notifier = if_addrs::IfChangeNotifier::new().unwrap();
loop {
    if let Ok(details) = notifier.wait(None) {
        println!("{:#?}", details);
    }
}
```

## License

This SAFE Network library is dual-licensed under the Modified BSD ([LICENSE-BSD](LICENSE-BSD) https://opensource.org/licenses/BSD-3-Clause) or the MIT license ([LICENSE-MIT](LICENSE-MIT) http://opensource.org/licenses/MIT) at your option.

## Contribution

Copyrights in the SAFE Network are retained by their contributors. No copyright assignment is required to contribute to this project.
