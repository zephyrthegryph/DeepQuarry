use crate::load_dmb;
use byond_dmb::dmb::Dmb;
use byond_dmb::opendream::OpenDreamProgram;
use byond_dmb::rsc::write_entry;
use std::io;

fn load_program(path: &str) -> io::Result<OpenDreamProgram> {
    OpenDreamProgram::from_path(path).map_err(io::Error::other)
}

struct TranslationInputs {
    program: OpenDreamProgram,
    baseline: OpenDreamProgram,
    template: Dmb,
}

fn load_translation_inputs(args: &[String]) -> io::Result<TranslationInputs> {
    Ok(TranslationInputs {
        program: load_program(&args[2])?,
        baseline: load_program(&args[3])?,
        template: load_dmb(&args[4])?,
    })
}

pub(crate) fn execute(name: &str, args: &[String]) -> io::Result<()> {
    match name {
        "od-proc-audit" => od_proc_audit(args),
        "od-class-audit" => od_class_audit(args),
        "od-map-audit" => od_map_audit(args),
        "od-lowering-audit" => od_lowering_audit(args),
        "od-diagnostic" => od_diagnostic(args),
        "od-to-dmb" => od_to_dmb(args),
        _ => Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("unknown command: {name}"),
        )),
    }
}

fn od_proc_audit(args: &[String]) -> io::Result<()> {
    let TranslationInputs {
        program,
        baseline,
        template,
    } = load_translation_inputs(args)?;
    let native = load_dmb(&args[6])?;
    let project_name = std::path::Path::new(&args[2])
        .file_stem()
        .and_then(|stem| stem.to_str());
    let emission = byond_dmb::od_emit::emit_diagnostic_hashed_with_baseline_named(
        &program,
        Some(&baseline),
        &template,
        std::path::Path::new(&args[5]),
        project_name,
    )
    .map_err(io::Error::other)?;
    let mut differences = byond_dmb::compare::compare_proc_tables(
        &native,
        &emission.dmb,
        if args.len() == 8 { usize::MAX } else { 100 },
    );
    if args.len() == 8 && args[7].starts_with("--field=") {
        let field = &args[7]["--field=".len()..];
        differences.retain(|difference| difference.field == field);
    }
    if differences.is_empty() {
        println!("no decoded procedure table discrepancies against native reference");
    } else {
        println!("{} procedure table differences", differences.len());
        if args.len() == 8 && args[7].starts_with("--pairs=") {
            let field = &args[7]["--pairs=".len()..];
            let mut pairs = std::collections::BTreeMap::<(&str, &str), (usize, &str)>::new();
            for difference in differences
                .iter()
                .filter(|difference| difference.field == field)
            {
                pairs
                    .entry((&difference.expected, &difference.actual))
                    .and_modify(|entry| entry.0 += 1)
                    .or_insert((1, &difference.path));
            }
            let mut pairs = pairs.into_iter().collect::<Vec<_>>();
            pairs.sort_by(|a, b| b.1 .0.cmp(&a.1 .0).then(a.0.cmp(&b.0)));
            for ((expected, actual), (count, example)) in pairs {
                println!("{count:>5} {field}: {expected} -> {actual} (e.g. {example})");
            }
        } else if args.len() == 8 && args[7].starts_with("--samples=") {
            let limit = args[7]["--samples=".len()..]
                .parse::<usize>()
                .map_err(io::Error::other)?
                .clamp(1, 100);
            let mut per_field = std::collections::BTreeMap::<&str, usize>::new();
            for difference in &differences {
                let count = per_field.entry(&difference.field).or_default();
                if *count < limit {
                    println!("{} {}", difference.path, difference.field);
                    println!(
                        "  expected: {}",
                        difference.expected.chars().take(350).collect::<String>()
                    );
                    println!(
                        "  actual:   {}",
                        difference.actual.chars().take(350).collect::<String>()
                    );
                }
                *count += 1;
            }
        } else if args.len() == 8 && (args[7] == "--grouped" || args[7] == "--grouped-values") {
            let mut groups = std::collections::BTreeMap::<&str, (usize, &str, &str, &str)>::new();
            for difference in &differences {
                groups
                    .entry(&difference.field)
                    .and_modify(|entry| entry.0 += 1)
                    .or_insert((
                        1,
                        &difference.path,
                        &difference.expected,
                        &difference.actual,
                    ));
            }
            let mut groups = groups.into_iter().collect::<Vec<_>>();
            groups.sort_by(|a, b| b.1 .0.cmp(&a.1 .0).then(a.0.cmp(b.0)));
            for (field, (count, example, expected, actual)) in groups.into_iter().take(50) {
                println!("{count:>5} {field} (e.g. {example})");
                if args[7] == "--grouped-values" {
                    println!(
                        "      expected: {}",
                        expected.chars().take(1000).collect::<String>()
                    );
                    println!(
                        "      actual:   {}",
                        actual.chars().take(1000).collect::<String>()
                    );
                }
            }
        } else {
            for difference in &differences {
                if args.len() == 8 {
                    println!("{} {}", difference.path, difference.field);
                } else {
                    println!(
                        "{} {}: expected {}, actual {}",
                        difference.path, difference.field, difference.expected, difference.actual
                    );
                }
            }
        }
        return Err(io::Error::other("procedure table audit found differences"));
    }
    Ok(())
}

