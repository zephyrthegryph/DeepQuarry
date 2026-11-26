//! Source-neutral transport of one `DeclarationMeaning`: no tree ids, arena indexes or source
//! positions, only symbols and spans relative to their expression. Used by the declaration chunk
//! facts (with an evidence encoding the decoder re-derives) and by portable resolver answers
//! (whose canonical bytes are checked by the caller instead).
use crate::{
    ArrayDeclaration, DeclarationMeaning, ExpressionToken, Parameter, ProcedureMetadata,
    ProcedureSetting, ProcedureSettingNode, ProcedureSignature, SemanticValue, SettingOperation,
    SymbolId, SymbolTable, SymbolicExpression,
};
use dm_syntax::{Span as SyntaxSpan, TokenKind};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// The spellings a decode checks symbols against; `Names::unchecked()` trusts the caller to
/// compare the restored value's canonical bytes with stored evidence.
#[derive(Clone, Copy)]
pub struct Names<'a>(Option<&'a SymbolTable>);
impl<'a> Names<'a> {
    pub fn table(table: &'a SymbolTable) -> Self {
        Self(Some(table))
    }
    pub fn unchecked() -> Self {
        Self(None)
    }
    fn known(self, id: SymbolId) -> bool {
        self.0.is_none_or(|table| table.text(id).is_some())
    }
    /// `None` for an unknown symbol, `Some(None)` when spellings are not checked.
    fn width(self, id: SymbolId) -> Option<Option<usize>> {
        match self.0 {
            None => Some(None),
            Some(table) => table.text(id).map(|text| Some(text.len())),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
enum ScalarConstant {
    Null,
    Number(u32),
    Text(Vec<u8>),
    Type(SymbolId),
}
#[derive(Clone, Debug, Serialize, Deserialize)]
struct Expression(Vec<(u8, SymbolId, [usize; 2])>);
#[derive(Clone, Debug, Serialize, Deserialize)]
struct Array {
    dimensions: Vec<Option<Expression>>,
    element: Option<SymbolId>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
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
#[derive(Clone, Debug, Serialize, Deserialize)]
enum Setting {
    Value(SymbolId, u8, Expression),
    Branch(Expression, Vec<Setting>, Vec<Setting>),
    Unsupported(Expression, Vec<Setting>),
}
#[derive(Clone, Debug, Serialize, Deserialize)]
struct Procedure {
    arguments: Vec<Argument>,
    variadic: bool,
    returns: Option<Expression>,
    settings: Vec<Setting>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PortableMeaning {
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
fn expr(value: Expression, symbols: Names) -> Option<SymbolicExpression> {
    let mut end = 0;
    let tokens = value
        .0
        .into_iter()
        .map(|(tag, text, span)| {
            let width = symbols.width(text)?;
            let kind = kind(tag)?;
            if span[0] < end || span[1].checked_sub(span[0])? != width.unwrap_or(span[1] - span[0]) {
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
    symbols: Names,
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
fn symbol(value: Option<SymbolId>, symbols: Names) -> Option<Option<SymbolId>> {
    if value.is_some_and(|id| !symbols.known(id)) {
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
fn arr(value: Array, symbols: Names) -> Option<Arc<ArrayDeclaration>> {
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
    symbols: Names,
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
                        symbols.known(name).then_some(())?;
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
fn proc(value: Procedure, symbols: Names) -> Option<Arc<ProcedureMetadata>> {
    let args = value
        .arguments
        .into_iter()
        .map(|arg| {
            symbols.known(arg.name).then_some(())?;
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
fn metadata(value: &DeclarationMeaning, evidence: bool) -> Option<PortableMeaning> {
    if value.inherited_opaque.is_some() {
        return None;
    }
    Some(PortableMeaning {
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
        evidence: if evidence { value.canonical_bytes() } else { Vec::new() },
    })
}
fn meta(value: PortableMeaning, symbols: Names) -> Option<DeclarationMeaning> {
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
                        symbols.known(path).then_some(())?;
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
    (value.evidence.is_empty() || result.canonical_bytes() == value.evidence).then_some(result)
}
impl PortableMeaning {
    /// `with_evidence` stores the meaning's canonical bytes so `restore` can re-derive them; a
    /// caller that keeps the canonical bytes elsewhere passes `false`. `None` for a meaning with
    /// an opaque inherited base or a constant that has no scalar form.
    pub fn capture(value: &DeclarationMeaning, with_evidence: bool) -> Option<Self> {
        metadata(value, with_evidence)
    }
    pub fn restore(self, symbols: Names) -> Option<DeclarationMeaning> {
        meta(self, symbols)
    }
}
