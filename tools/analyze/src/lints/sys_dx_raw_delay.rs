//! Port of `tools/ci/sys_rules/dx_raw_delay.py`: raw decisecond literals in delay arguments
//! (AGENTS.md 3f; dx_conventions.md section 7). The delay argument of a timer or delayed action
//! holds a numeric literal other than 0 that is not scaled by a time define.

use crate::raw_fixture_policy::PatternApi as _;
use crate::dm::dx::match_paren;
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::tree::SourceFile;
use crate::util::py_rstrip;
use crate::{pat, pat_match};

use crate::allow_registry_fields::sys_dx_raw_delay::RULES;

/// call name -> (positional index of the delay, named argument that can carry it)
const DELAY_ARGS: &[(&str, usize, &str)] = &[
    ("after", 1, "delay"),
    ("om_after", 1, "delay"),
    ("om_after_unique", 1, "delay"),
    ("om_after_replace", 1, "delay"),
    ("om_after_slot", 2, "delay"),
    ("after_slot", 2, "delay"),
    ("look_flash", 2, "duration"),
    ("om_after_realtime", 0, "delay"),
    ("addtimer", 1, "wait"),
    ("do_after", 1, "delay"),
    ("COOLDOWN_START", 2, "cd_time"),
    ("timed_set", 3, "for_time"),
    ("cap_tool", 3, "delay"),
];

const UNITS: &str = r"(?:MILLISECONDS?|DECISECONDS?|SECONDS?|MINUTES?|HOURS?|TICKS?|DAYS?)\b";

const NATIVE_CALL_SOURCE:&str=r"(?<![\w./:])(COOLDOWN_START|addtimer|after|after_slot|cap_tool|do_after|look_flash|om_after|om_after_realtime|om_after_replace|om_after_slot|om_after_unique|timed_set|cap_\w+)\s*\(";
const NATIVE_UNITS_SOURCE:&str=r"\s*(?:MILLISECONDS?|DECISECONDS?|SECONDS?|MINUTES?|HOURS?|TICKS?|DAYS?)\b";
fn require_image_pattern_binding(fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
 let prefix=r"(?<![\w./:])(";let suffix=r"|cap_\w+)\s*\(";
 let mut valid=NATIVE_UNITS_SOURCE.strip_prefix(r"\s*")==Some(UNITS);let mut count=0;let mut prior=None;
 if let Some(body)=NATIVE_CALL_SOURCE.strip_prefix(prefix).and_then(|source|source.strip_suffix(suffix)){
  for name in body.split('|'){valid&=DELAY_ARGS.iter().any(|row|row.0==name)&&prior.is_none_or(|old|old<name);prior=Some(name);count+=1;}
 }else{valid=false}
 valid&=count==DELAY_ARGS.len();fixture.require_pattern_binding(valid)
}
fn call_pat() -> &'static Pat {
    static P: std::sync::LazyLock<Pat> = std::sync::LazyLock::new(|| {
        let mut names: Vec<&str> = DELAY_ARGS.iter().map(|d| d.0).collect();
        names.sort();
        Pat::new(&format!(r"(?<![\w./:])({}|cap_\w+)\s*\(", names.join("|")))
    });
    &P
}

fn units_after() -> &'static Pat {
    static P: std::sync::LazyLock<Pat> = std::sync::LazyLock::new(|| Pat::new_match(&format!(r"\s*{}", UNITS)));
    &P
}

