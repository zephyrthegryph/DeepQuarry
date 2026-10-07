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
    while let Some(tail) = path.strip_prefix("var/").or_else(|| path.strip_prefix("/var/")) {
        path = if path.starts_with('/') { &path[4..] } else { tail };
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
