//! dmb-equiv A.dmb B.dmb [--rsc A.rsc B.rsc] [--json OUT] [--max-examples N] [--all]
//!                       [--strict-order] [--ignore-debug] [--quiet]
//! dmb-equiv permute IN.dmb OUT.dmb [--seed N] [--tables all|classes,procs,...]
//! dmb-equiv dump-proc FILE.dmb KEY-SUBSTRING
//!
//! Exit status: 0 equivalent, 1 different, 2 usage or decode error.
use byond_dmb::dmb::Dmb;
use dmb_equiv::{canon::Ctx, compare_bytes, permute, Options};
use std::process::ExitCode;
use std::time::Instant;

fn fail(msg: impl std::fmt::Display) -> ExitCode {
    eprintln!("dmb-equiv: {msg}");
    ExitCode::from(2)
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("permute") => permute_cmd(&args[1..]),
        Some("dump-proc") => dump_proc(&args[1..]),
        Some("word-report") => word_report(&args[1..]),
        Some("no-debug-ops") => no_debug_ops(&args[1..]),
        Some("dump-types") => {
            let Some(path) = args.get(1) else {
                return fail("dump-types FILE.dmb");
            };
            match std::fs::read(path).and_then(|b| Dmb::from_bytes(&b)) {
                Ok(d) => {
                    for (i, c) in d.classes.iter().enumerate() {
                        let name = d.string(c.path_string_id()).unwrap_or_default();
                        println!("{i}	{}", dmb_equiv::canon::esc_pub(name));
                    }
                    ExitCode::SUCCESS
                }
                Err(e) => fail(e),
            }
        }
        Some("dump-procs") => {
            let Some(path) = args.get(1) else {
                return fail("dump-procs FILE.dmb");
            };
            match std::fs::read(path).and_then(|b| Dmb::from_bytes(&b)) {
                Ok(d) => {
                    for (i, p) in d.procs.iter().enumerate() {
                        let name = d.string(p.strings[0]).unwrap_or_default();
                        println!("{i}	{}", dmb_equiv::canon::esc_pub(name));
                    }
                    ExitCode::SUCCESS
                }
                Err(e) => fail(e),
            }
        }
        Some("dump-strings") => {
            let Some(path) = args.get(1) else {
                return fail("dump-strings FILE.dmb");
            };
            match std::fs::read(path).and_then(|b| Dmb::from_bytes(&b)) {
                Ok(d) => {
                    for (i, s) in d.strings.iter().enumerate() {
                        println!("{i}	{}", dmb_equiv::canon::esc_pub(&s.data));
                    }
                    ExitCode::SUCCESS
                }
                Err(e) => fail(e),
            }
        }
        Some("-h" | "--help") | None => {
            eprintln!("usage: dmb-equiv A.dmb B.dmb [--rsc A.rsc B.rsc] [--json OUT] [--max-examples N] [--all] [--context N] [--ignore-order] [--strict-order] [--ignore-debug] [--quiet]\n       dmb-equiv permute IN.dmb OUT.dmb [--seed N] [--tables LIST]\n       dmb-equiv dump-proc FILE.dmb KEY-SUBSTRING");
            ExitCode::from(2)
        }
        _ => compare_cmd(&args),
    }
}

