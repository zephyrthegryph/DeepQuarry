//! Unique original expiry comparison, stored-write, cooldown-use and TIME_NOW policies.
use crate::raw_fixture_policy::PatternApi as _;
use std::collections::BTreeSet;
use serde::{Deserialize,Serialize};
use crate::{pat,pat::Pat,tree::SourceFile,util::{before_slashes,py_lstrip,py_strip},key_policy_control::Control};
const SKIP: &[&str] = &["code/datums/om/", "code/controllers/master.dm", "code/controllers/failsafe.dm"];
/// `cooldown_lint.SKIP_DIRS`.
const COOLDOWN_SKIP_DIRS: &[&str] = &["code/tests/unit_tests/", "code/controllers/", "code/world/kernel/", "code/world/systems/", "code/world/configuration/", "code/world/controllers/", "code/datums/om/"];

/// `CMP` of both modules (a compare operator that is not a shift, `==`, `!=` or `>>`).
macro_rules! cmp {
    () => {
        r"(?:>=|<=|(?<![<>=!])>(?![>=])|(?<![<>=])<(?![<=]))"
    };
}

fn skipped(rel: &str) -> bool {
    SKIP.iter().any(|p| rel.starts_with(p))
}

fn compare() -> &'static Pat {
    pat!(concat!(r"(?<![\w.])world\.time\s*", cmp!(), r"|", cmp!(), r"\s*world\.time(?![\w])"))
}

fn const_cmp() -> &'static Pat {
    pat!(concat!(
        r"world\.time\s*",
        cmp!(),
        r"\s*\d+(?:\.\d+)?(?:\s+(?:SECONDS?|MINUTES?|HOURS?|DECISECONDS?))?\s*(?:\)|$|&&|\|\|)|(?:^|\(|&&|\|\|)\s*\d+(?:\.\d+)?(?:\s+(?:SECONDS?|MINUTES?|HOURS?|DECISECONDS?))?\s*",
        cmp!(),
        r"\s*world\.time"
    ))
}

fn elapsed() -> &'static Pat {
    pat!(concat!(
        r#"(?<![\w.])world\.time\s*-\s*[\w.\[\]\"]+(?:\s*\))?\s*"#,
        cmp!(),
        r"|",
        cmp!(),
        r"\s*\(?\s*world\.time\s*-\s*\w"
    ))
}

/// `cooldown_lint.not_a_cooldown`: the compare reads a recorded time kept as data.
fn not_a_cooldown(rel: &str, line: &str, stamp: Option<&Pat>) -> bool {not_a_cooldown_using(rel,line,stamp,&original_expiry_pattern)}
fn not_a_cooldown_using<S:crate::raw_fixture_policy::PatternApi+?Sized,P:crate::raw_fixture_policy::PatternApi,F:Fn(usize)->P>(rel:&str,line:&str,stamp:Option<&S>,patterns:&F)->bool{
    if patterns(3).is_match(line)
        || patterns(4).is_match(line)
        || patterns(1).is_match(py_strip(line))
    {
        return true;
    }
    if let Some(s) = stamp {
        if s.is_match(line) {
            return true;
        }
    }
    (rel.starts_with("code/modules/reagents/") || rel.starts_with("code/content/reagents/")) && patterns(5).is_match(line)
}

