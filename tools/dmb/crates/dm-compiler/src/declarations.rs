use dm_ir::{FileId, Span, TypePath};
use dm_semantics::{Declaration, DeclarationKind, ProcKind};
use dm_syntax::{AstFile, Item, ItemKind};

pub fn lower_declarations(ast: &AstFile) -> Result<Vec<Declaration>, Vec<String>> {
    let mut declarations = Vec::new();
    let mut diagnostics = Vec::new();
    walk(&ast.items, "/", 0, &mut declarations, &mut diagnostics);
    if diagnostics.is_empty() {
        Ok(declarations)
    } else {
        Err(diagnostics)
    }
}

pub fn lower_fragment_declarations(fragments:&[dm_analysis::FrontendFragment]) -> Result<Vec<Declaration>,Vec<String>> {
    let mut declarations=Vec::new();let mut diagnostics=Vec::new();
    for fragment in fragments {walk(&fragment.ast.items,"/",fragment.source_offset,&mut declarations,&mut diagnostics);}
    if diagnostics.is_empty(){Ok(declarations)}else{Err(diagnostics)}
}

fn walk(
    items: &[Item],
    owner: &str,
    source_offset: usize,
    declarations: &mut Vec<Declaration>,
    diagnostics: &mut Vec<String>,
) {
    for item in items {
        let span = Span {
            file: FileId(0),
            start: (source_offset+item.span.start) as u32,
            end: (source_offset+item.span.end) as u32,
        };
        let header = item.header.trim();
        match item.kind {
            ItemKind::Type => {
                let path = resolve_path(owner, header);
                match TypePath::parse(&path) {
                    Ok(path) => {
                        declarations.push(Declaration {
                            kind: DeclarationKind::Type {
                                path: path.clone(),
                                explicit_parent: item
                                    .children
                                    .iter()
                                    .find_map(|child| {
                                        let (key, value) = child.header.split_once('=')?;
                                        (key.trim() == "parent_type")
                                            .then(|| TypePath::parse(value.trim()))
                                    })
                                    .transpose()
                                    .unwrap_or_else(|error| {
                                        diagnostics.push(format!("{}: {error}", item.span.start));
                                        None
                                    }),
                            },
                            span,
                        });
                        walk(
                            &item.children,
                            &path_to_owner(&path),
                            source_offset,
                            declarations,
                            diagnostics,
                        );
                    }
                    Err(error) => diagnostics.push(format!("{}: {error}", item.span.start)),
                }
            }
            ItemKind::Var => {
                let raw = header.split('=').next().unwrap_or(header).trim();
                let raw = raw.split_once(" as ").map_or(raw, |(name, _)| name).trim();
                let Some((prefix, name)) = raw.rsplit_once("var/") else {
                    diagnostics.push(format!("{}: unsupported var declaration", item.span.start));
                    continue;
                };
                let raw_owner = if prefix.is_empty()
                    || prefix == "/"
                    || prefix
                        .trim_matches('/')
                        .split('/')
                        .all(|part| part == "var")
                {
                    owner.to_owned()
                } else {
                    resolve_path(owner, prefix.trim_end_matches('/'))
                };
                let parts = name.split('/').collect::<Vec<_>>();
                let raw_name = parts.last().copied().unwrap_or("");
                let name = raw_name.split('[').next().unwrap_or(raw_name);
                let is_static = parts[..parts.len().saturating_sub(1)].contains(&"static");
                match TypePath::parse(&raw_owner) {
                    Ok(owner) if !name.is_empty() => {
                        declarations.push(Declaration {
                            kind: DeclarationKind::Var {
                                owner,
                                name: name.into(),
                                is_static,
                            },
                            span,
                        });
                    }
                    _ => diagnostics
                        .push(format!("{}: unsupported var declaration", item.span.start)),
                }
            }
            ItemKind::Proc | ItemKind::Verb => {
                let raw = header
                    .split('(')
                    .next()
                    .unwrap_or(header)
                    .trim()
                    .trim_end_matches('/');
                let marker = if item.kind == ItemKind::Verb {
                    "verb/"
                } else {
                    "proc/"
                };
                let (prefix, name) = raw
                    .strip_prefix(marker)
                    .map(|name| ("", name))
                    .or_else(|| raw.rsplit_once(&format!("/{marker}")))
                    .or_else(|| raw.rsplit_once('/'))
                    .unwrap_or(("", raw));
                let raw_owner = if prefix.is_empty() || prefix == "/" {
                    owner.to_owned()
                } else {
                    resolve_path(owner, prefix.trim_end_matches('/'))
                };
                match TypePath::parse(&raw_owner) {
                    Ok(owner) if !name.is_empty() && !name.contains('/') => {
                        declarations.push(Declaration {
                            kind: DeclarationKind::Proc {
                                owner,
                                name: name.into(),
                                kind: if item.kind == ItemKind::Verb {
                                    ProcKind::Verb
                                } else {
                                    ProcKind::Proc
                                },
                            },
                            span,
                        });
                    }
                    _ => diagnostics
                        .push(format!("{}: unsupported proc declaration", item.span.start)),
                }
            }
            ItemKind::Statement => {}
            ItemKind::Unknown if header.contains('=') && owner != "/" => {}
            ItemKind::Unknown => diagnostics.push(format!(
                "{}: unsupported declaration: {header}",
                item.span.start
            )),
        }
    }
}

fn resolve_path(owner: &str, raw: &str) -> String {
    let raw = if raw == "/" {
        raw
    } else {
        raw.trim_end_matches('/')
    };
    if raw.starts_with('/') {
        raw.to_owned()
    } else if owner == "/" {
        format!("/{raw}")
    } else {
        format!("{owner}/{raw}")
    }
}

fn path_to_owner(path: &TypePath) -> String {
    path.as_str().to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn typed_variables_implicit_procs_and_parent_alias_are_indexed() {
        let ast = dm_syntax::parse("/datum/other\n/datum/probe\n    parent_type = /datum/other\n    var/tmp/list/items\n    var/static/obj/item/tool\n    New()\n        return\n");
        let declarations = lower_declarations(&ast).unwrap();
        let index = dm_semantics::DeclarationIndex::build(declarations.clone()).unwrap();
        assert_eq!(index.vars.len(), 2);
        assert_eq!(index.procs.len(), 1);
        assert!(declarations.iter().any(|d| matches!(&d.kind, DeclarationKind::Var { name, is_static: true, .. } if name == "tool")));
        assert!(declarations.iter().any(|d| matches!(&d.kind, DeclarationKind::Type { explicit_parent: Some(parent), .. } if parent.as_str() == "/datum/other")));
    }

    #[test]
    fn nested_declarations_keep_order() {
        let ast = dm_syntax::parse("/obj/tool\n    var/x = 1\n    proc/use()\n        return x\n");
        let declarations = lower_declarations(&ast).unwrap();
        assert_eq!(declarations.len(), 3);
        let index = dm_semantics::DeclarationIndex::build(declarations).unwrap();
        assert_eq!(index.vars.len(), 1);
        assert_eq!(index.procs.len(), 1);
    }
}
