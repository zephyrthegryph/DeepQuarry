//! Port of `tools/ci/sys_rules/dx_raw_overlays.py`: raw overlay writes outside the look builder
//! (design review M9). `add_overlay(` / `cut_overlay(` / `cut_overlays(` / `overlays +=` /
//! `overlays -=` outside the look builder and the legacy appearance runtime.

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "dx_raw_overlays",
    hint: "draw the layer in draw(datum/look/look) (look.overlay/glow/gauge), not a raw overlay write (design review M9)",
}];

const EXEMPT: &[&str] = &[
    "code/engine/present/appearance_builder.dm",
    "code/controllers/subsystems/overlays.dm",
    "code/datums/sys/appearance.dm",
    "code/__defines/sys_appearance.dm",
];

/// `scan_file` of the Python: one site per sanitized line with a raw overlay write.
fn scan_lines(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    let raw = pat!(r"(?<![\w/])(?:add_overlay|cut_overlays?)\s*\(|(?<![\w/])overlays\s*[-+]=");
    for (number, code) in f.clean().numbered() {
        // Both alternatives need the word "overlay" in the line.
        if code.contains("overlay") && raw.is_match(code) {
            out.push(("dx_raw_overlays", number));
        }
    }
}

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    if EXEMPT.contains(&f.rel.as_str()) {
        return;
    }
    scan_lines(f, out);
}

fn selftest() -> Result<String, String> {
    let fixture = [
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
    let f = SourceFile::from_text("x.dm", &fixture.join("\n"));
    let mut v = Vec::new();
    scan_lines(&f, &mut v);
    let got: Vec<usize> = v.into_iter().map(|(_, n)| n).collect();
    if got != vec![1, 2, 3, 4, 5] {
        return Err(format!("dx_raw_overlays selftest: got {:?}", got));
    }
    let ex = SourceFile::from_text("code/engine/present/appearance_builder.dm", "A.add_overlay(added)");
    let mut v2 = Vec::new();
    scan_file(&ex, &mut v2);
    if !v2.is_empty() {
        return Err("dx_raw_overlays selftest: the look builder is exempt".to_string());
    }
    Ok("dx_raw_overlays".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: "dx_raw_overlays", rules: RULES, file_scan: Some(scan_file), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