fn compare_cmd(args: &[String]) -> ExitCode {
    let mut files = Vec::new();
    let mut rsc = None;
    let mut json = None;
    let mut quiet = false;
    let mut opts = Options::default();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--rsc" if i + 2 < args.len() => {
                rsc = Some((args[i + 1].clone(), args[i + 2].clone()));
                i += 2;
            }
            "--json" if i + 1 < args.len() => {
                json = Some(args[i + 1].clone());
                i += 1;
            }
            "--max-examples" if i + 1 < args.len() => {
                opts.max_examples = match args[i + 1].parse() {
                    Ok(n) => n,
                    Err(_) => return fail("--max-examples needs a number"),
                };
                i += 1;
            }
            "--ignore-order" => opts.ignore_order = true,
            "--context" if i + 1 < args.len() => {
                opts.context = match args[i + 1].parse() {
                    Ok(n) => n,
                    Err(_) => return fail("--context needs a number"),
                };
                i += 1;
            }
            "--all" => opts.max_examples = usize::MAX,
            "--strict-order" => opts.strict_order = true,
            "--ignore-debug" => opts.ignore_debug = true,
            "--quiet" => quiet = true,
            a if a.starts_with("--") => return fail(format!("unknown option {a}")),
            a => files.push(a.to_string()),
        }
        i += 1;
    }
    if files.len() != 2 {
        return fail("expected two DMB files");
    }
    let started = Instant::now();
    let read = |p: &str| std::fs::read(p).map_err(|e| format!("{p}: {e}"));
    let (a, b) = match (read(&files[0]), read(&files[1])) {
        (Ok(a), Ok(b)) => (a, b),
        (Err(e), _) | (_, Err(e)) => return fail(e),
    };
    let rsc_bytes = match &rsc {
        Some((ra, rb)) => match (read(ra), read(rb)) {
            (Ok(a), Ok(b)) => Some((a, b)),
            (Err(e), _) | (_, Err(e)) => return fail(e),
        },
        None => None,
    };
    let report = match compare_bytes(
        &a,
        rsc_bytes.as_ref().map(|r| r.0.as_slice()),
        &b,
        rsc_bytes.as_ref().map(|r| r.1.as_slice()),
        &opts,
    ) {
        Ok(r) => r,
        Err(e) => return fail(e),
    };
    let elapsed = started.elapsed().as_secs_f64();
    if !quiet {
        print!("{}", report.render_text());
    } else {
        println!(
            "{}",
            if report.equivalent() {
                "EQUIVALENT"
            } else {
                "NOT EQUIVALENT"
            }
        );
    }
    eprintln!("dmb-equiv: compared in {elapsed:.2}s");
    if let Some(path) = json {
        let mut value = report.to_json();
        value["a"] = files[0].clone().into();
        value["b"] = files[1].clone().into();
        value["seconds"] = elapsed.into();
        if let Err(e) = std::fs::write(&path, serde_json::to_string_pretty(&value).unwrap()) {
            return fail(format!("{path}: {e}"));
        }
    }
    if report.equivalent() {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(1)
    }
}

fn permute_cmd(args: &[String]) -> ExitCode {
    let mut files = Vec::new();
    let mut seed = 1u64;
    let mut tables = "all".to_string();
    let mut keep = 0usize;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--seed" if i + 1 < args.len() => {
                seed = args[i + 1].parse().unwrap_or(1);
                i += 1;
            }
            "--keep-strings" if i + 1 < args.len() => {
                keep = args[i + 1].parse().unwrap_or(0);
                i += 1;
            }
            "--tables" if i + 1 < args.len() => {
                tables = args[i + 1].clone();
                i += 1;
            }
            a => files.push(a.to_string()),
        }
        i += 1;
    }
    if files.len() != 2 {
        return fail("permute IN.dmb OUT.dmb");
    }
    let opts = match permute::PermuteOptions::parse(seed, &tables) {
        Ok(mut o) => {
            o.keep_strings = keep;
            o
        }
        Err(e) => return fail(e),
    };
    let result = std::fs::read(&files[0])
        .and_then(|b| Dmb::from_bytes(&b))
        .and_then(|d| permute::permute(&d, &opts))
        .and_then(|d| d.to_bytes())
        .and_then(|b| std::fs::write(&files[1], b));
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => fail(e),
    }
}

fn dump_proc(args: &[String]) -> ExitCode {
    if args.len() != 2 {
        return fail("dump-proc FILE.dmb KEY-SUBSTRING");
    }
    let dmb = match std::fs::read(&args[0]).and_then(|b| Dmb::from_bytes(&b)) {
        Ok(d) => d,
        Err(e) => return fail(e),
    };
    let ctx = Ctx::new(&dmb, None);
    for (p, key) in ctx.proc_keys.iter().enumerate() {
        if !key.contains(args[1].as_str()) {
            continue;
        }
        println!("== {key} (table #{p})");
        for f in ctx.proc_fields(p) {
            println!("  {} = {}", f.label, f.value);
        }
        if let Some(words) = dmb.proc_code_words(p) {
            match dmb_equiv::canon::render_code_lines_pub(&ctx, words) {
                Ok(lines) => {
                    let mut n = 0;
                    for (dbg, l) in lines {
                        if dbg {
                            println!("        {l}");
                        } else {
                            println!("  {n:>5} {l}");
                            n += 1;
                        }
                    }
                }
                Err(e) => println!("  {e}"),
            }
        }
    }
    ExitCode::SUCCESS
}

