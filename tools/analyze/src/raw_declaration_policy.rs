//! Shared original raw declaration policy, emitted as ephemeral callbacks.
//! This is not a semantic model; native callers retain only annotation lines.
use std::collections::BTreeSet;
use crate::{pat_match,tree::View,util::{py_lstrip,py_rstrip,py_strip}};
pub const MODIFIERS: &[&str] = &["tmp", "static", "global", "const", "final"];
pub type DeclarationParts=(String,BTreeSet<String>,String,bool);
fn split_decl(mut segs: Vec<&str>, block_mods: &BTreeSet<String>) -> Option<(String, BTreeSet<String>, String, bool)> {
    let mut mods = block_mods.clone();
    while !segs.is_empty() && MODIFIERS.contains(&segs[0]) {
        mods.insert(segs.remove(0).to_string());
    }
    if segs.is_empty() {
        return None;
    }
    let name = segs[segs.len() - 1].to_string();
    let mut tsegs: Vec<&str> = segs[..segs.len() - 1].to_vec();
    let mut is_list = false;
    if !tsegs.is_empty() && tsegs[0] == "list" {
        is_list = true;
        tsegs.remove(0);
    }
    let vtype = if tsegs.is_empty() { String::new() } else { format!("/{}", tsegs.join("/")) };
    Some((name, mods, vtype, is_list))
}

pub fn visit_file(rel:&str,code:&View,mut declare:impl FnMut(&str,DeclarationParts,&str,usize),mut latent:impl FnMut(&str,bool)) {
    let header = pat_match!(r"^(/?[A-Za-z_][\w/]*)\s*(?:$|=|\()");
    let block_member = pat_match!(r"^((?:[A-Za-z_]\w*/)*[A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:=|$)");
    let block_head = pat_match!(r"^var(/(tmp|static|global|const))*\s*$");
    let var_decl = pat_match!(r"^var((?:/[A-Za-z_]\w*)+)\s*(?:\[[^\]]*\])?\s*(?:=|$|as\b)");
    let latent_re = pat_match!(r"^latent_safe\s*=\s*(TRUE|FALSE|1|0)\b");
    let latent_registration = pat_match!(r"^register\(\s*(/[A-Za-z_][\w/]*)\s*,\s*TYPE_META_LATENT_SAFE\s*,\s*(TRUE|FALSE|1|0)\s*\)");
    let empty = BTreeSet::new();

    let mut cur: Option<String> = None; // current type block
    let mut in_proc = false; // inside a proc body
    let mut in_metadata_registration = false;
    let mut block_mods: Option<BTreeSet<String>> = None; // modifiers of an open `var` / `var/tmp` block
    let mut block_indent = 0usize;
    for (no, raw) in code.numbered() {
        if py_strip(raw).is_empty() {
            continue;
        }
        let stripped = raw.trim_start_matches(['\t', ' ']);
        let indent = raw.len() - stripped.len();
        let text = py_rstrip(stripped);
        if text.starts_with('#') {
            continue;
        }
        if indent == 0 {
            block_mods = None;
            in_proc = false;
            in_metadata_registration = false;
            cur = None;
            let Some(m) = header.captures(text) else { continue };
            let g1 = m.s(1);
            let full = if g1.starts_with('/') { g1.to_string() } else { format!("/{}", g1) };
            let segs: Vec<&str> = full.trim_matches('/').split('/').collect();
            let has_proc = segs.contains(&"proc");
            let has_verb = segs.contains(&"verb");
            if has_proc || has_verb || py_lstrip(&text[g1.len()..]).starts_with('(') {
                let k = if has_proc {
                    segs.iter().position(|s| *s == "proc").unwrap()
                } else if has_verb {
                    segs.iter().position(|s| *s == "verb").unwrap()
                } else {
                    segs.len() - 1
                };
                let _owner = format!("/{}", segs[..k].join("/"));
                in_proc = true;
                in_metadata_registration = matches!(full.as_str(),
                    "/datum/type_metadata_registry/register_defaults" |
                    "/datum/type_metadata_registry/register_test_defaults" |
                    "/datum/type_metadata_registry/proc/register_defaults" |
                    "/datum/type_metadata_registry/proc/register_test_defaults");
                continue;
            }
            if let Some(k) = segs.iter().position(|s| *s == "var") {
                let owner = format!("/{}", segs[..k].join("/"));
                if let Some(d) = split_decl(segs[k + 1..].to_vec(), &empty) {
                    declare(&owner,d,rel,no);
                }
                continue;
            }
            cur = Some(full.trim_end_matches('/').to_string());
            continue;
        }
        if in_proc {
            if in_metadata_registration {
                if let Some(m) = latent_registration.captures(text) {
                    latent(m.s(1),matches!(m.s(2),"TRUE"|"1"));
                }
            }
            continue;
        }
        let Some(cur_t) = cur.as_deref() else { continue };
        if let Some(bm) = &block_mods {
            if indent > block_indent {
                if let Some(m) = block_member.captures(text) {
                    if let Some(d) = split_decl(m.s(1).split('/').collect(), bm) {
                        declare(cur_t,d,rel,no);
                    }
                }
                continue;
            }
        }
        block_mods = None;
        if indent != 1 && !raw.starts_with("    ") {
            continue;
        }
        if block_head.is_match(text) {
            block_mods = Some(text.split('/').skip(1).map(|s| s.to_string()).collect());
            block_indent = indent;
            continue;
        }
        if let Some(m) = var_decl.captures(text) {
            if let Some(d) = split_decl(m.s(1).trim_matches('/').split('/').collect(), &empty) {
                declare(cur_t,d,rel,no);
            }
            continue;
        }
        if let Some(m) = latent_re.captures(text) {
            latent(cur_t,matches!(m.s(1),"TRUE"|"1"));
        }
    }
}
