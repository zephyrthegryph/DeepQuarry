//! `analyze sem ...`: ad-hoc queries on the semantic layer.

use std::path::Path;
use std::process::ExitCode;
use std::time::Instant;

use crate::run::{Engine, Options};

use super::decls::Decls;
use super::reads::{Annotations, ReadsEngine};

/// Engine-internal directories the reads walk does not enter (dispatchers that read `vars[]` by design).
pub const DEFAULT_OPAQUE: &[&str] = &["code/datums/sys/", "code/datums/om/", "code/modules/tgui/", "code/datums/capabilities/", "code/datums/reactions/", "code/datums/ownership/", "code/engine/", "code/__defines/verdigris/"];

pub fn run(args: &[String], root: &Path) -> ExitCode {
    let sub = args.first().map(|s| s.as_str()).unwrap_or("help");
    let o = Options { root: root.to_path_buf(), lints: vec!["sem/keys".to_string()], ..Default::default() };
    let engine = match Engine::new(crate::run::registry(), o) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("analyze: {}", e);
            return ExitCode::from(2);
        }
    };
    let t = Instant::now();
    let Some(sem) = super::sem_for(&engine.tree) else { return ExitCode::from(2) };
    eprintln!("sem build: {:.2?}, {} parse errors", t.elapsed(), sem.errors.len());
    let t = Instant::now();
    let decls = Decls::get(&engine.tree);
    eprintln!("decls: {:.2?} ({} markers)", t.elapsed(), decls.markers.len());
    let ann = Annotations::get(&sem, &decls);
    let eng = ReadsEngine::new(&sem, &decls, &ann).with_opaque(DEFAULT_OPAQUE);
    match sub {
        "reads" => {
            let (Some(ty), Some(name)) = (args.get(1), args.get(2)) else {
                eprintln!("usage: analyze sem reads /type proc");
                return ExitCode::from(2);
            };
            debug_proc(&sem, ty, name);
            let t = Instant::now();
            let set = eng.analyze(ty, name);
            eprintln!("analysis: {:.2?}", t.elapsed());
            for r in &set.reads {
                println!("{}\t{:?}\t{}", r.key(), r.kind, r.owner);
            }
            for d in &set.diags {
                println!("DIAG {} {}:{} {}", d.rule, d.rel, d.line, d.msg);
            }
            ExitCode::SUCCESS
        }
        "oracle" => {
            let cfg_path = root.join("tools/analyze/oracle/spike.toml");
            let cfg = std::fs::read_to_string(&cfg_path).map(|t| super::oracle::SpikeConfig::parse(&t)).unwrap_or_default();
            let all = args.iter().any(|a| a == "--all");
            let mut entries = super::oracle::entries(&sem);
            entries.extend(super::oracle::generated_entries(root));
            let rows = super::oracle::evaluate(&sem, &eng, &entries, &cfg.tokens);
            let mut shown = 0;
            let mut bad = 0;
            for r in &rows {
                let pinned = cfg.handlers.iter().any(|(t, k, v)| t == &r.ty && k == r.kind.label() && v == &r.var);
                if !all && !pinned {
                    continue;
                }
                shown += 1;
                if r.needs_annotation() {
                    bad += 1;
                }
                println!(
                    "{:<8} {:<62} {}{} declared={} generated={} tokens=[{}] missing=[{}] unresolved={}",
                    r.kind.label(),
                    r.ty,
                    if r.var.is_empty() { String::new() } else { format!("{} ", r.var) },
                    format!("procs={:?}", r.procs),
                    r.declared.len(),
                    r.generated.len(),
                    r.tokens.iter().cloned().collect::<Vec<_>>().join(","),
                    r.missing.iter().cloned().collect::<Vec<_>>().join(","),
                    r.unresolved
                );
            }
            let mut helpers: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
            let mut with_globals = 0;
            for r in &rows {
                if cfg.handlers.iter().any(|(t, k, v)| t == &r.ty && k == r.kind.label() && v == &r.var) || all {
                    if !r.unannotated.is_empty() {
                        with_globals += 1;
                    }
                    helpers.extend(r.unannotated.iter().cloned());
                }
            }
            println!("{} handlers, {} miss a hand-written read ({} entries in tree)", shown, bad, entries.len());
            println!("{} of them call {} distinct global procs without READS_FROM: {}", with_globals, helpers.len(), helpers.iter().cloned().collect::<Vec<_>>().join(", "));
            ExitCode::SUCCESS
        }
        _ => {
            println!("analyze sem reads /type proc | analyze sem oracle [--all]");
            ExitCode::SUCCESS
        }
    }
}

