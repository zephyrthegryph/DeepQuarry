//! Pinned Follow::Field missing-static-type warning + exact call-return hints.
//! SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc, GPL-3.0.
use crate::{
    checker_expression_visit::{Event, Walk},
    checker_return_facts::ReturnFixHint,
    checks::{Diagnostic, Note, Severity},
};
use dm_tree::frontend::{ArchivedBody, BodyArchive};
pub fn archived(
    archive: &BodyArchive,
    body: &ArchivedBody<'_>,
    resolver: &(impl dm_ir::Resolver + ?Sized),
    profile: dm_ir::PackedU128,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    if severity == Severity::Disabled {
        return Ok(Vec::new());
    }
    rows(
        archive,
        crate::checker_expression_visit::archived(archive, body, resolver, profile)?,
        severity,
    )
}
pub fn rows(
    archive: &BodyArchive,
    walk: Walk<'_>,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    let mut rows = Vec::new();
    for event in walk.events {
        let Event::FieldWithoutStaticType {
            expression,
            at,
            name,
            hint,
        } = event
        else {
            continue;
        };
        // The warning point needs exact original byte provenance too, including
        // unhinted constructor/locate cases with no definition note.
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
            // Old one-file fixture note projection is proven. Cross-file source
            // formatting must be captured separately before admitting it.
            if source.path != warning_source.path {
                return Err("cross-file checker note formatting is not yet admitted".into());
            }
            notes.push(Note {
                message,
                source: Some(source),
            });
        }
        rows.push(Diagnostic {
            family: "field_access_static_type",
            severity,
            span: at,
            expression_span: expression.span,
            message: format!("field access requires static type: {name:?}"),
            notes,
        });
    }
    Ok(rows)
}
// Source locations are compiler-issued scalar facts, not serialized models.
// Note::legacy_text retains existing string notes for old fixture consumers:
// source.map(|s|format!("{}:{}: {}",s.line,s.byte_column,message)).unwrap_or(message).
