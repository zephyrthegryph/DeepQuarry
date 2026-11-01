//! Whole immutable original keys oracle over the same checked-in initial bytes.
#[cfg(all(feature="legacy-sem",feature="unified-oracle"))]
#[path="../fixtures/native-keys/fixture.rs"]mod fixture;
#[cfg(all(feature="legacy-sem",feature="unified-oracle"))]
#[path="../../dmb/shared/test_scratch.rs"]mod test_scratch;
#[cfg(all(feature="legacy-sem",feature="unified-oracle"))]
fn main()->Result<(),Box<dyn std::error::Error>>{
 let case=std::env::args().nth(1).ok_or("expected basic|configured|order|bom|invalid_manifest")?;let files=fixture::files(&case).ok_or("unknown keys case")?;let root=test_scratch::dir(&format!("keys-original-{case}"));
 for(relative,bytes)in files{let path=root.join(relative);std::fs::create_dir_all(path.parent().ok_or("fixture parent absent")?)?;std::fs::write(path,bytes)?;}
 let output=dq_analyze::keys_original_reference::scan(&root,&case)?;println!("OLD_KEYS_FULL={output}");Ok(())
}
#[cfg(not(all(feature="legacy-sem",feature="unified-oracle")))]
fn main(){panic!("unified_keys_original requires legacy-sem and unified-oracle")}
