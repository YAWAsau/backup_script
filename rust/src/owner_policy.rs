//! Shared ownership mapping for application data repair and its verifier.
pub fn mapped(target: u32, previous: u32, uid: u32, gid: u32,
              root: bool, cache: bool, api: i32) -> (u32, u32) {
    if uid != previous && uid != target { return (uid, gid); }
    let app = target % 100000;
    let (root_gid, cache_gid) = if api >= 33 && (20000..=29999).contains(&app) {
        (9999, target)
    } else if api >= 37 && (30000..=39999).contains(&app) {
        (target, target + 30000)
    } else if api >= 26 && (10000..=19999).contains(&app) {
        (target, target + 10000)
    } else { (target, target) };
    (target, if root { root_gid } else if cache { cache_gid } else { target })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn remaps_app_and_cache_but_preserves_foreign_owner() {
        assert_eq!(mapped(10403,10631,0,0,false,false,37),(0,0));
        assert_eq!(mapped(10403,10631,10631,10631,false,false,37),(10403,10403));
        assert_eq!(mapped(10403,10631,10403,10631,false,true,37),(10403,20403));
        assert_eq!(mapped(22000,10631,10631,10631,true,false,37),(22000,9999));
        assert_eq!(mapped(32000,10631,10631,10631,false,true,37),(32000,62000));
        assert_eq!(mapped(10403,10631,1000,1000,true,false,37),(1000,1000));
    }
}
