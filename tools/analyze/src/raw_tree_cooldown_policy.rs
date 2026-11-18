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

macro_rules! cooldown_compare_source{($format:ident)=>{$format!(r"(?<![\w.])world\.time\s*{cmp}|{cmp}\s*world\.time(?![\w])",cmp=CMP)}}
macro_rules! cooldown_constant_source{($format:ident)=>{$format!(r"world\.time\s*{cmp}\s*{c}\s*(?:\)|$|&&|\|\|)|(?:^|\(|&&|\|\|)\s*{c}\s*{cmp}\s*world\.time",cmp=CMP,c=CONST)}}
const COOLDOWN_STATIC_SOURCES:&[&str]=&[r"\b\w*(?:_at|_until|_since|deadline|expires|expires_at|expiry|timestamp|timeofdeath)\b",r#"\[\s*(?:""|\d+)\s*\]"#,r"(?<![\w.])data\b"];
pub struct Patterns<P=Pat> {
    compare: P,
    time_name: P,
    data_slot: P,
    reagent_data: P,
    const_cmp: P,
}

impl Patterns {
    pub fn new() -> Patterns {
        Patterns {
            compare: Pat::new(&cooldown_compare_source!(format)),
            time_name: Pat::new(COOLDOWN_STATIC_SOURCES[0]),
            data_slot: Pat::new(COOLDOWN_STATIC_SOURCES[1]),
            reagent_data: Pat::new(COOLDOWN_STATIC_SOURCES[2]),
            const_cmp: Pat::new(&cooldown_constant_source!(format)),
        }
    }
}

fn not_a_cooldown<P:crate::raw_fixture_policy::PatternApi>(p:&Patterns<P>,rel:&str,line:&str,stamp:&Option<P>) -> bool {
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


pub fn judge<P:crate::raw_fixture_policy::PatternApi>(f:&SourceFile,p:&Patterns<P>,kept:impl FnMut(usize)->bool)->Vec<u32>{judge_using(f,p,kept,&mut crate::key_policy_control::Compatibility).expect("original cooldown judge")}
pub fn judge_using<P:crate::raw_fixture_policy::PatternApi,C:crate::key_policy_control::Control>(f:&SourceFile,p:&Patterns<P>,mut kept:impl FnMut(usize)->bool,c:&mut C)->Result<Vec<u32>,C::Error>{c.checkpoint()?;
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

#[cfg(feature="native-policy")]
pub fn native_patterns<'f,'a>(fixture:&'f crate::raw_fixture_policy::Fixture<'a>)->Result<Patterns<crate::raw_fixture_policy::Pattern<'f,'a>>,String>{
 use crate::raw_fixture_policy::PatternMode;
 Ok(Patterns{
  compare:fixture.formatted_pattern(cooldown_compare_source!(format_args),PatternMode::Search)?,
  time_name:fixture.pattern(COOLDOWN_STATIC_SOURCES[0],PatternMode::Search,||crate::pat!(COOLDOWN_STATIC_SOURCES[0])),
  data_slot:fixture.pattern(COOLDOWN_STATIC_SOURCES[1],PatternMode::Search,||crate::pat!(COOLDOWN_STATIC_SOURCES[1])),
  reagent_data:fixture.pattern(COOLDOWN_STATIC_SOURCES[2],PatternMode::Search,||crate::pat!(COOLDOWN_STATIC_SOURCES[2])),
  const_cmp:fixture.formatted_pattern(cooldown_constant_source!(format_args),PatternMode::Search)?,
 })
}
