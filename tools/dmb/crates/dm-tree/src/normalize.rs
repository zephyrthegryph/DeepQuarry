//! Normalize declaration namespaces without changing source spans or proc bodies.
use dm_syntax::{Item, ItemKind};

pub(crate) fn declarations_in_scope(items: &[Item], owner: &str) -> Vec<Item> {
    let mut result = Vec::new();
    walk(items, owner, None, &mut result);
    result
}
fn path(owner: &str, raw: &str) -> String {
    if raw == "/" {
        return "/".into();
    }
    if raw.starts_with('/') {
        raw.trim_end_matches('/').into()
    } else if owner == "/" {
        format!("/{}", raw.trim_end_matches('/'))
    } else {
        format!(
            "{}/{}",
            owner.trim_end_matches('/'),
            raw.trim_end_matches('/')
        )
    }
}
fn projected_item(item: &Item, kind: ItemKind, header: String, children: Vec<Item>) -> Item {
    Item {
        kind,
        header,
        span: item.span,
        header_span: item.header_span,
        indent: item.indent,
        children,
    }
}
fn walk(items: &[Item], owner: &str, namespace: Option<&str>, out: &mut Vec<Item>) {
    for item in items {
        let header = item.header.trim();
        if let Some(namespace) = namespace {
            let root = namespace.split('/').next().unwrap();
            if !header.contains('(')
                && dm_syntax::top_level_assignment_index(header).is_none()
                && !item.children.is_empty()
            {
                walk(
                    &item.children,
                    owner,
                    Some(&format!("{namespace}/{header}")),
                    out,
                );
                continue;
            }
            let mut member = item.clone();
            member.header = format!("{namespace}/{header}");
            member.kind = match root {
                "var" => ItemKind::Var,
                "verb" => ItemKind::Verb,
                _ => ItemKind::Proc,
            };
            // Preserve containing owner as an absolute member path.
            member.header = path(owner, &member.header);
            out.push(member);
            continue;
        }
        // Namespace markers belong to the declaration target, never its value.
        // A callback default such as /proc/finish is an expression, not a proc
        // namespace enclosing the field being assigned.
        let target = dm_syntax::top_level_assignment_index(header)
            .map_or(header, |index| header[..index].trim_end());
        let declaration = target.split_once('(').map_or(target, |(path, _)| path);
        let parts: Vec<_> = declaration.trim_matches('/').split('/').collect();
        let namespace_index = parts
            .iter()
            .position(|part| matches!(*part, "var" | "proc" | "verb"));
        if let Some(index) = namespace_index {
            let prefix = parts[..index].join("/");
            let member_owner = if prefix.is_empty() {
                if header.starts_with('/') {
                    "/".into()
                } else {
                    owner.to_owned()
                }
            } else {
                path(
                    owner,
                    &if header.starts_with('/') {
                        format!("/{prefix}")
                    } else {
                        prefix
                    },
                )
            };
            let tail = parts[index..].join("/");
            if !header.contains('(')
                && dm_syntax::top_level_assignment_index(header).is_none()
                && !item.children.is_empty()
            {
                walk(&item.children, &member_owner, Some(&tail), out);
                continue;
            }
            let mut member = item.clone();
            let suffix = &header[declaration.len()..];
            member.header = format!("{}/{}{}", member_owner.trim_end_matches('/'), tail, suffix);
            out.push(member);
            continue;
        }
        if item.kind == ItemKind::Type {
            let new_owner = path(owner, header);
            // Clone only the children retained in the type projection. Cloning
            // the whole subtree here and discarding it repeats descendant copies
            // at each nested type before the traversal emits those descendants.
            let ty = projected_item(
                item,
                item.kind,
                new_owner.clone(),
                item.children
                    .iter()
                    .filter(|child| child.header.trim_start().starts_with("parent_type"))
                    .cloned()
                    .collect(),
            );
            out.push(ty);
            walk(&item.children, &new_owner, None, out);
            continue;
        }
        let mut member = item.clone();
        if header.starts_with('/') && dm_syntax::top_level_assignment_index(header).is_some() {
            if let Some(index) = dm_syntax::top_level_assignment_index(header) {
                if let Some((target_owner, name)) = header[..index].trim().rsplit_once('/') {
                    let ty = projected_item(
                        item,
                        ItemKind::Type,
                        if target_owner.is_empty() {
                            "/".into()
                        } else {
                            target_owner.into()
                        },
                        Vec::new(),
                    );
                    out.push(ty);
                    member.header = format!("{name} = {}", header[index + 1..].trim());
                }
            }
        } else if matches!(item.kind, ItemKind::Unknown | ItemKind::Statement) {
            if let Some(index) = dm_syntax::top_level_assignment_index(header) {
                let target = header[..index].trim();
                // Flattening a nested type must not change the lexical owner of
                // its following siblings. parent_type remains attached to the
                // type projection rather than becoming an ordinary field.
                if target != "parent_type" {
                    // Preserve the target exactly: type path normalization
                    // would erase a malformed trailing slash before validation.
                    member.header = format!(
                        "{}/{}{}",
                        owner.trim_end_matches('/'),
                        target,
                        &header[index..]
                    );
                }
            }
        } else if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
            member.header = path(owner, header);
        }
        out.push(member);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn nested_type_projection_keeps_exact_parents_members_spans_and_body() {
        let ast = dm_syntax::parse("/datum/outer\n    parent_type = /datum\n    inner\n        parent_type = /datum/other\n        var/value = 1\n        proc/run(value)\n            if(value)\n                while(value > 0)\n                    value--\n            return value\n/datum/absolute/field = 3\n");
        assert!(ast.diagnostics.is_empty());
        let outer = &ast.items[0];
        let inner = &outer.children[1];
        let run = &inner.children[2];
        assert!(!run.children[0].children[0].children.is_empty());
        fn expected(item: &Item, kind: ItemKind, header: &str, children: Vec<Item>) -> Item {
            Item {
                kind,
                header: header.into(),
                span: item.span,
                header_span: item.header_span,
                indent: item.indent,
                children,
            }
        }
        let absolute = &ast.items[1];
        let expected = vec![
            expected(
                outer,
                outer.kind,
                "/datum/outer",
                vec![outer.children[0].clone()],
            ),
            outer.children[0].clone(),
            expected(
                inner,
                inner.kind,
                "/datum/outer/inner",
                vec![inner.children[0].clone()],
            ),
            inner.children[0].clone(),
            expected(
                &inner.children[1],
                inner.children[1].kind,
                "/datum/outer/inner/var/value = 1",
                inner.children[1].children.clone(),
            ),
            expected(
                run,
                run.kind,
                "/datum/outer/inner/proc/run(value)",
                run.children.clone(),
            ),
            expected(absolute, ItemKind::Type, "/datum/absolute", Vec::new()),
            expected(
                absolute,
                absolute.kind,
                "field = 3",
                absolute.children.clone(),
            ),
        ];
        assert_eq!(declarations_in_scope(&ast.items, "/"), expected);
    }
}
