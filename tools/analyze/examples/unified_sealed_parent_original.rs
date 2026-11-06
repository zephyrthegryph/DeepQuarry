//! Exact pinned DreamMaker reader/ancestry observation for the sealed-parent IPC fixture.
//! No native types, guessed diagnostics, or external checker executable.
use std::{error::Error, path::PathBuf};

fn main() -> Result<(), Box<dyn Error>> {
    let project = PathBuf::from(std::env::args_os().nth(1).ok_or("expected a DME path")?);
    if !project.is_absolute() {
        return Err("DME path must be absolute".into());
    }
    let context = dreammaker::Context::default();
    let preprocessor = dreammaker::preprocessor::Preprocessor::new(&context, project.clone())?;
    let mut parser = dreammaker::parser::Parser::new(
        &context,
        dreammaker::indents::IndentProcessor::new(&context, preprocessor),
    );
    parser.enable_procs();
    let (fatal, tree) = parser.parse_object_tree_2();
    if fatal {
        return Err(format!("pinned reader stopped: {:?}", context.errors()).into());
    }

    let position = |point: dreammaker::Location| {
        let file = context.file_path(point.file);
        serde_json::json!({"file": &*file, "line": point.line, "column": point.column})
    };
    let diagnostics: Vec<_> = context.errors().iter().map(|row| {
        let notes: Vec<_> = row.notes().iter().map(|note| {
            serde_json::json!({"location": position(note.location()), "message": note.description()})
        }).collect();
        serde_json::json!({
            "location": position(row.location()), "severity": row.severity().to_string(),
            "registration_tag": row.errortype(), "message": row.description(), "notes": notes,
        })
    }).collect();

    let mut ancestry = serde_json::Map::new();
    for owner in ["/alist", "/datum", "/list", "/savefile", "/world"] {
        let ty = tree.find(owner).ok_or("pinned owner missing")?;
        let parent = ty.parent_type().ok_or("pinned parent missing")?;
        let parent_path = if parent.get().is_root() { "/" } else { &parent.get().path };
        ancestry.insert(owner.to_owned(), serde_json::json!({
            "parent": parent_path,
            "has_marker": ty.get_var_declaration("unified_parent_marker").is_some(),
        }));
    }
    println!("{}", serde_json::json!({"diagnostics": diagnostics, "ancestry": ancestry}));
    Ok(())
}