pub fn pass_compares_using<C:Control>(f:&SourceFile,stamp:Option<&Pat>,control:&mut C,kept:&mut impl FnMut(usize,&mut C)->Result<bool,C::Error>)->Result<Vec<usize>,C::Error>{pass_compares_using_with_programs(f,stamp,control,kept,&original_expiry_pattern)}
#[cfg(feature="native-policy")]
pub fn pass_compares_with_fixture<C:Control>(f:&SourceFile,control:&mut C,kept:&mut impl FnMut(usize,&mut C)->Result<bool,C::Error>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<Vec<usize>,C::Error>{pass_compares_using_with_programs(f,None::<&Pat>,control,kept,&|id|native_expiry_pattern(fixture,id))}
pub fn pass_compares_using_with_programs<S:crate::raw_fixture_policy::PatternApi+?Sized,P:crate::raw_fixture_policy::PatternApi,F:Fn(usize)->P,C:Control>(f:&SourceFile,stamp:Option<&S>,control:&mut C,kept:&mut impl FnMut(usize,&mut C)->Result<bool,C::Error>,patterns:&F)->Result<Vec<usize>,C::Error>{
    control.checkpoint()?;
    let mut out = Vec::new();
    let rel = f.rel.as_str();
    if skipped(rel) || !f.raw().text.contains("world.time") {
        return Ok(out);
    }
    for (number, line) in f.raw().numbered() {
        control.checkpoint()?;
        let code = before_slashes(line);
        if !code.contains("world.time") || py_lstrip(code).starts_with('#') {
            continue;
        }
        let mut hit = false;
        if patterns(0).is_match(code) && !patterns(1).is_match(py_strip(code)) {
            // A compare cooldown_lint counts (not a recorded time) belongs to that lint.
            if not_a_cooldown_using(rel,code,stamp,patterns) || !rel.starts_with("code/") {
                hit = !kept(number,control)?;
            } else if COOLDOWN_SKIP_DIRS.iter().any(|p| rel.starts_with(p)) {
                hit = true;
            }
        }
        if !hit && patterns(2).is_match(code) {
            hit = true;
        }
        if hit {
            crate::raw_tree_report::row(control,&mut out)?;out.push(number);
        }
    }
    control.checkpoint()?;Ok(out)
}

#[derive(Serialize, Deserialize, Default, PartialEq)]
pub struct Writes {
    pub declared: Vec<String>,
    pub writes: Vec<usize>,
    pub uses: Vec<(usize, String)>,
}

pub fn pass_writes_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,control:&mut C,temp:&mut T)->Result<Writes,C::Error>{pass_writes_using_with_programs(f,control,temp,&original_expiry_pattern)}
#[cfg(feature="native-policy")]
pub fn pass_writes_with_fixture<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,control:&mut C,temp:&mut T,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<Writes,C::Error>{pass_writes_using_with_programs(f,control,temp,&|id|native_expiry_pattern(fixture,id))}
pub fn pass_writes_using_with_programs<P:crate::raw_fixture_policy::PatternApi,F:Fn(usize)->P,C:Control,T:Control<Error=C::Error>>(f:&SourceFile,control:&mut C,temp:&mut T,patterns:&F)->Result<Writes,C::Error>{
    control.checkpoint()?;crate::key_policy_control::reserve(temp,||f.text().len().checked_mul(128)?.checked_add(4096))?;
    let mut w = Writes { declared: Vec::new(), writes: Vec::new(), uses: Vec::new() };
    let skip = skipped(&f.rel);
    for (number, line) in f.raw().numbered() {
        control.checkpoint()?;
        if line.contains("COOLDOWN_") {
            for c in patterns(6).captures_iter(line) {
                control.checkpoint()?;crate::raw_tree_report::row(control,&mut w.declared)?;w.declared.push(crate::raw_tree_report::own(control,c.s(1))?);
            }
        }
        if skip {
            continue;
        }
        let code = before_slashes(line);
        if py_lstrip(code).starts_with('#') {
            continue;
        }
        if code.contains("world.time")
            && patterns(7).is_match(code)
            && !patterns(8).is_match(code)
        {
            crate::raw_tree_report::row(control,&mut w.writes)?;w.writes.push(number);
        }
        if code.contains("COOLDOWN_") {
            for c in patterns(9).captures_iter(code) {
                control.checkpoint()?;crate::raw_tree_report::row(control,&mut w.uses)?;w.uses.push((number, crate::raw_tree_report::own(control,c.s(1))?));
            }
        }
    }
    control.checkpoint()?;Ok(w)
}

