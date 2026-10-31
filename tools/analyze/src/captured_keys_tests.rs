use super::*;
use crate::captured_raw_policy::Configuration;
use dm_analysis::policy_inputs::{HostCapture,PolicyRole};
use dm_preprocess::SourceProvider;
use std::{cell::RefCell,collections::BTreeMap,path::{Path,PathBuf}};
struct Original {
    bytes: BTreeMap<PathBuf, Vec<u8>>,
    acquired: RefCell<BTreeMap<PathBuf, dm_preprocess::AcquiredSource>>,
}
impl dm_preprocess::SourceProvider for Original {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("must use original acquired bytes".into())
    }
    fn acquired_source(&self, p: &Path) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        if !self.acquired.borrow().contains_key(p) {
            let bytes = self
                .bytes
                .get(p)
                .ok_or("missing original fixture file")?
                .clone();
            self.acquired.borrow_mut().insert(
                p.into(),
                dm_preprocess::AcquiredSource::from_original_bytes(bytes, ()),
            );
        }
        Ok(self.acquired.borrow().get(p).cloned())
    }
    fn source_acquisition(
        &self,
        p: &Path,
        t: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.acquired
            .borrow()
            .get(p)
            .filter(|s| s.lease().source_text().same_view(t))
            .cloned()
    }
}
fn inputs(extra: &[(&str, &str)], raw: bool) -> (PathBuf, PolicyInputs) {
    let root = std::env::current_dir()
        .unwrap()
        .join("native-keys-unit");
    let manifest = root.join("deepquarry.dme");
    let provider = Original {
        bytes: std::iter::once((manifest.clone(), b"/datum\n".to_vec()))
            .chain(
                extra
                    .iter()
                    .map(|(rel, text)| (root.join(rel), text.as_bytes().to_vec())),
            )
            .collect(),
        acquired: Default::default(),
    };
    let frontend = dm_tree::frontend::build(&manifest, &provider, &Default::default(), 1).unwrap();
    // The original provider issues the manifest acquisition used by include_order;
    // AnalyzeRaw must be separately present even when compiler bytes are equal.
    let manifest_source = provider.acquired_source(&manifest).unwrap().unwrap();
    let mut captures = vec![HostCapture::analyze_raw(
        Arc::new(manifest.clone()),
        PolicyRole::DmSource,
        manifest_source.lease().source_text().clone(),
    )];
    if raw {
        for (rel, _) in extra {
            let path = root.join(rel);
            let source = provider.acquired_source(&path).unwrap().unwrap();
            captures.push(HostCapture::analyze_raw(
                Arc::new(path),
                PolicyRole::DmSource,
                source.lease().source_text().clone(),
            ));
        }
    }
    (root, PolicyInputs::capture(&frontend, captures).unwrap())
}

