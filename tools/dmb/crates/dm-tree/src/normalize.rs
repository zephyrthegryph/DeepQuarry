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
        let declaration = header.split_once('(').map_or(header, |(path, _)| path);
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
            let mut ty = item.clone();
            ty.header = new_owner.clone();
            // Parent settings remain attached so the adapter resolves them on
            // the owner; other members are flattened in original source order.
            ty.children = item
                .children
                .iter()
                .filter(|child| child.header.trim_start().starts_with("parent_type"))
                .cloned()
                .collect();
            out.push(ty);
            walk(&item.children, &new_owner, None, out);
            continue;
        }
        let mut member = item.clone();
        if header.starts_with('/') && dm_syntax::top_level_assignment_index(header).is_some() {
            if let Some(index) = dm_syntax::top_level_assignment_index(header) {
                if let Some((target_owner, name)) = header[..index].trim().rsplit_once('/') {
                    let mut ty = item.clone();
                    ty.kind = ItemKind::Type;
                    ty.header = if target_owner.is_empty() {
                        "/".into()
                    } else {
                        target_owner.into()
                    };
                    ty.children = Vec::new();
                    out.push(ty);
                    member.header = format!("{name} = {}", header[index + 1..].trim());
                }
            }
        } else if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
            member.header = path(owner, header);
        }
        out.push(member);
    }
}
