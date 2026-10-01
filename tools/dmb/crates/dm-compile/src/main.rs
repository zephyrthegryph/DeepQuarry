//! Developer entry point for the new compiler prototype.

use dm_compiled::{default_cache_root, Coordinator, Request, Response, SessionKey};
use dm_compiler::bootstrap::{
    compile_project_with_resources_and_defines, emit_global_procs, replace_existing_procs,
};
use dm_compiler::{CompilerSession, ProjectSession};
use dm_output::{apply_pair_in_place, plan_pair, validate_byond_pair, PairPlan, PatchPolicy};
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::path::PathBuf;

fn main() {
    if let Err(error) = dm_host::run_on_compiler_thread(|| run().map_err(|error| error.to_string()))
    {
        eprintln!("dm-compile: {error}");
        std::process::exit(1);
    }
}

fn parse_defines(
    args: impl IntoIterator<Item = String>,
) -> Result<BTreeMap<String, String>, String> {
    let mut args = args.into_iter();
    let mut defines = BTreeMap::new();
    while let Some(arg) = args.next() {
        let definition = if arg == "--define" || arg == "-D" {
            args.next().ok_or("missing macro after --define/-D")?
        } else if let Some(value) = arg
            .strip_prefix("--define=")
            .or_else(|| arg.strip_prefix("-D"))
        {
            value.to_owned()
        } else {
            return Err(format!(
                "unexpected argument: {arg}; expected -DNAME[=VALUE]"
            ));
        };
        let (name, value) = definition.split_once('=').unwrap_or((&definition, "1"));
        let mut chars = name.chars();
        if !chars
            .next()
            .is_some_and(|c| c == '_' || c.is_ascii_alphabetic())
            || !chars.all(|c| c == '_' || c.is_ascii_alphanumeric())
            || value.contains(['\n', '\r'])
        {
            return Err(format!("invalid build define: {definition}"));
        }
        if defines.insert(name.to_owned(), value.to_owned()).is_some() {
            return Err(format!("duplicate build define: {name}"));
        }
    }
    Ok(defines)
}

#[cfg(test)]
mod tests {
    use super::parse_defines;

    #[test]
    fn parses_build_configurations_without_losing_values() {
        let defines = parse_defines(
            ["-DCITESTING", "--define", "VALUE=a=b", "-D", "EMPTY="].map(str::to_owned),
        )
        .unwrap();
        assert_eq!(defines["CITESTING"], "1");
        assert_eq!(defines["VALUE"], "a=b");
        assert_eq!(defines["EMPTY"], "");
    }

    #[test]
    fn rejects_ambiguous_or_malformed_defines() {
        for args in [
            vec!["--define"],
            vec!["-D"],
            vec!["-D9BAD"],
            vec!["-DGOOD=1\n#define OTHER"],
            vec!["-DX", "-DX=2"],
            vec!["--unknown"],
        ] {
            assert!(parse_defines(args.into_iter().map(str::to_owned)).is_err());
        }
    }
}

