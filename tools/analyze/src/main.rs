//! `analyze`: the one lint engine. Usage: `analyze --help`.

use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::Instant;

use dq_analyze::baseline::Mode;
use dq_analyze::run::{self, Engine, Options};

/// Whether a full `analyze check` also runs the unused-ALLOW check on its own (every lint is in the
/// engine now, so every annotation's usage is visible to it).
const NATIVE_UNUSED_DEFAULT: bool = true;

const HELP: &str = "analyze: DeepQuarry's lint/analysis engine

USAGE
  analyze check [--lint NAME...] [--changed-only] [--no-cache] [--rehash] [--raw] [--ci] [--root DIR]
      Run lints (default: all). Exit 1 if any fails. --raw ignores baselines (every site is new);
      --changed-only judges only files changed against origin/master and the working tree.
  analyze baseline --update|--seed [--lint NAME...]
      Rewrite ratchet baselines: --update only ever drops fixed sites; --seed records every site.
  analyze parity [NAME... | --all] [--bless] [--fixtures-only]
      Run the legacy Python lint and the engine port on this tree (and on tools/analyze/fixtures/)
      and diff the findings. --bless writes expected.txt from a clean fixture comparison.
  analyze timing [--lint NAME...] [--no-cache]
      A full check with a per-lint timing table.
  analyze selftest [--lint NAME...]     Run each lint's fixture tests.
  analyze list                          The registered lints.
  analyze frontend-diff                 Compare the text scanner with the dreammaker parser.
  analyze gen [--check] [NAME...]       Write (or check) the generated DM under code/engine/_generated/.
  analyze codemod list | NAME [--check|--apply|--revert] [--path PREFIX...] [--write-residue]
      AST-aware rewriters (phase 2.5); `analyze codemod help`.
  analyze look-keys [--out FILE] [--explain TYPE] [--no-cache]
      Write the look plan (default data/look-plan.tsv): per concrete /obj, /mob and /turf type,
      `type TAB key TAB probes` (see src/look_keys.rs). --explain prints one type's closure and probes.
  analyze sem reads /type proc | oracle [--all]
                                        Semantic queries: a handler's reads; the reads spike oracle.