fn raw(root:&Path,inputs:&PolicyInputs)->CapturedRawPolicy{CapturedRawPolicy::capture(root,inputs,Configuration::ProvenMissing).unwrap()}
#[test]
fn actual_io_mid_key_scan_is_not_a_partial_result_and_same_source_recovers(){
 let(root,inputs)=inputs(&[("code/a.dm","CAPABILITIES(/datum/a, op(\"real\"), extend(\"missing\"))\n")],true);
 let raw=raw(&root,&inputs);let keys=BorrowedKeys::capture(&raw,&inputs);
 let mut calls=0;let error=keys.scan(Budget::new(16*1024*1024).unwrap(),16*1024*1024,1000,||{calls+=1;if calls==12{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}).err().expect("actual operation must fail");
 assert!(matches!(error,PolicyFailure::Operational(ref e)if e.raw_os_error()==Some(1450)),"{error:?}");
 let recovered=keys.scan(Budget::new(16*1024*1024).unwrap(),16*1024*1024,1000,||Ok(())).unwrap();
 assert_eq!(recovered.run.sites.len(),1);assert_eq!(recovered.run.sites[0].rule,"unresolved_op");
}
#[test]
fn key_source_admission_refuses_before_result_and_same_input_is_unchanged(){
 let(root,inputs)=inputs(&[("code/a.dm","STAT(/datum/a, energy)\nCAPABILITIES(/datum/a, op(\"real\"), extend(\"missing\"))\n")],true);
 let raw=raw(&root,&inputs);let keys=BorrowedKeys::capture(&raw,&inputs);
 assert!(matches!(keys.scan(Budget::new(256).unwrap(),256,1000,||Ok(())),Err(PolicyFailure::Operational(_))));
 let run=keys.scan(Budget::new(16*1024*1024).unwrap(),16*1024*1024,1000,||Ok(())).unwrap();assert_eq!(run.run.sites.len(),1);
}
#[test]
fn requested_system_membership_keeps_original_own_field_and_empty_type_policy(){
 let source="/datum/system/base\n    var/inherited\n/datum/system/base/child\n    var/own\n/datum/system/empty\nSYSTEM_ACCESSOR(base/child, yes, nameof(own))\nSYSTEM_ACCESSOR(base/child, no, nameof(inherited))\nSYSTEM_ACCESSOR(empty, no, nameof(missing))\nSYSTEM_ACCESSOR(absent, no, nameof(missing))\n";
 let(root,inputs)=inputs(&[("code/a.dm",source)],true);let raw=raw(&root,&inputs);
 let run=BorrowedKeys::capture(&raw,&inputs).scan(Budget::new(16*1024*1024).unwrap(),16*1024*1024,1000,||Ok(())).unwrap();
 assert_eq!(run.run.sites.len(),3);assert!(run.run.sites[0].msg.contains("has no var `inherited`"));assert!(run.run.sites[1].msg.contains("has no var `missing`"));assert!(run.run.sites[2].msg.contains("no system type"));
}
#[test]
fn borrowed_system_candidate_run_matches_original_allocation_policy(){
 fn old(code:&str,system:&str)->bool{let plain=!system.is_empty()&&system.chars().all(|c|c.is_alphanumeric()||c=='_');if !plain{return crate::system_accessors_policy::system_types(system).iter().any(|t|code.contains(t))}for prefix in ["/datum/world_service/","/datum/system/"]{let mut from=0;while let Some(i)=code[from..].find(prefix){let start=from+i+prefix.len();let run:String=code[start..].chars().take_while(|c|c.is_alphanumeric()||*c=='_').collect();if run.starts_with(system){return true}from=start}}false}
 for code in ["/datum/system/x_long","/datum/system/éclair\n/datum/world_service/z","/datum/system/base/child","/datum/system/","unrelated"]{for system in ["x","é","base/child","","missing"]{let types=crate::system_accessors_policy::system_types(system);assert_eq!(old(code,system),crate::system_accessors_policy::file_mentions_system_with_types(code,system,&types),"{code:?} {system:?}");}}
}

#[cfg(feature="legacy-sem")]
#[test]
fn complete_six_rule_fixture_matches_original_registered_policy_rows_and_allow_use(){
 let fixture=PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("fixtures/sem__keys");
 let names=["code/modules/keys/ids.dm","code/modules/keys/systems.dm","code/modules/keys/things.dm","code/modules/unit_tests/t.dm"];
 let owned:Vec<_>=names.iter().map(|name|(*name,std::fs::read_to_string(fixture.join(name)).unwrap())).collect();
 let borrowed:Vec<_>=owned.iter().map(|(name,text)|(*name,text.as_str())).collect();
 let(root,inputs)=inputs(&borrowed,true);let raw=raw(&root,&inputs);
 let actual=BorrowedKeys::capture(&raw,&inputs).scan(Budget::new(64*1024*1024).unwrap(),64*1024*1024,10000,||Ok(())).unwrap();
 let engine=crate::run::Engine::new(crate::run::registry(),crate::run::Options{root:fixture,lints:vec!["sem/keys".into()],no_cache:true,raw:true,..Default::default()}).unwrap();
 let original=engine.run_one(engine.reg.lints.iter().find(|lint|lint.meta().name=="sem/keys").unwrap().as_ref());
 assert_eq!(actual.run.sites,original.run.sites);assert_eq!(actual.run.notes,original.run.notes);assert_eq!(actual.allow_used,original.allow_used);
 let meta=crate::keys_policy::metadata();let scope=raw.scopes.for_lint(meta.name,meta.group);
 let(failed,text)=crate::policy_judge::judge_report(meta,&scope,&raw.tree,&actual.run,&root,&None,true,|_,_,_|false,|_,_|false);
 assert_eq!(text,original.text);assert_eq!(failed,original.failed);
 assert_eq!(actual.run.sites.len(),16);assert_eq!(actual.allow_used.len(),1);
 let rules:std::collections::BTreeSet<_>=actual.run.sites.iter().map(|row|row.rule.as_str()).collect();assert_eq!(rules.len(),6);
}
