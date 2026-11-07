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
    LocalVariable(Span),
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
    fund_note: impl FnOnce(usize) -> Result<(), E>,
) -> Result<Vec<Note>, E> {
    let current = archive.borrowed_source_note_point(at.start)?;
    let Some(hint) = hint else { return Ok(Vec::new()); };
    let cross_file_bytes = |source: dm_tree::frontend::BorrowedSourceNoteOrigin<'_>| {
        let (path, _, _) = source.reported_coordinates();
        if path == current.reported_coordinates().0 { 0 } else { path.as_os_str().len() }
    };
    let (fix, call) = match hint {
        FixHint::Return(fix, call) => (fix, call),
        FixHint::LocalVariable(anchor) => {
            let source = archive.borrowed_source_note_point(anchor.start)?;
            fund_note(cross_file_bytes(source))?;
            return Ok(vec![crate::checks_directive_binding::original_note_message(
                source, current, "add additional type info here",
            )]);
        }
        FixHint::AuthoredVariable(formal) => {
            let source = archive.borrowed_member_policy_point(formal)?;
            fund_note(cross_file_bytes(source))?;
            return Ok(vec![crate::checks_directive_binding::original_note_message(
                source, current, "add additional type info here",
            )]);
        }
    };
    let (source, owner, kind, name) = match fix {
        ReturnFixHint::UnannotatedSource(identity) => (
            archive.callable_header_source().reported_point_for_identity(identity)?,
            archive.tree().symbols().text(identity.owner)
                .ok_or("return note owner unavailable")?.trim_end_matches('/'),
            if identity.verb { "verb" } else { "proc" },
            archive.tree().symbols().text(identity.name)
                .ok_or("return note name unavailable")?,
        ),
        ReturnFixHint::EvaluatedNone => {
            let source = archive.borrowed_source_note_point(call.start)?;
            fund_note(cross_file_bytes(source))?;
            return Ok(vec![crate::checks_directive_binding::original_note_message(
                source, current, "return type evaluated to None",
            )]);
        }
        ReturnFixHint::None => {
            return Err("empty return hint must not produce a source note".into())
        }
        ReturnFixHint::UnissuedBuiltin => {
            return Err("builtin return note provenance is not issued".into())
        }
    };
    let bytes = cross_file_bytes(source).checked_add(owner.len())
        .and_then(|n| n.checked_add(name.len()))
        .ok_or("return note allowance overflow")?;
    fund_note(bytes)?;
    let message = format!("add a return type annotation to {owner}/{kind}/{name}");
    Ok(vec![crate::checks_directive_binding::original_note_message(
        source, current, &message,
    )])
}
