//! Neutral facts for one complete grammar-safe source chunk. No tree IDs,
//! engine metadata or current source provenance are persisted.
use crate::{
    allocation_ledger::*, AdaptedDeclarations, DefinitionMode, MemberKind, Provenance, Skeleton,
};
use dm_ir::*;
use dm_syntax::Span as SyntaxSpan;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
// Sibling defaults now retain their original lexical owner after flattening.
const SCHEMA: u32 = 5;
#[derive(Serialize, Deserialize)]
enum Declaration {
    Type(SymbolId, Option<SymbolId>),
    Member(SymbolId, SymbolId, u8, u8, Box<PortableMeaning>, u128),
}
#[derive(Serialize, Deserialize)]
enum Event {
    Type(SymbolId, SymbolId, bool),
    Namespace(SymbolId, u8, bool),
    Field(SymbolId, SymbolId, bool, bool, Option<[usize; 2]>),
    Procedure(SymbolId, bool, bool, SymbolId, [usize; 2]),
    Parent(SymbolId, [usize; 2]),
}
#[derive(Serialize, Deserialize)]
struct LedgerRow {
    span: [usize; 2],
    header: [usize; 2],
    kind: Event,
}
#[derive(Serialize, Deserialize)]
struct Payload {
    symbols: Vec<(SymbolId, String)>,
    declarations: Vec<Declaration>,
    origins: Vec<[usize; 2]>,
    ledger: Vec<LedgerRow>,
}
trait TransposeOption<T> {
    fn transpose_option(self) -> Option<Option<T>>;
}
impl<T> TransposeOption<T> for Option<Option<T>> {
    fn transpose_option(self) -> Option<Option<T>> {
        match self {
            None => Some(None),
            Some(Some(value)) => Some(Some(value)),
            Some(None) => None,
        }
    }
}
fn symbol(value: Option<SymbolId>, symbols: &SymbolTable) -> Option<Option<SymbolId>> {
    if value.is_some_and(|id| symbols.text(id).is_none()) {
        None
    } else {
        Some(value)
    }
}
fn relative(span: SyntaxSpan, offset: usize) -> Option<[usize; 2]> {
    Some([
        span.start.checked_sub(offset)?,
        span.end.checked_sub(offset)?,
    ])
}
fn absolute(span: [usize; 2], source: &str, offset: usize) -> Option<SyntaxSpan> {
    source.get(span[0]..span[1])?;
    Some(SyntaxSpan::new(
        span[0].checked_add(offset)?,
        span[1].checked_add(offset)?,
    ))
}
pub(super) fn encode(
    facts: &AdaptedDeclarations,
    ledger: &AllocationLedger,
    offset: usize,
) -> Result<Vec<u8>, String> {
    let payload = (|| {
        let declarations = facts
            .skeletons
            .iter()
            .map(|row| {
                Some(match row {
                    Skeleton::Type {
                        path,
                        explicit_parent,
                    } => Declaration::Type(*path, *explicit_parent),
                    Skeleton::Member {
                        owner,
                        name,
                        kind,
                        mode,
                        metadata: meaning,
                        content,
                    } => Declaration::Member(
                        *owner,
                        *name,
                        match kind {
                            MemberKind::Var => 0,
                            MemberKind::Proc => 1,
                            MemberKind::Verb => 2,
                        },
                        match mode {
                            DefinitionMode::Declare => 0,
                            DefinitionMode::Override => 1,
                            DefinitionMode::Reopen => 2,
                            DefinitionMode::Implicit => 3,
                        },
                        Box::new(PortableMeaning::capture(meaning, true)?),
                        *content,
                    ),
                })
            })
            .collect::<Option<Vec<_>>>()?;
        let origins = facts
            .origins
            .iter()
            .map(|origin| {
                if origin.span.file != FileId(0)
                    || origin.include_occurrence != 0
                    || origin.region != 0
                    || !origin.expansion_stack.is_empty()
                {
                    return None;
                }
                relative(
                    SyntaxSpan::new(origin.span.start as usize, origin.span.end as usize),
                    offset,
                )
            })
            .collect::<Option<Vec<_>>>()?;
        let rows = ledger
            .events
            .iter()
            .map(|event| {
                Some(LedgerRow {
                    span: relative(event.span, offset)?,
                    header: relative(event.header_span, offset)?,
                    kind: match event.kind {
                        AllocationKind::Type {
                            path,
                            lexical_owner,
                            absolute,
                        } => Event::Type(path, lexical_owner, absolute),
                        AllocationKind::Namespace {
                            owner,
                            kind,
                            absolute,
                        } => Event::Namespace(
                            owner,
                            match kind {
                                NamespaceKind::Var => 0,
                                NamespaceKind::Proc => 1,
                                NamespaceKind::Verb => 2,
                            },
                            absolute,
                        ),
                        AllocationKind::Field {
                            owner,
                            name,
                            formal,
                            var_namespace,
                            initializer,
                        } => Event::Field(
                            owner,
                            name,
                            formal,
                            var_namespace,
                            initializer
                                .map(|span| relative(span, offset))
                                .transpose_option()?,
                        ),
                        AllocationKind::Procedure {
                            owner,
                            formal,
                            verb,
                            name,
                            body,
                        } => Event::Procedure(owner, formal, verb, name, relative(body, offset)?),
                        AllocationKind::Parent { owner, value } => {
                            Event::Parent(owner, relative(value, offset)?)
                        }
                    },
                })
            })
            .collect::<Option<Vec<_>>>()?;
        Some(Payload {
            symbols: facts
                .symbols
                .ordered()
                .into_iter()
                .map(|(id, text)| (id, text.into()))
                .collect(),
            declarations,
            origins,
            ledger: rows,
        })
    })()
    .ok_or_else(|| "declaration facts cannot be represented in cache wire format".to_owned())?;
    dm_wire::encode(SCHEMA, &payload)
}
pub(super) fn decode(
    bytes: &[u8],
    source: &str,
    offset: usize,
) -> Option<(AdaptedDeclarations, AllocationLedger)> {
    let payload: Payload = dm_wire::decode(SCHEMA, bytes, bytes.len()).ok()?;
    if payload.declarations.len() != payload.origins.len() {
        return None;
    }
    let mut symbols = SymbolTable::default();
    for (id, text) in payload.symbols {
        if symbols.intern(&text).ok() != Some(id) {
            return None;
        }
    }
    let skeletons = payload
        .declarations
        .into_iter()
        .map(|row| {
            Some(match row {
                Declaration::Type(path, parent) => {
                    symbols.text(path)?;
                    Skeleton::Type {
                        path,
                        explicit_parent: symbol(parent, &symbols)?,
                    }
                }
                Declaration::Member(owner, name, tag, mode, meaning, content) => {
                    symbols.text(owner)?;
                    symbols.text(name)?;
                    let meaning = meaning.restore(PortableNames::table(&symbols))?;
                    if xxhash_rust::xxh3::xxh3_128(&meaning.canonical) != content {
                        return None;
                    }
                    Skeleton::Member {
                        owner,
                        name,
                        kind: match tag {
                            0 => MemberKind::Var,
                            1 => MemberKind::Proc,
                            2 => MemberKind::Verb,
                            _ => return None,
                        },
                        mode: match mode {
                            0 => DefinitionMode::Declare,
                            1 => DefinitionMode::Override,
                            2 => DefinitionMode::Reopen,
                            3 => DefinitionMode::Implicit,
                            _ => return None,
                        },
                        metadata: Arc::new(meaning),
                        content,
                    }
                }
            })
        })
        .collect::<Option<Vec<_>>>()?;
    let origins = payload
        .origins
        .into_iter()
        .map(|span| {
            let span = absolute(span, source, offset)?;
            Some(Provenance {
                span: dm_ir::Span {
                    file: FileId(0),
                    start: u32::try_from(span.start).ok()?,
                    end: u32::try_from(span.end).ok()?,
                },
                include_occurrence: 0,
                region: 0,
                expansion_stack: Arc::from([]),
            })
        })
        .collect::<Option<Vec<_>>>()?;
    let events = payload
        .ledger
        .into_iter()
        .enumerate()
        .map(|(encounter_order, row)| {
            let span = absolute(row.span, source, offset)?;
            let header_span = absolute(row.header, source, offset)?;
            if header_span.start < span.start || header_span.end > span.end {
                return None;
            }
            let kind = match row.kind {
                Event::Type(path, lexical_owner, absolute) => {
                    symbols.text(path)?;
                    symbols.text(lexical_owner)?;
                    AllocationKind::Type {
                        path,
                        lexical_owner,
                        absolute,
                    }
                }
                Event::Namespace(owner, kind, absolute) => {
                    symbols.text(owner)?;
                    AllocationKind::Namespace {
                        owner,
                        kind: match kind {
                            0 => NamespaceKind::Var,
                            1 => NamespaceKind::Proc,
                            2 => NamespaceKind::Verb,
                            _ => return None,
                        },
                        absolute,
                    }
                }
                Event::Field(owner, name, formal, var_namespace, initializer) => {
                    symbols.text(owner)?;
                    symbols.text(name)?;
                    AllocationKind::Field {
                        owner,
                        name,
                        formal,
                        var_namespace,
                        initializer: initializer
                            .map(|span| absolute(span, source, offset))
                            .transpose_option()?,
                    }
                }
                Event::Procedure(owner, formal, verb, name, body) => {
                    symbols.text(owner)?;
                    symbols.text(name)?;
                    AllocationKind::Procedure {
                        owner,
                        formal,
                        verb,
                        name,
                        body: absolute(body, source, offset)?,
                    }
                }
                Event::Parent(owner, value) => {
                    symbols.text(owner)?;
                    AllocationKind::Parent {
                        owner,
                        value: absolute(value, source, offset)?,
                    }
                }
            };
            Some(AllocationEvent {
                encounter_order,
                span,
                header_span,
                kind,
            })
        })
        .collect::<Option<crate::allocation_ledger::AllocationEvents>>()?;
    Some((
        AdaptedDeclarations {
            symbols,
            skeletons,
            origins,
        },
        AllocationLedger { events },
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn scalar_null_and_type_constants_roundtrip_and_require_type_symbols() {
        let source = "/datum/base\n    var/static/const/empty = null\n    var/static/const/type_value = /datum/base\n";
        let parsed = dm_syntax::parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty());
        let ast = dm_syntax::AstFile {
            items: parsed.items,
            ..Default::default()
        };
        let mut expected = crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0).unwrap();
        let ledger = capture(&ast.items, "/", &mut expected.symbols).unwrap();
        let values: Vec<_> = expected
            .skeletons
            .iter()
            .filter_map(|row| match row {
                Skeleton::Member { metadata, .. } => metadata.resolved_constant.clone(),
                _ => None,
            })
            .collect();
        assert_eq!(
            values,
            vec![
                SemanticValue::Null,
                SemanticValue::Type(SymbolId::of("/datum/base"))
            ]
        );
        let bytes = encode(&expected, &ledger, 0).unwrap();
        let (decoded, rebound) = decode(&bytes, source, 0).unwrap();
        assert!(decoded.skeletons == expected.skeletons);
        assert_eq!(decoded.symbols.ordered(), expected.symbols.ordered());
        assert_eq!(decoded.origins, expected.origins);
        assert_eq!(rebound.events, ledger.events);

        let type_metadata = expected
            .skeletons
            .iter()
            .find_map(|row| match row {
                Skeleton::Member { metadata, .. }
                    if matches!(metadata.resolved_constant, Some(SemanticValue::Type(_))) =>
                {
                    Some(metadata)
                }
                _ => None,
            })
            .unwrap();
        // A wire type value has no authority without its exact symbol receipt.
        assert!(PortableMeaning::capture(type_metadata, true).unwrap().restore(PortableNames::table(&SymbolTable::default())).is_none());
        assert!(PortableMeaning::capture(type_metadata, true).unwrap().restore(PortableNames::table(&expected.symbols)).is_some());
    }
    #[test]
    fn typed_chunk_facts_roundtrip_preserves_all_metadata_and_rebases_origins() {
        let source="/datum/base\n    var/list/obj/items[2]\n    var/static/const/value = 7\n    proc/read(list/obj/args[], count = 2 as num)\n        if(value)\n            set waitfor = 0\n        else\n            set name = \"display\"\n        return count\n/datum/base/child\n    parent_type = /datum/base\n/datum/base/value = 9\n";
        let ast = dm_syntax::parse_declaration_skeleton(source);
        assert!(ast.diagnostics.is_empty());
        let ast = dm_syntax::AstFile {
            items: ast.items,
            ..Default::default()
        };
        let mut expected = crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0).unwrap();
        let ledger = capture(&ast.items, "/", &mut expected.symbols).unwrap();
        let bytes = encode(&expected, &ledger, 0).unwrap();
        let (decoded, rebound) = decode(&bytes, source, 0).unwrap();
        assert!(
            decoded.skeletons == expected.skeletons,
            "typed metadata differs"
        );
        assert_eq!(decoded.origins, expected.origins);
        assert!(decoded.symbols.ordered() == expected.symbols.ordered());
        assert_eq!(rebound.events, ledger.events);
        let (shifted, shifted_ledger) = decode(&bytes, source, 31).unwrap();
        for (new, old) in shifted.origins.iter().zip(&expected.origins) {
            assert_eq!(new.span.start, old.span.start + 31);
            assert_eq!(new.span.end, old.span.end + 31);
        }
        assert_eq!(
            shifted_ledger.events.get(0).unwrap().span.start,
            ledger.events.get(0).unwrap().span.start + 31
        );
        assert!(decode(&bytes, "", 0).is_none());
        let mut corrupt = bytes;
        let last = corrupt.len() - 1;
        corrupt[last] ^= 1;
        assert!(decode(&corrupt, source, 0).is_none());
    }
}
