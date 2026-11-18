//! Port of `tools/ci/sys_rules/dx_raw_overlays.py`: raw overlay writes outside the look builder
//! (design review M9). `add_overlay(` / `cut_overlay(` / `cut_overlays(` / `overlays +=` /
//! `overlays -=` outside the look builder. A hard ban: the baseline is empty. The engine files that compile looks to overlays are
//! exempt by path in `[lint."sys/dx_raw_overlays"]` of tools/ci/lint_scopes.toml.

use crate::raw_fixture_policy::PatternApi as _;
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;

use crate::allow_registry_fields::sys_dx_raw_overlays::RULES;

/// `scan_file` of the Python: one site per sanitized line with a raw overlay write.
fn scan_lines(f:&SourceFile,out:&mut Vec<(&'static str,usize)>){
    scan_lines_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scanner has no admission refusal")
}
fn scan_lines_using(f:&SourceFile,out:&mut Vec<(&'static str,usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    fixture.check()?;
    let raw = fixture.pattern(r"(?<![\w/])(?:add_overlay|cut_overlays?)\s*\(|(?<![\w/])overlays\s*[-+]=",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w/])(?:add_overlay|cut_overlays?)\s*\(|(?<![\w/])overlays\s*[-+]="));
    for (number, code) in f.clean().numbered() {
        // Both alternatives need the word "overlay" in the line.
        if code.contains("overlay") && raw.is_match(code) {
            fixture.push(out,("dx_raw_overlays", number))?;
        }
    }
    Ok(())
}


fn scan_file(f:&SourceFile,out:&mut Vec<(&'static str,usize)>){
    scan_file_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scanner has no admission refusal")
}
fn scan_file_using(f:&SourceFile,out:&mut Vec<(&'static str,usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    fixture.check()?;
    scan_lines_using(f,out,fixture)?;
    Ok(())
}


fn selftest() -> Result<String, String> {
    selftest_with_fixture(&crate::raw_fixture_policy::Fixture::legacy())
}

fn selftest_with_fixture(fixture: &crate::raw_fixture_policy::Fixture<'_>) -> Result<String, String> {
    let fixture_lines = [
        "add_overlay(\"lights\")",
        "A.cut_overlay(old)",
        "overlays += image(icon, \"x\")",
        "src.overlays -= glow",
        "cut_overlays()",
        "look.overlay(\"lights\")",
        "// add_overlay(x)",
        "/atom/proc/add_overlay(list/add_overlays, priority)",
        "var/list/my_overlays = list()",
        "add_overlay_lighting(src, 3, 1)",
        "overlays == null",
    ];
    let f = fixture.file("x.dm", &fixture.join(&fixture_lines,"\n")?)?;
    let mut v = Vec::new();
    scan_lines_using(&f,&mut v,fixture)?;
    let got: Vec<usize> = fixture.collect(v.into_iter().map(|(_, n)| n))?;
    if got != [1, 2, 3, 4, 5] {
        return Err(fixture.detail(format_args!("dx_raw_overlays selftest: got {:?}", got))?);
    }
    Ok(fixture.own("dx_raw_overlays")?)
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_dx_raw_overlays::SCOPE_MODULE_NAME, rules: RULES, file_scan: Some(scan_file), fixture_file_scan:Some(scan_file_using), selftest: Some(selftest), fixture_selftest: Some(selftest_with_fixture), py_selftest: true, ..SysModule::DEFAULT },
    );
}
