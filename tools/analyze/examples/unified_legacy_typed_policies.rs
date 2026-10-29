//! Independent old-engine findings only; never a serialized semantic model.
use dq_analyze::run::{registry, Engine, Options};
use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = PathBuf::from(
        std::env::args()
            .nth(1)
            .ok_or("expected explicit fixture root")?,
    );
    let root = if root.is_absolute() {
        root
    } else {
        std::env::current_dir()?.join(root)
    };
    let names = ["init", "decl", "base_vars"];
    let engine = Engine::new(
        registry(),
        Options {
            root: root.clone(),
            scopes_from: Some(root),
            lints: names.iter().map(|name| name.to_string()).collect(),
            raw: true,
            no_cache: true,
            ..Default::default()
        },
    )?;
    let model =
        dq_analyze::sem::sem_for(&engine.tree).ok_or("independent legacy model unavailable")?;
    if !model.errors.is_empty() {
        return Err(format!("independent fixture has parse errors: {:?}", model.errors).into());
    }
    let mut runs = Vec::new();
    for name in names {
        let lint = engine.reg.find(name).ok_or("legacy policy unavailable")?;
        let (run, allow, _) = engine.scan(lint);
        runs.push(
            serde_json::json!({"name":name,"sites":run.sites,"allow_used":allow,"notes":run.notes}),
        );
    }
    println!("{}", serde_json::to_string(&runs)?);
    Ok(())
}