fn od_class_audit(args: &[String]) -> io::Result<()> {
    let TranslationInputs {
        program,
        baseline,
        template,
    } = load_translation_inputs(args)?;
    let native = load_dmb(&args[6])?;
    let project_name = std::path::Path::new(&args[2])
        .file_stem()
        .and_then(|stem| stem.to_str());
    let emission = byond_dmb::od_emit::emit_diagnostic_hashed_with_baseline_named(
        &program,
        Some(&baseline),
        &template,
        std::path::Path::new(&args[5]),
        project_name,
    )
    .map_err(io::Error::other)?;
    let grouped = args.len() == 8;
    let differences = byond_dmb::compare::compare_class_tables(
        &native,
        &emission.dmb,
        if grouped { usize::MAX } else { 100 },
    );
    if differences.is_empty() {
        println!("no decoded class table discrepancies against native reference");
    } else if args.len() == 8 && args[7] == "--paths" {
        for difference in &differences {
            println!("{} {}", difference.path, difference.field);
        }
        return Err(io::Error::other(format!(
            "{} class table discrepancies",
            differences.len()
        )));
    } else if grouped {
        let mut groups =
            std::collections::BTreeMap::<String, (usize, String, String, String)>::new();
        for difference in &differences {
            let entry = groups.entry(difference.field.clone()).or_insert_with(|| {
                (
                    0,
                    difference.path.clone(),
                    difference.expected.clone(),
                    difference.actual.clone(),
                )
            });
            entry.0 += 1;
        }
        let mut groups: Vec<_> = groups.into_iter().collect();
        groups.sort_by(|(a_field, (a_count, ..)), (b_field, (b_count, ..))| {
            b_count.cmp(a_count).then_with(|| a_field.cmp(b_field))
        });
        println!(
            "{} class table differences in {} field groups",
            differences.len(),
            groups.len()
        );
        for (field, (count, example, expected, actual)) in groups.into_iter().take(50) {
            println!("  {count:>5} {field} (e.g. {example})");
            if args[7] == "--grouped-values" {
                println!(
                    "        expected: {}",
                    expected.chars().take(220).collect::<String>()
                );
                println!(
                    "        actual:   {}",
                    actual.chars().take(220).collect::<String>()
                );
            }
        }
        return Err(io::Error::other("class table audit found differences"));
    } else {
        for difference in &differences {
            println!(
                "{} {}: expected {}, actual {}",
                difference.path, difference.field, difference.expected, difference.actual
            );
        }
        return Err(io::Error::other(format!(
            "{} class table discrepancies (showing at most 100)",
            differences.len()
        )));
    }
    Ok(())
}

fn od_map_audit(args: &[String]) -> io::Result<()> {
    let TranslationInputs {
        program,
        baseline,
        template,
    } = load_translation_inputs(args)?;
    let native = load_dmb(&args[6])?;
    let project_name = std::path::Path::new(&args[2])
        .file_stem()
        .and_then(|stem| stem.to_str());
    let emission = byond_dmb::od_emit::emit_diagnostic_with_baseline_named(
        &program,
        Some(&baseline),
        &template,
        std::path::Path::new(&args[5]),
        project_name,
    )
    .map_err(io::Error::other)?;
    let differences = if args.len() == 8 {
        byond_dmb::compare::compare_maps_semantic(&native, &emission.dmb, 100)
    } else {
        byond_dmb::compare::compare_maps(&native, &emission.dmb, 100)
    };
    if differences.is_empty() {
        println!("no decoded map discrepancies against native reference");
    } else {
        for difference in &differences {
            println!(
                "{} {}: expected {}, actual {}",
                difference.path, difference.field, difference.expected, difference.actual
            );
        }
        return Err(io::Error::other(format!(
            "{} map discrepancies (showing at most 100)",
            differences.len()
        )));
    }
    Ok(())
}

