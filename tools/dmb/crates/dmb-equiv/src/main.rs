//! dmb-equiv A.dmb B.dmb [--rsc A.rsc B.rsc] [--json OUT] [--max-examples N]
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
            eprintln!("usage: dmb-equiv A.dmb B.dmb [--rsc A.rsc B.rsc] [--json OUT] [--max-examples N] [--strict-order] [--ignore-debug] [--quiet]\n       dmb-equiv permute IN.dmb OUT.dmb [--seed N] [--tables LIST]\n       dmb-equiv dump-proc FILE.dmb KEY-SUBSTRING");
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