pub fn debug_proc(sem: &super::Sem, ty: &str, name: &str) {
    match sem.proc_ref(ty, name) {
        None => eprintln!("no proc {} {} (type known: {})", ty, name, sem.ty(ty).is_some()),
        Some(p) => {
            let b = sem.proc_body(p);
            eprintln!("proc {}::{} at {}:{} builtin={} code={}", b.owner, b.name, b.file, b.line, b.builtin, b.code.map(|c| c.len() as i64).unwrap_or(-1));
        }
    }
}

/// `analyze gen [--check] [NAME...]`.
pub fn gen(args: &[String], root: &Path) -> ExitCode {
    let check = args.iter().any(|a| a == "--check");
    let names: Vec<String> = args.iter().filter(|a| !a.starts_with("--")).cloned().collect();
    // Some generators read another's output (reads and derived_reads read declare.dm), so a write pass
    // that changed anything runs again on the reloaded tree until nothing changes (two passes from an
    // empty tree, one when the files are already fresh). The generated files are not committed: every
    // build runs this first (tools/build/build.ts GenTarget), so it must converge on its own.
    let mut written: Vec<std::path::PathBuf> = Vec::new();
    let mut results = Vec::new();
    for _pass in 0..4 {
        let o = Options { root: root.to_path_buf(), lints: vec!["sem/keys".to_string()], ..Default::default() };
        let engine = match Engine::new(crate::run::registry(), o) {
            Ok(e) => e,
            Err(e) => {
                eprintln!("analyze: {}", e);
                return ExitCode::from(2);
            }
        };
        results = super::gen::run(root, &engine.tree, &names, check);
        let wrote: Vec<_> = results.iter().filter(|r| r.state == super::gen::State::Written).map(|r| r.path.clone()).collect();
        if check || wrote.is_empty() {
            break;
        }
        written.extend(wrote);
    }
    if results.is_empty() {
        eprintln!("analyze gen: no generator named {:?}", names);
        return ExitCode::from(2);
    }
    // The last pass reports every file fresh; name the ones an earlier pass rewrote.
    written.sort();
    written.dedup();
    for r in results.iter_mut() {
        if r.state == super::gen::State::Fresh && written.contains(&r.path) {
            r.state = super::gen::State::Written;
        }
    }
    if super::gen::report(&results) {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

/// `analyze sem fixture NAME [--bless]`: the engine's findings (with messages) on `fixtures/NAME`;
/// `--bless` writes `expected.txt` from them. Review the output before blessing: there is no legacy script to compare with.
pub fn fixture(args: &[String], root: &Path) -> ExitCode {
    let Some(name) = args.iter().find(|a| !a.starts_with("--")) else {
        eprintln!("usage: analyze sem fixture LINT [--bless]");
        return ExitCode::from(2);
    };
    let bless = args.iter().any(|a| a == "--bless");
    let dir = crate::parity::fixture_dir(root, name);
    let opts = Options { root: dir.clone(), lints: vec![name.to_string()], no_cache: true, raw: true, scopes_from: Some(root.to_path_buf()), ..Default::default() };
    let engine = match Engine::new(crate::run::registry(), opts) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("analyze: {}", e);
            return ExitCode::from(2);
        }
    };
    let Some(lint) = engine.reg.find(name) else {
        eprintln!("no lint {}", name);
        return ExitCode::from(2);
    };
    let (run, _, _) = engine.scan(lint);
    let mut sites = run.sites.clone();
    sites.sort_by(|a, b| (a.rule.as_str(), a.rel.as_str(), a.line).cmp(&(b.rule.as_str(), b.rel.as_str(), b.line)));
    for s in &sites {
        println!("{}\t{}\t{}\t{}", s.rule, s.rel, s.line, s.msg);
    }
    println!("{} findings", sites.len());
    if bless {
        let findings = crate::parity::engine_raw_findings(&engine, lint);
        let text = crate::parity::format_expected(&findings);
        if let Err(e) = std::fs::write(dir.join("expected.txt"), text) {
            eprintln!("write expected.txt: {}", e);
            return ExitCode::FAILURE;
        }
        println!("wrote {}", dir.join("expected.txt").display());
    }
    ExitCode::SUCCESS
}
