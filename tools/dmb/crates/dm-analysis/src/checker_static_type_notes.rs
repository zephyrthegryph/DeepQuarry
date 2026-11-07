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
    notes_using(archive, at, hint, |_| Ok(()))
}

pub(crate) fn notes_using<E: From<String> + for<'a> From<&'a str>>(
    archive: &BodyArchive,
    at: Span,
    hint: Option<FixHint>,
    fund_authored: impl FnOnce(usize) -> Result<(), E>,
) -> Result<Vec<Note>, E> {
    let current = archive.borrowed_source_note_point(at.start)?;
    let Some(hint) = hint else { return Ok(Vec::new()); };
    let (fix, call) = match hint {
        FixHint::Return(fix, call) => (fix, call),
        FixHint::AuthoredVariable(formal) => {
            let source = archive.borrowed_member_policy_point(formal)?;
            let (path, _, _) = source.reported_coordinates();
            let path_bytes = if path == current.reported_coordinates().0 {
                0
            } else {
                path.as_os_str().len()
            };
            fund_authored(path_bytes)?;
            return Ok(vec![crate::checks_directive_binding::original_note_message(
                source, current, "add additional type info here",
            )]);
        }
    };
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
            archive.source_note_point(call.start)?,
            "return type evaluated to None".into(),
        ),
        ReturnFixHint::None => {
            return Err("empty return hint must not produce a source note".into())
        }
        ReturnFixHint::UnissuedBuiltin => {
            return Err("builtin return note provenance is not issued".into())
        }
    };
    if source.path.as_path() != current.physical_path() {
        return Err("cross-file checker note formatting is not yet admitted".into());
    }
    Ok(vec![Note { message, source: Some(source) }])
}
