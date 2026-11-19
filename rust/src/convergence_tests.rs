use super::*;
#[test] fn collected_manifest_matches_streaming_including_cache_rows(){
    let root=env::temp_dir().join(format!("manifest-writer-{}",std::process::id()));fs::create_dir_all(root.join("cache")).unwrap();fs::create_dir_all(root.join("code_cache")).unwrap();
    let path=root.to_str().unwrap();let output=root.join("manifest");
    let mut captured=Vec::new();
    let mut streamed=BufWriter::new(File::create(&output).unwrap());
    for entry in ["user","data","media"] {
        assert_eq!(write_presize_manifest_entry(&mut captured,"org.test\tapp",entry,path),write_presize_manifest_entry(&mut streamed,"org.test\tapp",entry,path));
    }
    captured.finish().unwrap();streamed.flush().unwrap();
    assert_eq!(captured.len(),7);
    assert_eq!(fs::read_to_string(&output).unwrap(),captured.iter().map(|r|format!("{}\t{}\t{}\n",r[0],r[1],r[2])).collect::<String>());
    fs::remove_dir_all(root).unwrap();
}
#[test] fn full_scope_is_shared_and_apk_rows_are_empty(){
    assert_eq!(presize_enabled_entries("true",false,"pkg"),["data","obb","media","user","user_de"]);
    assert!(presize_enabled_entries("false",false,"pkg").is_empty());
    assert!(presize_enabled_entries("true",true,"pkg").is_empty());
    assert!(presize_enabled_entries("true",false,"bin.mt.plus").is_empty());
    assert_eq!(full_dirsize_enabled_entries("true"),["user","user_de","data","obb","media"]);
}
#[test] fn conservative_read_plan_preserves_unknown_sizes_and_order(){
    let root=env::temp_dir().join(format!("converge-read-plan-{}",std::process::id()));fs::create_dir_all(&root).unwrap();
    let selected=root.join("selected");let sizes=root.join("sizes");let output=root.join("output");
    fs::write(&selected,"App\tpkg\t0\nAPK\tapk.pkg\t1\nMT\tbin.mt.plus\t0\n").unwrap();
    fs::write(&sizes,"pkg\tdata\t0\npkg\tuser\tunknown\n").unwrap();
    assert_eq!(conservative_read_plan(selected.to_str().unwrap(),sizes.to_str().unwrap(),output.to_str().unwrap(),"true",true,|_,e|matches!(e,"data"|"user"|"user_de")),0);
    assert_eq!(fs::read_to_string(&output).unwrap(),"App\tpkg\tdata\tlocal_entry_possible\t0\nApp\tpkg\tuser\tlocal_size_uncertain\tunknown\nApp\tpkg\tuser_de\tlocal_size_missing\t\n");
    fs::remove_dir_all(root).unwrap();
}