/// `word-report FILE.dmb [TOP]`: the `<global-init>` code size in words, attributed to the global each
/// statement assigns (words since the previous assignment, debug words included and totalled separately).
fn word_report(args: &[String]) -> ExitCode {
    let Some(path) = args.first() else {
        return fail("word-report FILE.dmb [TOP]");
    };
    let top: usize = args.get(1).and_then(|t| t.parse().ok()).unwrap_or(40);
    let dmb = match std::fs::read(path).and_then(|b| Dmb::from_bytes(&b)) {
        Ok(d) => d,
        Err(e) => return fail(e),
    };
    let ctx = Ctx::new(&dmb, None);
    let Some(p) = ctx.proc_keys.iter().position(|k| k == "<global-init>") else {
        return fail("no <global-init>");
    };
    let Some(words) = dmb.proc_code_words(p) else {
        return fail("no code");
    };
    let Ok(ins) = byond_dmb::bytecode::decode(words) else {
        return fail("decode error");
    };
    let Ok(lines) = dmb_equiv::canon::render_code_lines_pub(&ctx, words) else {
        return fail("render error");
    };
    let mut file = String::new();
    let mut acc = 0usize;
    let mut debug_words = 0usize;
    let mut rows: Vec<(usize, String, String)> = Vec::new();
    for (i, ((dbg, text), instr)) in lines.iter().zip(ins.iter()).enumerate() {
        let end = ins.get(i + 1).map(|n| n.offset).unwrap_or(words.len());
        let w = end - instr.offset;
        acc += w;
        if *dbg {
            debug_words += w;
            if let Some(f) = text.strip_prefix("DbgFile ") {
                file = f.trim_matches('"').to_string();
            }
        } else if text.starts_with("SetVar global:") || text.starts_with("SetVar ") {
            rows.push((acc, text.clone(), file.clone()));
            acc = 0;
        }
    }
    println!("total_words	{}", words.len());
    println!("debug_words	{debug_words}");
    println!("instructions	{}", ins.len());
    println!("trailing_words	{acc}");
    rows.sort_by(|a, b| b.0.cmp(&a.0));
    println!("assignments	{}", rows.len());
    for (w, t, f) in rows.iter().take(top) {
        println!("{w}	{t}	{f}");
    }
    ExitCode::SUCCESS
}

/// `no-debug-ops FILE.dmb`: exit 1 when any procedure carries `DbgFile`/`DbgLine`. DreamMaker emits them only
/// under `DEBUG`, so a production (no `DEBUG`) build must have none, in every procedure.
fn no_debug_ops(args: &[String]) -> ExitCode {
    let Some(path) = args.first() else {
        return fail("no-debug-ops FILE.dmb");
    };
    let dmb = match std::fs::read(path).and_then(|b| Dmb::from_bytes(&b)) {
        Ok(d) => d,
        Err(e) => return fail(e),
    };
    let (mut procs, mut ops) = (0usize, 0usize);
    for p in 0..dmb.procs.len() {
        let Some(words) = dmb.proc_code_words(p) else {
            continue;
        };
        let Ok(ins) = byond_dmb::bytecode::decode(words) else {
            return fail(format!("decode error in procedure #{p}"));
        };
        let n = ins.iter().filter(|i| i.opcode == 0x84 || i.opcode == 0x85).count();
        if n > 0 {
            procs += 1;
            ops += n;
            if procs <= 5 {
                eprintln!("procedure #{p}: {n} debug instructions");
            }
        }
    }
    println!("procedures_with_debug_ops	{procs}
debug_instructions	{ops}");
    if ops == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(1)
    }
}
