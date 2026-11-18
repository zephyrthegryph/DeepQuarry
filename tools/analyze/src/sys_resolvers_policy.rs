//! Port of `tools/ci/sys_rules/resolvers.py`: map-time resolvers (systems.md section 9).
//!
//! An `Initialize()`/`LateInitialize()` that unconditionally ends its life (`init_qdel`) or does
//! its work then deletes itself at its top level (`init_self_delete`).

use std::collections::{BTreeSet, HashSet};

use crate::dm::sys::{col0, in_family, register_module, SysModule};
#[cfg(feature="legacy-sem")] use crate::incr;
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::key_policy_control::{self as kc,Control};
use crate::tree::SourceFile;
#[cfg(feature="legacy-sem")] use crate::tree::Tree;
use crate::util::before_slashes;

pub(crate) const RULES: &[RuleMeta] = &[
    RuleMeta { name: "init_qdel", hint: "an atom that only works at load then goes: map_resolver(GLOBAL_PROC_REF(x)) in its CAPABILITIES block (systems.md section 9)" },
    RuleMeta {
        name: "init_self_delete",
        hint: "an Initialize that does its work then deletes itself: map_resolver(GLOBAL_PROC_REF(x)) in its CAPABILITIES block (systems.md section 9)",
    },
];

pub(crate) fn roots_of(f:&SourceFile)->Vec<String>{roots_of_using(f,&mut kc::Compatibility).unwrap_or_else(|never|match never{})}
pub(crate) fn roots_of_using<C:Control>(f:&SourceFile,control:&mut C)->Result<Vec<String>,C::Error>{
    let mut roots: BTreeSet<String> = BTreeSet::new();
    let mut cur: Option<String> = None;
    for line in f.raw().lines() {control.checkpoint()?;
        if let Some(c) = kc::captures_static(control,r"^CAPABILITIES(?:_PART)?\((/[\w/]+)[,)]",line,0,||pat!(r"^CAPABILITIES(?:_PART)?\((/[\w/]+)[,)]"))? {
            cur = Some(kc::own(control,c.s(1))?);
            continue;
        }
        if col0(line) {
            cur = None;
            continue;
        }
        if let Some(t) = &cur {
            if kc::is_match_static(control,r"^	(configure\()?map_resolver\(",line,||pat!(r"^	(configure\()?map_resolver\("))? {
                if !roots.contains(t){kc::reserve(control,||Some(1024+std::mem::size_of::<String>()))?;roots.insert(kc::own(control,t)?);}
            }
        }
    }
    let mut out=Vec::new();for value in roots{kc::row(control,&mut out)?;out.push(value);}Ok(out)
}

pub(crate) fn judge(f:&SourceFile,roots:&HashSet<String>,out:&mut Vec<(&'static str,usize)>){judge_using(f,roots,out,&mut kc::Compatibility).unwrap_or_else(|never|match never{})}
pub(crate) fn judge_using<C:Control>(f:&SourceFile,roots:&HashSet<String>,out:&mut Vec<(&'static str,usize)>,control:&mut C)->Result<(),C::Error>{
    {
        let mut cur: Option<String> = None;
        for (number, line) in f.raw().numbered() {control.checkpoint()?;
            if let Some(c) = kc::captures_static(control,r"^(/[\w/]+?)/(Initialize|LateInitialize)\(",line,0,||pat!(r"^(/[\w/]+?)/(Initialize|LateInitialize)\("))? {
                cur = Some(kc::own(control,c.s(1))?);
                continue;
            }
            if col0(line) {
                cur = None;
                continue;
            }
            let Some(c) = &cur else { continue };
            let code = before_slashes(line);
            if kc::is_match_static(control,r"^\t(return|\.\s*=)\s*INITIALIZE_HINT_QDEL\b",code,||pat!(r"^\t(return|\.\s*=)\s*INITIALIZE_HINT_QDEL\b"))?
                || (kc::is_match_static(control,r"\bINITIALIZE_HINT_QDEL\b",code,||pat!(r"\bINITIALIZE_HINT_QDEL\b"))? && in_family(c, roots))
            {
                kc::row(control,out)?;out.push(("init_qdel", number));
            } else if kc::is_match_static(control,r"^\t(qdel\(src\)|expire\(0\)|replace_with\(src\b|qdel_self\(\))",code,||pat!(r"^\t(qdel\(src\)|expire\(0\)|replace_with\(src\b|qdel_self\(\))"))? {
                kc::row(control,out)?;out.push(("init_self_delete", number));
            }
        }
    }
    Ok(())
}

#[cfg(feature="legacy-sem")]
fn scan_files(_tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let fs = incr::facts("sys-resolvers-facts", files, roots_of);
    let roots: BTreeSet<String> = fs.into_iter().flatten().collect();
    let key = incr::ctx_key(&roots);
    let roots: HashSet<String> = roots.into_iter().collect();
    let results = incr::keyed("sys-resolvers-judge", key, files, |f| {
        let mut v: Vec<(&'static str, usize)> = Vec::new();
        judge(f, &roots, &mut v);
        v.into_iter().map(|(rule, line)| (RULES.iter().position(|r| r.name == rule).unwrap_or(0) as u8, line as u32)).collect::<Vec<(u8, u32)>>()
    });
    let mut out = Vec::new();
    for (f, v) in files.iter().zip(results) {
        for (rule, line) in v {
            out.push((RULES[rule as usize].name, f.rel.clone(), line as usize));
        }
    }
    out
}

#[cfg(feature="legacy-sem")]
pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: crate::allow_registry_fields::sys_resolvers::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(scan_files), ..SysModule::DEFAULT });
}
