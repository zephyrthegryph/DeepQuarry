//! Neutral facts for one complete grammar-safe source chunk. No tree IDs,
//! engine metadata or current source provenance are persisted.
use crate::{
    allocation_ledger::*, AdaptedDeclarations, DefinitionMode, MemberKind, Provenance, Skeleton,
};
use dm_ir::*;
use dm_syntax::{Span as SyntaxSpan, TokenKind};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
const SCHEMA: u32 = 3;
#[derive(Serialize, Deserialize)]
enum ScalarConstant {
    Null,
    Number(u32),
    Text(Vec<u8>),
    Type(SymbolId),
}
#[derive(Serialize, Deserialize)]
struct Expression(Vec<(u8, SymbolId, [usize; 2])>);
#[derive(Serialize, Deserialize)]
struct Array {
    dimensions: Vec<Option<Expression>>,
    element: Option<SymbolId>,
}
#[derive(Serialize, Deserialize)]
struct Argument {
    name: SymbolId,
    declared: Option<SymbolId>,
    element: Option<SymbolId>,
    flags: u32,
    array: Option<Array>,
    default: Option<Expression>,
    annotation: Option<Expression>,
    source: Option<Expression>,
    span: [usize; 2],
}
#[derive(Serialize, Deserialize)]
enum Setting {
    Value(SymbolId, u8, Expression),
    Branch(Expression, Vec<Setting>, Vec<Setting>),
    Unsupported(Expression, Vec<Setting>),
}
#[derive(Serialize, Deserialize)]
struct Procedure {
    arguments: Vec<Argument>,
    variadic: bool,
    returns: Option<Expression>,
    settings: Vec<Setting>,
}
#[derive(Serialize, Deserialize)]
struct Metadata {
    constant: Option<ScalarConstant>,
    declared: Option<SymbolId>,
    element: Option<SymbolId>,
    display: Option<SymbolId>,
    flags: u32,
    array: Option<Array>,
    procedure: Option<Procedure>,
    initializer: Option<Expression>,
    formal_initializer: Option<Expression>,
    canonical: Vec<u8>,
    evidence: Vec<u8>,
}
#[derive(Serialize, Deserialize)]
enum Declaration {
    Type(SymbolId, Option<SymbolId>),
    Member(SymbolId, SymbolId, u8, u8, Box<Metadata>, u128),
}
#[derive(Serialize, Deserialize)]
enum Event {
    Type(SymbolId, SymbolId, bool),
    Namespace(SymbolId, u8, bool),
    Field(SymbolId, bool, bool, Option<[usize; 2]>),
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
fn token_kind(kind: TokenKind) -> u8 {
    match kind {
        TokenKind::Ident => 0,
        TokenKind::Number => 1,
        TokenKind::String => 2,
        TokenKind::Resource => 3,
        TokenKind::Interpolation => 4,
        TokenKind::Operator => 5,
        TokenKind::Punctuation => 6,
        TokenKind::Whitespace => 7,
        TokenKind::Newline => 8,
        TokenKind::Comment => 9,
        TokenKind::Unknown => 10,
    }
}
fn kind(value: u8) -> Option<TokenKind> {
    Some(match value {
        0 => TokenKind::Ident,
        1 => TokenKind::Number,
        2 => TokenKind::String,
        3 => TokenKind::Resource,
        4 => TokenKind::Interpolation,
        5 => TokenKind::Operator,
        6 => TokenKind::Punctuation,
        7 => TokenKind::Whitespace,
        8 => TokenKind::Newline,
        9 => TokenKind::Comment,
        10 => TokenKind::Unknown,
        _ => return None,
    })
}
fn expression(value: &SymbolicExpression) -> Expression {
    Expression(
        value
            .tokens
            .iter()
            .map(|token| {
                (
                    token_kind(token.kind),
                    token.text,
                    [token.relative_span.start, token.relative_span.end],
                )
            })
            .collect(),
    )
}
fn expr(value: Expression, symbols: &SymbolTable) -> Option<SymbolicExpression> {
    let mut end = 0;
    let tokens = value
        .0
        .into_iter()
        .map(|(tag, text, span)| {
            let spelling = symbols.text(text)?;
            let kind = kind(tag)?;
            if span[0] < end || span[1].checked_sub(span[0])? != spelling.len() {
                return None;
            }
            end = span[1];
            Some(ExpressionToken {
                kind,
                text,
                relative_span: SyntaxSpan::new(span[0], span[1]),
            })
        })
        .collect::<Option<Vec<_>>>()?;
    Some(SymbolicExpression {
        tokens: tokens.into(),
    })
}
fn opt_expr(
    value: Option<Expression>,
    symbols: &SymbolTable,
) -> Option<Option<SymbolicExpression>> {
    value.map(|value| expr(value, symbols)).transpose_option()
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
fn array(value: &ArrayDeclaration) -> Array {
    Array {
        element: value.element_type,
        dimensions: value
            .dimensions
            .iter()
            .map(|value| value.as_ref().map(expression))
            .collect(),
    }
}
fn arr(value: Array, symbols: &SymbolTable) -> Option<Arc<ArrayDeclaration>> {
    Some(Arc::new(ArrayDeclaration {
        element_type: symbol(value.element, symbols)?,
        dimensions: value
            .dimensions
            .into_iter()
            .map(|value| opt_expr(value, symbols))
            .collect::<Option<Vec<_>>>()?
            .into(),
    }))
}
fn settings(values: &[ProcedureSettingNode]) -> Vec<Setting> {
    values
        .iter()
        .map(|value| match value {
            ProcedureSettingNode::Setting(setting) => Setting::Value(
                setting.name,
                match setting.operation {
                    SettingOperation::Assign => 0,
                    SettingOperation::In => 1,
                },
                expression(&setting.value),
            ),
            ProcedureSettingNode::Conditional {
                condition,
                then_branch,
                else_branch,
            } => Setting::Branch(
                expression(condition),
                settings(then_branch),
                settings(else_branch),
            ),
            ProcedureSettingNode::UnsupportedContext {
                canonical_header,
                children,
            } => Setting::Unsupported(expression(canonical_header), settings(children)),
        })
        .collect()
}
fn decode_settings(
    values: Vec<Setting>,
    symbols: &SymbolTable,
    depth: usize,
) -> Option<Arc<[ProcedureSettingNode]>> {
    if depth > 256 {
        return None;
    }
    Some(
        values
            .into_iter()
            .map(|value| {
                Some(match value {
                    Setting::Value(name, operation, value) => {
                        symbols.text(name)?;
                        ProcedureSettingNode::Setting(ProcedureSetting {
                            name,
                            operation: match operation {
                                0 => SettingOperation::Assign,
                                1 => SettingOperation::In,
                                _ => return None,
                            },
                            value: expr(value, symbols)?,
                        })
                    }
                    Setting::Branch(condition, yes, no) => ProcedureSettingNode::Conditional {
                        condition: expr(condition, symbols)?,
                        then_branch: decode_settings(yes, symbols, depth + 1)?,
                        else_branch: decode_settings(no, symbols, depth + 1)?,
                    },
                    Setting::Unsupported(header, children) => {
                        ProcedureSettingNode::UnsupportedContext {
                            canonical_header: expr(header, symbols)?,
                            children: decode_settings(children, symbols, depth + 1)?,
                        }
                    }
                })
            })
            .collect::<Option<Vec<_>>>()?
            .into(),
    )
}
fn procedure(value: &ProcedureMetadata) -> Procedure {
    Procedure {
        variadic: value.signature.variadic,
        returns: value.signature.return_annotation.as_ref().map(expression),
        settings: settings(&value.settings),
        arguments: value
            .signature
            .parameters
            .iter()
            .map(|arg| Argument {
                name: arg.name,
                declared: arg.declared_type,
                element: arg.list_element_type,
                flags: arg.flags,
                array: arg.array.as_deref().map(array),
                default: arg.default.as_ref().map(expression),
                annotation: arg.input_annotation.as_ref().map(expression),
                source: arg.source_expression.as_ref().map(expression),
                span: [arg.relative_span.start, arg.relative_span.end],
            })
            .collect(),
    }
}
fn proc(value: Procedure, symbols: &SymbolTable) -> Option<Arc<ProcedureMetadata>> {
    let args = value
        .arguments
        .into_iter()
        .map(|arg| {
            symbols.text(arg.name)?;
            if arg.span[0] > arg.span[1] {
                return None;
            }
            Some(Parameter {
                name: arg.name,
                declared_type: symbol(arg.declared, symbols)?,
                list_element_type: symbol(arg.element, symbols)?,
                flags: arg.flags,
                array: arg
                    .array
                    .map(|value| arr(value, symbols))
                    .transpose_option()?,
                default: opt_expr(arg.default, symbols)?,
                input_annotation: opt_expr(arg.annotation, symbols)?,
                source_expression: opt_expr(arg.source, symbols)?,
                relative_span: SyntaxSpan::new(arg.span[0], arg.span[1]),
            })
        })
        .collect::<Option<Vec<_>>>()?;
    Some(Arc::new(ProcedureMetadata {
        signature: ProcedureSignature {
            parameters: args.into(),
            variadic: value.variadic,
            return_annotation: opt_expr(value.returns, symbols)?,
        },
        settings: decode_settings(value.settings, symbols, 0)?,
    }))
}
fn metadata(value: &DeclarationMeaning) -> Option<Metadata> {
    if value.inherited_opaque.is_some() {
        return None;
    }
    Some(Metadata {
        constant: value
            .resolved_constant
            .as_ref()
            .map(|constant| {
                Some(match constant {
                    SemanticValue::Null => ScalarConstant::Null,
                    SemanticValue::NumberBits(bits) => ScalarConstant::Number(*bits),
                    SemanticValue::Text(text) => ScalarConstant::Text(text.to_vec()),
                    SemanticValue::Type(path) => ScalarConstant::Type(*path),
                    _ => return None,
                })
            })
            .transpose_option()?,
        declared: value.declared_type,
        element: value.list_element_type,
        display: value.display_name,
        flags: value.flags,
        array: value.array.as_deref().map(array),
        procedure: value.procedure.as_deref().map(procedure),
        initializer: value.initializer.as_ref().map(expression),
        formal_initializer: value.declared_initializer.as_ref().map(expression),
        canonical: value.canonical.to_vec(),
        evidence: value.canonical_bytes(),
    })
}
fn meta(value: Metadata, symbols: &SymbolTable) -> Option<DeclarationMeaning> {
    let result = DeclarationMeaning {
        inherited_opaque: None,
        resolved_constant: value
            .constant
            .map(|constant| {
                Some(match constant {
                    ScalarConstant::Null => SemanticValue::Null,
                    ScalarConstant::Number(bits) => SemanticValue::NumberBits(bits),
                    ScalarConstant::Text(text) => SemanticValue::Text(text.into()),
                    ScalarConstant::Type(path) => {
                        symbols.text(path)?;
                        SemanticValue::Type(path)
                    }
                })
            })
            .transpose_option()?,
        declared_type: symbol(value.declared, symbols)?,
        list_element_type: symbol(value.element, symbols)?,
        display_name: symbol(value.display, symbols)?,
        flags: value.flags,
        array: value
            .array
            .map(|value| arr(value, symbols))
            .transpose_option()?,
        procedure: value
            .procedure
            .map(|value| proc(value, symbols))
            .transpose_option()?,
        initializer: opt_expr(value.initializer, symbols)?,
        declared_initializer: opt_expr(value.formal_initializer, symbols)?,
        canonical: value.canonical.into(),
    };
    (result.canonical_bytes() == value.evidence).then_some(result)
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
                        Box::new(metadata(meaning)?),
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
                            formal,
                            var_namespace,
                            initializer,
                        } => Event::Field(
                            owner,
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
                    let meaning = meta(*meaning, &symbols)?;
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
                Event::Field(owner, formal, var_namespace, initializer) => {
                    symbols.text(owner)?;
                    AllocationKind::Field {
                        owner,
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
        assert!(meta(metadata(type_metadata).unwrap(), &SymbolTable::default()).is_none());
        assert!(meta(metadata(type_metadata).unwrap(), &expected.symbols).is_some());
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
