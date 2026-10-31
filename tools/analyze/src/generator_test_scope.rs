//! Existing generator test-only scope, shared without a legacy model dependency.
pub const TEST_ONLY_DIRS: &[&str] = &["code/tests/", "code/modules/unit_tests/"];

/// The guard a generator wraps test-only declarations in.
pub const TEST_GUARD: &str = "#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)";

/// Whether a source file is compiled only in a test build, so whatever a generator writes for it must sit inside [`TEST_GUARD`].
pub fn test_only(rel: &str) -> bool {
    TEST_ONLY_DIRS.iter().any(|d| rel.starts_with(d))
}

/// The actual legacy generator CLI loads this lint's roots. Tree::load walks
/// those roots without Select's hidden-path filter; retain that exact domain.
pub fn cli_source_lint() -> &'static str { crate::keys_policy::metadata().name }
pub fn cli_source_roots() -> &'static [(&'static str, &'static str)] {
    crate::keys_policy::metadata().select.roots
}
pub fn cli_test_source(relative: &str) -> bool {
    crate::tree::Select { roots: cli_source_roots(), hidden: true }.matches_path(relative)
        && TestTypeCollector::eligible(relative)
}

pub(crate) fn defined_type(line: &str) -> Option<&str> {
    if !line.starts_with('/') || line.starts_with("//") {
        return None;
    }
    let end = line
        .find(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == '/'))
        .unwrap_or(line.len());
    let mut path = line[..end].trim_end_matches('/');
    for kw in ["/var/", "/proc/", "/verb/"] {
        if let Some(i) = path.find(kw) {
            path = &path[..i];
        }
    }
    if line[end..].trim_start().starts_with('(') {
        path = path.rsplit_once('/').map(|(a, _)| a).unwrap_or(path);
    }
    (path.len() > 1).then_some(path)
}


/// Source-free exact test-minus-production fold. File coverage remains the
/// caller's discovery obligation; CODE_DM completion alone is not all-DM proof.
#[derive(Default)]pub struct TestTypeCollector{test:std::collections::BTreeSet<String>,production:std::collections::HashSet<String>}
impl TestTypeCollector{
 pub(crate) fn eligible(relative:&str)->bool{relative.ends_with(".dm")&&!relative.starts_with("code/engine/_generated")&&!relative.starts_with("code/_generated/")}
 pub(crate) fn insert_owned(&mut self,is_test:bool,name:String){if is_test{self.test.insert(name);}else{self.production.insert(name);}}
 pub fn observe<C:crate::key_policy_control::Control>(&mut self,relative:&str,text:&str,control:&mut C)->Result<(),C::Error>{control.checkpoint()?;if !Self::eligible(relative){return Ok(())}let is_test=test_only(relative);for line in text.lines(){control.checkpoint()?;if let Some(name)=defined_type(line){if (is_test&&self.test.contains(name))||(!is_test&&self.production.contains(name)){continue}crate::key_policy_control::reserve(control,||name.len().checked_mul(4).and_then(|n|n.checked_add(1024)))?;self.insert_owned(is_test,crate::key_policy_control::own(control,name)?);}}control.checkpoint()}
 pub fn finish(mut self)->std::collections::BTreeSet<String>{self.test.retain(|name|!self.production.contains(name));self.test}
}

#[cfg(all(test,feature="legacy-sem"))]
mod cli_domain_tests {
 use super::*;
 #[test]
 fn actual_generator_cli_tree_domain_includes_hidden_code_but_not_other_lint_roots() {
  let root=std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/generator-cli-scope");
  let engine=crate::run::Engine::new(crate::run::registry(),crate::run::Options {
   root:root.clone(),lints:vec![cli_source_lint().to_owned()],raw:true,no_cache:true,..Default::default()
  }).unwrap();
  let paths=engine.tree.files.iter().map(|f|f.rel.as_str()).collect::<Vec<_>>();
  assert!(paths.contains(&"code/.hidden/production.dm"));assert!(!paths.contains(&"maps/production.dm"));
  let types=crate::sem::gen::test_only_types(&engine.tree);
  assert_eq!(types,std::collections::BTreeSet::from(["/datum/test_only".to_owned()]));
  for file in &engine.tree.files {
   assert_eq!(cli_test_source(&file.rel),TestTypeCollector::eligible(&file.rel));
  }
  assert!(!crate::tree::CODE_DM.matches_path("code/.hidden/production.dm"));
  assert!(cli_test_source("code/.hidden/production.dm"));
  assert!(!cli_test_source("code/engine/_generated/ignored.dm"));
  assert!(!cli_test_source("code/_generated/ignored.dm"));
  let broad=crate::run::Engine::new(crate::run::registry(),crate::run::Options {
   root,raw:true,no_cache:true,..Default::default()
  }).unwrap();
  assert!(!crate::sem::gen::test_only_types(&broad.tree).contains("/datum/test_only"),"arbitrary all-lint trees retain their distinct broader domain");
 }
}

#[cfg(test)]mod exact_test_type_policy_tests{use super::*;
 #[test]fn test_type_data_fold_preserves_all_dm_domain_and_generated_exclusions(){let files=[("code/tests/probe.dm","/datum/test_only\n/datum/shared\n/datum/generated_only\n"),("maps/production.dm","/datum/shared\n"),("code/_generated/reads.dm","/datum/generated_only\n"),("code/engine/_generated/table.dm","/datum/test_only\n")];let mut all=TestTypeCollector::default();for(relative,text)in files{all.observe(relative,text,&mut crate::key_policy_control::Compatibility).unwrap();}assert_eq!(all.finish(),std::collections::BTreeSet::from(["/datum/test_only".to_owned(),"/datum/generated_only".to_owned()]));let mut code_only=TestTypeCollector::default();for(relative,text)in files.into_iter().filter(|(relative,_)|relative.starts_with("code/")){code_only.observe(relative,text,&mut crate::key_policy_control::Compatibility).unwrap();}assert!(code_only.finish().contains("/datum/shared"),"CODE_DM-only absence cannot certify the original all-DM production redeclaration domain");}
 // The original helper trims /proc/ or /verb/ before applying its final
 // callable-parent trim. Retain that existing spelling policy during extraction.
 #[test]fn defined_type_projection_retains_original_header_spelling_rules(){for(line,want)in [("/datum/probe",Some("/datum/probe")),("/datum/probe/var/value=1",Some("/datum/probe")),("/datum/probe/proc/read()",Some("/datum")),("/datum/probe/verb/read()",Some("/datum")),("/datum/probe/read()",Some("/datum/probe")),("    /datum/probe",None),("// /datum/probe",None)]{assert_eq!(defined_type(line),want);}}
}
