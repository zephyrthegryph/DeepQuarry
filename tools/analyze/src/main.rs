//! `analyze`: the one lint engine. Usage: `analyze --help`.

use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::Instant;

use dq_analyze::baseline::Mode;
use dq_analyze::run::{self, Engine, Options};

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
    }
}

fn main() -> ExitCode {
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
            let outcomes = engine.run_all();
            let (text, failed) = run::render(&outcomes, engine.opts.ci);
            print!("{}", text);
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
