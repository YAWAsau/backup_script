// GNU tar default (gnu format, blocking-factor=20) accounting.
pub fn round512(n: u64) -> u64 { n.div_ceil(512) * 512 }
pub fn long_extra(n: usize) -> u64 { if n > 100 { 512 + round512(n as u64 + 1) } else { 0 } }
pub fn finish(n: u64) -> u64 { (n + 1024).div_ceil(10240) * 10240 }
#[derive(Default)]
pub struct Accumulator {
    pub bytes: u64,
    links: std::collections::HashMap<(u64, u64), usize>,
}
impl Accumulator {
    pub fn add(&mut self, member: &[u8], kind: u8, size: u64, dev: u64, ino: u64, nlink: u64) {
        if kind == b's' { return; }
        self.bytes += 512 + long_extra(member.len());
        if matches!(kind, b'f' | b'l') && nlink > 1 {
            if let Some(first_len) = self.links.get(&(dev, ino)) {
                self.bytes += long_extra(*first_len);
                return;
            }
            self.links.insert((dev, ino), member.len());
        }
        if kind == b'f' { self.bytes += round512(size); }
        else if kind == b'l' { self.bytes += long_extra(size as usize); }
    }
}
pub fn excluded(member: &[u8], root: &[u8], external: bool) -> bool {
    // tar exclusion defaults: wildcards, no-anchored, wildcards-match-slash.
    // Literal root/component patterns match at any component boundary.
    let mut previous: Option<&[u8]> = None;
    for c in member.split(|b| *b == b'/') {
        if external && c.starts_with(b"Backup_") { return true; }
        let parent_matches = previous == Some(root);
        previous = Some(c);
        if !parent_matches { continue; }
        if external {
            if c.starts_with(b".") || [b"cache".as_slice(), b"QQ", b"Telegram"].contains(&c) { return true; }
        } else if [b".ota".as_slice(), b"cache", b"lib", b"code_cache", b"no_backup"].contains(&c) { return true; }
    }
    false
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn records_and_long_names() {
        assert_eq!(finish(512), 10240);
        assert_eq!(finish(9728), 20480);
        assert_eq!(long_extra(100), 0);
        assert_eq!(long_extra(101), 1024);
        assert_eq!(long_extra(512), 1536);
    }
    #[test]
    fn excludes_match_unanchored_tar_patterns() {
        assert!(excluded(b"pkg/cache/x", b"pkg", false));
        assert!(excluded(b"pkg/a/pkg/cache/x", b"pkg", false));
        assert!(!excluded(b"pkg/a/cache/x", b"pkg", false));
        assert!(excluded(b"pkg/a/Backup_x/y", b"pkg", true));
        assert!(excluded(b"pkg/.hidden/x", b"pkg", true));
        assert!(!excluded(b"pkg/a/.hidden/x", b"pkg", true));
        assert!(!excluded(b"pkg/cachex", b"pkg", false));
    }
    #[test]
    fn hardlink_longlink_and_special_members() {
        let mut a = Accumulator::default();
        a.add(&vec![b'x'; 101], b'f', 513, 1, 2, 2);
        assert_eq!(a.bytes, 2560);
        a.add(b"short", b'f', 513, 1, 2, 2);
        assert_eq!(a.bytes, 4096);
        a.add(b"link", b'l', 101, 1, 3, 1);
        assert_eq!(a.bytes, 5632);
        a.add(b"socket", b's', 0, 1, 4, 1);
        assert_eq!(a.bytes, 5632);
        a.add(b"fifo", b'p', 0, 1, 5, 1);
        a.add(b"device", b'c', 0, 1, 6, 1);
        assert_eq!(a.bytes, 6656);
    }
    #[test]
    fn fifo_hardlinks_each_keep_their_own_member_header() {
        let mut a = Accumulator::default();
        a.add(&vec![b'x'; 105], b'p', 0, 7, 11, 2);
        a.add(b"f", b'p', 0, 7, 11, 2);
        // FIFO entries are never entered in GNU tar's hardlink table:
        // long name record + first header + second header.
        assert_eq!(a.bytes, 2048);
    }
}
