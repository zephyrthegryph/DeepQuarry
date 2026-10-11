//! Local declaration meaning from the same parsed stored-declaration walk.
use super::*;
pub(super) fn local(
    declaration: &str,
    symbols: &mut SymbolTable,
) -> Result<(dm_ir::SymbolId, Option<dm_ir::SymbolId>), String> {
    let declaration = declaration.trim();
    let path = declaration
        .strip_prefix("var/")
        .or_else(|| declaration.strip_prefix("var "))
        .unwrap_or(declaration);
    let base = path.split('[').next().ok_or("missing local name")?.trim();
    let components: Vec<_> = base.split('/').filter(|part| !part.is_empty()).collect();
    let Some((name, prefix)) = components.split_last() else {
        return Err("missing local name".into());
    };
    let name = symbols.intern(name).map_err(|error| error.to_string())?;
    let types: Vec<_> = prefix
        .iter()
        .copied()
        .filter(|part| !matches!(*part, "tmp" | "static" | "const" | "global"))
        .collect();
    let declared_type = if path.contains('[') {
        Some(symbols.intern("/list").map_err(|error| error.to_string())?)
    } else if types.is_empty() {
        None
    } else {
        Some(
            symbols
                .intern(&format!("/{}", types.join("/")))
                .map_err(|error| error.to_string())?,
        )
    };
    Ok((name, declared_type))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stored_declarations_capture_current_lexical_scope_without_later_or_sibling_names() {
        let procedure = ProcedureIdentity {
            owner: dm_ir::SymbolId::of("/"),
            name: dm_ir::SymbolId::of("p"),
            verb: false,
            occurrence: 0,
        };
        let source = "/proc/p()\n    var/outer = 1\n    var/static/first = nameof(outer)\n    var/static/second = nameof(outer)\n    if(1)\n        var/datum/inside = null\n        var/static/nested = nameof(inside)\n    var/static/after = nameof(outer)\n    var/later = 2\n";
        let parsed = dm_syntax::parse(source);
        let plan = capture(procedure, &parsed.items[0].children).unwrap();
        assert_eq!(plan.declarations.len(), 4);
        assert_eq!(
            &*plan.declarations[0].lexical_locals,
            &[(dm_ir::SymbolId::of("outer"), None)]
        );
        assert!(Arc::ptr_eq(
            &plan.declarations[0].lexical_locals,
            &plan.declarations[1].lexical_locals
        ));
        assert_eq!(
            &*plan.declarations[2].lexical_locals,
            &[
                (dm_ir::SymbolId::of("outer"), None),
                (
                    dm_ir::SymbolId::of("inside"),
                    Some(dm_ir::SymbolId::of("/datum"))
                )
            ]
        );
        assert_eq!(
            plan.declarations[3].lexical_locals,
            plan.declarations[0].lexical_locals
        );
        assert!(!plan.declarations.iter().any(|d| d
            .lexical_locals
            .iter()
            .any(|(n, _)| *n == dm_ir::SymbolId::of("later"))));
        let changed = dm_syntax::parse(&source.replace("var/outer", "var/renamed"));
        let changed = capture(procedure, &changed.items[0].children).unwrap();
        assert_ne!(
            plan.declarations[0].canonical_bytes(),
            changed.declarations[0].canonical_bytes()
        );
    }
}
