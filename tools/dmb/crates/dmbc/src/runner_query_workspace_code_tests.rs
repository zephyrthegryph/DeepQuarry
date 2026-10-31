//! Actual original workspace source loans, including eligible uncompiled code.
use super::*;
use dq_analyze::captured_reactive_reads::Failure;

#[test]
fn actual_generator_cli_test_domain_reads_hidden_code_without_promoting_code_only_coverage() {
 let root=fixture("workspace-generator-cli-test-domain",1);
 for folder in ["code/tests","code/.hidden","code/engine/_generated","maps"] {std::fs::create_dir_all(root.join(folder)).unwrap();}
 for(path,text)in[("code/tests/only.dm","/datum/test_only\n/datum/shared_with_hidden\n"),("code/.hidden/production.dm","/datum/shared_with_hidden\n"),("code/engine/_generated/ignored.dm","/datum/test_only\n"),("maps/production.dm","/datum/test_only\n")]{std::fs::write(root.join(path),text).unwrap();}
 let db=Arc::new(crate::query_db::QueryDb::default());let physical=Physical{reads:Mutex::new(BTreeMap::new())};let inputs=RecordingInputs::new(&physical,4_000_000_000);let front=frontend(&root,&inputs,&db);
 let discovery=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.clone()]}).unwrap());
 let capture=workspace_capture::capture(&front,&inputs,discovery,&root.join("missing.toml")).unwrap();let snap=snapshot(&front,&db,&inputs,&capture);let scope=snap.workspace_native_read().unwrap();let policy=dm_analysis::policy_inputs::PolicyInputs::capture(&front,[]).unwrap();let reads=physical.reads();
 let(paths,witness)=db.with_workspace_code_pages(&capture,&scope,|reader| {
  let mut paths=Vec::new();let traversal=reader.for_each_generator_test_file_completed(&policy,&mut|relative,views| {
   let text=views.raw()?;reader.budget().charge(relative.len()+text.len()+1024).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
   paths.push(relative.to_owned());Ok(true)
  })?;Ok((paths,traversal.into_witness()?.expect("completed actual generator test domain")))
 }).unwrap();
 assert!(paths.iter().any(|path|path=="code/.hidden/production.dm"));assert!(paths.iter().any(|path|path=="code/tests/only.dm"));
 assert!(!paths.iter().any(|path|path.starts_with("maps/")||path.starts_with("code/engine/_generated/")));
 assert!(witness.matches(&capture,&scope,&policy).unwrap());let mut backing=0;witness.visit_storage(|_,bytes|backing+=bytes);assert!(backing>0);
 let code=db.with_workspace_code_pages(&capture,&scope,|reader| {let mut paths=Vec::new();reader.for_each_code_file_completed(&policy,&mut|relative,_|{paths.push(relative.to_owned());Ok(true)})?.into_witness()?.expect("actual CODE_DM completion");Ok(paths)}).unwrap();
 assert!(!code.iter().any(|path|path=="code/.hidden/production.dm"));assert!(code.iter().any(|path|path=="code/engine/_generated/ignored.dm"));
 db.with_workspace_code_pages(&capture,&scope,|reader| {assert!(reader.for_each_generator_test_file_completed(&policy,&mut|_,_|Ok(false))?.into_witness()?.is_none());Ok(())}).unwrap();
 assert_eq!(physical.reads(),reads,"both domains loan the same already recorded source acquisitions");assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
 // A separate recorded acquisition is needed for a different discovery-root
 // contract; reusing the full walk would ask the same folder to change whether
 // it follows its root, which the recorder correctly rejects.
 let db=Arc::new(crate::query_db::QueryDb::default());let inputs=RecordingInputs::new(FileSystemInputs,4_000_000_000);let front=frontend(&root,&inputs,&db);
 let subset=Arc::new(workspace_discovery::discover(&inputs,DiscoveryContract{root:root.clone(),recursive_roots:vec![root.join("code/tests")]}).unwrap());
 let partial=workspace_capture::capture(&front,&inputs,subset,&root.join("missing.toml")).unwrap();let partial_snap=snapshot(&front,&db,&inputs,&partial);let partial_scope=partial_snap.workspace_native_read().unwrap();let mut entered=0;
 let policy=dm_analysis::policy_inputs::PolicyInputs::capture(&front,[]).unwrap();
 let result=db.with_workspace_code_pages(&partial,&partial_scope,|reader|reader.for_each_generator_test_file_completed(&policy,&mut|_,_|{entered+=1;Ok(true)})?.into_witness());
 assert!(result.is_err());assert_eq!(entered,0,"a genuine subtree cannot certify hidden production absence");
}

