//! SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc, GPL-3.0.
//! Shared exact pinned fix-hint note projection for field/call static-type
//! warnings. Retains compiler-issued original points, never searches source text.
use crate::{checker_return_facts::ReturnFixHint, checks::Note};
use dm_syntax::Span;
use dm_tree::{frontend::BodyArchive, MemberId};

#[derive(Clone, Copy, Debug)]
pub enum FixHint {
    Return(ReturnFixHint, Span),
    /// The original evaluator selected this formal in the same archive.
    AuthoredVariable(MemberId),
}
pub fn notes(
    archive: &BodyArchive,
    at: Span,
    hint: Option<FixHint>,
) -> Result<Vec<Note>, String> {
    let warning_source = archive.source_note_point(at.start)?;
    let mut notes = Vec::new();
    if let Some(fix) = hint {
        let (source, message) = match fix {
            FixHint::Return(ReturnFixHint::UnannotatedSource(identity), _) => {
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
            FixHint::Return(ReturnFixHint::EvaluatedNone, call) => (
                archive.source_note_point(call.start)?,
                "return type evaluated to None".into(),
            ),
            FixHint::Return(ReturnFixHint::None, _) => {
                return Err("empty return hint must not produce a source note".into())
            }
            FixHint::Return(ReturnFixHint::UnissuedBuiltin, _) => {
                return Err("builtin return note provenance is not issued".into())
            }
            FixHint::AuthoredVariable(formal) => (
                archive.member_policy_point(formal)?,
                "add additional type info here".into(),
            ),
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
