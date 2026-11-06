//! Shared declaration-block policy; facts and sinks carry no source completion authority.
use crate::lint::{Meta,Policy,RuleMeta,ScanKind};
use crate::tree::{SourceFile,CODE_DM};
use crate::raw_tree_report::Reporter;
const TWO_HINT: &str = "a type has one CAPABILITIES block: move this block's entries under the first one (a codemod that adds a declaration appends to the existing block)";
const BUNDLE_HINT: &str = "BUNDLE is gone: entries one type groups are a section(name, \"doc\") inside its CAPABILITIES block (PROC_REF, nameof(v)); entries several types share are a capability (CAPABILITY_DEF/TYPE) or a plain /proc/name() returning list(entries)";
const HINT: &str = "write the entries as indented statements under the header (CAPABILITIES(T) then one entry per line); `python tools/dx/codemods/capabilities_block.py` converts a file";

pub static META: Meta = Meta {
    name: crate::allow_registry_fields::declaration_block::SCOPE_META_0.name,
    group: crate::allow_registry_fields::declaration_block::SCOPE_META_0.group,
    label: "declaration_block",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Both,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "backslash_list", hint: HINT }, RuleMeta { name: "two_blocks", hint: TWO_HINT }, RuleMeta { name: "bundle", hint: BUNDLE_HINT }],
    allow: crate::allow_registry_fields::declaration_block::ALLOW_0,
    lists: crate::allow_registry_fields::declaration_block::SCOPE_META_0.lists,
};

pub fn scan_file(f:&SourceFile,out:&mut impl Reporter){
        let head = crate::pat_match!(r"^(CAPABILITIES|STATE_GRAPH)\(");
        let inline = crate::pat_match!(r"^(?:CAPABILITIES|STATE_GRAPH)\([^,()]*,");
        let bundle = crate::pat_match!(r"^BUNDLE\(");
        for (number, line) in f.raw().numbered() {if !out.checkpoint(){return}
            if bundle.is_match(line) {
                out.site_in_msg("bundle", &f.rel, number, "BUNDLE(...) is no longer a declaration form".to_string());
                continue;
            }
            if !head.is_match(line) {
                continue;
            }
            let t = line.trim_end();
            if t.ends_with('\\')|| inline.is_match(line) {
                out.site_in_msg("backslash_list", &f.rel, number, format!("{} is written as a backslash list", line.split('(').next().unwrap_or("")));
            }
        }
}
pub fn blocks(f:&SourceFile,mut visit:impl FnMut(&str,usize)){blocks_using(f,visit,&mut crate::key_policy_control::Compatibility).expect("original declaration_block source index")}
pub fn blocks_using<C:crate::key_policy_control::Control>(f:&SourceFile,mut visit:impl FnMut(&str,usize),c:&mut C)->Result<(),C::Error>{c.checkpoint()?;
 if !f.rel.ends_with(".dm")||f.rel.starts_with("code/engine/_generated/"){return Ok(())}
 let head=crate::pat_match!(r"^CAPABILITIES\((/[\w/]+)\)");
 for(number,line)in f.code().numbered(){c.checkpoint()?;if let Some(m)=head.captures(line){visit(m.s(1),number)}}
c.checkpoint()?;Ok(())}
pub fn assemble<'a>(rows:impl IntoIterator<Item=(&'a str,&'a str,usize)>,out:&mut impl Reporter){
 let mut first:std::collections::HashMap<String,(String,usize)>=std::collections::HashMap::new();
 for(ty,rel,number)in rows{if !out.checkpoint(){return}match first.get(ty){None=>{first.insert(ty.to_string(),(rel.to_string(),number));},Some((rel0,at))=>out.site_in_msg("two_blocks",rel,number,format!("{} already has a CAPABILITIES block at {}:{}",ty,rel0,at))}}
}
