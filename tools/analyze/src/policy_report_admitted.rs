//! Resource-only report work over already authentic delivered DATA. No source,
//! parser, model, completion, role, counter or cache is constructed here.
use std::{collections::{BTreeMap,BTreeSet,HashSet},io::{self,Read},path::Path};
use crate::{baseline,lint::{Run,Policy},scopes::LintScope};
#[cfg(feature="native-policy")]use crate::captured_derived_reads::DerivedReadData;
/// A scoped loan from the actual hosting operation. Production issuers must
/// reserve BEFORE allocation and retain that credit until physical payload drop.
pub trait Work{fn temporary(&self,_slot:usize,bytes:usize)->io::Result<()>{self.reserve(bytes)}fn checkpoint(&self)->io::Result<()>;fn reserve(&self,bytes:usize)->io::Result<()>;fn overflow(&self)->io::Error;}
fn add(work:&dyn Work,a:usize,b:usize)->io::Result<usize>{a.checked_add(b).ok_or_else(||work.overflow())}
fn mul(work:&dyn Work,a:usize,b:usize)->io::Result<usize>{a.checked_mul(b).ok_or_else(||work.overflow())}
/// The old baseline reader deliberately treats actual read/UTF8 failure as an
/// empty baseline. Preserve that rule while propagating the FIRST admission or
/// cancellation failure unchanged (those do not masquerade as file absence).
fn read_baseline(path:&Path,work:&dyn Work)->io::Result<BTreeMap<String,baseline::Counter>>{
 work.checkpoint()?;let Ok(mut file)=std::fs::File::open(path)else{return Ok(BTreeMap::new())};let mut bytes=Vec::new();let mut buffer=[0u8;8192];
 loop{work.checkpoint()?;let n=match file.read(&mut buffer){Ok(0)=>break,Ok(n)=>n,Err(e)if e.kind()==io::ErrorKind::Interrupted=>continue,Err(_)=>return Ok(BTreeMap::new())};let needed=add(work,bytes.len(),n)?;
  if needed>bytes.capacity(){let cap=needed.max(bytes.capacity().saturating_mul(2)).max(8192);work.reserve(add(work,mul(work,cap,4)?,64)?)?;bytes.try_reserve_exact(cap-bytes.len()).map_err(|_|work.overflow())?;if bytes.capacity()>cap.saturating_mul(4){return Err(work.overflow())}}
  bytes.extend_from_slice(&buffer[..n]);
 }
 let Ok(text)=String::from_utf8(bytes)else{return Ok(BTreeMap::new())};let lines=text.bytes().filter(|b|*b==b'\n').count().saturating_add(1);
 // Covers both universal-newline copies, canonical text's temporary pieces and
 // actual BTree key/node copies. It is an admission envelope, NOT a heap census.
 work.reserve(add(work,mul(work,text.len().saturating_add(1),128)?,mul(work,lines,4096)?)?)?;Ok(baseline::parse_sites_text(text))
}
pub struct Text{pub clean:bool,pub text:String,pub allow_usage:BTreeSet<(String,String,u32)>}
/// Use the SAME policy judge and SAME baseline parser. Source-owned entries
/// stay borrowed. The few legacy Run/ALLOW and formatter scratch copies are
/// preadmitted against measured actual widths before the common code creates
/// them; no unaccounted second report is decoded or semantically recomputed.
#[cfg(feature="native-policy")]pub fn derived(data:&DerivedReadData,scope:&LintScope,root:&Path,changed:Option<&[String]>,raw:bool,ci:bool,work:&dyn Work)->io::Result<Text>{
 selected(data,data.metadata(),data.sites(),data.source_text(),data.allow_used(),&|p|data.allow_source_digest(p).copied(),data.post_judge_message(),scope,root,changed,raw,ci,true,work)
}
#[cfg(feature="native-policy")]
pub fn handlers(data:&crate::captured_sem_handlers::Data,scope:&LintScope,root:&Path,changed:Option<&[String]>,raw:bool,ci:bool,complete:bool,work:&dyn Work)->io::Result<Text>{
 selected(data,data.metadata(),data.sites(),data.source_text(),data.allow_used(),&|p|data.allow_digests().get(p).copied(),None,scope,root,changed,raw,ci,complete,work)
}
#[cfg(feature="native-policy")]
fn selected(data:&dyn baseline::SiteText,meta:&crate::lint::Meta,sites:&[crate::lint::Site],source_text:&[String],used:&[crate::lint::AllowUse],digest:&dyn Fn(&str)->Option<[u8;20]>,post:Option<&str>,scope:&LintScope,root:&Path,changed:Option<&[String]>,raw:bool,ci:bool,complete:bool,work:&dyn Work)->io::Result<Text>{
 work.checkpoint()?;if sites.len()!=source_text.len(){return Err(io::Error::new(io::ErrorKind::InvalidData,"selected report source text/row loan differs"))}let mut width=meta.name.len()+meta.label.len();
 width=add(work,width,mul(work,root.as_os_str().len(),4)?)?;let mut changed_count=0usize;if let Some(paths)=changed{for path in paths{width=add(work,width,path.len())?;changed_count=add(work,changed_count,1)?;}}
 for rule in meta.rules{width=add(work,width,rule.name.len()+rule.hint.len())?}
 for(site,text)in sites.iter().zip(source_text){for value in [&site.rule,&site.rel,&site.msg,&site.key,&site.ident,text]{width=add(work,width,value.len())?}}
 for value in used{width=add(work,width,value.name.len()+value.rel.len()+value.code.len()+40)?}
 let count=add(work,add(work,sites.len(),used.len())?,meta.rules.len()+changed_count+1)?;
 // Includes changed-only Run copies, grouping/fingerprint/key/new-line scratch,
 // ceiling formatting, final text+CI wrappers and exact name/digest/line ledger.
 work.reserve(add(work,mul(work,width.saturating_add(1),128)?,mul(work,count,8192)?)?)?;
 let prepared=match meta.policy{Policy::Sites{baseline,..}if !raw=>read_baseline(&root.join(baseline),work)?,_=>BTreeMap::new()};
 let mut base_width=0usize;let mut base_nodes=0usize;for(rule,rows)in &prepared{base_width=add(work,base_width,rule.len())?;for((file,text),_)in rows{base_width=add(work,base_width,file.len()+text.len())?;base_nodes=add(work,base_nodes,1)?}}
 work.reserve(add(work,mul(work,base_width,16)?,mul(work,base_nodes,4096)?)?)?;
 let changed=changed.map(|paths|paths.iter().cloned().collect::<HashSet<_>>());
 let run=Run{sites:sites.to_vec(),notes:Vec::new()};let(failed,body)=crate::policy_judge::judge_report_prepared(meta,scope,data,&run,root,&changed,raw,|_,_,_|false,|_,text|{if let Some(message)=post{text.push_str(message);true}else{false}},Some(&prepared));
 let mut text=String::new();if ci{text.push_str("::group::");text.push_str(meta.name);text.push('\n')}text.push_str(&body);if ci{text.push_str("::endgroup::\n")};if !complete{text.push_str("sem/handlers: full source preparation failed; structural results only.\n")}else if failed{text.push_str("Ratchet lints failed: ");text.push_str(meta.name);text.push('\n')}else{text.push_str("All ratchet lints passed.\n")}
 let mut allow_usage=BTreeSet::new();for used in used{let digest=digest(&used.rel).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"missing actual selected ALLOW digest"))?;let mut hex=String::with_capacity(40);use std::fmt::Write as _;for b in digest{write!(hex,"{b:02x}").map_err(io::Error::other)?}allow_usage.insert((used.name.clone(),hex,used.line));}
 work.checkpoint()?;Ok(Text{clean:complete&&!failed,text,allow_usage})
}
