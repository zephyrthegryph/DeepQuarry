//! Migration parity driver. Production admission/baselines remain with Analyze.
use dm_analysis::{untyped_native, value_program::Values, value_schemas::Schemas};
use dm_tree::frontend::BodyArena;
#[path = "support/reference_hierarchy.rs"]
mod reference_hierarchy;
fn build<P: dm_preprocess::SourceProvider>(
    project: &std::path::Path,
    provider: &P,
    defines: &std::collections::BTreeMap<String, String>,
    workers: usize,
) -> Result<dm_tree::frontend::ColdFrontend, Vec<dm_tree::frontend::Diagnostic>> {
    dm_tree::frontend::build_with_config(
        project,
        provider,
        defines,
        dm_tree::frontend::FrontendConfig {
            workers,
            engine: Some(&reference_hierarchy::seed()),
            observer: None,
        },
    )
}

use std::path::{Path, PathBuf};
struct Files {
    project: PathBuf,
    manifest: String,
}
impl dm_preprocess::SourceProvider for Files {
    fn read(&self, path: &Path) -> Result<String, String> {
        if path == self.project {
            Ok(self.manifest.clone())
        } else {
            std::fs::read_to_string(path).map_err(|error| error.to_string())
        }
    }
}
fn collect(path: &Path, files: &mut Vec<PathBuf>) -> Result<(), std::io::Error> {
    for entry in std::fs::read_dir(path)? {
        let entry = entry?;
        if entry.file_type()?.is_dir() {
            collect(&entry.path(), files)?;
        } else if entry
            .path()
            .extension()
            .is_some_and(|extension| extension == "dm")
        {
            files.push(entry.path());
        }
    }
    Ok(())
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root =
        PathBuf::from(std::env::args().nth(1).ok_or("expected fixture root")?).canonicalize()?;
    let mut files = Vec::new();
    collect(&root.join("code"), &mut files)?;
    files.sort();
    let project = root.join("native-untyped-virtual.dme");
    let manifest = files
        .iter()
        .map(|path| {
            format!(
                "#include \"{}\"\n",
                path.to_string_lossy().replace('\\', "/")
            )
        })
        .collect();
    let frontend = build(
        &project,
        &Files {
            project: project.clone(),
            manifest,
        },
        &Default::default(),
        1,
    )
    .map_err(|error| format!("native frontend: {error:?}"))?;
    let bodies = BodyArena::new_typed(&frontend, |_| true);
    let mut schemas = Schemas::default();
    for file in frontend.files.iter().filter(|file| file.captured) {
        schemas.read_source(file.text.as_str())?;
    }
    let values = Values::build(&frontend, &bodies, frontend.snapshot.tree.as_ref(), &[])?;
    for finding in
        untyped_native::findings(&frontend, &bodies, &values, &schemas, &root, &[], |_| false)?
    {
        println!(
            "{}",
            serde_json::json!({"rule":finding.rule.name(),"file":finding.file,"line":finding.line,"message":finding.message,"identity":finding.identity})
        );
    }
    Ok(())
}