pub fn pass_at_writes_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,control:&mut C,temp:&mut T)->Result<Vec<usize>,C::Error>{pass_at_writes_using_with_programs(f,control,temp,&original_expiry_pattern)}
#[cfg(feature="native-policy")]
pub fn pass_at_writes_with_fixture<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,control:&mut C,temp:&mut T,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<Vec<usize>,C::Error>{pass_at_writes_using_with_programs(f,control,temp,&|id|native_expiry_pattern(fixture,id))}
pub fn pass_at_writes_using_with_programs<P:crate::raw_fixture_policy::PatternApi,F:Fn(usize)->P,C:Control,T:Control<Error=C::Error>>(f:&SourceFile,control:&mut C,temp:&mut T,patterns:&F)->Result<Vec<usize>,C::Error>{
    control.checkpoint()?;crate::key_policy_control::reserve(temp,||f.text().len().checked_mul(256)?.checked_add(4096))?;
    let mut out = Vec::new();
    if skipped(&f.rel) || !f.raw().text.contains("TIME_NOW(") {
        return Ok(out);
    }
    let mut local: BTreeSet<String> = BTreeSet::new();
    for (number, line) in f.raw().numbered() {
        control.checkpoint()?;
        if let Some(ch) = line.chars().next() {
            if !crate::util::is_py_space(ch) {
                local.clear();
                if let Some(head) = patterns(10).captures(line) {
                    let params = head.s(1);
                    for c in patterns(11).captures_iter(params) {
                        control.checkpoint()?;
                        local.insert(c.s(1).to_string());
                    }
                    for w in params.split(',') {
                        control.checkpoint()?;
                        local.insert(py_strip(w.split('=').next().unwrap_or("")).to_string());
                    }
                }
                continue;
            }
        }
        let code = before_slashes(line);
        for c in patterns(12).captures_iter(code) {
            control.checkpoint()?;
            local.insert(c.s(1).to_string());
        }
        let Some(m) = patterns(13).captures(code) else { continue };
        if py_lstrip(code).starts_with("var/") {
            continue;
        }
        let (mut owner, name) = (m.s(1), m.s(2));
        if owner.starts_with("GLOB.") {
            owner = &owner[5..];
            if owner.is_empty() {
                continue; // a GLOBAL_VAR cannot be COOLDOWN_DECLAREd
            }
        }
        if !owner.is_empty() || !local.contains(name) {
            crate::raw_tree_report::row(control,&mut out)?;out.push(number);
        }
    }
    control.checkpoint()?;Ok(out)
}

