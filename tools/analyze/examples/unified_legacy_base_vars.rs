//! Independent unchanged Analyze supplement oracle, enabled explicitly only.
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
        return Err("oracle fixture requires explicit real deepquarry.dme includes".into());
    }
    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_owned();
    let engine = Engine::new(
        registry(),
        Options {
            root,
            scopes_from: Some(repo),
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
    for row in dq_analyze::lints::base_vars::unified_oracle_supplement(&sem) {
        println!("{row}");
    }
    Ok(())
}
