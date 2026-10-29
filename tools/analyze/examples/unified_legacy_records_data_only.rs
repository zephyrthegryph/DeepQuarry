//! Independent complete named-rule oracle. Calls unchanged legacy lint policy.
use dq_analyze::run::{registry, Engine, Options};
use std::path::PathBuf;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = PathBuf::from(std::env::args().nth(1).ok_or("expected fixture root")?);
    let root = if root.is_absolute() {
        root
    } else {
        std::env::current_dir()?.join(root)
    };
    if !std::fs::read_to_string(root.join("deepquarry.dme"))?.contains("#include") {
        return Err("oracle requires explicit real deepquarry.dme includes".into());
    }
    if !root.join("tools/ci/lint_scopes.toml").is_file() {
        return Err("oracle requires fixture-local lint_scopes.toml".into());
    }
    let engine = Engine::new(
        registry(),
        Options {
            root: root.clone(),
            scopes_from: Some(root),
            lints: vec!["base_vars".into()],
            raw: true,
            no_cache: true,
            ..Default::default()
        },
    )?;
    let sem = dq_analyze::sem::sem_for(&engine.tree).ok_or("legacy semantic model unavailable")?;
    if !sem.errors.is_empty() {
        return Err(format!("legacy fixture parse errors:\n{}", sem.errors.join("\n")).into());
    }
    let lint = engine
        .reg
        .lints
        .iter()
        .find(|lint| lint.meta().name == "base_vars")
        .ok_or("legacy base_vars lint missing")?;
    let (run, _, _) = engine.scan(lint.as_ref());
    for note in run.notes {
        eprintln!("{note}");
    }
    for site in run
        .sites
        .into_iter()
        .filter(|site| site.rule == "records_data_only")
    {
        println!(
            "{}",
            serde_json::json!({"rule":site.rule,"rel":site.rel,"line":site.line,"msg":site.msg,"key":site.key,"ident":site.ident})
        );
    }
    Ok(())
}
