//! Shared custom report policy over already-observed findings and ceilings.
//! Pure judgement plus baseline-only delivery helpers; no source/configuration
//! reads, semantic model or query receipt is created.
use std::{collections::BTreeMap,fmt::Write as _};
use crate::{lint::{Meta,Policy,RuleMeta,ScanKind,Run},tree::CODE_MAPS_DM};

pub(crate) const LINT: &str = "system_boundary";
pub(crate) const BASELINE: &str = "tools/ci/system_boundary_baseline.txt";
pub(crate) const HEADER: &[&str] = &[
    "System boundary ratchet (tools/ci/system_boundary_lint.py). `<rule>:<file>:<owner> <count>`; only shrinks.",
    "Regenerate the file with --generate only when the rules change; otherwise --update lowers ceilings.",
];

const HINT: &str = "see tools/ci/system_boundary_lint.py and doc/rewrite/kernel.md sec 2.5";

pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::system_boundary::SCOPE_META_0.name,
    group: crate::allow_registry_fields::system_boundary::SCOPE_META_0.group,
    label: "system_boundary",
    legacy: "tools/ci/system_boundary_lint.py",
    select: CODE_MAPS_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "B1", hint: HINT },
        RuleMeta { name: "B2", hint: HINT },
        RuleMeta { name: "B3", hint: HINT },
        RuleMeta { name: "B4", hint: HINT },
        RuleMeta { name: "B5", hint: HINT },
        RuleMeta { name: "B6", hint: HINT },
        RuleMeta { name: "B7", hint: HINT },
    ],
    allow: crate::allow_registry_fields::system_boundary::ALLOW_SHARED_0,
    lists: crate::allow_registry_fields::system_boundary::SCOPE_META_0.lists,
};

pub fn judge(run:&Run,base:&BTreeMap<String,i64>,text:&mut String)->bool{
        let mut by_key: BTreeMap<&str, Vec<&crate::lint::Site>> = BTreeMap::new();
        for s in &run.sites {
            by_key.entry(s.key.as_str()).or_default().push(s);
        }
        let mut failed = false;
        for (name, sites) in &by_key {
            let ceiling = base.get(*name).copied();
            let count = sites.len() as i64;
            if ceiling.is_none() || count > ceiling.unwrap() {
                let c = ceiling.map(|c| c.to_string()).unwrap_or_else(|| "none".to_string());
                let _ = writeln!(text, "system_boundary: FAIL {}: {} (ceiling {})", name, count, c);
                for s in sites.iter().take(5) {
                    let _ = writeln!(text, "    {}", s.msg);
                }
                failed = true;
            }
        }
        let lowered = base.iter().filter(|(k, v)| (by_key.get(k.as_str()).map(|s| s.len()).unwrap_or(0) as i64) < **v).count();
        let mut totals: Vec<String> = Vec::new();
        for r in ["B1", "B2", "B3", "B4", "B5", "B6", "B7"] {
            totals.push(format!("{}={}", r, run.sites.iter().filter(|s| s.rule == r).count()));
        }
        let _ = writeln!(
            text,
            "system_boundary: {}; {}; {} entries below their ceiling (--update lowers them)",
            totals.join(", "),
            if failed { "FAILED" } else { "ok" },
            lowered
        );
        failed
}

/// Exact existing policy metadata; observational data only.
pub fn metadata()->&'static Meta{&META}

/// Unique original custom baseline policy. This performs baseline-only I/O;
/// it reads no source/configuration and issues no completion/source receipt.
pub(crate) fn finish_after_delivery(root:&std::path::Path,run:&Run,text:&mut String)->bool{let base=crate::baseline::read_ceilings(&root.join(BASELINE));judge(run,&base,text)}
pub(crate) fn update_after_delivery(root:&std::path::Path,run:&Run,mode:crate::baseline::Mode)->std::io::Result<String>{let path=root.join(BASELINE);match mode{crate::baseline::Mode::Update=>{let n=crate::baseline::update_ceilings(&path,HEADER,&run.sites)?;Ok(format!("system_boundary: baseline lowered to {} entries",n))},crate::baseline::Mode::Migrate=>Ok("system_boundary: count ceilings have no rows to migrate".to_string()),crate::baseline::Mode::Seed=>{let counts=crate::baseline::key_counts(&run.sites);crate::baseline::write_ceilings(&path,HEADER,&counts)?;Ok(format!("system_boundary: wrote {} entries",counts.len()))}}}
