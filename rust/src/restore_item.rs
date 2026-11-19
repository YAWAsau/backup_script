//! Shared restore classification. Identity is never inferred from localized UI text.
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum RemoteItemKind { App, MediaArchive, MediaAll, Wifi, Messages, Calls }
pub fn remote_item_kind(name:&str)->RemoteItemKind {
    match name {
        "wifi"=>RemoteItemKind::Wifi,"Media"=>RemoteItemKind::MediaAll,
        "@telephony:messages"=>RemoteItemKind::Messages,"@telephony:calls"=>RemoteItemKind::Calls,
        _ if archive_stem(name).is_some()=>RemoteItemKind::MediaArchive,
        _=>RemoteItemKind::App,
    }
}
pub fn archive_stem(name:&str)->Option<&str> {
    [".tar.zst",".tar.gz",".tar.bz2",".tar.xz",".tar.lz4",".tar.lzma",".tar.lzo",".tar"].iter().find_map(|ext|name.strip_suffix(ext))
}
pub fn remote_apk_supported(name:&str)->bool {remote_item_kind(name)==RemoteItemKind::App}
// The downloader currently publishes only these formats. Classification of legacy
// formats must not silently extend the execution protocol.
pub fn downloadable_media_stem(name:&str)->Option<&str>{name.strip_suffix(".tar.zst").or_else(||name.strip_suffix(".tar"))}
// Old local lists accepted tar-containing filenames; keep them visible for repair.
pub fn catalog_media(name:&str)->bool{archive_stem(name).is_some()||name.contains(".tar")}
#[cfg(test)] mod tests {
    use super::*;
    #[test] fn classifications_and_legacy_formats(){
        for name in ["wifi","Media","@telephony:messages","@telephony:calls","相片.tar","相片.tar.zst","相片.tar.gz"]{assert!(!remote_apk_supported(name));}
        assert!(remote_apk_supported("App"));assert_eq!(archive_stem("相片.tar.zst"),Some("相片"));
        assert!(downloadable_media_stem("相片.tar.gz").is_none());assert!(archive_stem("notes.tar.backup").is_none());
    }
}
