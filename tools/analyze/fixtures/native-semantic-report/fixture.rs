//! Original source-only cases with a complete real CLI configuration.
//! Minimal private policy fixtures do not certify global CLI validation.
#[path="../native-sem-reads/fixture.rs"]mod reads;
#[path="../native-untracked-inputs/fixture.rs"]mod untracked;
pub fn cases(family:&str)->Option<&'static[&'static str]>{match family{"sem/reads"=>Some(reads::CASES),"untracked_inputs"=>Some(untracked::CASES),_=>None}}
pub fn files(family:&str,case:&str)->Option<Vec<(String,Vec<u8>)>>{
 let mut files=match family{"sem/reads"=>reads::files(case)?,"untracked_inputs"=>untracked::files(case)?,_=>return None};
 // Replace only this target's scope, using the exact initial source fixture's
 // intended exemptions. Every unrelated real required list stays present.
 let target=if family=="sem/reads"{"sem/reads"}else{"untracked_inputs"};let prefix=format!("[lint.{target}");let quoted=format!("[lint.\"{target}\"");let mut keep=true;let mut config=String::new();
 for line in include_str!("../../../ci/lint_scopes.toml").split_inclusive('\n'){let head=line.trim_start();if head.starts_with('['){keep=!(head.starts_with(&prefix)&&(head.as_bytes().get(prefix.len()).is_some_and(|b|matches!(*b,b'.'|b']')))||head.starts_with(&quoted));}if keep{config.push_str(line);}}
 if let Some(index)=files.iter().position(|(relative,_)|relative=="tools/ci/lint_scopes.toml"){let(_,overlay)=files.remove(index);config.push('\n');config.push_str(std::str::from_utf8(&overlay).ok()?);}else{config.push_str(&format!("\n[lint.\"{target}\"]\n"));}
 files.push(("tools/ci/lint_scopes.toml".into(),config.into_bytes()));Some(files)
}
