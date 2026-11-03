//! Unique original expiry comparison, stored-write, cooldown-use and TIME_NOW policies.
use std::collections::BTreeSet;
use serde::{Deserialize,Serialize};
use crate::{pat,pat::Pat,tree::SourceFile,util::{before_slashes,py_lstrip,py_strip},key_policy_control::Control};
const SKIP: &[&str] = &["code/datums/om/", "code/controllers/master.dm", "code/controllers/failsafe.dm"];
/// `cooldown_lint.SKIP_DIRS`.
const COOLDOWN_SKIP_DIRS: &[&str] = &["code/modules/unit_tests/", "code/tests/unit_tests/", "code/controllers/", "code/datums/om/"];

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
fn not_a_cooldown(rel: &str, line: &str, stamp: Option<&Pat>) -> bool {
    if pat!(r"\b\w*(?:_at|_until|_since|deadline|expires|expires_at|expiry|timestamp|timeofdeath)\b").is_match(line)
        || pat!(r#"\[\s*(?:""|\d+)\s*\]"#).is_match(line)
        || const_cmp().is_match(py_strip(line))
    {
        return true;
    }
    if let Some(s) = stamp {
        if s.is_match(line) {
            return true;
        }
    }
    (rel.starts_with("code/modules/reagents/") || rel.starts_with("code/content/reagents/")) && pat!(r"(?<![\w.])data\b").is_match(line)
}

pub fn pass_compares_using<C:Control>(f:&SourceFile,stamp:Option<&Pat>,control:&mut C,kept:&mut impl FnMut(usize,&mut C)->Result<bool,C::Error>)->Result<Vec<usize>,C::Error>{
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
        if compare().is_match(code) && !const_cmp().is_match(py_strip(code)) {
            // A compare cooldown_lint counts (not a recorded time) belongs to that lint.
            if not_a_cooldown(rel, code, stamp) || !rel.starts_with("code/") {
                hit = !kept(number,control)?;
            } else if COOLDOWN_SKIP_DIRS.iter().any(|p| rel.starts_with(p)) {
                hit = true;
            }
        }
        if !hit && elapsed().is_match(code) {
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

pub fn pass_writes_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,control:&mut C,temp:&mut T)->Result<Writes,C::Error>{
    control.checkpoint()?;crate::key_policy_control::reserve(temp,||f.text().len().checked_mul(128)?.checked_add(4096))?;
    let mut w = Writes { declared: Vec::new(), writes: Vec::new(), uses: Vec::new() };
    let skip = skipped(&f.rel);
    for (number, line) in f.raw().numbered() {
        control.checkpoint()?;
        if line.contains("COOLDOWN_") {
            for c in pat!(r"\b(?:STATIC_)?COOLDOWN_(?:TMP_)?DECLARE\(\s*(\w+)\s*\)").captures_iter(line) {
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
            && pat!(r"(?<![=!<>])=(?!=)\s*\(?\s*world\.time\b(?!\s*[-*/%])").is_match(code)
            && !pat!(r"\A(?:\s*var/(?!static))").is_match(code)
        {
            crate::raw_tree_report::row(control,&mut w.writes)?;w.writes.push(number);
        }
        if code.contains("COOLDOWN_") {
            for c in pat!(r"\b(?:COOLDOWN_(?:EXTEND|RUNNING|LAPSED)(?:_OWN)?|COOLDOWN_(?:START|FINISHED|TIMELEFT)_OWN)\(\s*[^,()]+(?:\([^()]*\))?\s*,\s*(\w+)").captures_iter(code) {
                control.checkpoint()?;crate::raw_tree_report::row(control,&mut w.uses)?;w.uses.push((number, crate::raw_tree_report::own(control,c.s(1))?));
            }
        }
    }
    control.checkpoint()?;Ok(w)
}

pub fn pass_at_writes_using<C:Control,T:Control<Error=C::Error>>(f:&SourceFile,control:&mut C,temp:&mut T)->Result<Vec<usize>,C::Error>{
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
                if let Some(head) = pat!(r"\A(?:/[\w/]*\(([^)]*)\))").captures(line) {
                    let params = head.s(1);
                    for c in pat!(r"\bvar/(?:[\w]+/)*(\w+)").captures_iter(params) {
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
        for c in pat!(r"\bvar/(?:[\w]+/)*(\w+)").captures_iter(code) {
            control.checkpoint()?;
            local.insert(c.s(1).to_string());
        }
        let Some(m) = pat!(r"\A(?:\s*((?:\w+\.)*)(\w+)\s*=\s*TIME_NOW\()").captures(code) else { continue };
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
