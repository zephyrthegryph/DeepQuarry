//! Unique cooldown judge; selected source and completion remain caller-issued.
use crate::lint::{Meta,Policy,RuleMeta,ScanKind};
use crate::tree::{SourceFile,CODE_DM};
use crate::pat::Pat;
use crate::util::{py_lstrip,py_strip};
pub static META: Meta = Meta {
    name: crate::allow_registry_fields::cooldown::SCOPE_META_0.name,
    group: crate::allow_registry_fields::cooldown::SCOPE_META_0.group,
    label: "cooldown",
    legacy: "tools/ci/cooldown_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "raw_compare",
        hint: "use COOLDOWN_START/COOLDOWN_FINISHED (code/defines/engine/cooldowns.dm) or om_after()",
    }],
    allow: crate::allow_registry_fields::cooldown::ALLOW_0,
    lists: crate::allow_registry_fields::cooldown::SCOPE_META_0.lists,
};

const CMP: &str = r"(?:>=|<=|(?<![<>=!])>(?![>=])|(?<![<>=])<(?![<=]))";
const CONST: &str = r"\d+(?:\.\d+)?(?:\s+(?:SECONDS?|MINUTES?|HOURS?|DECISECONDS?))?";

pub struct Patterns {
    compare: Pat,
    time_name: Pat,
    data_slot: Pat,
    reagent_data: Pat,
    const_cmp: Pat,
}

impl Patterns {
    pub fn new() -> Patterns {
        Patterns {
            compare: Pat::new(&format!(r"(?<![\w.])world\.time\s*{cmp}|{cmp}\s*world\.time(?![\w])", cmp = CMP)),
            time_name: Pat::new(r"\b\w*(?:_at|_until|_since|deadline|expires|expires_at|expiry|timestamp|timeofdeath)\b"),
            data_slot: Pat::new(r#"\[\s*(?:""|\d+)\s*\]"#),
            reagent_data: Pat::new(r"(?<![\w.])data\b"),
            const_cmp: Pat::new(&format!(
                r"world\.time\s*{cmp}\s*{c}\s*(?:\)|$|&&|\|\|)|(?:^|\(|&&|\|\|)\s*{c}\s*{cmp}\s*world\.time",
                cmp = CMP,
                c = CONST
            )),
        }
    }
}

fn not_a_cooldown(p: &Patterns, rel: &str, line: &str, stamp: &Option<Pat>) -> bool {
    if p.time_name.is_match(line) || p.data_slot.is_match(line) || p.const_cmp.is_match(py_strip(line)) {
        return true;
    }
    if let Some(s) = stamp {
        if s.is_match(line) {
            return true;
        }
    }
    (rel.starts_with("code/modules/reagents/") || rel.starts_with("code/content/reagents/")) && p.reagent_data.is_match(line)
}


pub fn judge(f:&SourceFile,p:&Patterns,kept:impl FnMut(usize)->bool)->Vec<u32>{judge_using(f,p,kept,&mut crate::key_policy_control::Compatibility).expect("original cooldown judge")}
pub fn judge_using<C:crate::key_policy_control::Control>(f:&SourceFile,p:&Patterns,mut kept:impl FnMut(usize)->bool,c:&mut C)->Result<Vec<u32>,C::Error>{c.checkpoint()?;
                let mut lines: Vec<u32> = Vec::new();
                if !f.text().contains("world.time") {
                    return Ok(lines);
                }
                for (number, line) in f.code().numbered() {c.checkpoint()?;
                    if py_lstrip(line).starts_with('#') {
                        continue;
                    }
                    if p.compare.is_match(line) && !not_a_cooldown(p, &f.rel, line, &None) {
                        // ALLOW is asked only for a line that would count.
                        if !kept(number) {
                            crate::raw_tree_report::row(c,&mut lines)?;lines.push(number as u32);
                        }
                    }
                }
                c.checkpoint()?;Ok(lines)
}
