//! Runtime container and authored list element hints are separate meanings.
//! Input is an already parsed type path, without modifiers or variable name.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DeclarationType<'a> {
    pub runtime_path: &'a str,
    pub list_element_path: Option<&'a str>,
}

pub fn project_declaration_type(path: &str) -> DeclarationType<'_> {
    let path = normalize_declaration_type(path);
    let body = path.strip_prefix('/').unwrap_or(path);
    if body == "list" || body.starts_with("list/") {
        DeclarationType {
            runtime_path: if path.starts_with('/') {
                "/list"
            } else {
                "list"
            },
            list_element_path: body.strip_prefix("list/").filter(|value| !value.is_empty()),
        }
    } else {
        DeclarationType {
            runtime_path: path,
            list_element_path: None,
        }
    }
}

/// Redundant declaration namespace segments do not become type names.
pub fn normalize_declaration_type(mut path: &str) -> &str {
    while let Some(tail) = path
        .strip_prefix("var/")
        .or_else(|| path.strip_prefix("/var/"))
    {
        path = if path.starts_with('/') {
            &path[4..]
        } else {
            tail
        };
    }
    path
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn list_container_projection_preserves_the_authored_element_hint() {
        assert_eq!(
            project_declaration_type("/list/datum/item"),
            DeclarationType {
                runtime_path: "/list",
                list_element_path: Some("datum/item")
            }
        );
        assert_eq!(
            project_declaration_type("list/datum/item").runtime_path,
            "list"
        );
        assert_eq!(project_declaration_type("/list").list_element_path, None);
        assert_eq!(
            project_declaration_type("/datum/list/item").runtime_path,
            "/datum/list/item"
        );
    }
}

/// Classify the spelling of an ALREADY parsed native type path for conservative
/// policy refusal. This does not parse declarations or strip qualifiers. A false
/// result is NOT proof that source annotations/macros were absent.
pub fn has_checker_qualifiers(path: &str) -> bool {
    path.split('/').any(|part| {
        matches!(
            part,
            "final" | "SpacemanDMM_final" | "SpacemanDMM_private" | "SpacemanDMM_protected"
        )
    })
}
#[cfg(test)]
mod checker_qualifier_classification_tests {
    use super::*;
    #[test]
    fn classify_exact_owned_path_segments_without_inferring_a_type() {
        for path in [
            "/SpacemanDMM_private",
            "/list/SpacemanDMM_protected/datum",
            "/datum/final",
            "SpacemanDMM_final/datum",
        ] {
            assert!(has_checker_qualifiers(path), "{path}");
        }
        for path in [
            "/datum",
            "/datum/private",
            "/datum/SpacemanDMM_private_suffix",
            "/list/datum/finality",
        ] {
            assert!(!has_checker_qualifiers(path), "{path}");
        }
    }
}

/// Exact existing VarTypeBuilder modifier vocabulary used at each original
/// static_type recursion; this classifies an already-issued component only.
pub fn is_original_static_type_modifier(component:&str)->bool{crate::local_variable_syntax::source_modifier(component).is_some()}