fn print_audit_groups(audit: &dm_syntax::StreamingAudit) {
    let mut groups = audit.diagnostic_groups.iter().collect::<Vec<_>>();
    groups.sort_by(|(left_name, left_count), (right_name, right_count)| {
        right_count.cmp(left_count).then(left_name.cmp(right_name))
    });
    for (message, count) in groups.into_iter().take(15) {
        println!("  {count}: {message}");
        if let Some(example) = audit.diagnostic_examples.get(message) {
            println!(
                "    example bytes {}..{}: {}",
                example.span.start, example.span.end, example.message
            );
        }
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let _process_budget = dm_host::install_process_budget()?;
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        Some("audit-resources") => {
            let source = PathBuf::from(args.next().ok_or("usage: dm-compile audit-resources EXPANDED.dm PROJECT.dme")?);
            let project = PathBuf::from(args.next().ok_or("missing project path")?);
            let defines = parse_defines(args)?;
            let source = dm_preprocess::read_source_file(&source)?;
            let session = ProjectSession::from_disk(project.clone(), defines);
            let expanded = session.preprocess_incremental();
            if !expanded.diagnostics.is_empty() { return Err(format!("project preprocessing failed: {:?}", expanded.diagnostics.iter().take(5).collect::<Vec<_>>()).into()); }
            let audit = dm_compiler::bootstrap::audit_resource_files_with_dirs(&project, &source, &expanded.file_dirs)?;
            for error in audit.errors { eprintln!("{error}"); }
            println!("resource audit: {} unique source assets, {} bytes, {} missing files", audit.resources, audit.total_bytes, audit.missing_count);
            if audit.missing_count > 0 { return Err("resource audit gaps found".into()); }
            Ok(())
        }
        Some("audit-initializers") => {
            let source_path = PathBuf::from(args.next().ok_or("usage: dm-compile audit-initializers EXPANDED.dm BUILTINS.dmb")?);
            let builtin_path = PathBuf::from(args.next().ok_or("missing builtin schema")?);
            if args.next().is_some() { return Err("unexpected audit-initializers argument".into()); }
            let source = dm_preprocess::read_source_file(&source_path)?;
            let builtins = fs::read(builtin_path)?;
            let audit = dm_compiler::audit_initializers(&source, &builtins)?;
            println!("initializer audit: {} classes, {} variables, {} default errors, {} dependency errors",
                audit.classes, audit.variables, audit.errors.len(), audit.dependency_errors.len());
            for error in &audit.errors { println!("  default: {error}"); }
            for error in &audit.dependency_errors { println!("  dependency: {error}"); }
            if !audit.errors.is_empty() || !audit.dependency_errors.is_empty() {
                return Err("initializer audit gaps found".into());
            }
            Ok(())
        }
        Some("audit-lowering") => {
            let source_path = PathBuf::from(args.next().ok_or("usage: dm-compile audit-lowering EXPANDED.dm BUILTINS.dmb")?);
            let builtin_path = PathBuf::from(args.next().ok_or("missing builtin schema")?);
            if args.next().is_some() { return Err("unexpected audit-lowering argument".into()); }
            let source = dm_preprocess::read_source_file(&source_path)?;
            let builtins = fs::read(builtin_path)?;
            let audit = dm_compiler::bootstrap::audit_lowering(&source, 1024 * 1024, &builtins)?;
            println!("lowering audit: {} procedures, {} passed, {} failed, {} errors", audit.procedures, audit.passed, audit.failed, audit.error_count);
            let mut groups = audit.groups.iter().collect::<Vec<_>>();
            groups.sort_by(|(left_name, left), (right_name, right)| right.count.cmp(&left.count).then(left_name.cmp(right_name)));
            for (message, group) in groups {
                println!("  {}: {}", group.count, message);
                for sample in &group.samples { println!("    {} at bytes {}..{}: {}", sample.procedure, sample.span.start, sample.span.end, sample.statement); }
            }
            if audit.failed > 0 { return Err("lowering audit gaps found".into()); }
            Ok(())
        }
        Some("audit-declarations") => {
            let path = PathBuf::from(args.next().ok_or("usage: dm-compile audit-declarations EXPANDED.dm")?);
            if args.next().is_some() { return Err("unexpected audit-declarations argument".into()); }
            let source = dm_preprocess::read_source_file(&path)?;
            let audit = dm_compiler::bootstrap::audit_declarations(&source, 1024 * 1024);
            for diagnostic in &audit.syntax_errors { eprintln!("{diagnostic:?}"); }
            for diagnostic in &audit.index_errors { eprintln!("{diagnostic}"); }
            println!("declaration audit: {} chunks, {} compact items, {} compact header bytes, {} procedure items; {} indexed types, {} variables, {} procedures; {} syntax errors, {} index errors, {} skipped declarations",
                audit.parsed_chunks, audit.compact_items, audit.compact_header_bytes, audit.procedure_items,
                audit.indexed_types, audit.indexed_variables, audit.indexed_procedures, audit.syntax_error_count, audit.index_error_count, audit.skipped_declarations);
            if audit.syntax_error_count > 0 || audit.index_error_count > 0 || audit.skipped_declarations > 0 { return Err("declaration audit gaps found".into()); }
            Ok(())
        }
        Some("audit-source") => {
            let path = PathBuf::from(args.next().ok_or("usage: dm-compile audit-source EXPANDED.dm")?);
            if args.next().is_some() { return Err("unexpected audit-source argument".into()); }
            let source = dm_preprocess::read_source_file(&path)?;
            let audit = dm_syntax::audit_source_streaming(&source, 256 * 1024, 50);
            for diagnostic in &audit.diagnostics { eprintln!("{diagnostic:?}"); }
            println!("syntax audit: {} chunks, {} procedures, {} statements, {} unsupported statements, {} diagnostics, {} oversized declarations skipped",
                audit.parsed_chunks, audit.procedures, audit.statements, audit.unsupported_statements, audit.diagnostic_count, audit.skipped_declarations);
            print_audit_groups(&audit);
            if audit.diagnostic_count > 0 || audit.unsupported_statements > 0 || audit.skipped_declarations > 0 {
                return Err("syntax audit gaps found".into());
            }
            Ok(())
        }
        Some(command @ ("preprocess" | "audit-project")) => {
            let path = PathBuf::from(args.next().ok_or("usage: dm-compile preprocess PROJECT.dme [-DNAME=VALUE]")?);
            let defines = parse_defines(args)?;
            let session = ProjectSession::from_disk(path, defines);
            let project = session.preprocess_incremental();
            if let Some(path) = env::var_os("DM_PREPROCESS_DUMP") { fs::write(path, &project.text)?; }
            for diagnostic in project.diagnostics.iter().take(50) { eprintln!("{diagnostic:?}"); }
            if project.diagnostics.len() > 50 { eprintln!("{} additional diagnostics omitted", project.diagnostics.len() - 50); }
            let (hits, misses) = session.preprocess_cache_stats();
            println!("{} included files, {} expanded bytes, {} source lines, {} active maps; include cache {} hits / {} misses",
                project.dependencies.len(), project.text.len(), project.origins.len(), project.map_includes.len(), hits, misses);
            if !project.diagnostics.is_empty() { return Err("preprocessing diagnostics emitted".into()); }
            if command == "audit-project" {
                let audit = dm_syntax::audit_source_streaming(&project.text, 256 * 1024, 50);
                for diagnostic in &audit.diagnostics {
                    let line = project.text.as_bytes()[..diagnostic.span.start.min(project.text.len())].iter().filter(|&&byte| byte == b'\n').count() + 1;
                    let origin = project.origins.iter().find(|origin| origin.output_line == line);
                    if let Some(origin) = origin {
                        eprintln!("{}:{}: {}", origin.path.display(), origin.source_line, diagnostic.message);
                    } else { eprintln!("expanded line {line}: {}", diagnostic.message); }
                }
                println!("syntax audit: {} chunks, {} procedures, {} statements, {} unsupported statements, {} diagnostics, {} oversized declarations skipped",
                    audit.parsed_chunks, audit.procedures, audit.statements, audit.unsupported_statements, audit.diagnostic_count, audit.skipped_declarations);
                print_audit_groups(&audit);
            if audit.diagnostic_count > 0 || audit.unsupported_statements > 0 || audit.skipped_declarations > 0 {
                    return Err("syntax audit gaps found".into());
                }
            }
            Ok(())
        }
        Some("check") => {
            let path = PathBuf::from(args.next().ok_or("usage: dm-compile check FILE.dm")?);
            let defines = parse_defines(args)?;
            if path.extension().is_some_and(|ext| ext.eq_ignore_ascii_case("dme")) {
                let session = ProjectSession::from_disk(path, defines);
                // The diagnostic parser still materializes a whole-project AST.
                // Keep this convenience command bounded until it can stream.
                let limit = dm_compiler::check_source_limit();
                if let Some(size) = session.preprocessed_byte_len() {
                    dm_compiler::check_source_size(size, limit)?;
                }
                let preprocessed = session.preprocess_incremental();
                let syntax = dm_syntax::parse(&preprocessed.text);
                for diagnostic in &preprocessed.diagnostics {
                    eprintln!("{diagnostic:?}");
                }
                for diagnostic in &syntax.diagnostics {
                    eprintln!("{diagnostic:?}");
                }
                println!(
                    "{} included files, {} top-level syntax items",
                    preprocessed.dependencies.len(),
                    syntax.items.len()
                );
                if !preprocessed.diagnostics.is_empty() || !syntax.diagnostics.is_empty() {
                    return Err("project diagnostics emitted".into());
                }
            } else {
                if !defines.is_empty() {
                    return Err("build defines require a .dme project".into());
                }
                let text = fs::read_to_string(&path)?;
                dm_compiler::check_source_size(text.len(), dm_compiler::check_source_limit())?;
                let mut compiler = CompilerSession::default();
                compiler.update_file(path.clone(), text);
                let syntax = compiler.parse(&path).expect("source was just registered");
                for diagnostic in &syntax.diagnostics {
                    eprintln!("{path:?}: {diagnostic:?}");
                }
                println!("{} top-level syntax items", syntax.items.len());
                if !syntax.diagnostics.is_empty() {
                    return Err("syntax diagnostics emitted".into());
                }
            }
            Ok(())
        }
        Some("check-daemon") => {
            let address = args.next().ok_or("usage: dm-compile check-daemon ADDRESS FILE.dm")?;
            let path = PathBuf::from(args.next().ok_or("usage: dm-compile check-daemon ADDRESS FILE.dm")?);
            if args.next().is_some() { return Err("usage: dm-compile check-daemon ADDRESS FILE.dm".into()); }
            let text = fs::read_to_string(&path)?;
            let root = env::current_dir()?;
            let key = SessionKey::new(&root, &path, "516.1687", vec![], "check")?;
            let request = Request::Check { key, source: path, text };
            let mut stream = TcpStream::connect(address)?;
            serde_json::to_writer(&mut stream, &request)?;
            stream.write_all(b"\n")?;
            let mut response_line = String::new();
            BufReader::new(stream).read_line(&mut response_line)?;
            let response: Response = serde_json::from_str(&response_line)?;
            for diagnostic in &response.diagnostics { eprintln!("{diagnostic}"); }
            if let Some(error) = response.error { return Err(error.into()); }
            println!("{} top-level syntax items, source {}, shared syntax cache {}", response.item_count, response.source_digest.as_deref().unwrap_or("unknown"), if response.shared_syntax_hit { "hit" } else { "miss" });
            if !response.ok { return Err("syntax diagnostics emitted".into()); }
            Ok(())
        }
        Some("check-project-daemon") => {
            let address = args.next().ok_or("usage: dm-compile check-project-daemon ADDRESS PROJECT.dme")?;
            let path = PathBuf::from(args.next().ok_or("usage: dm-compile check-project-daemon ADDRESS PROJECT.dme")?);
            let defines = parse_defines(args)?;
            let root = env::current_dir()?;
            let key = SessionKey::new(&root, &path, "516.1687", defines.into_iter().collect(), "check")?;
            let mut stream = TcpStream::connect(address)?;
            serde_json::to_writer(&mut stream, &Request::CheckProject { key })?;
            stream.write_all(b"\n")?;
            let mut response_line = String::new();
            BufReader::new(stream).read_line(&mut response_line)?;
            let response: Response = serde_json::from_str(&response_line)?;
            for diagnostic in &response.diagnostics { eprintln!("{diagnostic}"); }
            if let Some(error) = response.error { return Err(error.into()); }
            println!("{} top-level syntax items, shared project cache {}", response.item_count, if response.shared_syntax_hit { "hit" } else { "miss" });
            if !response.ok { return Err("project diagnostics emitted".into()); }
            Ok(())
        }
        Some("bootstrap-procs") => {
            let source = PathBuf::from(args.next().ok_or("usage: dm-compile bootstrap-procs SOURCE.dm TEMPLATE.dmb OUTPUT.dmb")?);
            let template = PathBuf::from(args.next().ok_or("usage: dm-compile bootstrap-procs SOURCE.dm TEMPLATE.dmb OUTPUT.dmb")?);
            let output = PathBuf::from(args.next().ok_or("usage: dm-compile bootstrap-procs SOURCE.dm TEMPLATE.dmb OUTPUT.dmb")?);
            if args.next().is_some() { return Err("usage: dm-compile bootstrap-procs SOURCE.dm TEMPLATE.dmb OUTPUT.dmb".into()); }
            let source_text = fs::read_to_string(source)?;
            let template_bytes = fs::read(template)?;
            let (dmb, emitted) = replace_existing_procs(&source_text, &template_bytes)?;
            if emitted.is_empty() { return Err("source contained no supported procedures".into()); }
            let bytes = dmb.to_bytes()?;
            byond_dmb::dmb::Dmb::from_bytes(&bytes)?.validate_references()?;
            fs::write(&output, bytes)?;
            println!("lowered {} procedure bodies to {}", emitted.len(), output.display());
            Ok(())
        }
        Some("emit-global-procs") => {
            let source = PathBuf::from(args.next().ok_or("usage: dm-compile emit-global-procs SOURCE.dm BUILTINS.dmb OUTPUT.dmb")?);
            let builtins = PathBuf::from(args.next().ok_or("usage: dm-compile emit-global-procs SOURCE.dm BUILTINS.dmb OUTPUT.dmb")?);
            let output = PathBuf::from(args.next().ok_or("usage: dm-compile emit-global-procs SOURCE.dm BUILTINS.dmb OUTPUT.dmb")?);
            if args.next().is_some() { return Err("usage: dm-compile emit-global-procs SOURCE.dm BUILTINS.dmb OUTPUT.dmb".into()); }
            let world_name = source.file_stem().and_then(|stem| stem.to_str()).ok_or("source filename has no world name")?;
            let (dmb, emitted) = emit_global_procs(&fs::read_to_string(&source)?, &fs::read(builtins)?, world_name)?;
            let bytes = dmb.to_bytes()?;
            byond_dmb::dmb::Dmb::from_bytes(&bytes)?.validate_references()?;
            fs::write(&output, bytes)?;
            println!("emitted {} global procedures to {}", emitted.len(), output.display());
            Ok(())
        }
        Some("build-project") => {
            let usage = "usage: dm-compile build-project PROJECT.dme BUILTINS.dmb OUTPUT_DIR";
            let project = PathBuf::from(args.next().ok_or(usage)?);
            let builtins = PathBuf::from(args.next().ok_or(usage)?);
            let output_root = PathBuf::from(args.next().ok_or(usage)?);
            let defines = parse_defines(args)?;
            let key = SessionKey::new(env::current_dir()?, &project, "516.1687", defines.into_iter().collect(), "build")?;
            let mut coordinator = Coordinator::new(default_cache_root(&project))?;
            let response = coordinator.handle(Request::BuildProject { key, builtins, output_root });
            for diagnostic in &response.diagnostics { eprintln!("{diagnostic}"); }
            if let Some(error) = response.error { return Err(error.into()); }
            if !response.ok { return Err("project diagnostics emitted".into()); }
            let build = response.build.ok_or("build returned no generation")?;
            println!("emitted {} procedures to {} (output cache {}, {} lowered, {} reused)", build.emitted_procs, build.dmb.display(), if build.cache_hit { "hit" } else { "miss" }, build.lowered_procs, build.reused_procs);
            Ok(())
        }
        Some("build-project-daemon") => {
            let usage = "usage: dm-compile build-project-daemon ADDRESS PROJECT.dme BUILTINS.dmb OUTPUT_DIR";
            let address = args.next().ok_or(usage)?;
            let project = PathBuf::from(args.next().ok_or(usage)?);
            let builtins = PathBuf::from(args.next().ok_or(usage)?);
            let output_root = PathBuf::from(args.next().ok_or(usage)?);
            let defines = parse_defines(args)?;
            let root = env::current_dir()?;
            let key = SessionKey::new(&root, &project, "516.1687", defines.into_iter().collect(), "build")?;
            let mut stream = TcpStream::connect(address)?;
            serde_json::to_writer(&mut stream, &Request::BuildProject { key, builtins, output_root })?;
            stream.write_all(b"\n")?;
            let mut response_line = String::new();
            BufReader::new(stream).read_line(&mut response_line)?;
            let response: Response = serde_json::from_str(&response_line)?;
            for diagnostic in &response.diagnostics { eprintln!("{diagnostic}"); }
            if let Some(error) = response.error { return Err(error.into()); }
            if !response.ok { return Err("project diagnostics emitted".into()); }
            let build = response.build.ok_or("daemon returned no build result")?;
            println!("emitted {} procedures to {} (output cache {}, {} lowered, {} reused)", build.emitted_procs, build.dmb.display(), if build.cache_hit { "hit" } else { "miss" }, build.lowered_procs, build.reused_procs);
            Ok(())
        }
        Some("build-project-patch-daemon") => {
            let usage = "usage: dm-compile build-project-patch-daemon ADDRESS PROJECT.dme BUILTINS.dmb OUTPUT.dmb OUTPUT.rsc --exclusive";
            let address = args.next().ok_or(usage)?;
            let project = PathBuf::from(args.next().ok_or(usage)?);
            let builtins = PathBuf::from(args.next().ok_or(usage)?).canonicalize()?;
            let dmb = PathBuf::from(args.next().ok_or(usage)?).canonicalize()?;
            let rsc = PathBuf::from(args.next().ok_or(usage)?).canonicalize()?;
            if args.next().as_deref() != Some("--exclusive") {
                return Err(usage.into());
            }
            let defines = parse_defines(args)?;
            let root = env::current_dir()?;
            let key = SessionKey::new(&root, &project, "516.1687", defines.into_iter().collect(), "build")?;
            let mut stream = TcpStream::connect(address)?;
            serde_json::to_writer(&mut stream, &Request::BuildProjectPatch {
                key, builtins, dmb, rsc, exclusive: true,
            })?;
            stream.write_all(b"\n")?;
            let mut response_line = String::new();
            BufReader::new(stream).read_line(&mut response_line)?;
            let response: Response = serde_json::from_str(&response_line)?;
            for diagnostic in &response.diagnostics { eprintln!("{diagnostic}"); }
            if let Some(error) = response.error { return Err(error.into()); }
            if !response.ok { return Err("project diagnostics emitted".into()); }
            let build = response.build.ok_or("daemon returned no patch result")?;
            println!("patched {} and {} (output cache {})", build.dmb.display(), build.rsc.display(), if build.cache_hit { "hit" } else { "miss" });
            Ok(())
        }
        Some("build-project-patch") => {
            let usage = "usage: dm-compile build-project-patch PROJECT.dme BUILTINS.dmb OUTPUT.dmb OUTPUT.rsc --exclusive";
            let project = PathBuf::from(args.next().ok_or(usage)?);
            let builtins = PathBuf::from(args.next().ok_or(usage)?);
            let dmb_path = PathBuf::from(args.next().ok_or(usage)?);
            let rsc_path = PathBuf::from(args.next().ok_or(usage)?);
            if args.next().as_deref() != Some("--exclusive") {
                return Err(usage.into());
            }
            let defines = parse_defines(args)?;
            let world_name = project.file_stem().and_then(|stem| stem.to_str()).ok_or("project filename has no world name")?;
            let output = compile_project_with_resources_and_defines(&project, &fs::read(builtins)?, world_name, &defines)?;
            let new_dmb = output.dmb.to_bytes()?;
            validate_byond_pair(&new_dmb, &output.rsc_bytes)?;
            let old_dmb = fs::read(&dmb_path)?;
            let old_rsc = fs::read(&rsc_path)?;
            match plan_pair(&old_dmb, &old_rsc, &new_dmb, &output.rsc_bytes, PatchPolicy::default()) {
                PairPlan::Unchanged => println!("output is unchanged"),
                plan @ PairPlan::Patch { .. } => {
                    let changed_bytes = match &plan {
                        PairPlan::Patch { dmb, rsc, .. } => dmb.iter().chain(rsc.iter())
                            .flat_map(|patch| patch.spans.iter())
                            .map(|span| span.after.len()).sum::<usize>(),
                        _ => 0,
                    };
                    let journal = dmb_path.with_extension("dmb.undo-journal");
                    apply_pair_in_place(&dmb_path, &rsc_path, &journal, &plan)?;
                    println!("patched {} in place ({} bytes written)", dmb_path.display(), changed_bytes);
                }
                PairPlan::Rebuild { .. } => return Err("output layout changed; use build-project for a new generation".into()),
            }
            Ok(())
        }
        Some("patch-global-procs") => {
            let usage = "usage: dm-compile patch-global-procs SOURCE.dm BUILTINS.dmb OUTPUT.dmb OUTPUT.rsc --exclusive";
            let source = PathBuf::from(args.next().ok_or(usage)?);
            let builtins = PathBuf::from(args.next().ok_or(usage)?);
            let dmb_path = PathBuf::from(args.next().ok_or(usage)?);
            let rsc_path = PathBuf::from(args.next().ok_or(usage)?);
            if args.next().as_deref() != Some("--exclusive") || args.next().is_some() { return Err(usage.into()); }
            let world_name = source.file_stem().and_then(|stem| stem.to_str()).ok_or("source filename has no world name")?;
            let (world, emitted) = emit_global_procs(&fs::read_to_string(&source)?, &fs::read(builtins)?, world_name)?;
            if emitted.is_empty() { return Err("source contained no supported procedures".into()); }
            let new_dmb = world.to_bytes()?;
            let new_rsc = Vec::new();
            validate_byond_pair(&new_dmb, &new_rsc)?;
            let old_dmb = fs::read(&dmb_path)?;
            let old_rsc = fs::read(&rsc_path)?;
            match plan_pair(&old_dmb, &old_rsc, &new_dmb, &new_rsc, PatchPolicy::default()) {
                PairPlan::Unchanged => println!("output is unchanged"),
                plan @ PairPlan::Patch { .. } => {
                    let changed_bytes = match &plan {
                        PairPlan::Patch { dmb, rsc, .. } => dmb.iter().chain(rsc.iter())
                            .flat_map(|patch| patch.spans.iter())
                            .map(|span| span.after.len())
                            .sum::<usize>(),
                        _ => 0,
                    };
                    let journal = dmb_path.with_extension("dmb.undo-journal");
                    apply_pair_in_place(&dmb_path, &rsc_path, &journal, &plan)?;
                    println!("patched {} in place ({} bytes written)", dmb_path.display(), changed_bytes);
                }
                PairPlan::Rebuild { .. } => return Err("output layout changed; use a new output generation".into()),
            }
            Ok(())
        }
        _ => Err("prototype commands: check FILE.dm|PROJECT.dme; check-daemon ADDRESS FILE.dm; check-project-daemon ADDRESS PROJECT.dme; bootstrap-procs SOURCE.dm TEMPLATE.dmb OUTPUT.dmb; emit-global-procs SOURCE.dm BUILTINS.dmb OUTPUT.dmb; build-project PROJECT.dme BUILTINS.dmb OUTPUT_DIR; build-project-daemon ADDRESS PROJECT.dme BUILTINS.dmb OUTPUT_DIR; build-project-patch-daemon ADDRESS PROJECT.dme BUILTINS.dmb OUTPUT.dmb OUTPUT.rsc --exclusive; build-project-patch PROJECT.dme BUILTINS.dmb OUTPUT.dmb OUTPUT.rsc --exclusive; patch-global-procs SOURCE.dm BUILTINS.dmb OUTPUT.dmb OUTPUT.rsc --exclusive".into()),
    }
}
