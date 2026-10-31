//! Actual original workspace source loans, including eligible uncompiled code.
use super::*;
use dq_analyze::captured_reactive_reads::Failure;

#[test]
fn original_workspace_code_pages_cover_uncompiled_normalized_sources_without_reread_or_body_demand(){
 let root=fixture("workspace-code-original-257",257);
 std::fs::write(root.join("code/0140.dm"),b"\xef\xbb\xbf// original comment\r\nTRACKED(/datum/ghost,state)\rset_state(\"quoted\")\r\n// \xff\r\n").unwrap();
 std::fs::create_dir(root.join("code/.hidden")).unwrap();std::fs::write(root.join("code/.hidden/skip.dm"),b"set_hidden(1)\n").unwrap();
 let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new())};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);
 let capture=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&root.join("missing.toml")).unwrap();let snap=snapshot(&front,&db,&inputs,&capture);let scope=snap.workspace_native_read().unwrap();let before=physical.reads();
 let policy_inputs=dm_analysis::policy_inputs::PolicyInputs::capture(&front,[]).unwrap();
 let(rows,witness)=db.with_workspace_code_pages(&capture,&scope,|reader|{
  reader.require_policy_inputs(&policy_inputs)?;assert_eq!(reader.root(),root.as_path());assert_eq!(reader.configuration().0,root.join("missing.toml"));let mut out=Vec::new();
  let traversal=reader.for_each_code_file_completed(&policy_inputs,&mut|relative,views|{
   let raw=views.raw()?;let marker=views.marker()?;let code=views.code()?;
   assert!(!relative.contains("/.hidden/"));
   reader.budget().charge(relative.len().checked_add(raw.len()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(512)).unwrap()).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   if relative=="code/0140.dm"{assert!(raw.starts_with('\u{feff}'));assert!(!raw.contains('\r'));assert!(raw.contains('\u{fffd}'));assert!(marker.contains("TRACKED(/datum/ghost,state)"));assert!(!marker.contains("original comment"));assert!(code.text.contains("set_state("));assert!(!code.text.contains("quoted"));}
   out.push((relative.to_owned(),raw.to_owned()));Ok(true)
  })?;let witness=traversal.into_witness()?.expect("full fold cannot stop early");Ok((out,witness))
 }).unwrap();assert!(witness.matches(&capture,&scope,&policy_inputs).unwrap());assert_eq!(rows.len(),257);assert!(rows.iter().any(|(path,_)|path=="code/0140.dm"));assert_eq!(physical.reads(),before,"every query source comes from the recorded original acquisition, including uncompiled files");assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0,"raw code views cannot demand or manufacture compiled bodies");
 let count=db.with_workspace_code_pages(&capture,&scope,|reader|{let mut count=0;assert!(reader.for_each_code_file_completed(&policy_inputs,&mut|_,_|{count+=1;Ok(false)})?.into_witness()?.is_none());Ok(count)}).unwrap();assert_eq!(count,1,"false stops the requested-name search globally");assert_eq!(physical.reads(),before);
 // A distinct current frontend has its own acquisition recorder; rebuilding
 // on the primary recorder would retire the original lease under test.
 let foreign_recording=RecordingInputs::new(&physical,4_000_000_000);let foreign_front=frontend(&root,&foreign_recording,&db);let foreign_inputs=dm_analysis::policy_inputs::PolicyInputs::capture(&foreign_front,[]).unwrap();let mut foreign_visits=0;assert!(db.with_workspace_code_pages(&capture,&scope,|reader|reader.for_each_code_file_completed(&foreign_inputs,&mut|_,_|{foreign_visits+=1;Ok(true)})?.into_witness()).is_err());assert_eq!(foreign_visits,0,"foreign compiled mapping cannot start or seal a raw traversal");
 let wrong=crate::query_db::QueryDb::default();assert!(matches!(wrong.with_workspace_code_pages(&capture,&scope,|_|Ok(())),Err(Failure::Operational(_))));
 let other=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&root.join("other-missing.toml")).unwrap();let entered=std::cell::Cell::new(false);assert!(matches!(db.with_workspace_code_pages(&other,&scope,|_|{entered.set(true);Ok(())}),Err(Failure::Operational(_))));assert!(!entered.get(),"foreign config/discovery capture cannot enter the original fold");let other_snap=snapshot(&front,&db,&inputs,&other);let other_scope=other_snap.workspace_native_read().unwrap();assert!(!witness.matches(&other,&other_scope,&policy_inputs).unwrap(),"same compiled frame cannot promote another workspace/config/discovery owner");
}

