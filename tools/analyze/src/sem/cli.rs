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

/// What `analyze gen` remembers of its last converged run: the analyzer, a digest of every file the generators can read, and the
/// content digest of every file it wrote or found fresh. While all three still hold, a run has nothing to do.
#[derive(serde::Serialize, serde::Deserialize, Default)]
struct GenState {
    engine: String,
    key: u128,
    outputs: Vec<(String, u128)>,
}

fn gen_state_path() -> Option<std::path::PathBuf> {
    crate::incr::dir().map(|d| d.join("gen-state.bin"))
}

/// A digest of everything a generator reads: the content of every file in the tree, and `deepquarry.dme`.
fn gen_input_key(tree: &crate::tree::Tree, root: &Path) -> u128 {
    let mut h = blake3::Hasher::new();
    for f in &tree.files {
        h.update(f.rel.as_bytes());
        h.update(&f.hash.to_le_bytes());
    }
    h.update(&std::fs::read(root.join("deepquarry.dme")).unwrap_or_default());
    u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
}

fn file_digest(path: &Path) -> Option<u128> {
    let bytes = std::fs::read(path).ok()?;
    Some(u128::from_le_bytes(blake3::hash(&bytes).as_bytes()[..16].try_into().unwrap()))
}

fn engine_stamp() -> String {
    format!("gen-v1|{}", crate::cache::ENGINE_HASH)
}

/// The outputs of the last converged run when nothing they depend on changed (None = run the generators).
fn gen_memo_hit(tree: &crate::tree::Tree, root: &Path) -> Option<Vec<std::path::PathBuf>> {
    let st: GenState = crate::incr::de(&std::fs::read(gen_state_path()?).ok()?).ok()?;
    if st.engine != engine_stamp() || st.outputs.is_empty() || st.key != gen_input_key(tree, root) {
        return None;
    }
    let mut paths = Vec::new();
    for (p, d) in &st.outputs {
        let path = std::path::PathBuf::from(p);
        if file_digest(&path) != Some(*d) {
            return None;
        }
        paths.push(path);
    }
    Some(paths)
}

fn gen_memo_store(tree: &crate::tree::Tree, root: &Path, results: &[super::gen::GenResult]) {
    let Some(path) = gen_state_path() else { return };
    let mut outputs = Vec::new();
    for r in results {
        // A generator that wrote nothing has no output; every other result must be a fresh file we can digest.
        if r.path.ends_with("tgui/packages/tgui/interfaces/generated") {
            continue;
        }
        match file_digest(&r.path) {
            Some(d) => outputs.push((r.path.to_string_lossy().to_string(), d)),
            None => return,
        }
    }
    let st = GenState { engine: engine_stamp(), key: gen_input_key(tree, root), outputs };
    if let Ok(bytes) = crate::incr::ser(&st) {
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let tmp = path.with_extension(format!("tmp{}", std::process::id()));
        if std::fs::write(&tmp, bytes).is_ok() {
            let _ = std::fs::rename(&tmp, &path);
        }
    }
}

/// `analyze gen [--check] [NAME...]`.
///
/// Some generators read another's output (`reads` and `derived_reads` read `declare.dm` and the model includes every generated
/// file), so the generators run in two stages (`Generator::stage`): stage 0, the ones that read only declarations and text, to a
/// fixed point, then stage 1 on the settled files, so the full model (the 8-15 s parse) is built once against its final inputs. A
/// stage that wrote something is followed by a pass on the reloaded tree until nothing changes, which also proves the fixed
/// point. The generated files are not committed: every build runs this first (tools/build/build.ts GenTarget), so it must
/// converge on its own. A run that converged records a digest of its inputs and outputs (`gen-state.bin`); the next run with the
/// same inputs and intact outputs returns at once.
pub fn gen(args: &[String], root: &Path) -> ExitCode {
    let check = args.iter().any(|a| a == "--check");
    let names: Vec<String> = args.iter().filter(|a| !a.starts_with("--")).cloned().collect();
    let trace = std::env::var("DQ_ANALYZE_TRACE").is_ok();
    let mut written: Vec<std::path::PathBuf> = Vec::new();
    let mut results = Vec::new();
    let mut last_tree: Option<Engine> = None;
    for pass in 0..5 {
        let o = Options { root: root.to_path_buf(), lints: vec!["sem/keys".to_string()], ..Default::default() };
        let engine = match Engine::new(crate::run::registry(), o) {
            Ok(e) => e,
            Err(e) => {
                eprintln!("analyze: {}", e);
                return ExitCode::from(2);
            }
        };
        if pass == 0 && names.is_empty() {
            if let Some(paths) = gen_memo_hit(&engine.tree, root) {
                if trace {
                    eprintln!("analyze: gen: inputs and outputs unchanged since the last run; nothing to do");
                }
                for p in paths {
                    println!("fresh {}", p.display());
                }
                return ExitCode::SUCCESS;
            }
        }
        let r0 = super::gen::run_stage(root, &engine.tree, &names, check, Some(0));
        let wrote0: Vec<_> = r0.iter().filter(|r| r.state == super::gen::State::Written).map(|r| r.path.clone()).collect();
        if !check && !wrote0.is_empty() {
            // Stage 1 reads these files: reload the tree and start over.
            if trace {
                eprintln!("analyze: gen pass {}: stage 0 wrote {} file(s); reloading before stage 1", pass + 1, wrote0.len());
            }
            written.extend(wrote0);
            results = r0;
            continue;
        }
        let r1 = super::gen::run_stage(root, &engine.tree, &names, check, Some(1));
        let wrote1: Vec<_> = r1.iter().filter(|r| r.state == super::gen::State::Written).map(|r| r.path.clone()).collect();
        // Report in registry order, as a single pass always did.
        let mut all = r0;
        all.extend(r1);
        let order: Vec<&'static str> = super::gen::registry().iter().map(|g| g.name()).collect();
        all.sort_by_key(|r| order.iter().position(|n| *n == r.name).unwrap_or(usize::MAX));
        results = all;
        if check || wrote1.is_empty() {
            last_tree = Some(engine);
            break;
        }
        if trace {
            eprintln!("analyze: gen pass {}: stage 1 wrote {} file(s); checking the fixed point", pass + 1, wrote1.len());
        }
        written.extend(wrote1);
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
    let clean = super::gen::report(&results);
    if clean && !check && names.is_empty() {
        if let Some(e) = &last_tree {
            gen_memo_store(&e.tree, root, &results);
        }
    }
    if clean {
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
