//! Test-only complete record; never a source or policy completion issuer.
use super::analyze;
use std::{collections::BTreeMap,path::Path};
use analyze::{captured_keys_pages::KeyData,captured_raw_file::Config};
struct MessageOnly;
impl analyze::baseline::SiteText for MessageOnly{fn site_text(&self,_:&str,_:usize)->String{panic!("keys Hard report unexpectedly requested source text")}}
fn hex(bytes:&[u8])->String{use std::fmt::Write;let mut text=String::with_capacity(bytes.len()*2);for byte in bytes{write!(&mut text,"{byte:02x}").unwrap();}text}
pub fn record(data:&KeyData,config:&Config,root:&Path,case:&str)->serde_json::Value{
 let meta=analyze::keys_policy::metadata();assert!(matches!(meta.policy,analyze::lint::Policy::Hard));assert!(data.sites().iter().all(|row|!row.msg.is_empty()),"source-independent message contract must be proved before standard report");
 let empty=analyze::scopes::LintScope::default();let scope=config.borrowed_report_scope(meta.name,meta.group).unwrap_or(&empty);let run=analyze::lint::Run{sites:data.sites().to_vec(),notes:Vec::new()};
 let(failed,text)=analyze::policy_judge::judge_report(meta,scope,&MessageOnly,&run,root,&None,true,|_,_,_|panic!("keys has no Custom policy"),|_,_|false);
 let mut digests=BTreeMap::new();for used in data.allow_used(){digests.entry(used.rel.clone()).or_insert_with(||hex(data.allow_source_digest(&used.rel).expect("every consumed original ALLOW needs its same-loan file digest")));}
 serde_json::json!({"case":case,"sites":data.sites(),"notes":[],"allow_used":data.allow_used(),"allow_digests":digests,"failed":failed,"text":text})
}