#[test]
fn actual_workspace_query_scope_registered_context_records_real_child_dependencies() {
 let root=fixture("workspace-query-scope-context",1);
 let db=Arc::new(crate::query_db::QueryDb::default());
 let inputs=RecordingInputs::new(FileSystemInputs,4_000_000_000);let front=frontend(&root,&inputs,&db);
 let capture=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&root.join("missing.toml")).unwrap();
 let snap=snapshot(&front,&db,&inputs,&capture);
 let scope=Arc::new(snap.workspace_native_read().unwrap().query_receipt(&mut |_|Ok(())).unwrap());
 let policy=Arc::new(dm_analysis::policy_inputs::PolicyInputs::capture(&front,[]).unwrap());
 let other=Arc::new(crate::query_db::QueryDb::default());let calls=Arc::new(AtomicUsize::new(0));
 let input=dm_query::Key::new(dm_query::Kind(800),1);let derived=dm_query::Key::new(dm_query::Kind(801),1);
 for graph in [&db,&other] {
  graph.db().define_input(input.kind,"scope-context-input");graph.db().set_input(input,9u64,9);
  let receipt=scope.clone();let capture=Arc::downgrade(&capture);let policy=Arc::downgrade(&policy);let calls=calls.clone();
  graph.db().define(derived.kind,"actual-workspace-scope-context",move |context,_| {
   let capture=capture.upgrade().ok_or(dm_query::QueryError::Missing(derived))?;
   let policy=policy.upgrade().ok_or(dm_query::QueryError::Missing(derived))?;
   let value:io::Result<Result<u64,String>>=receipt.with_context(context,&capture,&policy,|queries,guard,context| {
    assert!(guard.uses_queries(queries));calls.fetch_add(1,Ordering::Relaxed);
    let value=context.input::<u64>(input).map_err(|error|io::Error::other(format!("fixture child: {error:?}")))?;
    Ok(Ok(*value+1))
   });
   let value=value.map_err(|actual|dm_query::QueryError::operational(derived,actual))?
    .map_err(|reason|dm_query::QueryError::operational(derived,io::Error::other(reason)))?;
   Ok(dm_query::Outcome::new(value,value as u128,8))
  });
 }
 assert_eq!(*db.db().get::<u64>(derived,Arc::new(())).unwrap(),10);
 assert_eq!(calls.load(Ordering::Relaxed),1);
 assert!(db.db().dependants(&[input]).contains(&derived),"the SAME actual context records the child read");
 assert_eq!(*db.db().get::<u64>(derived,Arc::new(())).unwrap(),10);assert_eq!(calls.load(Ordering::Relaxed),1);
 let error=other.db().get::<u64>(derived,Arc::new(())).unwrap_err().into_operational().unwrap();
 assert!(error.to_string().contains("executing context differs"));assert_eq!(calls.load(Ordering::Relaxed),1);
 assert_eq!(other.db().stats(derived.kind).computed,0,"foreign context cannot publish a result");
}

