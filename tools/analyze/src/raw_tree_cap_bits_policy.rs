//! Port of `tools/ci/cap_bits_lint.py`: the cap_state bit registry check
//! (code/defines/engine/cap_bits.dm; dx_conventions.md section 2).
//!
//! Fails when a `CAP_*` bit is defined outside the registry file, two bits share a value, or a bit
//! reaches `1<<24` (DM's safe bitwise range); also rejects raw writes to `cap_state` outside the
//! framework (`cap_set()` is the writer). No baseline and no ALLOW: any problem fails.
//!
//! Quirk kept: the "shares bit" message goes to the later file in the walk. The Python walked
//! `glob.glob` order (the OS directory order); the engine walks files sorted by path, so for a
//! collision between files the flagged side can differ from a Windows run of the Python.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::lint::{Meta,Policy,RuleMeta,ScanKind};
use crate::raw_tree_report::Reporter;
use crate::pat;
use crate::tree::{SourceFile, CODE_DM};
use crate::util::{before_slashes, starts_with_any};

pub static META: Meta = Meta {
    name: crate::allow_registry_fields::cap_bits::SCOPE_META_0.name,
    group: crate::allow_registry_fields::cap_bits::SCOPE_META_0.group,
    label: "cap_bits",
    legacy: "tools/ci/cap_bits_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "outside_registry", hint: "allocate the bit in code/defines/engine/cap_bits.dm" },
        RuleMeta { name: "bit_range", hint: "a cap bit must stay below 1<<24" },
        RuleMeta { name: "bit_shared", hint: "every CAP_* bit needs its own value" },
        RuleMeta { name: "raw_write", hint: "write cap_state through cap_set()" },
    ],
    allow: crate::allow_registry_fields::cap_bits::ALLOW_0,
    lists: crate::allow_registry_fields::cap_bits::SCOPE_META_0.lists,
};


/// What one line of a file contributes: a `#define CAP_x (1<<n)` and/or a raw `cap_state` write.
#[derive(Clone,Serialize, Deserialize, PartialEq)]
pub struct Ev {
    line: u32,
    define: Option<(String, u128)>,
    raw_write: bool,
}

#[derive(Clone,Serialize, Deserialize, Default, PartialEq)]
pub struct Facts {
    events: Vec<Ev>,
}

/// One file's events. `writers` / `write_exempt` decide `raw_write`, a function of the file's path.
pub fn facts_of(f:&SourceFile,writers:&[String],write_exempt:&[String])->Facts{facts_of_using(f,writers,write_exempt,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original cap-bit facts")}
pub fn facts_of_using<C:crate::key_policy_control::Control,T:crate::key_policy_control::Control<Error=C::Error>>(f:&SourceFile,writers:&[String],write_exempt:&[String],keep:&mut C,temp:&mut T)->Result<Facts,C::Error>{
    keep.checkpoint()?;let mut temporary_peak=0;
    let rel = f.rel.as_str();
    let mut events = Vec::new();
    for (number, line) in f.raw().numbered() {
        keep.checkpoint()?;crate::raw_tree_report::peak(temp,&mut temporary_peak,||line.len().checked_mul(8)?.checked_add(1024))?;
        let mut define = None;
        if let Some(m) = pat!(r"^\s*#define\s+(CAP_[A-Z0-9_]+)\s+\(1\s*<<\s*(\d+)\)").captures(line) {
            let shift: u128 = m.s(2).parse().unwrap_or(u128::MAX);
            define = Some((crate::raw_tree_report::own(keep,m.s(1))?, shift));
        }
        let code = pat!(r#""[^"]*""#).replace_all(before_slashes(line), "\"\"");
        let mut raw_write = false;
        if pat!(r"\bcap_state\s*(\|=|&=|\^=|=(?!=))").is_match(&code) && !writer_using(writers,rel,keep)? && !exempt_using(rel,write_exempt,keep)? {
            let var_line = pat!(r"^\s*var/").is_match(&code);
            let tab_assign = pat!(r"^\t+cap_state\s*=").is_match(&code);
            // `A or B and C` in the Python: `and` binds tighter.
            let type_default = (var_line || (tab_assign && !code.contains('/'))) && pat!(r"^\tcap_state\s*=").is_match(&code);
            // a type default (`cap_state = CAP_X` under a type) is configuration, not a write
            raw_write = !type_default;
        }
        if define.is_some() || raw_write {
            crate::raw_tree_report::row(keep,&mut events)?;events.push(Ev { line: number as u32, define, raw_write });
        }
    }
    keep.checkpoint()?;Ok(Facts { events })
}

/// The findings, from every file's events in file order (the shared `seen` table is the only
/// cross-file state).
pub fn assemble<'a>(pairs:impl IntoIterator<Item=(&'a str,&'a Facts)>,registry:&[String],out:&mut impl Reporter) {
    let registry_path = registry.first().map(|s| s.as_str()).unwrap_or("");
    let mut seen: HashMap<u128, String> = HashMap::new();
    for (rel, fa) in pairs {
        if !out.checkpoint(){return}
        for ev in &fa.events {
            if !out.checkpoint(){return}
            let number = ev.line as usize;
            if let Some((name, shift)) = &ev.define {
                if rel != registry_path {
                    out.site_in_msg("outside_registry", rel, number, format!("{} is allocated outside {}", name, registry_path));
                }
                if *shift >= 24 {
                    out.site_in_msg("bit_range", rel, number, format!("{} uses bit {} (max 23)", name, shift));
                }
                if let Some(prev) = seen.get(shift) {
                    out.site_in_msg("bit_shared", rel, number, format!("{} shares bit {} with {}", name, shift, prev));
                }
                seen.insert(*shift, name.to_string());
            }
            if ev.raw_write {
                out.site_in_msg("raw_write", rel, number, "write cap_state through cap_set()");
            }
        }
    }
}


pub fn retained_bound(facts:&Facts)->Option<usize>{let mut bytes=facts.events.capacity().checked_mul(std::mem::size_of::<Ev>())?.checked_add(128)?;for event in &facts.events{if let Some((name,_))=&event.define{bytes=bytes.checked_add(name.capacity())?.checked_add(128)?;}}Some(bytes)}

pub fn assembly_entries(facts:&Facts)->usize{facts.events.len()}

fn writer_using<C:crate::key_policy_control::Control>(writers:&[String],rel:&str,c:&mut C)->Result<bool,C::Error>{for name in writers{c.checkpoint()?;if name==rel{return Ok(true)}}Ok(false)}
fn exempt_using<C:crate::key_policy_control::Control>(rel:&str,prefixes:&[String],c:&mut C)->Result<bool,C::Error>{for prefix in prefixes{c.checkpoint()?;if rel.starts_with(prefix){return Ok(true)}}Ok(false)}