A lint is selected by its name or its group (`sys` selects every sys/* lint).";

struct Args {
    cmd: String,
    lints: Vec<String>,
    flags: Vec<String>,
    root: Option<PathBuf>,
}

fn parse(argv: Vec<String>) -> Args {
    let mut it = argv.into_iter().skip(1);
    let cmd = it.next().unwrap_or_else(|| "help".to_string());
    let mut lints = Vec::new();
    let mut flags = Vec::new();
    let mut root = None;
    let mut taking_lints = false;
    let mut rest: Vec<String> = it.collect();
    let mut i = 0;
    while i < rest.len() {
        let a = std::mem::take(&mut rest[i]);
        i += 1;
        match a.as_str() {
            "--lint" => taking_lints = true,
            "--root" => {
                root = rest.get(i).map(PathBuf::from);
                i += 1;
                taking_lints = false;
            }
            s if s.starts_with("--") => {
                flags.push(s.to_string());
                taking_lints = false;
            }
            _ => {
                if taking_lints || cmd == "parity" {
                    for n in a.split(',') {
                        if !n.is_empty() {
                            lints.push(n.to_string());
                        }
                    }
                } else {
                    flags.push(a);
                }
            }
        }
    }
    Args { cmd, lints, flags, root }
}

fn find_root(explicit: Option<PathBuf>) -> PathBuf {
    if let Some(r) = explicit {
        return r;
    }
    let mut dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    loop {
        if dir.join("deepquarry.dme").exists() {
            return dir;
        }
        if !dir.pop() {
            return std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        }
    }
}

fn options(args: &Args, root: &Path) -> Options {
    let has = |f: &str| args.flags.iter().any(|x| x == f);
    Options {
        root: root.to_path_buf(),
        lints: args.lints.clone(),
        changed_only: has("--changed-only"),
        no_cache: has("--no-cache"),
        rehash: has("--rehash"),
        raw: has("--raw"),
        ci: has("--ci"),
        scopes_from: None,
    }
}

fn main() -> ExitCode {
    dq_analyze::tree::start_watchdog();
    let args = parse(std::env::args().collect());
    let root = find_root(args.root.clone());
    let has = |f: &str| args.flags.iter().any(|x| x == f);
    match args.cmd.as_str() {
        "help" | "--help" | "-h" => {
            println!("{}", HELP);
            ExitCode::SUCCESS
        }
        "list" => {
            let reg = run::registry();
            for l in &reg.lints {
                let m = l.meta();
                println!("{:<28} group={:<8} scan={:?} legacy={}", m.name, m.group, m.scan, m.legacy);
            }
            println!("{} lints", reg.lints.len());
            ExitCode::SUCCESS
        }
        "check" | "report" => {
            let mut o = options(&args, &root);
            if args.cmd == "report" {
                o.raw = true;
            }
            let t0 = Instant::now();
            let engine = match Engine::new(run::registry(), o) {
                Ok(e) => e,
                Err(e) => {
                    eprintln!("analyze: {}", e);
                    return ExitCode::from(2);
                }
            };
            let problems = engine.validate_scopes();
            if !problems.is_empty() {
                for p in &problems {
                    eprintln!("analyze: {}", p);
                }
                return ExitCode::from(2);
            }
            // Fixture selftests first: a lint whose own fixtures fail can't be trusted to ratchet.
            let mut failed: Vec<String> = Vec::new();
            let t_self = Instant::now();
            if args.cmd == "check" && !has("--no-selftest") {
                // A selftest is a function of the engine build alone: once every selected lint's passed for
                // this build (and none was skipped), a marker in the cache says so.
                let names: Vec<String> = run::selected(&engine.reg, &engine.opts.lints).iter().map(|l| l.meta().name.to_string()).collect();
                let marker = dq_analyze::incr::dir().map(|d| d.join("selftest.ok"));
                let stamp = format!("{}|{}", dq_analyze::cache::ENGINE_HASH, names.join(","));
                let known = marker.as_ref().and_then(|m| std::fs::read_to_string(m).ok()).map(|t| t == stamp).unwrap_or(false);
                if !known {
                    dq_analyze::incr::suspend(true);
                    for lint in run::selected(&engine.reg, &engine.opts.lints) {
                        if let Err(e) = lint.selftest() {
                            println!("selftest FAILED: {}: {}", lint.meta().name, e);
                            failed.push(format!("{} --selftest", lint.meta().name));
                        }
                    }
                    dq_analyze::incr::suspend(false);
                    if failed.is_empty() {
                        if let Some(m) = &marker {
                            let _ = std::fs::create_dir_all(m.parent().unwrap());
                            let _ = std::fs::write(m, &stamp);
                        }
                    }
                }
            }
            let t_run = Instant::now();
            let outcomes = engine.run_all();
            if std::env::var("DQ_ANALYZE_TRACE").is_ok() {
                eprintln!("analyze: startup {:.0?}, selftests {:.0?}, lints {:.0?}, files loaded {}", t_self.duration_since(t0), t_run.duration_since(t_self), t_run.elapsed(), engine.tree.fresh_count());
            }
            let (text, lint_failed) = run::render(&outcomes, engine.opts.ci);
            failed.extend(lint_failed);
            print!("{}", text);
            write_allow_usage(&engine, &outcomes);
            // The unused-ALLOW check needs every lint's usage: a full run only. While legacy Python
            // lints remain, check_ratchets.sh keeps doing it (they record into DQ_ALLOW_USAGE).
            let full_run = engine.opts.lints.iter().all(|n| n.starts_with('-'));
            if args.cmd == "check" && full_run && (has("--unused") || NATIVE_UNUSED_DEFAULT) && !has("--no-unused") && std::env::var("DQ_ALLOW_USAGE").is_err() {
                use dq_analyze::lints::allow_annotations;
                let used: Vec<dq_analyze::lint::AllowUse> = outcomes.iter().flat_map(|o| o.allow_used.iter().cloned()).collect();
                let problems = allow_annotations::unused(&engine.tree, &used, &[], &|_| String::new());
                for p in &problems {
                    println!("{}", p);
                }
                println!("allow annotations: {} unused", problems.len());
                if !problems.is_empty() {
                    failed.push("allow_annotations --unused".to_string());
                }
            }
            if has("--timing") {
                print_timing(&engine, &outcomes, t0.elapsed());
            }
            if failed.is_empty() {
                println!("All ratchet lints passed.");
                ExitCode::SUCCESS
            } else {
                println!("Ratchet lints failed: {}", failed.join(" "));
                ExitCode::FAILURE
            }
        }
        "timing" => {
            let o = options(&args, &root);
            let t0 = Instant::now();
            let engine = match Engine::new(run::registry(), o) {
                Ok(e) => e,
                Err(e) => {
                    eprintln!("analyze: {}", e);
                    return ExitCode::from(2);
                }
            };
            let outcomes = engine.run_all();
            print_timing(&engine, &outcomes, t0.elapsed());
            ExitCode::SUCCESS
        }
        "baseline" => {
            let mode = if has("--seed") {
                Mode::Seed
            } else if has("--update") {
                Mode::Update
            } else {
                eprintln!("analyze baseline: pass --update or --seed");
                return ExitCode::from(2);
            };
            let o = options(&args, &root);
            let engine = match Engine::new(run::registry(), o) {
                Ok(e) => e,
                Err(e) => {
                    eprintln!("analyze: {}", e);
                    return ExitCode::from(2);
                }
            };
            let mut code = ExitCode::SUCCESS;
            for lint in run::selected(&engine.reg, &engine.opts.lints) {
                match engine.update_baseline(lint, mode) {
                    Ok(s) => {
                        if !s.is_empty() {
                            println!("{}", s)
                        }
                    }
                    Err(e) => {
                        eprintln!("{}: {}", lint.meta().name, e);
                        code = ExitCode::FAILURE;
                    }
                }
            }
            code
        }
        "parity" => {
            let mut o = options(&args, &root);
            o.no_cache = true;
            let names = if has("--all") { Vec::new() } else { args.lints.clone() };
            if names.is_empty() && !has("--all") {
                eprintln!("analyze parity: name a lint or pass --all");
                return ExitCode::from(2);
            }
            ExitCode::from(dq_analyze::parity::run(&o, &names, has("--bless"), has("--fixtures-only")) as u8)
        }
        "selftest" => {
            let o = options(&args, &root);
            let engine = match Engine::new(run::registry(), o) {
                Ok(e) => e,
                Err(e) => {
                    eprintln!("analyze: {}", e);
                    return ExitCode::from(2);
                }
            };
            let mut failed = false;
            for lint in run::selected(&engine.reg, &engine.opts.lints) {
                match lint.selftest() {
                    Ok(s) => println!("selftest ok: {} {}", lint.meta().name, s),
                    Err(e) => {
                        println!("selftest FAILED: {}: {}", lint.meta().name, e);
                        failed = true;
                    }
                }
            }
            if failed {
                ExitCode::FAILURE
            } else {
                ExitCode::SUCCESS
            }
        }
        "sem" => dq_analyze::sem::cli::run(&args.flags, &root),
        "look-keys" => dq_analyze::look_keys::run(&args.flags, &root),
        "gen" => dq_analyze::sem::cli::gen(&args.flags, &root),
        "codemod" => dq_analyze::codemod::cli(&args.flags, &root),
        "fixture" => dq_analyze::sem::cli::fixture(&args.flags, &root),
        "frontend-diff" => {
            use dq_analyze::frontend::{self, Frontend};
            let mut o = options(&args, &root);
            o.lints = vec![];
            let engine = match Engine::new(run::registry(), o) {
                Ok(e) => e,
                Err(e) => {
                    eprintln!("analyze: {}", e);
                    return ExitCode::from(2);
                }
            };
            let t = Instant::now();
            let text = frontend::TextFrontend.analyze(&root, &engine.tree);
            println!("text frontend: {:?}", t.elapsed());
            let t = Instant::now();
            let dm = frontend::DreamMakerFrontend::default().analyze(&root, &engine.tree);
            println!("dreammaker frontend: {:?}", t.elapsed());
            match (text, dm) {
                (Ok(a), Ok(b)) => {
                    println!("text: {} types, {} procs, {} vars", a.types.len(), a.proc_count(), a.var_count());
                    println!("dreammaker: {} types, {} procs, {} vars, {} parse errors", b.types.len(), b.proc_count(), b.var_count(), b.diagnostics.len());
                    for l in frontend::diff(&a, &b, 60) {
                        println!("{}", l);
                    }
                    ExitCode::SUCCESS
                }
                (a, b) => {
                    eprintln!("frontend error: {:?} / {:?}", a.err(), b.err());
                    ExitCode::FAILURE
                }
            }
        }
        other => {
            eprintln!("analyze: unknown command {:?}\n\n{}", other, HELP);
            ExitCode::from(2)
        }
    }
}

fn print_timing(engine: &Engine, outcomes: &[run::Outcome], total: std::time::Duration) {
    println!("\n-- timing (tree load {:.0?}, {} files in tree, meta cache {} entries) --", engine.load_time, engine.files_read, engine.meta_len());
    let mut rows: Vec<&run::Outcome> = outcomes.iter().collect();
    rows.sort_by(|a, b| b.timing.total.cmp(&a.timing.total));
    println!("{:<30} {:>9} {:>7} {:>9} {:>6}", "lint", "time", "files", "rescanned", "memo");
    for o in rows {
        println!(
            "{:<30} {:>9.1?} {:>7} {:>9} {:>6}",
            o.name,
            o.timing.total,
            o.timing.files,
            o.timing.rescanned,
            if o.timing.tree_memo_hit { "hit" } else { "-" }
        );
    }
    println!("total wall time: {:.2?}", total);
}

/// With `DQ_ALLOW_USAGE=<file>` set (check_ratchets.sh), appends one `lint<TAB>file digest<TAB>line`
/// row per ALLOW annotation that kept a site: the format `allow_annotations.py --unused` reads, so
/// annotations used by engine lints count as used. The digest is sha1 of the file text without
/// trailing newlines (what the Python's `digest_of` computes).
fn write_allow_usage(engine: &Engine, outcomes: &[run::Outcome]) {
    use sha1::{Digest, Sha1};
    use std::io::Write;
    let Ok(path) = std::env::var("DQ_ALLOW_USAGE") else { return };
    if path.is_empty() {
        return;
    }
    let mut rows: std::collections::BTreeSet<(String, String, u32)> = std::collections::BTreeSet::new();
    let mut digests: std::collections::HashMap<String, String> = std::collections::HashMap::new();
    for o in outcomes {
        for u in &o.allow_used {
            let digest = digests.entry(u.rel.clone()).or_insert_with(|| match engine.tree.get(&u.rel) {
                Some(f) => {
                    let mut h = Sha1::new();
                    h.update(f.text().trim_end_matches('\n').as_bytes());
                    h.finalize().iter().map(|b| format!("{:02x}", b)).collect()
                }
                None => String::new(),
            });
            rows.insert((u.name.clone(), digest.clone(), u.line));
        }
    }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&path) {
        for (name, digest, line) in rows {
            let _ = writeln!(f, "{}\t{}\t{}", name, digest, line);
        }
    }
}