fn od_lowering_audit(args: &[String]) -> io::Result<()> {
    let examples = if let Some(option) = args[6..].iter().find(|arg| arg.starts_with("--examples="))
    {
        option["--examples=".len()..]
            .parse::<usize>()
            .map_err(io::Error::other)?
            .clamp(1, 100)
    } else {
        1
    };
    let TranslationInputs {
        program,
        baseline,
        template,
    } = load_translation_inputs(args)?;
    let project_name = std::path::Path::new(&args[2])
        .file_stem()
        .and_then(|stem| stem.to_str());
    let emission = byond_dmb::od_emit::emit_diagnostic_with_baseline_named(
        &program,
        Some(&baseline),
        &template,
        std::path::Path::new(&args[5]),
        project_name,
    )
    .map_err(io::Error::other)?;
    let issues = byond_dmb::translate::audit_lowering_with_debug(
        &program,
        &emission,
        args[6..].iter().any(|arg| arg == "--debug-lines"),
    );
    let mut groups = std::collections::BTreeMap::<&str, (usize, Vec<(String, usize)>)>::new();
    for issue in &issues {
        let owner = program
            .procs
            .get(issue.od_proc_id)
            .and_then(|proc| program.types.get(proc.owning_type_id))
            .map(|ty| ty.path.trim_end_matches('/'))
            .unwrap_or("");
        let path = if issue.od_proc_id == usize::MAX {
            issue.name.clone()
        } else {
            format!("{owner}/{} [proc#{}]", issue.name, issue.od_proc_id)
        };
        let family = issue
            .reason
            .split_once(" (")
            .map_or(issue.reason.as_str(), |(prefix, _)| prefix);
        groups
            .entry(family)
            .and_modify(|entry| {
                entry.0 += 1;
                if entry.1.len() < examples {
                    entry.1.push((path.clone(), issue.offset));
                }
            })
            .or_insert((1, vec![(path, issue.offset)]));
    }
    println!(
        "audited {} OpenDream procedures; {} first errors in {} groups",
        program.procs.len(),
        issues.len(),
        groups.len()
    );
    let mut sorted = groups.into_iter().collect::<Vec<_>>();
    sorted.sort_by(|left, right| right.1 .0.cmp(&left.1 .0).then(left.0.cmp(right.0)));
    for (reason, (count, examples)) in sorted {
        println!("{count:>5} {reason}");
        for (name, offset) in examples {
            println!("        {name} at byte {offset}");
        }
    }
    if !issues.is_empty() {
        return Err(io::Error::other(format!(
            "{} procedures could not be lowered",
            issues.len()
        )));
    }
    Ok(())
}

fn od_diagnostic(args: &[String]) -> io::Result<()> {
    let TranslationInputs {
        program,
        baseline,
        template,
    } = load_translation_inputs(args)?;
    let project_name = std::path::Path::new(&args[2])
        .file_stem()
        .and_then(|stem| stem.to_str());
    let emitted = byond_dmb::translate::translate_diagnostic(
        &program,
        &baseline,
        &template,
        std::path::Path::new(&args[5]),
        project_name,
    )
    .map_err(io::Error::other)?;
    println!(
                "diagnostic translation passed: classes={} procs={} resources={} (payloads skipped; no output written)",
                emitted.dmb.classes.len(),
                emitted.dmb.procs.len(),
                emitted.dmb.resources.len()
            );
    Ok(())
}

fn od_to_dmb(args: &[String]) -> io::Result<()> {
    let TranslationInputs {
        program,
        baseline,
        template,
    } = load_translation_inputs(args)?;
    let project_name = std::path::Path::new(&args[2])
        .file_stem()
        .and_then(|stem| stem.to_str());
    let emitted = byond_dmb::translate::translate_named_debug(
        &program,
        &baseline,
        &template,
        std::path::Path::new(&args[5]),
        project_name,
        args.len() == 9,
    )
    .map_err(io::Error::other)?;
    let dmb_bytes = emitted.dmb.to_bytes()?;
    let mut rsc_bytes = Vec::new();
    for entry in &emitted.resources {
        write_entry(&mut rsc_bytes, entry)?;
    }
    std::fs::write(&args[6], dmb_bytes)?;
    std::fs::write(&args[7], rsc_bytes)?;
    println!("wrote {} and {}", args[6], args[7]);
    Ok(())
}
