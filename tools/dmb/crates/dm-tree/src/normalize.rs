//! Normalize declaration namespaces without changing source spans or proc bodies.
use dm_syntax::{ItemKind, OriginalItem, OriginalItems};
use std::borrow::Cow;
#[cfg(test)]
use dm_syntax::Item;

#[derive(Clone, Copy)]
enum Children { All, ParentClauses, Empty }

/// Stack-scoped spelling projection over the exact authored item. Only
/// headers that need namespace/absolute spelling allocate; body items are
/// always lent from the producer, never cloned into a second tree.
pub(crate) struct ProjectedItem<'a> {
    pub(crate) raw: OriginalItem<'a>,
    pub(crate) kind: ItemKind,
    pub(crate) header: Cow<'a, str>,
    children: Children,
}
impl<'a> ProjectedItem<'a> {
    pub(crate) fn authored(raw: OriginalItem<'a>) -> Self {
        Self { raw, kind:raw.kind(), header:Cow::Borrowed(raw.header()), children:Children::All }
    }
    pub(crate) fn children(&self) -> impl Iterator<Item=OriginalItem<'a>> {
        let children=self.children;
        self.raw.children().iter().take(if matches!(children,Children::Empty){0}else{usize::MAX}).filter(move |child|match children {
            Children::All=>true,
            Children::ParentClauses=>child.header().trim_start().starts_with("parent_type"),
            Children::Empty=>false,
        })
    }
}

pub(crate) fn visit_declarations_in_scope<'a,E>(
    items: OriginalItems<'a>, owner: &str,
    checkpoint: &mut impl FnMut()->Result<(),E>,
    visit: &mut impl FnMut(ProjectedItem<'a>)->Result<(),E>,
)->Result<(),E>{walk(items,owner,None,checkpoint,visit)}

#[cfg(test)]
pub(crate) fn declarations_in_scope(items: &[Item], owner: &str) -> Vec<Item> {
    fn materialize(item: ProjectedItem<'_>) -> Item {
        let children = item.children().map(ProjectedItem::authored).map(materialize).collect();
        Item {
            kind: item.kind, header: item.header.into_owned(), span: item.raw.span(),
            header_span: item.raw.header_span(), declaration_cursor: item.raw.declaration_cursor(),
            checker_qualifiers: item.raw.checker_qualifiers(),
            original_outer_terminator: item.raw.original_outer_terminator(),
            indent: item.raw.indent(), children,
        }
    }
    let mut result=Vec::new();
    visit_declarations_in_scope(OriginalItems::from_items(items),owner,&mut || Ok(()),&mut |item| {
        result.push(materialize(item));
        Ok::<_,std::convert::Infallible>(())
    }).unwrap();
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
fn walk<'a,E>(
    items: OriginalItems<'a>, owner: &str, namespace: Option<&str>,
    checkpoint: &mut impl FnMut()->Result<(),E>,
    visit: &mut impl FnMut(ProjectedItem<'a>)->Result<(),E>,
)->Result<(),E>{
    for item in items.iter() {
        checkpoint()?;
        let header = item.header().trim();
        if let Some(namespace) = namespace {
            let root = namespace.split('/').next().unwrap();
            if !header.contains('(')
                && dm_syntax::top_level_assignment_index(header).is_none()
                && !item.children().is_empty()
            {
                walk(
                    item.children(),
                    owner,
                    Some(&format!("{namespace}/{header}")),
                    checkpoint,
                    visit,
                )?;
                continue;
            }
            let mut member = ProjectedItem::authored(item);
            member.kind = match root {
                "var" => ItemKind::Var,
                "verb" => ItemKind::Verb,
                _ => ItemKind::Proc,
            };
            // Preserve containing owner as an absolute member path.
            member.header = Cow::Owned(path(owner, &format!("{namespace}/{header}")));
            visit(member)?;
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
                && !item.children().is_empty()
            {
                walk(item.children(), &member_owner, Some(&tail), checkpoint, visit)?;
                continue;
            }
            let mut member = ProjectedItem::authored(item);
            let suffix = &header[declaration.len()..];
            member.header = Cow::Owned(format!("{}/{}{}", member_owner.trim_end_matches('/'), tail, suffix));
            visit(member)?;
            continue;
        }
        if item.kind() == ItemKind::Type {
            let new_owner = path(owner, header);
            visit(ProjectedItem { raw:item, kind:item.kind(), header:Cow::Owned(new_owner.clone()), children:Children::ParentClauses })?;
            walk(item.children(), &new_owner, None, checkpoint, visit)?;
            continue;
        }
        let mut member = ProjectedItem::authored(item);
        if header.starts_with('/') && dm_syntax::top_level_assignment_index(header).is_some() {
            if let Some(index) = dm_syntax::top_level_assignment_index(header) {
                if let Some((target_owner, name)) = header[..index].trim().rsplit_once('/') {
                    let owner = if target_owner.is_empty() { "/" } else { target_owner };
                    visit(ProjectedItem { raw:item, kind:ItemKind::Type, header:Cow::Borrowed(owner), children:Children::Empty })?;
                    member.header = Cow::Owned(format!("{name} = {}", header[index + 1..].trim()));
                }
            }
        } else if matches!(item.kind(), ItemKind::Unknown | ItemKind::Statement) {
            if let Some(index) = dm_syntax::top_level_assignment_index(header) {
                let target = header[..index].trim();
                // Flattening a nested type must not change the lexical owner of
                // its following siblings. parent_type remains attached to the
                // type projection rather than becoming an ordinary field.
                if target != "parent_type" {
                    // Preserve the target exactly: type path normalization
                    // would erase a malformed trailing slash before validation.
                    member.header = Cow::Owned(format!(
                        "{}/{}{}",
                        owner.trim_end_matches('/'),
                        target,
                        &header[index..]
                    ));
                }
            }
        } else if matches!(item.kind(), ItemKind::Proc | ItemKind::Verb) {
            member.header = Cow::Owned(path(owner, header));
        }
        visit(member)?;
    }
    Ok(())
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
                declaration_cursor: item.declaration_cursor,
                checker_qualifiers: item.checker_qualifiers,
        original_outer_terminator: item.original_outer_terminator,
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
