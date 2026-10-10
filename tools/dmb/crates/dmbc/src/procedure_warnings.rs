//! Source-independent procedure warning receipts, bound to current debug issuance.
use crate::debug_sources::{FrozenDebugOrigins, OriginAccess};
use crate::initializer_policy::warnings::{InitializerWarning, WarningLocation};
use dm_codegen_byond::ProcedureWarning;
use dm_ir::SymbolTable;

pub(crate) fn bind(
    warnings: &[ProcedureWarning],
    origins: &FrozenDebugOrigins,
    symbols: &SymbolTable,
    local_names: &[String],
) -> Result<Vec<InitializerWarning>, String> {
    let mut output = Vec::with_capacity(warnings.len());
    for warning in warnings {
        let ordinal = warning
            .source_ordinal
            .ok_or("unbound procedure warning ordinal")?;
        let origin = origins
            .iter()
            .nth(ordinal as usize)
            .ok_or("procedure warning ordinal outside current debug origins")?;
        validate_subject(warning, symbols, local_names)?;
        if origin.line == 0 || origin.semantic_path.is_empty() {
            return Err("invalid current procedure warning binding".into());
        }
        let name = warning
            .name
            .map(|id| {
                spelling(id, symbols, local_names)
                    .map(str::to_owned)
                    .ok_or("procedure warning spelling absent")
            })
            .transpose()?;
        let location = WarningLocation {
            semantic_path: std::sync::Arc::clone(origin.semantic_path),
            line: origin.line as usize,
        };
        output.push(InitializerWarning {
            source_ordinal: ordinal as usize,
            code: warning.code,
            name,
            location,
        });
    }
    Ok(output)
}

pub(crate) fn validate(
    warnings: &[ProcedureWarning],
    count: usize,
    symbols: &SymbolTable,
    local_names: &[String],
) -> Result<(), String> {
    for warning in warnings {
        let ordinal = warning
            .source_ordinal
            .ok_or("unbound procedure warning ordinal")?;
        if ordinal as usize >= count {
            return Err("invalid procedure warning receipt".into());
        }
        validate_subject(warning, symbols, local_names)?;
    }
    Ok(())
}

pub(crate) fn valid_receipt(
    warning: &ProcedureWarning,
    count: usize,
    present: impl FnOnce(dm_ir::SymbolId) -> bool,
) -> bool {
    warning
        .source_ordinal
        .is_some_and(|ordinal| (ordinal as usize) < count)
        && valid_subject(warning, present)
}

pub(crate) fn valid_subject(
    warning: &ProcedureWarning,
    present: impl FnOnce(dm_ir::SymbolId) -> bool,
) -> bool {
    warning.code.requires_name() == warning.name.is_some() && warning.name.is_none_or(present)
}
fn validate_subject(
    warning: &ProcedureWarning,
    symbols: &SymbolTable,
    locals: &[String],
) -> Result<(), String> {
    if valid_subject(warning, |id| {
        spelling(id, symbols, locals).is_some_and(|text| !text.is_empty())
    }) {
        Ok(())
    } else {
        Err("invalid procedure warning subject".into())
    }
}

fn spelling<'a>(
    name: dm_ir::SymbolId,
    symbols: &'a SymbolTable,
    locals: &'a [String],
) -> Option<&'a str> {
    locals
        .iter()
        .find(|text| dm_ir::SymbolId::of(text) == name)
        .map(String::as_str)
        .or_else(|| symbols.text(name))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::debug_sources::{DebugOrigin, DebugOrigins};
    #[test]
    fn current_rebinding_rejects_unbound_ordinals_and_missing_names() {
        let symbols = SymbolTable::default();
        let names = vec!["value".to_owned()];
        let receipt = ProcedureWarning {
            code: dm_ir::WarningCode::ListDoubleInit,
            name: Some(dm_ir::SymbolId::of("value")),
            source_ordinal: Some(0),
        };
        for (path, line) in [("first.dm", 2), ("shifted.dm", 17)] {
            let origins: FrozenDebugOrigins = DebugOrigins {
                entries: vec![DebugOrigin {
                    semantic_path: path.into(),
                    line,
                }],
            }
            .into();
            let warnings =
                bind(std::slice::from_ref(&receipt), &origins, &symbols, &names).unwrap();
            assert_eq!(
                crate::initializer_policy::warnings::render(&warnings).unwrap(),
                [format!(
                    "{path}:{line}:warning (list_double_init): value: list doubly initialized\n"
                )]
            );
            assert!(bind(std::slice::from_ref(&receipt), &origins, &symbols, &[]).is_err());
            for ordinal in [None, Some(1), Some(u32::MAX)] {
                let bad = ProcedureWarning {
                    source_ordinal: ordinal,
                    ..receipt.clone()
                };
                assert!(bind(&[bad], &origins, &symbols, &names).is_err());
            }
        }
    }
    #[test]
    fn subject_free_warning_preserves_exact_message_and_rejects_fake_name() {
        let origins: FrozenDebugOrigins = DebugOrigins {
            entries: vec![DebugOrigin {
                semantic_path: "input.dm".into(),
                line: 4,
            }],
        }
        .into();
        let symbols = SymbolTable::default();
        let receipt = ProcedureWarning {
            code: dm_ir::WarningCode::ListWithoutFilter,
            name: None,
            source_ordinal: Some(0),
        };
        let warnings = bind(std::slice::from_ref(&receipt), &origins, &symbols, &[]).unwrap();
        assert_eq!(crate::initializer_policy::warnings::render(&warnings).unwrap(),
            ["input.dm:4:warning (list_without_filter): it is recommended that you use an object filter or 'anything' when combining constant input types with lists\n"]);
        let invalid = ProcedureWarning {
            name: Some(dm_ir::SymbolId::of("input")),
            ..receipt
        };
        assert!(bind(&[invalid], &origins, &symbols, &["input".into()]).is_err());
        let invalid = ProcedureWarning {
            code: dm_ir::WarningCode::ListDoubleInit,
            name: None,
            source_ordinal: Some(0),
        };
        assert!(bind(&[invalid], &origins, &symbols, &[]).is_err());
    }
}
