//! Pre-normalization declaration allocation facts, independent of target IDs.
//! This ledger retains grammar distinctions erased by flattened declarations.
use dm_ir::{SymbolId, SymbolTable, TypePath};
use dm_syntax::{Item, ItemKind, Span};
#[path = "allocation_bound.rs"]
mod bound;
#[path = "allocation_events.rs"]
mod storage;
pub(crate) use bound::ValidatedEventLeaf;
pub use storage::AllocationEvents;
pub(crate) use storage::EventBuilder;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NamespaceKind {
    Var,
    Proc,
    Verb,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AllocationKind {
    Type {
        path: SymbolId,
        lexical_owner: SymbolId,
        absolute: bool,
    },
    Namespace {
        owner: SymbolId,
        kind: NamespaceKind,
        absolute: bool,
    },
    Field {
        owner: SymbolId,
        formal: bool,
        var_namespace: bool,
        initializer: Option<Span>,
    },
    Procedure {
        owner: SymbolId,
        formal: bool,
        verb: bool,
        name: SymbolId,
        body: Span,
    },
    Parent {
        owner: SymbolId,
        value: Span,
    },
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AllocationEvent {
    pub encounter_order: usize,
    pub span: Span,
    pub header_span: Span,
    pub kind: AllocationKind,
}
#[derive(Clone, Debug)]
pub struct AllocationLedger {
    pub events: AllocationEvents,
}
#[derive(Clone, Debug)]
pub struct Error {
    pub span: Span,
    pub message: String,
}
struct Namespace {
    owner: String,
    kind: NamespaceKind,
}
fn kind(name: &str) -> Option<NamespaceKind> {
    match name {
        "var" => Some(NamespaceKind::Var),
        "proc" => Some(NamespaceKind::Proc),
        "verb" => Some(NamespaceKind::Verb),
        _ => None,
    }
}
fn path(owner: &str, authored: &str) -> String {
    if authored == "/" {
        "/".into()
    } else if authored.starts_with('/') {
        authored.trim_end_matches('/').into()
    } else if owner == "/" {
        format!("/{}", authored.trim_end_matches('/'))
    } else {
        format!(
            "{}/{}",
            owner.trim_end_matches('/'),
            authored.trim_end_matches('/')
        )
    }
}
fn intern(symbols: &mut SymbolTable, text: &str, span: Span) -> Result<SymbolId, Error> {
    if text.starts_with('/') {
        symbols.intern("/").map_err(|error| Error {
            span,
            message: error.to_string(),
        })?;
        for (index, byte) in text.bytes().enumerate().skip(1) {
            if byte == b'/' {
                symbols.intern(&text[..index]).map_err(|error| Error {
                    span,
                    message: error.to_string(),
                })?;
            }
        }
    }
    symbols.intern(text).map_err(|error| Error {
        span,
        message: error.to_string(),
    })
}
fn push(events: &mut EventBuilder, item: &Item, kind: AllocationKind) {
    events.push(AllocationEvent {
        encounter_order: events.len(),
        span: item.span,
        header_span: item.header_span,
        kind,
    });
}
/// Invoke on grammar-safe chunks before compacting bodies or flattening groups.
/// Events keep borrowed-source ranges; no executable AST enters the ledger.
pub fn capture(
    items: &[Item],
    owner: &str,
    symbols: &mut SymbolTable,
) -> Result<AllocationLedger, Error> {
    TypePath::parse(owner).map_err(|message| Error {
        span: Span::new(0, 0),
        message: message.into(),
    })?;
    let mut events = EventBuilder::new();
    walk(items, owner, None, symbols, &mut events)?;
    Ok(AllocationLedger {
        events: events.finish(),
    })
}
fn walk(
    items: &[Item],
    owner: &str,
    namespace: Option<&Namespace>,
    symbols: &mut SymbolTable,
    events: &mut EventBuilder,
) -> Result<(), Error> {
    for item in items {
        let header = item.header.trim();
        let assignment = dm_syntax::top_level_assignment_index(header);
        let target = assignment.map_or(header, |index| header[..index].trim_end());
        let declaration = target
            .split_once('(')
            .map_or(target, |(head, _)| head)
            .trim();
        let lexical = dm_syntax::lex_spans(declaration);
        if let Some(error) = lexical.diagnostics.first() {
            return Err(Error {
                span: item.header_span,
                message: error.message.clone(),
            });
        }
        let normalized = lexical
            .tokens
            .iter()
            .filter(|token| {
                !matches!(
                    token.kind,
                    dm_syntax::TokenKind::Whitespace
                        | dm_syntax::TokenKind::Newline
                        | dm_syntax::TokenKind::Comment
                )
            })
            .map(|token| token.text(declaration))
            .collect::<String>();
        // Match the declaration adapter's optional signature separator so the
        // allocation owner excludes the procedure name itself.
        let normalized = if target.contains('(') {
            normalized.trim_end_matches('/')
        } else {
            normalized.as_str()
        };
        let parts = normalized
            .trim_matches('/')
            .split('/')
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>();
        let marker = parts.iter().position(|part| kind(part).is_some());
        let explicit = marker.map(|index| {
            let prefix = parts[..index].join("/");
            let member_owner = if prefix.is_empty() {
                if normalized.starts_with('/') {
                    "/".into()
                } else {
                    owner.to_owned()
                }
            } else {
                path(
                    owner,
                    &if normalized.starts_with('/') {
                        format!("/{prefix}")
                    } else {
                        prefix
                    },
                )
            };
            (member_owner, kind(parts[index]).unwrap(), index)
        });
        let effective_owner = explicit
            .as_ref()
            .map(|(owner, _, _)| owner.as_str())
            .or_else(|| namespace.map(|namespace| namespace.owner.as_str()))
            .unwrap_or(owner);
        let ns_kind = explicit
            .as_ref()
            .map(|(_, kind, _)| *kind)
            .or_else(|| namespace.map(|namespace| namespace.kind));
        let callable = target.contains('(');
        // Namespace syntax is a declaration event even when empty. Nested type
        // qualifiers inside a variable namespace are not class declarations.
        let namespace_block = explicit
            .as_ref()
            .is_some_and(|(_, _, index)| *index + 1 == parts.len() || !item.children.is_empty())
            && !callable
            && assignment.is_none();
        if namespace_block {
            let (member_owner, ns_kind, _) = explicit.unwrap();
            let owner_id = intern(symbols, &member_owner, item.header_span)?;
            push(
                events,
                item,
                AllocationKind::Namespace {
                    owner: owner_id,
                    kind: ns_kind,
                    absolute: normalized.starts_with('/'),
                },
            );
            let context = Namespace {
                owner: member_owner,
                kind: ns_kind,
            };
            walk(
                &item.children,
                &context.owner,
                Some(&context),
                symbols,
                events,
            )?;
            continue;
        }
        if namespace.is_some() && !callable && assignment.is_none() && !item.children.is_empty() {
            walk(&item.children, effective_owner, namespace, symbols, events)?;
            continue;
        }
        if callable
            && (matches!(item.kind, ItemKind::Proc | ItemKind::Verb)
                || matches!(ns_kind, Some(NamespaceKind::Proc | NamespaceKind::Verb)))
        {
            let mut member_owner = effective_owner.to_owned();
            let name = parts.last().copied().ok_or_else(|| Error {
                span: item.header_span,
                message: "procedure name absent".into(),
            })?;
            if explicit.is_none() && namespace.is_none() && parts.len() > 1 {
                member_owner = path(owner, &normalized[..normalized.rfind('/').unwrap()]);
            }
            let owner_id = intern(symbols, &member_owner, item.header_span)?;
            let name_id = intern(symbols, name, item.header_span)?;
            push(
                events,
                item,
                AllocationKind::Procedure {
                    owner: owner_id,
                    formal: matches!(ns_kind, Some(NamespaceKind::Proc | NamespaceKind::Verb)),
                    verb: ns_kind == Some(NamespaceKind::Verb) || item.kind == ItemKind::Verb,
                    name: name_id,
                    body: item.span,
                },
            );
            continue;
        }
        if ns_kind == Some(NamespaceKind::Var) || item.kind == ItemKind::Var || assignment.is_some()
        {
            let mut field_owner = effective_owner.to_owned();
            if ns_kind.is_none() && parts.len() > 1 {
                field_owner = path(owner, &normalized[..normalized.rfind('/').unwrap()]);
            }
            let owner_id = intern(symbols, &field_owner, item.header_span)?;
            let expression = assignment.map(|index| {
                Span::new(
                    item.header_span.start + index + 1,
                    item.header_span.start + item.header.len(),
                )
            });
            if parts.last() == Some(&"parent_type") {
                let value = expression.ok_or_else(|| Error {
                    span: item.header_span,
                    message: "parent clause has no expression".into(),
                })?;
                push(
                    events,
                    item,
                    AllocationKind::Parent {
                        owner: owner_id,
                        value,
                    },
                );
            } else {
                push(
                    events,
                    item,
                    AllocationKind::Field {
                        owner: owner_id,
                        formal: ns_kind == Some(NamespaceKind::Var) || item.kind == ItemKind::Var,
                        var_namespace: normalized.starts_with('/')
                            || namespace
                                .is_some_and(|namespace| namespace.kind == NamespaceKind::Var),
                        initializer: expression,
                    },
                );
            }
            continue;
        }
        if item.kind == ItemKind::Type {
            let full = path(owner, normalized);
            TypePath::parse(&full).map_err(|message| Error {
                span: item.header_span,
                message: message.into(),
            })?;
            let owner_id = intern(symbols, owner, item.header_span)?;
            let path_id = intern(symbols, &full, item.header_span)?;
            push(
                events,
                item,
                AllocationKind::Type {
                    path: path_id,
                    lexical_owner: owner_id,
                    absolute: normalized.starts_with('/'),
                },
            );
            walk(&item.children, &full, None, symbols, events)?;
            continue;
        }
        return Err(Error {
            span: item.header_span,
            message: "unsupported declaration allocation grammar".into(),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn trailing_signature_separator_does_not_become_allocation_owner() {
        let ast = dm_syntax::parse("/obj/machinery/status_display/supply_display/receive_signal/(datum/signal/signal)\n    return signal\n");
        let mut symbols = SymbolTable::default();
        let ledger = capture(&ast.items, "/", &mut symbols).unwrap();
        let procedure = ledger
            .events
            .iter()
            .find_map(|event| match event.kind {
                AllocationKind::Procedure {
                    owner,
                    name,
                    formal,
                    ..
                } => Some((owner, name, formal)),
                _ => None,
            })
            .unwrap();
        assert_eq!(
            procedure,
            (
                SymbolId::of("/obj/machinery/status_display/supply_display"),
                SymbolId::of("receive_signal"),
                false
            )
        );
    }
    #[test]
    fn grammar_groups_and_source_values_survive_normalization_distinctions() {
        let source="/datum/owner\n    var/list\n        empty\n        asset='A.txt'\n/datum/owner/var/x=null\n/datum/owner/proc/p()\n    return 'B.txt'\n/datum/owner/New()\n    return 'C.txt'\n/datum/owner/parent_type=/datum/base\n/datum/owner/a='D.txt'\n";
        let ast = dm_syntax::parse(source);
        assert!(ast.diagnostics.is_empty());
        let mut symbols = SymbolTable::default();
        let ledger = capture(&ast.items, "/", &mut symbols).unwrap();
        assert!(ledger.events.iter().any(|event| matches!(
            event.kind,
            AllocationKind::Namespace {
                kind: NamespaceKind::Var,
                ..
            }
        )));
        let fields = ledger
            .events
            .iter()
            .filter_map(|event| match event.kind {
                AllocationKind::Field {
                    formal,
                    var_namespace,
                    initializer,
                    ..
                } => Some((formal, var_namespace, initializer)),
                _ => None,
            })
            .collect::<Vec<_>>();
        assert_eq!(fields.len(), 4);
        assert_eq!(fields[0], (true, true, None));
        assert!(fields[1].0);
        assert!(fields[1].1);
        assert!(fields[2].0);
        assert!(fields[2].1);
        assert!(!fields[3].0);
        let procedures = ledger
            .events
            .iter()
            .filter_map(|event| match event.kind {
                AllocationKind::Procedure { formal, .. } => Some(formal),
                _ => None,
            })
            .collect::<Vec<_>>();
        assert_eq!(procedures, [true, false]);
        let parent = ledger
            .events
            .iter()
            .find_map(|event| match event.kind {
                AllocationKind::Parent { value, .. } => Some(value),
                _ => None,
            })
            .unwrap();
        assert_eq!(source[parent.range()].trim(), "/datum/base");
        assert!(symbols.text(SymbolId::of("/datum")).is_some());
    }
    #[test]
    fn relative_typed_var_does_not_create_absolute_var_phase() {
        let source =
            "/datum/owner\n    var/list/asset='A.txt'\n/datum/owner/var/list/asset='B.txt'\n";
        let ast = dm_syntax::parse(source);
        let mut symbols = SymbolTable::default();
        let ledger = capture(&ast.items, "/", &mut symbols).unwrap();
        assert_eq!(
            ledger
                .events
                .iter()
                .filter_map(|event| match event.kind {
                    AllocationKind::Field { var_namespace, .. } => Some(var_namespace),
                    _ => None,
                })
                .collect::<Vec<_>>(),
            [false, true]
        );
    }
}
