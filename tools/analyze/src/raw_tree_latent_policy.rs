//! Unique latent holder/index and Python-line judge. No complete source authority.
use std::collections::{BTreeSet,HashSet};
use serde::{Serialize,Deserialize};
use crate::lint::{Meta,Policy,RuleMeta,ScanKind};
use crate::tree::{SourceFile,Select};
use crate::dm::pylines::py_splitlines;
use crate::util::is_py_space;
const HINT: &str = "go through latent_materialize_all()/latent_entries()/slot_contents()";

pub static META: Meta = Meta {
    name: crate::allow_registry_fields::latent::SCOPE_META_0.name,
    group: crate::allow_registry_fields::latent::SCOPE_META_0.group,
    label: "latent",
    legacy: "tools/ci/latent_lint.py",
    // os.walk: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "raw_walks", hint: HINT }],
    allow: crate::allow_registry_fields::latent::ALLOW_0,
    lists: crate::allow_registry_fields::latent::SCOPE_META_0.lists,
};



/// One file's contribution to the holder index, and its count of legacy contents loops.
#[derive(Serialize, Deserialize, Default, PartialEq)]
pub struct Facts {
    pub holders: Vec<String>,
    pub eager: Vec<String>,
    pub legacy: u32,
}

pub fn facts_of(f:&SourceFile)->Facts{facts_of_using(f,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original latent facts")}
pub fn facts_of_using<C:crate::key_policy_control::Control,T:crate::key_policy_control::Control<Error=C::Error>>(f:&SourceFile,keep:&mut C,temp:&mut T)->Result<Facts,C::Error>{
 use crate::{key_policy_control as kc,raw_tree_report as growth};keep.checkpoint()?;
 let type_header=crate::pat_match!(r"(/[\w/]+)\s*$");let latent_decl=crate::pat_match!(r"\s+latent_contents\s*=\s*(TRUE|FALSE)");let legacy_loop=crate::pat!(r"\bfor\s*\(.*\bin\s+(?:[\w.]+\.)?contents\b");
 kc::reserve(temp,||f.text().len().checked_add(1)?.checked_mul(4*std::mem::size_of::<&str>())?.checked_add(128))?;let lines=py_splitlines(f.text());if T::CHECKED&&lines.capacity()>f.text().len().saturating_add(1).saturating_mul(4){return Err(temp.allocation_failed())}
 let(mut holders,mut eager)=(BTreeSet::<String>::new(),BTreeSet::<String>::new());let mut legacy=0u32;let mut current:Option<&str>=None;
 for line in &lines{keep.checkpoint()?;if let Some(h)=type_header.captures(line){current=Some(h.s(1));continue}if !line.is_empty()&&!line.chars().next().map(is_py_space).unwrap_or(false){current=None}if let(Some(cur),Some(d))=(current,latent_decl.captures(line)){let target=if d.s(1)=="TRUE"{&mut holders}else{&mut eager};if !target.contains(cur){kc::reserve(keep,||Some(2048))?;target.insert(growth::own(keep,cur)?);}}}
 for line in &lines{keep.checkpoint()?;if legacy_loop.is_match(line){legacy=legacy.checked_add(1).ok_or_else(||keep.overflow())?;}}
 let mut out=Facts::default();for name in holders{growth::row(keep,&mut out.holders)?;out.holders.push(name)}for name in eager{growth::row(keep,&mut out.eager)?;out.eager.push(name)}out.legacy=legacy;keep.checkpoint()?;Ok(out)
}

/// The raw-walk sites of one file (line numbers), given the holder index. ALLOW questions are
/// recorded (the cache replays them).
pub fn judge(f:&SourceFile,holders:&HashSet<String>,eager:&HashSet<String>,allowed:impl FnMut(&[&str],usize)->bool)->Vec<u32>{judge_using(f,holders,eager,allowed,&mut crate::key_policy_control::Compatibility).expect("original latent judge")}
fn is_holder_using<C:crate::key_policy_control::Control>(path:&str,holders:&HashSet<String>,eager:&HashSet<String>,c:&mut C)->Result<bool,C::Error>{let mut longest=[None,None];for(slot,roots)in longest.iter_mut().zip([holders,eager]){for root in roots{c.checkpoint()?;if path==root||(path.starts_with(root.as_str())&&path.as_bytes().get(root.len())==Some(&b'/')){if slot.map(|n|root.len()>n).unwrap_or(true){*slot=Some(root.len());}}}}Ok(match longest{[Some(l),Some(o)]=>l>o,[Some(_),None]=>true,_=>false})}
pub fn judge_using<C:crate::key_policy_control::Control>(f:&SourceFile,holders:&HashSet<String>,eager:&HashSet<String>,mut allowed:impl FnMut(&[&str],usize)->bool,c:&mut C)->Result<Vec<u32>,C::Error>{
    c.checkpoint()?;let mut temporary_peak=0;
    let proc_header = crate::pat_match!(r"(/[\w/]+?)/(?:proc/|verb/)?(\w+)\(");
    let own_walk = crate::pat!(
        r"\bin\s+(?:src\.)?contents\b|\bin\s+src\s*\)|(?<![\w.])contents\.len\b|length\(\s*(?:src\.)?contents\s*\)"
    );
    let typed_var = crate::pat!(r"var/([\w/]+)/(\w+)");
    crate::key_policy_control::reserve(c,||f.text().len().checked_add(1)?.checked_mul(4*std::mem::size_of::<&str>())?.checked_add(128))?;let lines=py_splitlines(f.text());if C::CHECKED&&lines.capacity()>f.text().len().saturating_add(1).saturating_mul(4){return Err(c.allocation_failed())}
    let mut sites: Vec<u32> = Vec::new();
    let mut owner: Option<String> = None;
    let mut typed: Vec<String> = Vec::new();
    for (i, line) in lines.iter().enumerate() {
        c.checkpoint()?;crate::raw_tree_report::peak(c,&mut temporary_peak,||line.len().checked_mul(8)?.checked_add(1024))?;let number = i + 1;
        if allowed(&lines,number) {
            continue;
        }
        if let Some(h) = proc_header.captures(line) {
            owner = Some(crate::raw_tree_report::own(c,h.s(1))?);
            typed.clear();
        } else if !line.is_empty() && !line.chars().next().map(is_py_space).unwrap_or(false) && !line.starts_with("//") {
            owner = None;
            typed.clear();
        }
        let code = line.split("//").next().unwrap_or("");
        for m in typed_var.captures_iter(code) {c.checkpoint()?;
            let var_type = format!("/{}", m.s(1).trim_start_matches('/'));
            if is_holder_using(&var_type, holders, eager,c)? && !typed.iter().any(|t| t == m.s(2)) {
                crate::raw_tree_report::row(c,&mut typed)?;typed.push(crate::raw_tree_report::own(c,m.s(2))?);
            }
        }
        if let Some(o) = &owner {
            if is_holder_using(o, holders, eager,c)? && own_walk.is_match(code) {
                crate::raw_tree_report::row(c,&mut sites)?;sites.push(number as u32);
                continue;
            }
        }
        for name in &typed {c.checkpoint()?;
            if crate::raw_name_match::contents_walk(code, name) {
                crate::raw_tree_report::row(c,&mut sites)?;sites.push(number as u32);
                break;
            }
        }
    }
    c.checkpoint()?;Ok(sites)
}
