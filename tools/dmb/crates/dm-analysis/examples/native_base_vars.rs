//! Bounded supplement differential fixture; no raw lint/admission parity claim.
use dm_analysis::base_var_declarations::{base_var_declarations, record_procedures};
use dm_tree::frontend::{build_with_config, FrontendConfig, SourceLocation};
use std::{
    cell::RefCell,
    collections::BTreeMap,
    path::{Path, PathBuf},
};
#[path = "support/reference_hierarchy.rs"]
mod reference_hierarchy;

#[derive(Default)]
struct Files(RefCell<BTreeMap<PathBuf, Vec<u8>>>);
impl dm_preprocess::SourceProvider for Files {
    fn read(&self, path: &Path) -> Result<String, String> {
        if !self.0.borrow().contains_key(path) {
            let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
            self.0.borrow_mut().insert(path.to_owned(), bytes);
        }
        Ok(dm_preprocess::decode_source_bytes(
            self.0.borrow().get(path).unwrap(),
        ))
    }
}
fn relative(root: &Path, path: &Path) -> String {
    let path = path
        .strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/");
    if !path.contains("/.") {
        return path;
    }
    let mut out = Vec::new();
    for part in path.split('/') {
        match part {
            "." => (),
            ".." if out.last().is_some_and(|last| *last != "..") => {
                out.pop();
            }
            _ => out.push(part),
        }
    }
    out.join("/")
}
// Apply legacy raw-display line numbering to the immutable bytes captured by
// this host's source provider. Never reread a changing worktree after build.
fn line(files: &Files, source: &SourceLocation) -> Result<usize, String> {
    let captures = files.0.borrow();
    let bytes = captures
        .get(source.path.as_ref())
        .ok_or("raw source capture unavailable")?;
    let mut model_line = 1;
    let mut preceding = 0;
    for (index, byte) in bytes.iter().enumerate() {
        match byte {
            b'\n' => model_line += 1,
            b'\r' if bytes.get(index + 1) != Some(&b'\n') && model_line < source.line => {
                preceding += 1
            }
            _ => (),
        }
    }
    Ok(source.line + preceding)
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = PathBuf::from(std::env::args().nth(1).ok_or("expected fixture root")?);
    let root = if root.is_absolute() {
        root
    } else {
        std::env::current_dir()?.join(root)
    };
    let project = root.join("deepquarry.dme");
    let files = Files::default();
    let seed = reference_hierarchy::seed();
    let frontend = build_with_config(
        &project,
        &files,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .map_err(|e| format!("native frontend: {e:?}"))?;
    let archive = frontend
        .body_archive()
        .ok_or("native archive unavailable")?;
    let tree = archive.tree();
    let base_types = [
        "/atom",
        "/atom/movable",
        "/obj",
        "/obj/item",
        "/obj/machinery",
        "/mob",
        "/mob/living",
        "/mob/living/carbon",
        "/mob/living/carbon/human",
    ];
    for row in base_var_declarations(&archive, &base_types, &root)? {
        println!(
            "{}",
            serde_json::json!({"row":"base_var_declaration", "rel":relative(&root,&row.source.path), "line":line(&files,&row.source)?, "owner":tree.symbols().text(row.owner).ok_or("owner unavailable")?, "name":tree.symbols().text(row.name).ok_or("name unavailable")?, "vtype":row.declared_type_text()?, "base":row.base, "list_init":row.list_init})
        );
    }
    for row in record_procedures(&archive, &root)? {
        println!(
            "{}",
            serde_json::json!({"row":"record_proc", "rel":relative(&root,&row.source.path), "line":line(&files,row.source)?, "name":tree.symbols().text(row.name).ok_or("proc name unavailable")?})
        );
    }
    Ok(())
}