pub(crate) fn pass_compares(f:&SourceFile,stamp:Option<&Pat>)->Vec<usize>{pass_compares_using(f,stamp,&mut crate::key_policy_control::Compatibility,&mut|number,_|Ok(crate::dm::sys::kept_recorded(f,number,"cooldown"))).expect("original expiry compares")}
pub(crate) fn pass_writes(f:&SourceFile)->Writes{pass_writes_using(f,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original expiry writes")}
pub(crate) fn pass_at_writes(f:&SourceFile)->Vec<usize>{pass_at_writes_using(f,&mut crate::key_policy_control::Compatibility,&mut crate::key_policy_control::Compatibility).expect("original expiry TIME_NOW writes")}

fn original_expiry_pattern(id:usize)->&'static Pat{match id{0=>compare(),1=>const_cmp(),2=>elapsed(),3=>crate::pat!(r"\b\w*(?:_at|_until|_since|deadline|expires|expires_at|expiry|timestamp|timeofdeath)\b"),4=>crate::pat!(r#"\[\s*(?:""|\d+)\s*\]"#),5=>crate::pat!(r"(?<![\w.])data\b"),6=>crate::pat!(r"\b(?:STATIC_)?COOLDOWN_(?:TMP_)?DECLARE\(\s*(\w+)\s*\)"),7=>crate::pat!(r"(?<![=!<>])=(?!=)\s*\(?\s*world\.time\b(?!\s*[-*/%])"),8=>crate::pat!(r"\A(?:\s*var/(?!static))"),9=>crate::pat!(r"\b(?:COOLDOWN_(?:EXTEND|RUNNING|LAPSED)(?:_OWN)?|COOLDOWN_(?:START|FINISHED|TIMELEFT)_OWN)\(\s*[^,()]+(?:\([^()]*\))?\s*,\s*(\w+)"),10=>crate::pat!(r"\A(?:/[\w/]*\(([^)]*)\))"),11=>crate::pat!(r"\bvar/(?:[\w]+/)*(\w+)"),12=>crate::pat!(r"\bvar/(?:[\w]+/)*(\w+)"),13=>crate::pat!(r"\A(?:\s*((?:\w+\.)*)(\w+)\s*=\s*TIME_NOW\()"),_=>unreachable!("closed original expiry pattern slot")}}
#[cfg(feature="native-policy")]
fn native_expiry_pattern<'f,'a>(fixture:&'f crate::raw_fixture_policy::Fixture<'a>,id:usize)->crate::raw_fixture_policy::Pattern<'f,'a>{match id{0=>fixture.pattern(concat!(r"(?<![\w.])world\.time\s*", cmp!(), r"|", cmp!(), r"\s*world\.time(?![\w])"),crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(0)),1=>fixture.pattern(concat!(
        r"world\.time\s*",
        cmp!(),
        r"\s*\d+(?:\.\d+)?(?:\s+(?:SECONDS?|MINUTES?|HOURS?|DECISECONDS?))?\s*(?:\)|$|&&|\|\|)|(?:^|\(|&&|\|\|)\s*\d+(?:\.\d+)?(?:\s+(?:SECONDS?|MINUTES?|HOURS?|DECISECONDS?))?\s*",
        cmp!(),
        r"\s*world\.time"
    ),crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(1)),2=>fixture.pattern(concat!(
        r#"(?<![\w.])world\.time\s*-\s*[\w.\[\]\"]+(?:\s*\))?\s*"#,
        cmp!(),
        r"|",
        cmp!(),
        r"\s*\(?\s*world\.time\s*-\s*\w"
    ),crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(2)),3=>fixture.pattern(r"\b\w*(?:_at|_until|_since|deadline|expires|expires_at|expiry|timestamp|timeofdeath)\b",crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(3)),4=>fixture.pattern(r#"\[\s*(?:""|\d+)\s*\]"#,crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(4)),5=>fixture.pattern(r"(?<![\w.])data\b",crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(5)),6=>fixture.pattern(r"\b(?:STATIC_)?COOLDOWN_(?:TMP_)?DECLARE\(\s*(\w+)\s*\)",crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(6)),7=>fixture.pattern(r"(?<![=!<>])=(?!=)\s*\(?\s*world\.time\b(?!\s*[-*/%])",crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(7)),8=>fixture.pattern(r"\A(?:\s*var/(?!static))",crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(8)),9=>fixture.pattern(r"\b(?:COOLDOWN_(?:EXTEND|RUNNING|LAPSED)(?:_OWN)?|COOLDOWN_(?:START|FINISHED|TIMELEFT)_OWN)\(\s*[^,()]+(?:\([^()]*\))?\s*,\s*(\w+)",crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(9)),10=>fixture.pattern(r"\A(?:/[\w/]*\(([^)]*)\))",crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(10)),11=>fixture.pattern(r"\bvar/(?:[\w]+/)*(\w+)",crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(11)),12=>fixture.pattern(r"\bvar/(?:[\w]+/)*(\w+)",crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(12)),13=>fixture.pattern(r"\A(?:\s*((?:\w+\.)*)(\w+)\s*=\s*TIME_NOW\()",crate::raw_fixture_policy::PatternMode::Search,||original_expiry_pattern(13)),_=>unreachable!("closed native expiry pattern slot")}}

#[cfg(test)]mod borrowed_stamp_lifetime_controls{
 use super::*;
 #[test]fn local_stamp_borrow_is_independent_of_static_recipe_lifetime(){
  let stamp=Pat::new(r"\bremembered\b");let text="if(world.time > remembered) return";
  assert!(not_a_cooldown("code/content/probe.dm",text,Some(&stamp)));
  assert!(!not_a_cooldown("code/content/probe.dm",text,None));
  let file=SourceFile::from_text("code/content/probe.dm",text);let mut control=crate::key_policy_control::Compatibility;
  assert_eq!(pass_compares_using(&file,Some(&stamp),&mut control,&mut|_,_|Ok(false)).unwrap(),vec![1]);
  assert!(pass_compares_using(&file,None,&mut control,&mut|_,_|Ok(false)).unwrap().is_empty());
 }
}
