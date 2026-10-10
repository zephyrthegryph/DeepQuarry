//! Versioned compact grammar-descriptor payloads. No file IDs or executable ASTs.
use dm_syntax::{Diagnostic, DiagnosticKind, Item, ItemKind, Span};
use serde::{Deserialize, Serialize};
// Embedded declaration-fact schema and semantics belong to this identity:
// changing them must invalidate both independent and region-enriched fragments.
// Lexical proc settings are unconditional declarations; old guarded metadata
// must never replay under the same fragment identity.
// Revision 7 includes lexical-owner qualification for sibling field defaults.
// Older fragments may contain semantically misplaced declaration facts.
pub(super) const VERSION: u32 = 9;
#[derive(Serialize, Deserialize)]
struct Node {
    kind: u8,
    header: String,
    span: [usize; 2],
    header_span: [usize; 2],
    indent: usize,
    children: Vec<Node>,
}
#[derive(Serialize, Deserialize)]
struct Error {
    kind: u8,
    span: [usize; 2],
    message: String,
}
#[derive(Serialize, Deserialize)]
struct Payload {
    version: u32,
    items: Vec<Node>,
    errors: Vec<Error>,
    facts: Option<Vec<u8>>,
}
// Serde encodes borrowed strings/slices identically to their owned counterparts.
// The write projection avoids duplicating every compact declaration header.
#[derive(Serialize)]
struct BorrowedNode<'a> {
    kind: u8,
    header: &'a str,
    span: [usize; 2],
    header_span: [usize; 2],
    indent: usize,
    children: Vec<BorrowedNode<'a>>,
}
#[derive(Serialize)]
struct BorrowedError<'a> {
    kind: u8,
    span: [usize; 2],
    message: &'a str,
}
#[derive(Serialize)]
struct BorrowedPayload<'a> {
    version: u32,
    items: Vec<BorrowedNode<'a>>,
    errors: Vec<BorrowedError<'a>>,
    facts: Option<&'a [u8]>,
}
fn bounds(span: Span) -> [usize; 2] {
    [span.start, span.end]
}
fn span(value: [usize; 2], source: &str) -> Option<Span> {
    source.get(value[0]..value[1])?;
    Some(Span::new(value[0], value[1]))
}
fn encode_item(item: &Item, offset: usize) -> BorrowedNode<'_> {
    BorrowedNode {
        kind: match item.kind {
            ItemKind::Type => 0,
            ItemKind::Proc => 1,
            ItemKind::Verb => 2,
            ItemKind::Var => 3,
            ItemKind::Statement => 4,
            ItemKind::Unknown => 5,
        },
        header: &item.header,
        span: [item.span.start - offset, item.span.end - offset],
        header_span: [
            item.header_span.start - offset,
            item.header_span.end - offset,
        ],
        indent: item.indent,
        children: item
            .children
            .iter()
            .map(|child| encode_item(child, offset))
            .collect(),
    }
}
fn decode_item(node: Node, source: &str, depth: usize) -> Option<Item> {
    if depth > 256 {
        return None;
    }
    let item_span = span(node.span, source)?;
    let header_span = span(node.header_span, source)?;
    if header_span.start < item_span.start
        || header_span.end > item_span.end
        || source.get(header_span.range())? != node.header
    {
        return None;
    }
    Some(Item {
        kind: match node.kind {
            0 => ItemKind::Type,
            1 => ItemKind::Proc,
            2 => ItemKind::Verb,
            3 => ItemKind::Var,
            4 => ItemKind::Statement,
            5 => ItemKind::Unknown,
            _ => return None,
        },
        header: node.header,
        span: item_span,
        header_span,
        indent: node.indent,
        children: node
            .children
            .into_iter()
            .map(|child| decode_item(child, source, depth + 1))
            .collect::<Option<_>>()?,
    })
}
pub(super) fn encode_with_facts(
    items: &[Item],
    errors: &[Diagnostic],
    offset: usize,
    facts: Option<Vec<u8>>,
) -> Result<Vec<u8>, String> {
    dm_wire::encode(
        VERSION,
        &BorrowedPayload {
            version: VERSION,
            items: items.iter().map(|item| encode_item(item, offset)).collect(),
            facts: facts.as_deref(),
            errors: errors
                .iter()
                .map(|error| BorrowedError {
                    kind: match error.kind {
                        DiagnosticKind::Lexical => 0,
                        DiagnosticKind::Expression => 1,
                        DiagnosticKind::Statement => 2,
                        DiagnosticKind::Indentation => 3,
                        DiagnosticKind::Unsupported => 4,
                        DiagnosticKind::IncompleteExpression => 5,
                    },
                    span: bounds(error.span),
                    message: &error.message,
                })
                .collect(),
        },
    )
}
type DecodedFacts = (Vec<Item>, Vec<Diagnostic>, Option<Vec<u8>>);
pub(super) fn decode_with_facts(bytes: &[u8], source: &str) -> Option<DecodedFacts> {
    let payload: Payload = dm_wire::decode(VERSION, bytes, bytes.len()).ok()?;
    if payload.version != VERSION {
        return None;
    }
    let items = payload
        .items
        .into_iter()
        .map(|node| decode_item(node, source, 0))
        .collect::<Option<Vec<_>>>()?;
    let errors = payload
        .errors
        .into_iter()
        .map(|error| {
            Some(Diagnostic {
                span: span(error.span, source)?,
                kind: match error.kind {
                    0 => DiagnosticKind::Lexical,
                    1 => DiagnosticKind::Expression,
                    2 => DiagnosticKind::Statement,
                    3 => DiagnosticKind::Indentation,
                    4 => DiagnosticKind::Unsupported,
                    5 => DiagnosticKind::IncompleteExpression,
                    _ => return None,
                },
                message: error.message,
            })
        })
        .collect::<Option<Vec<_>>>()?;
    Some((items, errors, payload.facts))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn borrowed_fragment_projection_preserves_owned_wire_bytes() {
        let source = "/datum/probe\n    var/value = 1\n    proc/check()\n        set waitfor = 0\n        return value\n";
        let ast = dm_syntax::parse_declaration_skeleton(source);
        let items = super::super::compact_declarations(ast.items, 0);
        let errors = vec![Diagnostic {
            kind: DiagnosticKind::Unsupported,
            span: Span::new(0, 6),
            message: "preserved diagnostic".into(),
        }];
        let bytes = encode_with_facts(&items, &errors, 0, Some(vec![1, 2, 3])).unwrap();
        let owned: Payload = dm_wire::decode(VERSION, &bytes, bytes.len()).unwrap();
        assert_eq!(bytes, dm_wire::encode(VERSION, &owned).unwrap());
        let (decoded, diagnostics, facts) = decode_with_facts(&bytes, source).unwrap();
        assert_eq!(decoded, items);
        assert_eq!(diagnostics, errors);
        assert_eq!(facts, Some(vec![1, 2, 3]));
    }
    #[test]
    fn previous_fact_schema_cannot_reuse_parser_fragment_identity() {
        const PREVIOUS_VERSION: u32 = 8;
        let source = "/datum/probe\n    var/value = 1\n";
        let ast = dm_syntax::parse_declaration_skeleton(source);
        let items = super::super::compact_declarations(ast.items, 0);
        let current = encode_with_facts(&items, &[], 0, None).unwrap();
        let mut previous: Payload = dm_wire::decode(VERSION, &current, current.len()).unwrap();
        previous.version = PREVIOUS_VERSION;
        let old_wire = dm_wire::encode(PREVIOUS_VERSION, &previous).unwrap();
        assert!(decode_with_facts(&old_wire, source).is_none());
        // Even a relabelled outer envelope cannot admit an old payload version.
        let relabelled = dm_wire::encode(VERSION, &previous).unwrap();
        assert!(decode_with_facts(&relabelled, source).is_none());
        assert!(decode_with_facts(&current, source).is_some());
        assert_ne!(
            dm_preprocess::regions::FragmentRecord::lookup_key(PREVIOUS_VERSION, source),
            dm_preprocess::regions::FragmentRecord::lookup_key(VERSION, source),
        );
    }
}
