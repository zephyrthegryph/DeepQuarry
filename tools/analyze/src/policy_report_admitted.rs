//! Resource-only report work over already authentic delivered DATA. No source,
//! parser, model, completion, role, counter or cache is constructed here.
use std::{collections::{BTreeMap,BTreeSet,HashSet},io::{self,Read},path::Path};
use crate::{baseline,lint::{Run,Policy},scopes::LintScope};
#[cfg(feature="native-policy")]use crate::captured_derived_reads::DerivedReadData;
/// A scoped loan from the actual hosting operation. Production issuers must
/// reserve BEFORE allocation and retain that credit until physical payload drop.
pub use dq_analyze_client::report_work::Work;
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
 // Covers canonical text's temporary pieces and actual BTree key/node
 // copies. It is an admission envelope, not a heap census.
 work.reserve(add(work,mul(work,text.len().saturating_add(1),128)?,mul(work,lines,4096)?)?)?;Ok(baseline::parse_sites_text(text))
}
/// Fixed library baseline judgment over actual captured bytes and finding
/// lines. None means proven missing or unreadable under the fixed role.
/// Readable invalid UTF-8 also yields the ordinary reader's empty allowance.
pub fn judge_captured_sites(
    meta: &crate::lint::Meta, scope: &LintScope, source_lines: &[String], run: &Run, root: &Path,
    bytes: Option<&[u8]>, work: &dyn Work,
) -> io::Result<(bool, String)> {
    work.checkpoint()?;
    if meta.name != "library_layering" || !matches!(meta.policy, Policy::Sites { .. })
        || meta.rules.iter().any(|rule| rule.name == "init_lines") || run.sites.len() != source_lines.len()
    {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "fixed library Sites judgment requires exact findings and literal fingerprint rules"));
    }
    // Both indexes borrow rule/path/source bytes. Fingerprints are the only
    // new per-site text, at most one per issued row. Pre-grant their measured
    // width and both maps' node/control geometry before allocating either.
    let mut width = 0usize;
    for (site, line) in run.sites.iter().zip(source_lines) {
        work.checkpoint()?;
        width = add(work, width, add(work, line.len(), add(work, site.ident.len(), 1)?)?)?;
    }
    let rows = add(work, run.sites.len(), add(work, meta.rules.len(), 1)?)?;
    work.reserve(add(work, mul(work, width, 4)?, mul(work, rows, 4096)?)?)?;
    struct CapturedLines<'a>(BTreeMap<&'a str, BTreeMap<u32, &'a str>>);
    impl baseline::SiteText for CapturedLines<'_> {
        fn site_text(&self, relative: &str, line: usize) -> String {
            u32::try_from(line).ok().and_then(|line| self.0.get(relative)?.get(&line))
                .copied().unwrap_or_default().to_owned()
        }
    }
    let mut source = CapturedLines(BTreeMap::new());
    let mut projected = baseline::ProjectedSites::default();
    for rule in meta.rules { projected.register_rule(rule.name); }
    for (site, line) in run.sites.iter().zip(source_lines) {
        work.checkpoint()?;
        let prior = source.0.entry(site.rel.as_str()).or_default().insert(site.line, line.as_str());
        if prior.is_some_and(|prior| prior != line.as_str()) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "conflicting captured text for a library finding"));
        }
        projected.register_site(site, line);
    }
    if let Some(text) = bytes.and_then(|bytes| std::str::from_utf8(bytes).ok()) {
        // Each parsed row is borrowed, including the stale and unknown rows.
        // No second copy or retained map of all baseline lines is required.
        for line in baseline::sites_lines(text) {
            work.checkpoint()?;
            if let Some((rule, file, fingerprint)) = baseline::parse_sites_row(line) {
                projected.observe_literal_row(rule, file, fingerprint).ok_or_else(|| work.overflow())?;
            }
        }
    }
    let report = crate::policy_judge::judge_report_using(meta, scope, &source, run, root, &None, false,
        |_, _, _| false, |_, _| false, Some(crate::policy_judge::Sites::Projected(projected)), None);
    work.checkpoint()?;
    Ok(report)
}
/// Judgment over one actual baseline loan. The issuer is responsible for path,
/// observation and freshness authority; this adapter opens no file.
pub fn judge_captured_baseline<S: baseline::SiteText + ?Sized>(
    meta: &crate::lint::Meta, scope: &LintScope, source: &S, run: &Run, root: &Path,
    bytes: Option<&[u8]>, work: &dyn Work,
    post: impl FnMut(&Run, &mut String) -> bool,
) -> io::Result<(bool, String)> {
    judge_captured_baseline_changed(meta,scope,source,run,root,bytes,work,post,&None)
}