/// `blank_scaled_groups`: `expr` with every (...) group followed by a time define blanked.
fn blank_scaled_groups_using(expr:&str,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<String,String>{
    require_image_pattern_binding(fixture)?;
    fixture.check()?;
    let mut chars = fixture.collect(expr.bytes())?;
    for (i, c) in expr.bytes().enumerate() {
        if c != b'(' {
            continue;
        }
        if let Some(end) = match_paren(expr, i) {
            if end > 0 && fixture.pattern(NATIVE_UNITS_SOURCE,crate::raw_fixture_policy::PatternMode::Match,units_after).is_match(&expr[end + 1..]) {
                for byte in chars.iter_mut().take(end).skip(i + 1) {
                    *byte = b' ';
                }
            }
        }
    }
    match String::from_utf8(chars){Ok(value)=>Ok(value),Err(_)=>fixture.own(expr)}
}

/// `raw_literal`: a numeric literal other than 0 not scaled by a unit or used as a factor.
fn raw_literal_using(expr:&str,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<bool,String>{
    require_image_pattern_binding(fixture)?;
    fixture.check()?;
    let expr = blank_scaled_groups_using(expr,fixture)?;
    let number = fixture.pattern(r"(?<![\w.])(\d+(?:\.\d+)?(?:e[+-]?\d+)?|\.\d+)(?![\w.])",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w.])(\d+(?:\.\d+)?(?:e[+-]?\d+)?|\.\d+)(?![\w.])"));
    for m in fixture.captures_iter(&number,&expr)? {
        let lit = m.s(1);
        if lit.parse::<f64>().map(|v| v == 0.0).unwrap_or(false) {
            continue;
        }
        let (start, end) = (m.start(0), m.end(0));
        let after = &expr[end..];
        let before = py_rstrip(&expr[..start]);
        if fixture.pattern(NATIVE_UNITS_SOURCE,crate::raw_fixture_policy::PatternMode::Match,units_after).is_match(after) {
            continue;
        }
        if before.ends_with('*') || before.ends_with('/') || fixture.pattern(r"\s*\*",crate::raw_fixture_policy::PatternMode::Match,||crate::pat_match!(r"\s*\*")).is_match(after) {
            continue;
        }
        return Ok(true);
    }
    Ok(false)
}

/// `delays_of`: the delay expressions of one call.
fn delays_of_using(name:&str,args:&[String],fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<Vec<String>,String>{
    fixture.check()?;
    let mut out: Vec<Option<String>> = Vec::new();
    if let Some((_, index, key)) = DELAY_ARGS.iter().find(|d| d.0 == name) {
        let mut got = fixture.pick_arg(args,Some(*index),key)?;
        if got.is_none() && *key != "delay" {
            got = fixture.pick_arg(args,None,"delay")?;
        }
        fixture.push(&mut out,got)?;
    }
    if name.starts_with("cap_") {
        fixture.push(&mut out,fixture.pick_arg(args,None,"delay")?)?;
        fixture.push(&mut out,fixture.pick_arg(args,None,"cooldown")?)?;
    }
    fixture.collect(out.into_iter().flatten().filter(|d| !d.is_empty()))
}

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    let text = f.text();
    if !["after", "addtimer", "COOLDOWN_START", "timed_set", "cap_", "look_flash"].iter().any(|k| text.contains(k)) {
        return;
    }
    scan_lines(f, out);
}

fn scan_lines(f:&SourceFile,out:&mut Vec<(&'static str,usize)>){scan_lines_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scanner has no admission refusal")}
fn scan_lines_using(f:&SourceFile,out:&mut Vec<(&'static str,usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    require_image_pattern_binding(fixture)?;
    fixture.check()?;
    for (number, code) in f.clean().numbered() {
        for m in fixture.captures_iter(&fixture.pattern(NATIVE_CALL_SOURCE,crate::raw_fixture_policy::PatternMode::Search,call_pat),code)? {
            let Some(args) = fixture.args(code,m.end(0)-1)? else{continue};
            if args.is_empty() {
                continue;
            }
            let mut raw=false;for delay in delays_of_using(m.s(1),&args,fixture)?{if raw_literal_using(&delay,fixture)?{raw=true;break}}
            if raw {
                fixture.push(out,("dx_raw_delay", number))?;
                break;
            }
        }
    }
    Ok(())
}

fn selftest() -> Result<String, String> {
    selftest_with_fixture(&crate::raw_fixture_policy::Fixture::legacy())
}

fn selftest_with_fixture(fixture: &crate::raw_fixture_policy::Fixture<'_>) -> Result<String, String> {
    let fixture_lines = [
        "om_after(src, 20, PROC_REF(finish))",
        "om_after(src, 2 SECONDS, PROC_REF(finish))",
        "om_after_slot(src, \"x\", rand(10, 20), PROC_REF(x))",
        "om_after_slot(src, \"x\", rand(1, 2) SECONDS, PROC_REF(x))",
        "timed_set(src, nameof(a), TRUE, for_time = 90 SECONDS / severity)",
        "timed_set(src, nameof(a), TRUE, for_time = 50)",
        "timed_set(src, nameof(a), 5, for_time = duration)",
        "COOLDOWN_START(src, cooldown, 15)",
        "COOLDOWN_START(src, cooldown, base_delay * 2)",
        "after(src, 0, PROC_REF(now))",
        "cap_tool(\"Unbolt\", TOOL_WRENCH, PROC_REF(unbolt), 40)",
        "cap_cover(open_tool = TOOL_CROWBAR, delay = 2 SECONDS)",
        "cap_cover(open_tool = TOOL_CROWBAR, delay = 30)",
        "om_after(src, (base + 5) SECONDS, PROC_REF(x))",
        "om_after(src, delay + 5, PROC_REF(x))",
        "/proc/om_after(datum/E, delay, proc_ref, ...)",
        "addtimer(CALLBACK(src, PROC_REF(x)), 10)",
        "do_after(user, 1.5 SECONDS, target)",
        "after_slot(src, \"x\", 5, PROC_REF(x))",
        "cap_hand(\"Ring\", PROC_REF(ring), cooldown = 30)",
        "cap_hand(\"Ring\", PROC_REF(ring), cooldown = 3 SECONDS)",
        "look_flash(src, \"sparks\", 12)",
    ];
    let f = fixture.file("x.dm", &fixture.join(&fixture_lines,"\n")?)?;
    let mut v = Vec::new();
    scan_lines_using(&f,&mut v,fixture)?;
    let got: Vec<usize> = fixture.collect(v.into_iter().map(|(_, n)| n))?;
    let want = [1, 3, 6, 8, 11, 13, 15, 17, 19, 20, 22];
    if got != want {
        return Err(fixture.detail(format_args!("dx_raw_delay selftest: got {:?}, want {:?}", got, want))?);
    }
    Ok(fixture.own("dx_raw_delay")?)
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_dx_raw_delay::SCOPE_MODULE_NAME, rules: RULES, file_scan: Some(scan_file), fixture_file_scan:Some(scan_lines_using), selftest: Some(selftest), fixture_selftest: Some(selftest_with_fixture), py_selftest: true, ..SysModule::DEFAULT },
    );
}
