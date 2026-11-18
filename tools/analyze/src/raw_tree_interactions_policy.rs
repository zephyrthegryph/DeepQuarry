//! Unique interactions declaration/inheritance algorithm.
use crate::raw_fixture_policy::PatternApi as _;
use std::collections::BTreeMap;
use crate::lint::{Meta,Policy,RuleMeta,ScanKind};
use crate::tree::{SourceFile,CODE_DM};
use crate::pat;
use crate::raw_tree_report::Reporter;
pub static META: Meta = Meta {
    name: crate::allow_registry_fields::interactions::SCOPE_META_0.name,
    group: crate::allow_registry_fields::interactions::SCOPE_META_0.group,
    label: "interactions",
    legacy: "tools/ci/interactions_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "shadow",
        hint: "use EXTEND_INTERACTIONS, or annotate `// ALLOW(interactions): reason`",
    }],
    allow: crate::allow_registry_fields::interactions::ALLOW_0,
    lists: crate::allow_registry_fields::interactions::SCOPE_META_0.lists,
};


pub fn declarations(f:&SourceFile,mut visit:impl FnMut(&str,usize)){declarations_using(f,visit,&mut crate::key_policy_control::Compatibility).expect("original interactions source index")}
pub fn declarations_using<C:crate::key_policy_control::Control>(f:&SourceFile,mut visit:impl FnMut(&str,usize),c:&mut C)->Result<(),C::Error>{declarations_using_with_fixture(f,visit,c,&crate::raw_fixture_policy::Fixture::legacy())}
pub fn declarations_using_with_fixture<C:crate::key_policy_control::Control>(f:&SourceFile,mut visit:impl FnMut(&str,usize),c:&mut C,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),C::Error>{c.checkpoint()?;for(number,line)in f.raw().numbered(){c.checkpoint()?;let m=fixture.pattern(r"^\s*DECLARE_INTERACTIONS\(\s*(/[\w/]+)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^\s*DECLARE_INTERACTIONS\(\s*(/[\w/]+)")).captures(line).or_else(||fixture.pattern(r"^(/[\w/]+)/get_interactions\(\)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^(/[\w/]+)/get_interactions\(\)")).captures(line));if let Some(m)=m{visit(m.s(1),number)}}c.checkpoint()?;Ok(())}
pub fn assemble<'a>(rows:impl IntoIterator<Item=(&'a str,&'a str,usize,bool)>,out:&mut impl Reporter){let mut sites:BTreeMap<String,(String,usize,bool)>=BTreeMap::new();for(path,rel,line,ok)in rows{if !out.checkpoint(){return}sites.insert(path.to_string(),(rel.to_string(),line,ok));}
        let mut bad = 0;
        for (path, (rel, number, ok)) in &sites {
 if !out.checkpoint(){return}
            let parts: Vec<&str> = path.split('/').collect();
            let mut cut = parts.len() as i64 - 1;
            while cut > 1 {
 if !out.checkpoint(){return}
                let ancestor = parts[..cut as usize].join("/");
                if let Some((arel, anum, _)) = sites.get(&ancestor) {
                    if !ok {
                        bad += 1;
                        out.site_in_msg(
                            "shadow",
                            rel,
                            *number,
                            format!(
                                "DECLARE_INTERACTIONS({}) discards {}'s specs ({}:{}): use EXTEND_INTERACTIONS, or annotate `// ALLOW(interactions): reason`",
                                path, ancestor, arel, anum
                            ),
                        );
                    }
                    break;
                }
                cut -= 1;
            }
        }
        out.note(format!("interactions_lint: {} declaring types, {} unannotated shadowing sites", sites.len(), bad));
}