#[test]
fn original_workspace_late_code_io_and_quota_return_no_completed_fold_and_same_source_recovers(){
 let root=fixture("workspace-code-late-operation",257);let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new())};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);let capture=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&root.join("missing.toml")).unwrap();let snap=snapshot(&front,&db,&inputs,&capture);let scope=snap.workspace_native_read().unwrap();let before=physical.reads();let policy_inputs=dm_analysis::policy_inputs::PolicyInputs::capture(&front,[]).unwrap();
 for actual_io in[false,true]{let mut visited=0;let result=db.with_workspace_code_pages(&capture,&scope,|reader|{reader.for_each_code_file_completed(&policy_inputs,&mut|_,views|{visited+=1;let _=views.code()?;if visited==141{reader.budget().deny();if actual_io{return Err(Failure::Operational(io::Error::from_raw_os_error(1450)))}}Ok(true)})?.into_witness()});assert_eq!(visited,141,"failure is inside the second real original-source page");let failure=result.err().expect("no completed fold after actual later-page operation failure");if actual_io{assert!(matches!(failure,Failure::Operational(ref error)if error.raw_os_error()==Some(1450)),"first actual IO precedes final quota checks")}else{assert!(matches!(failure,Failure::Operational(ref error)if error.kind()==io::ErrorKind::OutOfMemory))}}
 let count=db.with_workspace_code_pages(&capture,&scope,|reader|{let mut count=0;assert!(reader.for_each_code_file(&mut|_,views|{let _=views.code()?;count+=1;Ok(true)})?);Ok(count)}).unwrap();assert_eq!(count,257);assert_eq!(physical.reads(),before);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
}

#[test]
fn original_code_completion_requires_recursive_typed_unfiltered_selector_coverage(){
 let root=fixture("workspace-code-discovery-contract",2);std::fs::create_dir(root.join("code/sub")).unwrap();std::fs::write(root.join("code/sub/nested.dm"),b"TRACKED(/datum/nested,state)\n").unwrap();
 // A normal flat folder fact is a weaker role and cannot be promoted to
 // recursive typed discovery, even when it names the correct code root.
 struct Flat;
 impl SnapshotProvider for Flat{
  fn stamp(&self,path:&Path)->io::Result<Stamp>{FileSystemInputs.stamp(path)}
  fn read(&self,path:&Path)->io::Result<(Stamp,Vec<u8>)>{FileSystemInputs.read(path)}
  fn list(&self,path:&Path)->io::Result<FolderListing>{FileSystemInputs.list(path)}
 }
 let flat=RecordingInputs::new(Flat,4_000_000_000);flat.record_search_folder(&root.join("code")).unwrap();assert!(flat.snapshot().unwrap().folders().contains_key(&dm_preprocess::regions::canonical_path(&root.join("code"))));
 assert!(workspace_discovery::discover(&flat,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code")]}).is_err(),"nonrecursive folder evidence cannot mint the typed recursive receipt");
 // Generated-output exclusions affect ordinary membership facts, never the
 // typed directory observations used by the actual discovery selector.
 let generated=crate::input_snapshot::GeneratedOutputInputs::new(FileSystemInputs,[root.join("code/0001.dm")]);let recorded=RecordingInputs::new(generated,4_000_000_000);recorded.record_search_folder(&root.join("code")).unwrap();let facts=recorded.snapshot().unwrap();let FolderListing::Present(names)=facts.folders().get(&dm_preprocess::regions::canonical_path(&root.join("code"))).unwrap()else{panic!("actual folder exists")};assert!(!names.iter().any(|name|name=="0001.dm"));
 let full=discover(&root,&recorded);assert_eq!(full.files().len(),3,"actual recursive .dm selector includes nested and membership-filtered originals");let mut admitted=0;assert!(full.covers_code_dm(&mut|bytes|{admitted+=bytes;Ok(())}).unwrap());assert!(admitted>0);
 // The same current compiled frame plus an honestly completed subtree receipt
 // remains insufficient for complete CODE_DM policy data.
 let db=Arc::new(crate::query_db::QueryDb::default());let inputs=RecordingInputs::new(FileSystemInputs,4_000_000_000);let front=frontend(&root,&inputs,&db);let subset=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code/sub")]}).unwrap());
 let capture=workspace_capture::capture(&front,&inputs,subset,&root.join("missing.toml")).unwrap();let snap=snapshot(&front,&db,&inputs,&capture);let scope=snap.workspace_native_read().unwrap();let policy_inputs=dm_analysis::policy_inputs::PolicyInputs::capture(&front,[]).unwrap();let mut visits=0;
 let result=db.with_workspace_code_pages(&capture,&scope,|reader|reader.for_each_code_file_completed(&policy_inputs,&mut|_,_|{visits+=1;Ok(true)})?.into_witness());assert!(matches!(result,Err(Failure::Unsupported(_))));assert_eq!(visits,0,"subset evidence is rejected before any completion callback");
 let count=db.with_workspace_code_pages(&capture,&scope,|reader|{let mut count=0;assert!(reader.for_each_code_file(&mut|_,_|{count+=1;Ok(true)})?);Ok(count)}).unwrap();assert_eq!(count,1,"data-only scoped searches retain their original honest scope");
}
