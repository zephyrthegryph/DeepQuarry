//! Independent old Engine.scan output for raw-only workspace discovery proof.
//! No native model or frontend is used by this executable.
use dq_analyze::{
    captured_raw_policy::RAW_FILE_LINTS,
    run::{registry, Engine, Options},
};
use std::path::PathBuf;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    if std::env::args().nth(1).as_deref() == Some("--manifest") {
        let registry = registry();
        let mut roots = std::collections::BTreeSet::new();
        let mut selectors = Vec::new();
        for name in RAW_FILE_LINTS {
            let lint = registry.find(name).ok_or("old raw lint absent")?;
            for (root, extension) in lint.meta().select.roots {
                if *extension != "dm" {
                    return Err("workspace raw producer has a non-DM selected family".into());
                }
                roots.insert(*root);
            }
            selectors.push(serde_json::json!({"name":name,"roots":lint.meta().select.roots}));
        }
        println!(
            "{}",
            serde_json::to_string(
                &serde_json::json!({"scope":"actual-old-raw27-metadata","lints":RAW_FILE_LINTS,"recursive_roots":roots,"selectors":selectors})
            )?
        );
        return Ok(());
    }
    let root = PathBuf::from(
        std::env::args()
            .nth(1)
            .ok_or("explicit old workspace root required")?,
    )
    .canonicalize()?;
    let names = RAW_FILE_LINTS
        .iter()
        .map(|s| s.to_string())
        .collect::<Vec<_>>();
    let old = Engine::new(
        registry(),
        Options {
            root: root.clone(),
            scopes_from: Some(root),
            lints: names,
            raw: true,
            no_cache: true,
            ..Default::default()
        },
    )?;
    let mut runs = Vec::new();
    for name in RAW_FILE_LINTS {
        let (run, allow, _) = old.scan(old.reg.find(name).ok_or("old raw lint absent")?);
        runs.push(
            serde_json::json!({"name":name,"sites":run.sites,"allow_used":allow,"notes":run.notes}),
        );
    }
    println!("{}", serde_json::to_string(&runs)?);
    Ok(())
}
