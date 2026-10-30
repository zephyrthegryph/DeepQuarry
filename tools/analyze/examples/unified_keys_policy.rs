//! Frozen original marker-key implementation against the shared policy.
//! This is a legacy oracle for extraction, not native/full-workspace coverage.
pub use dq_analyze::{lint,tree};
pub use dq_analyze::sem::decls;
#[path="support/keys_original/keys.rs"]pub mod old_keys;
pub mod sem {pub use crate::decls;pub use crate::old_keys as keys;pub use dq_analyze::sem::gen;}
#[path="support/keys_original/lint.rs"]mod old_lint;
use dq_analyze::run::{Engine,Options};
fn main(){
 let root=std::env::args().nth(1).unwrap_or_else(||"tools/analyze/fixtures/sem__keys".into());
 let options=Options{root:std::fs::canonicalize(root).unwrap(),lints:vec!["sem/keys".into()],no_cache:true,raw:true,..Default::default()};
 let candidate=Engine::new(dq_analyze::run::registry(),options.clone()).unwrap();
 let decls=decls::Decls::get(&candidate.tree);
 let old=old_keys::KeyIndex::build(&decls);let shared=dq_analyze::sem::keys::KeyIndex::build(&decls);
 assert_eq!(format!("{old:?}"),format!("{shared:?}"),"complete key tables and duplicate source order");
 assert!(!old.stats.is_empty());assert!(!old.ops.is_empty());assert!(!old.duplicates.is_empty());
 let mut registry=lint::Registry::default();old_lint::register(&mut registry);
 let original=Engine::new(registry,options).unwrap();
 let a=original.run_one(original.reg.lints.first().unwrap().as_ref());
 let c=candidate.run_one(candidate.reg.lints.iter().find(|lint|lint.meta().name=="sem/keys").unwrap().as_ref());
 assert_eq!(a.run.sites,c.run.sites,"all original finding text, source order and fields");
 assert_eq!(a.run.notes,c.run.notes);assert_eq!(a.allow_used,c.allow_used);assert_eq!(a.text,c.text);assert_eq!(a.failed,c.failed);
 assert!(a.internal_error.is_none());assert!(c.internal_error.is_none());assert!(!a.allow_used.is_empty());
 let rules:std::collections::BTreeSet<_>=a.run.sites.iter().map(|s|s.rule.as_str()).collect();
 for name in ["unresolved_id","unresolved_op","unresolved_capability","text_source","duplicate_declaration","accessor_var"]{assert!(rules.contains(name),"positive whole-policy coverage {name}");}
 println!("shared keys policy matches all {} sites, {} annotation uses, complete tables and full report; native admission not enabled",a.run.sites.len(),a.allow_used.len());
}
