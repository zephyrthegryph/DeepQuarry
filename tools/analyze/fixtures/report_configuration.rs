//! Test-only full CLI configuration overlay, never a metadata issuer.
fn lint_root(header:&str)->Option<&str>{let text=header.trim().strip_prefix("[lint.")?;let end=if let Some(quoted)=text.strip_prefix('"'){quoted.find('"')?+2}else{text.find(['.',']'])?};Some(&text[..end])}
pub fn complete(configuration:&std::path::Path){
 let overlay=match std::fs::read_to_string(configuration){Ok(text)=>text,Err(error)if error.kind()==std::io::ErrorKind::NotFound=>String::new(),Err(error)=>panic!("actual fixture configuration read failed: {error}")};
 let text=with_overlay(&overlay);std::fs::create_dir_all(configuration.parent().unwrap()).unwrap();std::fs::write(configuration,text).unwrap();
}
pub fn with_overlay(overlay:&str)->String{
 let roots:std::collections::BTreeSet<_>=overlay.lines().filter_map(lint_root).collect();let mut keep=true;let mut text=String::new();
 for line in include_str!("../../ci/lint_scopes.toml").split_inclusive('\n'){if line.trim_start().starts_with('['){keep=!lint_root(line).is_some_and(|root|roots.contains(root));}if keep{text.push_str(line);}}
 text.push('\n');text.push_str(overlay);text
}