pub fn judge_captured_baseline_changed<S: baseline::SiteText + ?Sized>(
    meta: &crate::lint::Meta, scope: &LintScope, source: &S, run: &Run, root: &Path,
    bytes: Option<&[u8]>, work: &dyn Work,
    post: impl FnMut(&Run, &mut String) -> bool,
    changed: &Option<std::collections::HashSet<String>>,
) -> io::Result<(bool, String)> {
    work.checkpoint()?;
    let text = bytes.and_then(|bytes| std::str::from_utf8(bytes).ok()).unwrap_or_default();
    let mut lines = 1usize;
    for chunk in text.as_bytes().chunks(8192) {
        work.checkpoint()?;
        lines = add(work, lines, chunk.iter().filter(|b| matches!(**b, b'\r' | b'\n')).count())?;
    }
    // Retain parsed keys and account for the legacy Sites allowance clones.
    work.reserve(add(work, mul(work, text.len(), 32)?, mul(work, lines, 4096)?)?)?;
    let report = match meta.policy {
        Policy::Sites { .. } => {
            let baseline = baseline::parse_sites_text(text.to_owned());
            crate::policy_judge::judge_report_using(
                meta, scope, source, run, root, changed, false, |_, _, _| false, post,
                Some(crate::policy_judge::Sites::Complete(&baseline)), None,
            )
        }
        Policy::Ceilings { .. } => {
            let baseline = baseline::parse_ceilings_text(text);
            crate::policy_judge::judge_report_using(
                meta, scope, source, run, root, changed, false, |_, _, _| false, post,
                None, Some(&baseline),
            )
        }
        _ => return Err(io::Error::new(io::ErrorKind::InvalidInput,
            "captured baseline judgment requires Sites or Ceilings metadata")),
    };
    work.checkpoint()?;
    Ok(report)
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

/// Exact update-only Sites renderer over captured old bytes and actual Run DATA.
/// The host funds current grouping/fingerprints/text before invoking this loan.
pub fn render_captured_sites_update<S:baseline::SiteText+?Sized>(meta:&crate::lint::Meta,scope:&LintScope,source:&S,run:&Run,bytes:&[u8])->io::Result<(String,usize,String)>{render_captured_sites_mode(meta,scope,source,run,bytes,baseline::Mode::Update)}
pub fn render_captured_sites_mode<S:baseline::SiteText+?Sized>(meta:&crate::lint::Meta,scope:&LintScope,source:&S,run:&Run,bytes:&[u8],mode:baseline::Mode)->io::Result<(String,usize,String)>{
 let Policy::Sites{header,banned,..}=meta.policy else{return Err(io::Error::new(io::ErrorKind::InvalidInput,"captured Sites updater needs actual Sites metadata"))};
 let by_rule=run.by_rule(meta);let groups:Vec<(&str,Vec<&crate::lint::Site>)>=by_rule.iter().filter(|(rule,_)|!scope.ceilings.contains_key(*rule)).map(|(rule,sites)|(*rule,sites.clone())).collect();
 let rules:Vec<&str>=meta.rules.iter().map(|rule|rule.name).filter(|rule|!banned.contains(rule)&&!scope.ceilings.contains_key(*rule)).collect();
 let old=baseline::parse_sites_text(std::str::from_utf8(bytes).unwrap_or_default().to_owned());
 let(text,count)=baseline::render_sites(&old,header,source,&groups,&rules,mode)?;
 let counts=groups.iter().map(|(rule,sites)|format!("{} {}",rule,sites.len())).collect::<Vec<_>>().join(", ");
 Ok((text,count,counts))
}
/// Exact old-key/min/current count update over captured baseline bytes.
pub fn render_captured_count_update(bytes:&[u8],header:&[&str],run:&Run)->(String,usize){let old=baseline::parse_ceilings_text(std::str::from_utf8(bytes).unwrap_or_default());baseline::render_updated_ceilings(&old,header,&run.sites)}

/// Pure actual captured count-mode semantics; Migrate performs no write.
pub fn render_captured_count_mode(bytes:&[u8],header:&[&str],run:&Run,mode:baseline::Mode)->(Option<String>,usize){match mode{baseline::Mode::Update=>{let(text,n)=render_captured_count_update(bytes,header,run);(Some(text),n)},baseline::Mode::Seed=>{let counts=baseline::key_counts(&run.sites);let text=baseline::render_ceilings(header,&counts);(Some(text),counts.len())},baseline::Mode::Migrate=>(None,baseline::parse_ceilings_text(std::str::from_utf8(bytes).unwrap_or_default()).len())}}
