//! Port of `tools/ci/dcs_lints.py`: the DCS ban (doc/rewrite/object_model_core.md sec 10 and 16).
//!
//! The DCS (signals, components, elements) is deleted. Any use of the old API in `code/` fails;
//! there is no ceiling and no ALLOW annotation. Comments and strings are ignored.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

const HINT: &str = "The DCS is gone: use OM events, om_hook() and behaviours (object_model_core.md sec 10, 16)";

static META: Meta = Meta {
    name: crate::allow_registry_fields::dcs::SCOPE_META_0.name,
    group: crate::allow_registry_fields::dcs::SCOPE_META_0.group,
    label: "dcs",
    legacy: "tools/ci/dcs_lints.py",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "register_signal", hint: HINT },
        RuleMeta { name: "send_signal", hint: HINT },
        RuleMeta { name: "add_component", hint: HINT },
        RuleMeta { name: "add_element", hint: HINT },
        RuleMeta { name: "comsig", hint: HINT },
    ],
    allow: crate::allow_registry_fields::dcs::ALLOW_0,
    lists: crate::allow_registry_fields::dcs::SCOPE_META_0.lists,
};

const DCS_PATTERN_SOURCES:&[(&str,&str)]=&[
    ("register_signal",r"(?<![\w/])(?:RegisterSignals?|UnregisterSignal)\s*\("),
    ("send_signal",r"(?<![\w/])(?:SEND_SIGNAL|SEND_GLOBAL_SIGNAL)\s*\(|\bSIGNAL_HANDLER\b"),
    ("add_component",r"(?<![\w/])(?:AddComponent|AddComponentFrom|LoadComponent|GetComponents?|GetExactComponent)\s*\(|/datum/component\b"),
    ("add_element",r"(?<![\w/])(?:AddElement|RemoveElement)\s*\(|/datum/element\b"),
    ("comsig",r"\b(?:COMSIG_[A-Z0-9_]+|SIGNAL_ADDTRAIT|SIGNAL_REMOVETRAIT)\b"),
];

struct Dcs {
    patterns: Vec<(&'static str, Pat)>,
}

impl Dcs {
    fn new() -> Dcs {
        Dcs {
            patterns: vec![
                (DCS_PATTERN_SOURCES[0].0,Pat::new(DCS_PATTERN_SOURCES[0].1)),
                (DCS_PATTERN_SOURCES[1].0,Pat::new(DCS_PATTERN_SOURCES[1].1)),
                (DCS_PATTERN_SOURCES[2].0,Pat::new(DCS_PATTERN_SOURCES[2].1)),
                (DCS_PATTERN_SOURCES[3].0,Pat::new(DCS_PATTERN_SOURCES[3].1)),
                (DCS_PATTERN_SOURCES[4].0,Pat::new(DCS_PATTERN_SOURCES[4].1)),
            ],
        }
    }
    fn scan_patterns_using(&self,f:&SourceFile,out:&mut Sink,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
        fixture.check()?;
        for (no, line) in f.code().numbered() {
            for (name, pat) in &self.patterns {
                for _ in fixture.find_iter(pat,line)? {
                    fixture.site(out,name,no)?;
                }
            }
        }
            Ok(())
    }

}

impl Lint for Dcs {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self,_cx:&Cx,f:&SourceFile,out:&mut Sink){self.scan_patterns_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scanner has no admission refusal")}

    fn selftest(&self) -> Result<String, String> {
        self.selftest_with_fixture(&crate::raw_fixture_policy::Fixture::legacy())
    }

