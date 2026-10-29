//! SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc, GPL-3.0.
//! Shared exact pinned fix-hint note projection for field/call static-type
//! warnings. Retains compiler-issued original points, never searches source text.
use crate::{checker_return_facts::ReturnFixHint, checks::Note};
use dm_syntax::Span;
use dm_tree::frontend::BodyArchive;
pub fn notes(
    archive: &BodyArchive,
    at: Span,
    hint: Option<(ReturnFixHint, Span)>,
) -> Result<Vec<Note>, String> {
    let warning_source = archive.original_note_origin(at.start)?;
    let mut notes = Vec::new();
    if let Some((fix, call)) = hint {
        let (source, message) = match fix {
            ReturnFixHint::UnannotatedSource(identity) => {
                let owner = archive
                    .tree()
                    .symbols()
                    .text(identity.owner)
                    .ok_or("return note owner unavailable")?;
                let name = archive
                    .tree()
                    .symbols()
                    .text(identity.name)
                    .ok_or("return note name unavailable")?;
                let kind = if identity.verb { "verb" } else { "proc" };
                (
                    archive.callable_note_origin(identity)?,
                    format!(
                        "add a return type annotation to {}/{kind}/{name}",
                        owner.trim_end_matches('/')
                    ),
                )
            }
            ReturnFixHint::EvaluatedNone => (
                archive.original_note_origin(call.start)?,
                "return type evaluated to None".into(),
            ),
            ReturnFixHint::None => {
                return Err("empty return hint must not produce a source note".into())
            }
            ReturnFixHint::UnissuedBuiltin => {
                return Err("builtin return note provenance is not issued".into())
            }
        };
        if source.path != warning_source.path {
            return Err("cross-file checker note formatting is not yet admitted".into());
        }
        notes.push(Note {
            message,
            source: Some(source),
        });
    }
    Ok(notes)
}
