//! `vg-replay`: replays a `.vglog` and verifies its state hashes.
//!
//! ```text
//! vg-replay verify <log.vglog>                        replay, compare hashes
//! vg-replay info <log.vglog>                          print the header
//! vg-replay record <scenario> <frames> <out> [seed]   record a synthetic session
//! vg-replay list                                      list known scenarios
//! ```
//! Exit status: 0 on a match, 1 on a hash mismatch, 2 on usage or I/O errors.

use std::process::ExitCode;

use vg_core::replay::{decode_header, verify};
use vg_core::sim::SimConfig;
use vg_replay::{SCENARIOS, record, scenario};

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("vg-replay: {e}");
            ExitCode::from(2)
        }
    }
}

fn run(args: &[String]) -> Result<ExitCode, Box<dyn std::error::Error>> {
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    match args.as_slice() {
        ["verify", path] => {
            let bytes = std::fs::read(path)?;
            let verdict = verify(&bytes, |head| {
                let build = scenario(&head.scenario)
                    .ok_or_else(|| format!("unknown scenario {:?}", head.scenario))?;
                let built = build(SimConfig::default());
                Ok((built.builder, built.codecs))
            })?;
            println!("replayed {} frames", verdict.frames);
            println!("actual   {:016x?}", verdict.actual);
            if verdict.expected.is_empty() {
                println!("no recorded hashes to compare");
                return Ok(ExitCode::SUCCESS);
            }
            println!("expected {:016x?}", verdict.expected);
            Ok(if verdict.ok() {
                println!("OK");
                ExitCode::SUCCESS
            } else {
                println!("MISMATCH");
                ExitCode::from(1)
            })
        }
        ["info", path] => {
            let head = decode_header(&std::fs::read(path)?)?;
            println!(
                "scenario {}\nseed {}\ndomains {:?}",
                head.scenario, head.seed, head.domains
            );
            Ok(ExitCode::SUCCESS)
        }
        ["record", name, frames, out, rest @ ..] => {
            let seed = rest.first().map_or(Ok(1), |s| s.parse())?;
            let bytes = record(name, seed, frames.parse()?)?;
            std::fs::write(out, bytes)?;
            println!("wrote {frames} frames of {name} to {out}");
            Ok(ExitCode::SUCCESS)
        }
        ["list"] => {
            for (name, _) in SCENARIOS {
                println!("{name}");
            }
            Ok(ExitCode::SUCCESS)
        }
        _ => Err(
            "usage: vg-replay verify <log> | info <log> | record <scenario> <frames> <out> [seed] | list"
                .into(),
        ),
    }
}
