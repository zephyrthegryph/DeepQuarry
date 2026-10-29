//! Project an ALREADY PRIMARY-PARSED local declaration, never a procedure parser.
//! Runtime and semantic clients share the exact borrowed type-path projection.
//! Semantic clients separately decline arrays/stored declarations until their
//! checker context is implemented; runtime admission is never narrowed by that.
use crate::{local_name, project_declaration_type, DeclarationType};

/// Exact projection previously repeated by native runtime lowering. This is not
/// an admission check: preserve raw array/modifier spellings and the caller's
/// existing fallback. Input belongs to the primary-issued declaration grammar.
pub fn local_type_path(declaration: &str) -> Option<&str> {
    declaration
        .strip_prefix("var/")?
        .rsplit_once('/')
        .map(|(path, _)| path)
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct LocalDeclaration<'a> {
    pub name: &'a str,
    pub declared_type: Option<DeclarationType<'a>>,
    pub flags: u32,
}
pub fn project_local_declaration(declaration: &str) -> Result<LocalDeclaration<'_>, &'static str> {
    if declaration.contains('[') || declaration.contains(']') {
        return Err("local array type/initializer projection is not issued");
    }
    let name = local_name(declaration).ok_or("native local name is unavailable")?;
    if !declaration.starts_with("var/") && declaration != format!("var {name}") {
        return Err("native local declaration namespace is unavailable");
    }
    let mut raw = local_type_path(declaration).unwrap_or("");
    let mut flags = 0;
    loop {
        if raw == "const" {
            flags |= 2;
            raw = "";
        } else if raw == "tmp" {
            flags |= 4;
            raw = "";
        } else if let Some(tail) = raw.strip_prefix("const/") {
            flags |= 2;
            raw = tail;
        } else if let Some(tail) = raw.strip_prefix("tmp/") {
            flags |= 4;
            raw = tail;
        } else {
            break;
        }
    }
    if raw.split('/').any(|part| {
        matches!(
            part,
            "static"
                | "global"
                | "final"
                | "SpacemanDMM_final"
                | "SpacemanDMM_private"
                | "SpacemanDMM_protected"
        )
    }) {
        return Err("stored/checker-modifier local declaration needs primary flag projection");
    }
    let declared_type = (!raw.is_empty()).then(|| project_declaration_type(raw));
    Ok(LocalDeclaration {
        name,
        declared_type,
        flags,
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn primary_declaration_type_and_list_element_hints_remain_separate() {
        let p = project_local_declaration("var/const/list/datum/item/values").unwrap();
        assert_eq!(p.name, "values");
        assert_eq!(p.flags, 2);
        assert_eq!(
            p.declared_type.unwrap(),
            DeclarationType {
                runtime_path: "list",
                list_element_path: Some("datum/item")
            }
        );
        assert_eq!(
            project_local_declaration("var/datum/item/value")
                .unwrap()
                .declared_type
                .unwrap()
                .runtime_path,
            "datum/item"
        );
        assert!(project_local_declaration("var/value")
            .unwrap()
            .declared_type
            .is_none());
    }
    #[test]
    fn unsupported_array_storage_and_checker_modifiers_cannot_be_guessed() {
        for raw in [
            "var/value[side_effect()]",
            "var/static/datum/item/x",
            "var/SpacemanDMM_private/datum/item/x",
            "var/datum/static/x",
        ] {
            assert!(project_local_declaration(raw).is_err(), "{raw}");
        }
    }
    #[test]
    fn runtime_path_projection_preserves_arrays_and_stored_fallback_inputs() {
        for (declaration, expected) in [
            ("var/datum/item/value", Some("datum/item")),
            ("var/list/datum/item/items", Some("list/datum/item")),
            ("var/list/items[3]", Some("list")),
            ("var/static/list/items", Some("static/list")),
            ("var/global/datum/item/value", Some("global/datum/item")),
            ("var/items[]", None),
            ("var/value", None),
        ] {
            assert_eq!(local_type_path(declaration), expected);
        }
        // The policy's unsupported admission is not the compiler's admission.
        assert!(project_local_declaration("var/static/list/items").is_err());
        assert!(local_type_path("var/static/list/items").is_some());
        let declaration = "var/datum/item/value";
        let path = local_type_path(declaration).unwrap();
        assert_eq!(
            path.as_ptr(),
            declaration[4..].as_ptr(),
            "projection borrows primary bytes"
        );
    }
}
