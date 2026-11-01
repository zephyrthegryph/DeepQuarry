//! Whole immutable original check_grep policy, including original semantic
//! exemptions/custom report. No native rows, source stubs, filtered diagnostics,
//! baseline filtering or substituted semantic source owner are supplied.
pub use dq_analyze::{baseline,lint,parity,scopes,tree,pat,pat_match,util,raw_marker_policy,incr,dm,allow};
#[path="support/check_grep_original/sem.rs"]pub mod sem;
#[path="support/check_grep_original/mod.rs"]mod original;
#[path="../fixtures/native-check-grep/fixture.rs"]mod fixture;
#[path="../../dmb/shared/test_scratch.rs"]mod test_scratch;
use std::io::Write;
fn main()->Result<(),Box<dyn std::error::Error>>{
 use sha1::Digest as _;
 assert_eq!(<[u8;20]>::from(sha1::Sha1::digest(include_bytes!("support/check_grep_original/mod.rs"))),[113,58,134,145,222,172,237,230,74,190,137,150,121,82,10,28,66,249,152,216],"immutable original tools/analyze/src/lints/check_grep/mod.rs changed");
 assert_eq!(<[u8;20]>::from(sha1::Sha1::digest(include_bytes!("support/check_grep_original/framework.rs"))),[203,232,24,228,109,110,113,188,137,243,195,255,135,104,197,254,150,30,104,192],"immutable original tools/analyze/src/lints/check_grep/framework.rs changed");
 assert_eq!(<[u8;20]>::from(sha1::Sha1::digest(include_bytes!("support/check_grep_original/parts_code_a.rs"))),[69,55,192,3,81,35,135,49,26,61,63,183,89,100,209,241,132,184,118,229],"immutable original tools/analyze/src/lints/check_grep/parts_code_a.rs changed");
 assert_eq!(<[u8;20]>::from(sha1::Sha1::digest(include_bytes!("support/check_grep_original/parts_code_b.rs"))),[154,220,249,243,39,137,103,75,41,112,43,28,56,35,237,230,35,101,4,143],"immutable original tools/analyze/src/lints/check_grep/parts_code_b.rs changed");
 assert_eq!(<[u8;20]>::from(sha1::Sha1::digest(include_bytes!("support/check_grep_original/parts_maps.rs"))),[105,197,183,150,251,165,188,229,213,125,248,78,45,226,48,23,6,156,220,51],"immutable original tools/analyze/src/lints/check_grep/parts_maps.rs changed");
 assert_eq!(<[u8;20]>::from(sha1::Sha1::digest(include_bytes!("support/check_grep_original/parts_pcre.rs"))),[247,233,250,180,251,230,219,127,136,66,39,135,45,239,161,182,22,48,226,206],"immutable original tools/analyze/src/lints/check_grep/parts_pcre.rs changed");
 assert_eq!(<[u8;20]>::from(sha1::Sha1::digest(include_bytes!("support/check_grep_original/tags.rs"))),[65,235,236,50,180,40,37,107,170,108,195,65,198,147,175,137,188,156,38,50],"immutable original tools/analyze/src/lints/check_grep/tags.rs changed");
 assert_eq!(<[u8;20]>::from(sha1::Sha1::digest(include_bytes!("support/check_grep_original/semantic_checks.rs"))),[228,2,199,176,44,133,147,67,192,30,185,90,139,65,110,251,99,69,41,152],"immutable original tools/analyze/src/sem/checks.rs changed");

 let case=std::env::args().nth(1).ok_or("expected basic, configured or lossy")?;
 let root=test_scratch::dir("immutable-whole-check-grep");
 for(relative,bytes)in fixture::files(&case)?{let path=root.join(relative);std::fs::create_dir_all(path.parent().ok_or("fixture parent absent")?)?;std::fs::write(path,fixture::source_bytes(&case,relative,bytes))?;}
 dq_analyze::sem::incremental::disable_capture();
 let mut registry=lint::Registry::default();original::register(&mut registry);
 let engine=dq_analyze::run::Engine::new(registry,dq_analyze::run::Options{root:root.clone(),lints:vec!["check_grep".into()],no_cache:true,raw:true,..Default::default()})?;
 let lint=engine.reg.find("check_grep").ok_or("immutable original policy not registered")?;let scope=engine.scopes.for_lint(lint.meta().name,lint.meta().group);let cx=lint::Cx{tree:&engine.tree,meta:lint.meta(),scope:&scope};
 let semantic=cx.sem().ok_or("actual complete original semantic preparation absent")?;
 if !semantic.errors.is_empty(){return Err(format!("actual original semantic preparation failed: {:?}",semantic.errors).into())}
 let(run,allow_used,_timing)=engine.scan(lint);let(failed,report)=engine.judge(lint,&run);
 let value=serde_json::json!({"case":case,"report":report,"failed":failed,"sites":run.sites,"notes":run.notes,"allow_used":allow_used});
 let mut output=std::io::stdout().lock();write!(output,"OLD_CHECK_GREP_FULL={value}\n")?;Ok(())
}
