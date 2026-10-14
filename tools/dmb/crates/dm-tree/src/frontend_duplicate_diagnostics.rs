//! Current declaration provenance for duplicate variable and procedure diagnostics.
use super::*;
pub(super) fn resolve(
    error: &SnapshotError,
    skeletons: &[Skeleton],
    origins: &[crate::Provenance],
    mapping: &Mapping<'_>,
    opaque_engine: bool,
    symbols: &SymbolTable,
    intrinsics: &[crate::IntrinsicMember],
) -> Vec<Diagnostic> {
    let duplicate = match error {
        SnapshotError::Tree(crate::TreeError::Duplicate { owner, name, kind }) => {
            Some((*owner, *owner, *name, false, *kind))
        }
        SnapshotError::Tree(crate::TreeError::InheritedDuplicate {
            owner,
            previous_owner,
            name,
            kind: MemberKind::Var,
        }) => Some((*owner, *previous_owner, *name, true, MemberKind::Var)),
        _ => None,
    };
    let Some((owner, previous_owner, name, inherited, member_kind)) = duplicate else {
        return vec![resolution_error(
            error,
            skeletons,
            origins,
            mapping,
            opaque_engine,
            symbols,
            intrinsics,
        )];
    };
    let declarations = |wanted| {
        skeletons.iter().enumerate().filter_map(move |(index, skeleton)| {
        matches!(skeleton, Skeleton::Member { owner: found, name: found_name, kind: found_kind, mode: crate::DefinitionMode::Declare, .. }
            if *found == wanted && *found_name == name && *found_kind == member_kind).then_some(index)
    }).collect::<Vec<_>>()
    };
    let current = declarations(owner);
    let previous = declarations(previous_owner);
    let indices = if inherited {
        current.last().copied().zip(previous.first().copied())
    } else if member_kind != MemberKind::Var {
        // DreamMaker reports a repeated procedure at the later definition.
        current.get(1).copied().zip(current.first().copied())
    } else {
        current.first().copied().zip(current.get(1).copied())
    };
    let Some((duplicate, previous)) = indices else {
        return vec![resolution_error(
            error,
            skeletons,
            origins,
            mapping,
            opaque_engine,
            symbols,
            intrinsics,
        )];
    };
    let Some(spelling) = symbols.text(name) else {
        return vec![resolution_error(
            error,
            skeletons,
            origins,
            mapping,
            opaque_engine,
            symbols,
            intrinsics,
        )];
    };
    [
        (duplicate, "duplicate definition"),
        (previous, "previous definition"),
    ]
    .into_iter()
    .map(|(index, message)| {
        let location = origins.get(index).and_then(|origin| {
            let source = mapping.files.get(origin.span.file.index())?;
            let line = source
                .line_starts
                .partition_point(|start| *start <= origin.span.start as usize);
            let mut location = mapping.line(&source.path, line)?;
            let occurrence = usize::try_from(origin.include_occurrence).ok()?;
            let current = mapping.plan.occurrences.get(occurrence)?;
            if current.path.as_path() != source.path.as_path() {
                return None;
            }
            // A repeated include shares physical bytes, but not its logical
            // encounter. Use the current provenance occurrence's actual region.
            let region = mapping.plan.regions.iter().find(|region| {
                region.occurrence == occurrence
                    && region.source_span.start <= origin.span.start as usize
                    && (origin.span.start as usize) < region.source_span.end
            })?;
            location.encounter_ordinal = region.encounter_ordinal;
            location.include_occurrence = occurrence;
            location.include_chain = mapping.include_chain(occurrence);
            location.path = current.path.clone();
            location.semantic_path = current.semantic_path.clone();
            Some(location)
        });
        Diagnostic {
            kind: DiagnosticKind::SourceError,
            stage: DiagnosticStage::Resolution,
            message: format!("{spelling}: {message}"),
            location,
        }
    })
    .collect()
}

#[cfg(test)]
#[path = "frontend_duplicate_diagnostics_tests.rs"]
mod tests;
