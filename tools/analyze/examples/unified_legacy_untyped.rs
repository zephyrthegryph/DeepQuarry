//! Independent legacy-policy oracle for native migration. Does not share native facts.
use dq_analyze::run::{registry, Engine, Options};
use std::path::PathBuf;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Match the legacy CLI's lexical absolute root. Windows canonicalize()
    // adds a verbatim prefix that the legacy preprocessor's FileList removes;
    // that would make every declaration appear outside the fixture root.
    let root = PathBuf::from(std::env::args().nth(1).ok_or("expected fixture root")?);
    let root = if root.is_absolute() {
        root
    } else {
        std::env::current_dir()?.join(root)
    };
    let scopes = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_owned();
    let engine = Engine::new(
        registry(),
        Options {
            root,
            scopes_from: Some(scopes),
            lints: vec!["untyped".into()],
            raw: true,
            no_cache: true,
            ..Default::default()
        },
    )?;
    // A partial or missing parse cannot serve as an independent clean oracle.
    // This is the existing legacy model; no native model is imported here.
    let semantic =
        dq_analyze::sem::sem_for(&engine.tree).ok_or("legacy semantic model unavailable")?;
    if !semantic.errors.is_empty() {
        return Err(format!(
            "legacy fixture parse errors:\n{}",
            semantic.errors.join("\n")
        )
        .into());
    }
    let lint = engine
        .reg
        .lints
        .iter()
        .find(|lint| lint.meta().name == "untyped")
        .ok_or("missing legacy policy")?;
    let (run, _, _) = engine.scan(lint.as_ref());
    for note in &run.notes {
        eprintln!("{note}");
    }
    for site in run.sites {
        println!(
            "{}",
            serde_json::json!({"rule":site.rule,"file":site.rel,"line":site.line,"message":site.msg,"identity":site.ident})
        );
    }
    Ok(())
}