    fn selftest_with_fixture(&self,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<String,String>{
        selftest_kernel(fixture,|file,out,fixture|self.scan_patterns_using(file,out,fixture))
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/dcs_lints.py"],
            old_raw: &[
                &["tools/ci/dcs_lints.py", "--report", "register_signal"],
                &["tools/ci/dcs_lints.py", "--report", "send_signal"],
                &["tools/ci/dcs_lints.py", "--report", "add_component"],
                &["tools/ci/dcs_lints.py", "--report", "add_element"],
                &["tools/ci/dcs_lints.py", "--report", "comsig"],
            ],
            blank: &[],
            parse: ParseKind::Bare,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Dcs::new());
}

fn selftest_kernel(fixture:&crate::raw_fixture_policy::Fixture<'_>,scan:impl FnOnce(&SourceFile,&mut Sink,&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>)->Result<String,String>{

        let f = fixture.file("code/a.dm", "\tRegisterSignal(src, COMSIG_X, PROC_REF(a))\n\t// SEND_SIGNAL(src, X)\n\tx.AddElement(/datum/element/y)\n")?;
        let mut out = fixture.sink()?;
        out.cur = fixture.own(&f.rel)?;
        scan(&f,&mut out,fixture)?;
        let rules: Vec<&str> = fixture.collect(out.sites.iter().map(|s| s.rule.as_str()))?;
        if rules == ["register_signal", "comsig", "add_element", "add_element"] {
            Ok(String::new())
        } else {
            Err(fixture.detail(format_args!("unexpected sites {:?}", rules))?)
        }

}

// Native metadata discovery must not eagerly compile five legacy Pats. The
// original registration and Dcs::new constructor above remain unchanged.
struct NativeDcs{legacy:std::sync::OnceLock<Dcs>}
impl Lint for NativeDcs{
 fn meta(&self)->&Meta{&META}
 fn scan_file(&self,cx:&Cx,file:&SourceFile,out:&mut Sink){if let Some(fixture)=cx.fixture{fixture.note_scan(native_scan_patterns_using(file,out,fixture))}else{self.legacy.get_or_init(Dcs::new).scan_file(cx,file,out)}}
 fn selftest(&self)->Result<String,String>{self.legacy.get_or_init(Dcs::new).selftest()}
 fn parity(&self)->Option<Parity>{self.legacy.get_or_init(Dcs::new).parity()}
 fn selftest_with_fixture(&self,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<String,String>{
  selftest_kernel(fixture,native_scan_patterns_using)
 }
}
pub fn register_native(reg:&mut Registry){reg.add(NativeDcs{legacy:std::sync::OnceLock::new()})}

fn native_scan_patterns_using(file:&SourceFile,out:&mut Sink,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
   use crate::raw_fixture_policy::{PatternApi,PatternMode};
   for(no,line)in file.code().numbered(){
    for _ in fixture.find_iter(&fixture.pattern(DCS_PATTERN_SOURCES[0].1,PatternMode::Search,||crate::pat!(DCS_PATTERN_SOURCES[0].1)),line)?{fixture.site(out,DCS_PATTERN_SOURCES[0].0,no)?;}
    for _ in fixture.find_iter(&fixture.pattern(DCS_PATTERN_SOURCES[1].1,PatternMode::Search,||crate::pat!(DCS_PATTERN_SOURCES[1].1)),line)?{fixture.site(out,DCS_PATTERN_SOURCES[1].0,no)?;}
    for _ in fixture.find_iter(&fixture.pattern(DCS_PATTERN_SOURCES[2].1,PatternMode::Search,||crate::pat!(DCS_PATTERN_SOURCES[2].1)),line)?{fixture.site(out,DCS_PATTERN_SOURCES[2].0,no)?;}
    for _ in fixture.find_iter(&fixture.pattern(DCS_PATTERN_SOURCES[3].1,PatternMode::Search,||crate::pat!(DCS_PATTERN_SOURCES[3].1)),line)?{fixture.site(out,DCS_PATTERN_SOURCES[3].0,no)?;}
    for _ in fixture.find_iter(&fixture.pattern(DCS_PATTERN_SOURCES[4].1,PatternMode::Search,||crate::pat!(DCS_PATTERN_SOURCES[4].1)),line)?{fixture.site(out,DCS_PATTERN_SOURCES[4].0,no)?;}
   }Ok(())
}
