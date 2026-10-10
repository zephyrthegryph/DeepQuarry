//! Successful declaration diagnostics from the current authored encounter roster.
use crate::initializer_diagnostics::{captured_locations, InitializerLoweringError};
use crate::initializer_policy::warnings::InitializerWarning;
use dm_ir::WarningCode;
use dm_tree::frontend::ColdFrontend;
use dm_tree::initializers::{InitializerOrigin, InitializerOriginKind};
use dm_tree::{DefinitionMode, MemberKind, OccurrenceId, Target};
use std::collections::BTreeMap;

pub(crate) fn capture(
    frontend: &ColdFrontend,
) -> Result<Vec<InitializerWarning>, InitializerLoweringError> {
    let mut pending = BTreeMap::new();
    let mut selected = Vec::new();
    for (ordinal, occurrence) in frontend
        .snapshot
        .occurrences
        .source_order()
        .iter()
        .enumerate()
    {
        let Target::Member(id) = occurrence.target else {
            continue;
        };
        let member = frontend.snapshot.tree.member(id).ok_or_else(|| {
            InitializerLoweringError::Invariant("callable warning member absent".into())
        })?;
        if !matches!(member.kind, MemberKind::Proc | MemberKind::Verb) {
            continue;
        }
        let key = (member.owner, member.name, member.kind);
        if member.definition == DefinitionMode::Declare {
            if let Some(earlier) = pending.remove(&key) {
                let mut earlier: Vec<usize> = earlier;
                if !earlier.is_empty() {
                    selected.push((
                        earlier.remove(0),
                        WarningCode::OverrideBeforeDefinition,
                        member.name,
                    ));
                    selected.push((ordinal, WarningCode::DefinitionAfterOverride, member.name));
                    selected.extend(earlier.into_iter().map(|ordinal| {
                        (ordinal, WarningCode::OverrideBeforeDefinition, member.name)
                    }));
                }
            }
        } else if matches!(
            member.definition,
            DefinitionMode::Implicit | DefinitionMode::Override
        ) {
            pending.entry(key).or_insert_with(Vec::new).push(ordinal);
        }
    }
    let origins = selected
        .iter()
        .map(|(ordinal, _, _)| {
            let occurrence = &frontend.snapshot.occurrences.source_order()[*ordinal];
            let Target::Member(member) = occurrence.target else {
                unreachable!();
            };
            Ok(InitializerOrigin {
                occurrence: OccurrenceId(u32::try_from(*ordinal).map_err(|_| {
                    InitializerLoweringError::Invariant("too many warning occurrences".into())
                })?),
                kind: InitializerOriginKind::Declaration(member),
                encounter_ordinal: *ordinal,
                emission_ordinal: *ordinal,
                provenance: occurrence.provenance.clone(),
            })
        })
        .collect::<Result<Vec<_>, InitializerLoweringError>>()?;
    let locations = captured_locations(frontend, &origins.iter().collect::<Vec<_>>())?;
    selected
        .into_iter()
        .zip(locations)
        .map(|((source_ordinal, code, name), location)| {
            let name = frontend.snapshot.tree.symbols().text(name).ok_or_else(|| {
                InitializerLoweringError::Invariant("callable warning spelling absent".into())
            })?;
            Ok(InitializerWarning {
                source_ordinal,
                code,
                name: Some(name.to_owned()),
                location: location.into(),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Source(String);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.clone())
        }
    }
    #[test]
    fn authored_callable_warning_order_and_current_shift_match_pinned_capture() {
        let mut retained = crate::runner_host::BuildHost::one_shot();
        let engine = retained
            .engine(
                "matrix.dme".into(),
                Default::default(),
                true,
                include_bytes!("../../../fixtures/native_template.bin").to_vec(),
            )
            .unwrap();
        for shift in [0, 2] {
            let source = "\n".repeat(shift)
                + include_str!("../../../fixtures/native/callable_warnings/matrix.dm");
            let frontend = dm_tree::frontend::build_with_config(
                std::path::Path::new("matrix.dme"),
                &Source(source),
                &Default::default(),
                dm_tree::frontend::FrontendConfig {
                    workers: 1,
                    engine: Some(engine.frontend_seed()),
                    observer: None,
                },
            )
            .unwrap();
            let warnings = capture(&frontend).unwrap();
            assert_eq!(
                warnings
                    .iter()
                    .map(|w| (w.location.line, w.code))
                    .collect::<Vec<_>>(),
                vec![
                    (Some(7 + shift), WarningCode::OverrideBeforeDefinition),
                    (Some(9 + shift), WarningCode::DefinitionAfterOverride),
                    (Some(11 + shift), WarningCode::OverrideBeforeDefinition),
                    (Some(15 + shift), WarningCode::DefinitionAfterOverride),
                    (Some(13 + shift), WarningCode::OverrideBeforeDefinition),
                ]
            );
            assert!(warnings.iter().all(|w| w.name.as_deref() == Some("f")));
        }
    }
}