#[test]
fn actual_workspace_query_scope_preserves_issued_frame_and_refuses_foreign_owners() {
 let root=fixture("workspace-query-scope",2);
 let db=Arc::new(crate::query_db::QueryDb::default());
 let physical=Physical{reads:Mutex::new(BTreeMap::new())};
 let inputs=RecordingInputs::new(&physical,4_000_000_000);
 let front=frontend(&root,&inputs,&db);
 let capture=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&root.join("missing.toml")).unwrap();
 let snap=snapshot(&front,&db,&inputs,&capture);
 let guard=snap.workspace_native_read().unwrap();
 let policy=dm_analysis::policy_inputs::PolicyInputs::capture(&front,[]).unwrap();
 let counts=|| (Arc::weak_count(snap.source_mapping.as_ref().unwrap()),Arc::weak_count(&db),Arc::weak_count(&capture));
 let before=counts();
 let denied=guard.query_receipt(&mut |_|Err(io::Error::from_raw_os_error(1450))).err().unwrap();
 assert_eq!(denied.raw_os_error(),Some(1450));
 assert_eq!(counts(),before,"failed admission cannot create weak backing");
 let mut admitted=0;
 let receipt=guard.query_receipt(&mut |bytes|{admitted+=bytes;Ok(())}).unwrap();
 assert_eq!(admitted,super::super::workspace_native_guard::WorkspaceQueryScope::retained_charge().unwrap());
 assert!(admitted>std::mem::size_of_val(&receipt));
 let mut storage=Vec::new();receipt.visit_storage(|owner,address,bytes|storage.push((owner,address,bytes)));
 assert_eq!(storage.len(),3);assert!(storage.iter().all(|(_,address,bytes)|*address!=0&&*bytes>0));
 let reads=physical.reads();
 let actual:io::Result<Result<usize,String>>=receipt.with_guard(&db,&capture,&policy,|loan|{assert!(loan.uses_queries(&db));capture.require_scope(loan)?;Ok(Ok(17))});
 assert_eq!(actual.unwrap().unwrap(),17);assert_eq!(physical.reads(),reads,"receipt reborrow cannot acquire sources");
 let mut entered=0;
 let wrong=crate::query_db::QueryDb::default();
 let result:io::Result<Result<(),String>>=receipt.with_guard(&wrong,&capture,&policy,|_|{entered+=1;Ok(Ok(()))});
 assert!(result.is_err());assert_eq!(entered,0);
 let foreign_recording=RecordingInputs::new(&physical,4_000_000_000);
 let foreign_front=frontend(&root,&foreign_recording,&db);
 let foreign=dm_analysis::policy_inputs::PolicyInputs::capture(&foreign_front,[]).unwrap();
 let result:io::Result<Result<(),String>>=receipt.with_guard(&db,&capture,&foreign,|_|{entered+=1;Ok(Ok(()))});
 assert!(result.is_err());assert_eq!(entered,0,"equal text cannot promote a foreign original mapping");
 let other=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&root.join("other.toml")).unwrap();
 let result:io::Result<Result<(),String>>=receipt.with_guard(&db,&other,&policy,|_|{entered+=1;Ok(Ok(()))});
 assert!(result.is_err());assert_eq!(entered,0);
 let actual:io::Result<Result<(),String>>=receipt.with_guard(&db,&capture,&policy,|_|Err(io::Error::from_raw_os_error(1450)));
 assert_eq!(actual.unwrap_err().raw_os_error(),Some(1450));
 let token=crate::daemon::control::Cancellation::default();
 let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));
 token.cancel();
 let cancelled:io::Result<Result<(),String>>=receipt.with_guard(&db,&capture,&policy,|_|{entered+=1;Ok(Ok(()))});
 assert_eq!(cancelled.unwrap_err().kind(),io::ErrorKind::Interrupted);assert_eq!(entered,0);drop(binding);
 let healthy:io::Result<Result<(),String>>=receipt.with_guard(&db,&capture,&policy,|_|Ok(Ok(())));assert!(healthy.unwrap().is_ok());
 let semantic:io::Result<Result<(),String>>=receipt.with_guard(&db,&capture,&policy,|_|Ok(Err("source refusal".into())));
 assert_eq!(semantic.unwrap().unwrap_err(),"source refusal");
 let token=crate::daemon::control::Cancellation::default();
 let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));
 let semantic:io::Result<Result<(),String>>=receipt.with_guard(&db,&capture,&policy,|_|{token.cancel();Ok(Err("late semantic refusal".into()))});
 assert_eq!(semantic.unwrap_err().kind(),io::ErrorKind::Interrupted);drop(binding);
 let token=crate::daemon::control::Cancellation::default();
 let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));
 let actual:io::Result<Result<(),String>>=receipt.with_guard(&db,&capture,&policy,|_|{token.cancel();Err(io::Error::from_raw_os_error(1450))});
 assert_eq!(actual.unwrap_err().raw_os_error(),Some(1450));drop(binding);
}

#[test]
fn actual_workspace_query_scope_cannot_keep_expired_source_owners_alive() {
 fn expired()->super::super::workspace_native_guard::WorkspaceQueryScope {
  let root=fixture("workspace-query-scope-expired",1);
  let db=Arc::new(crate::query_db::QueryDb::default());
  let inputs=RecordingInputs::new(FileSystemInputs,4_000_000_000);
  let front=frontend(&root,&inputs,&db);
  let capture=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&root.join("missing.toml")).unwrap();
  let snap=snapshot(&front,&db,&inputs,&capture);
  snap.workspace_native_read().unwrap().query_receipt(&mut |_|Ok(())).unwrap()
 }
 let receipt=expired();
 let root=fixture("workspace-query-scope-current",1);
 let db=Arc::new(crate::query_db::QueryDb::default());
 let inputs=RecordingInputs::new(FileSystemInputs,4_000_000_000);let front=frontend(&root,&inputs,&db);
 let capture=workspace_capture::capture(&front,&inputs,discover(&root,&inputs),&root.join("missing.toml")).unwrap();
 let policy=dm_analysis::policy_inputs::PolicyInputs::capture(&front,[]).unwrap();let mut entered=false;
 let result:io::Result<Result<(),String>>=receipt.with_guard(&db,&capture,&policy,|_|{entered=true;Ok(Ok(()))});
 assert_eq!(result.unwrap_err().kind(),io::ErrorKind::NotFound);assert!(!entered);
}

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
