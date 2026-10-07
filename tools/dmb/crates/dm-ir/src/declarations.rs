//! Inspectable symbolic signatures and declaration settings. Values retain their
//! lexical token meanings; BYOND flag packing is a separate output concern.
use crate::{SymbolId, SymbolTable};
use dm_syntax::{Span, TokenKind};
use std::sync::Arc;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ExpressionToken {
    pub kind: TokenKind,
    pub text: SymbolId,
    /// Offset relative to this expression, never an absolute source position.
    pub relative_span: Span,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SymbolicExpression {
    pub tokens: Arc<[ExpressionToken]>,
}
impl SymbolicExpression {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"dm-symbolic-expression-v1\0");
        let mut previous = None;
        for token in self.tokens.iter() {
            let sensitive =
                previous.is_some_and(|(kind, _)| {
                    matches!(kind, TokenKind::Operator | TokenKind::Punctuation)
                }) && matches!(token.kind, TokenKind::Operator | TokenKind::Punctuation);
            bytes.push(if sensitive {
                if previous.is_some_and(|(_, end)| end == token.relative_span.start) {
                    1
                } else {
                    2
                }
            } else {
                0
            });
            previous = Some((token.kind, token.relative_span.end));
            bytes.push(token.kind as u8);
            bytes.extend_from_slice(&token.text.bits().to_le_bytes());
        }
        bytes
    }
    /// Reconstruct token spelling with equivalent adjacency. Whitespace/comments
    /// need not be retained, but joining operator characters changes DM meaning.
    pub fn source_text(&self, symbols: &SymbolTable) -> Option<String> {
        let mut text = String::new();
        let mut previous_end = None;
        for token in self.tokens.iter() {
            let spelling = symbols.text(token.text)?;
            if spelling.len()
                != token
                    .relative_span
                    .end
                    .checked_sub(token.relative_span.start)?
            {
                return None;
            }
            if previous_end.is_some_and(|end| end > token.relative_span.start) {
                return None;
            }
            if previous_end.is_some_and(|end| end < token.relative_span.start) {
                text.push(' ')
            }
            text.push_str(spelling);
            previous_end = Some(token.relative_span.end);
        }
        Some(text)
    }
    pub fn fingerprint(&self) -> u128 {
        xxhash_rust::xxh3::xxh3_128(&self.canonical_bytes())
    }
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Parameter {
    pub name: SymbolId,
    pub declared_type: Option<SymbolId>,
    /// Authored list/T element hint, distinct from the runtime /list container.
    pub list_element_type: Option<SymbolId>,
    /// Declaration modifiers, using the shared variable declaration flag masks.
    pub flags: u32,
    pub array: Option<Arc<ArrayDeclaration>>,
    pub default: Option<SymbolicExpression>,
    pub input_annotation: Option<SymbolicExpression>,
    pub source_expression: Option<SymbolicExpression>,
    /// Location in this signature's argument text for the occurrence mapper.
    pub relative_span: Span,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProcedureSignature {
    pub parameters: Arc<[Parameter]>,
    pub variadic: bool,
    pub return_annotation: Option<SymbolicExpression>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SettingOperation {
    Assign,
    In,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProcedureSetting {
    pub name: SymbolId,
    pub operation: SettingOperation,
    pub value: SymbolicExpression,
}
/// Ordered, unevaluated procedure metadata. Executable statements are excluded;
/// guards stay symbolic until a backend demands their exact constant meanings.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ProcedureSettingNode {
    Setting(ProcedureSetting),
    Conditional {
        condition: SymbolicExpression,
        then_branch: Arc<[ProcedureSettingNode]>,
        else_branch: Arc<[ProcedureSettingNode]>,
    },
    UnsupportedContext {
        canonical_header: SymbolicExpression,
        children: Arc<[ProcedureSettingNode]>,
    },
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProcedureMetadata {
    pub signature: ProcedureSignature,
    /// Source setting order and branch structure, without early guard evaluation.
    pub settings: Arc<[ProcedureSettingNode]>,
}
fn append_expression(bytes: &mut Vec<u8>, value: Option<&SymbolicExpression>) {
    bytes.push(u8::from(value.is_some()));
    if let Some(value) = value {
        let data = value.canonical_bytes();
        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&data);
    }
}
impl ProcedureSignature {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"dm-procedure-signature-v2\0");
        bytes.push(u8::from(self.variadic));
        bytes.extend_from_slice(&(self.parameters.len() as u64).to_le_bytes());
        for parameter in self.parameters.iter() {
            bytes.extend_from_slice(&parameter.name.bits().to_le_bytes());
            bytes.extend_from_slice(&parameter.flags.to_le_bytes());
            bytes.push(u8::from(parameter.array.is_some()));
            if let Some(array) = &parameter.array {
                let encoded = array.canonical_bytes();
                bytes.extend_from_slice(&(encoded.len() as u64).to_le_bytes());
                bytes.extend_from_slice(&encoded);
            }
            bytes.push(u8::from(parameter.declared_type.is_some()));
            bytes.extend_from_slice(
                &parameter
                    .declared_type
                    .map(SymbolId::bits)
                    .unwrap_or(0)
                    .to_le_bytes(),
            );
            append_expression(&mut bytes, parameter.default.as_ref());
            bytes.push(u8::from(parameter.list_element_type.is_some()));
            bytes.extend_from_slice(&parameter.list_element_type.map(SymbolId::bits).unwrap_or(0).to_le_bytes());
            append_expression(&mut bytes, parameter.input_annotation.as_ref());
            append_expression(&mut bytes, parameter.source_expression.as_ref());
        }
        append_expression(&mut bytes, self.return_annotation.as_ref());
        bytes
    }
}
impl ProcedureMetadata {
    /// Last authored top-level setting. This is not an effective-setting query:
    /// guarded declarations may override it after backend guard evaluation.
    pub fn unconditional_setting(&self, name: SymbolId) -> Option<&ProcedureSetting> {
        self.settings.iter().rev().find_map(|node| match node {
            ProcedureSettingNode::Setting(setting) if setting.name == name => Some(setting),
            _ => None,
        })
    }
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"dm-procedure-metadata-v2\0");
        let signature = self.signature.canonical_bytes();
        bytes.extend_from_slice(&(signature.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&signature);
        append_settings(&mut bytes, &self.settings);
        bytes
    }
}
fn append_settings(bytes: &mut Vec<u8>, nodes: &[ProcedureSettingNode]) {
    bytes.extend_from_slice(&(nodes.len() as u64).to_le_bytes());
    for node in nodes {
        match node {
            ProcedureSettingNode::Setting(setting) => {
                bytes.push(0);
                bytes.extend_from_slice(&setting.name.bits().to_le_bytes());
                bytes.push(setting.operation as u8);
                append_expression(bytes, Some(&setting.value));
            }
            ProcedureSettingNode::Conditional {
                condition,
                then_branch,
                else_branch,
            } => {
                bytes.push(1);
                append_expression(bytes, Some(condition));
                append_settings(bytes, then_branch);
                append_settings(bytes, else_branch);
            }
            ProcedureSettingNode::UnsupportedContext {
                canonical_header,
                children,
            } => {
                bytes.push(2);
                append_expression(bytes, Some(canonical_header));
                append_settings(bytes, children);
            }
        }
    }
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ArrayDeclaration {
    /// One None means unsized []; Some expressions must resolve to valid sizes.
    pub dimensions: Arc<[Option<SymbolicExpression>]>,
    pub element_type: Option<SymbolId>,
}
impl ArrayDeclaration {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"dm-array-declaration-v1\0");
        bytes.push(u8::from(self.element_type.is_some()));
        bytes.extend_from_slice(
            &self
                .element_type
                .map(SymbolId::bits)
                .unwrap_or(0)
                .to_le_bytes(),
        );
        bytes.extend_from_slice(&(self.dimensions.len() as u64).to_le_bytes());
        for dimension in self.dimensions.iter() {
            append_expression(&mut bytes, dimension.as_ref())
        }
        bytes
    }
}

/// Canonical resolved values supplied to lowering; floating values use exact
/// BYOND f32 bits so equality and cache signatures have an explicit contract.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SemanticValue {
    Null,
    NumberBits(u32),
    Text(Arc<[u8]>),
    Type(SymbolId),
    /// Exact resolver-issued source callable occurrence; not a type or wire ID.
    Procedure(crate::ProcedureIdentity),
    ModifiedInstance(Arc<crate::ModifiedInstance>),
    Resource(SymbolId),
    /// Ordered entries; None is a positional entry, Some is an associative key.
    /// Mutable list identity is retained by the initializer occurrence, not
    /// merged merely because two default expressions yield equal entries.
    List(Arc<[(Option<SemanticValue>, SemanticValue)]>),
}
impl SemanticValue {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        match self {
            Self::Null => bytes.push(0),
            Self::NumberBits(number) => {
                bytes.push(1);
                bytes.extend_from_slice(&number.to_le_bytes());
            }
            Self::Text(text) => {
                bytes.push(2);
                bytes.extend_from_slice(&(text.len() as u64).to_le_bytes());
                bytes.extend_from_slice(text);
            }
            Self::Type(path) => {
                bytes.push(3);
                bytes.extend_from_slice(&path.bits().to_le_bytes());
            }
            Self::Procedure(procedure) => {
                bytes.push(6);
                bytes.extend_from_slice(&procedure.owner.bits().to_le_bytes());
                bytes.extend_from_slice(&procedure.name.bits().to_le_bytes());
                bytes.push(u8::from(procedure.verb));
                bytes.extend_from_slice(&procedure.occurrence.to_le_bytes());
            }
            Self::ModifiedInstance(instance) => {
                bytes.push(7);
                let data = instance.canonical_bytes();
                bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
                bytes.extend_from_slice(data);
            }
            Self::Resource(path) => {
                bytes.push(4);
                bytes.extend_from_slice(&path.bits().to_le_bytes());
            }
            Self::List(entries) => {
                bytes.push(5);
                bytes.extend_from_slice(&(entries.len() as u64).to_le_bytes());
                for (key, value) in entries.iter() {
                    bytes.push(u8::from(key.is_some()));
                    if let Some(key) = key {
                        let data = key.canonical_bytes();
                        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
                        bytes.extend_from_slice(&data);
                    }
                    let data = value.canonical_bytes();
                    bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
                    bytes.extend_from_slice(&data);
                }
            }
        }
        bytes
    }
}
/// Metadata is canonical semantic data, not original source text. The adapter
/// must include argument names/types/defaults, all set settings, and var flags.
/// Unknown settings must produce diagnostics before building this model.
/// A schema-pinned catalog may certify a type without decoding inherited field
/// flags/defaults/array shape. Unsupported never means an untyped declaration.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DeclaredTypeKnowledge {
    Known(SymbolId),
    KnownUntyped,
    Unsupported,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OpaqueFieldBase {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub declared_type: DeclaredTypeKnowledge,
}
impl OpaqueFieldBase {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = b"dm-opaque-intrinsic-field-v1\0".to_vec();
        bytes.extend_from_slice(&self.owner.bits().to_le_bytes());
        bytes.extend_from_slice(&self.name.bits().to_le_bytes());
        match self.declared_type {
            DeclaredTypeKnowledge::Known(path) => {
                bytes.push(1);
                bytes.extend_from_slice(&path.bits().to_le_bytes());
            }
            DeclaredTypeKnowledge::Unsupported => bytes.push(0),
            DeclaredTypeKnowledge::KnownUntyped => bytes.push(2),
        }
        bytes
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DeclarationMeaning {
    /// Authored overrides preserve their exact initializer, but flags, array
    /// shape and formal default are unknown when this inherited base is opaque.
    /// Consumers must not interpret syntax-only zero/None as inherited values.
    pub inherited_opaque: Option<OpaqueFieldBase>,
    pub declared_type: Option<SymbolId>,
    /// Formal authored list/T hint. Inherited opaque metadata leaves it unknown.
    pub list_element_type: Option<SymbolId>,
    pub display_name: Option<SymbolId>,
    pub flags: u32,
    pub procedure: Option<Arc<ProcedureMetadata>>,
    pub array: Option<Arc<ArrayDeclaration>>,
    pub initializer: Option<SymbolicExpression>,
    /// Formal field declaration default, retained apart from class overrides.
    pub declared_initializer: Option<SymbolicExpression>,
    pub resolved_constant: Option<SemanticValue>,
    pub canonical: Arc<[u8]>,
}
impl DeclarationMeaning {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        fn part(out: &mut Vec<u8>, bytes: &[u8]) {
            out.extend_from_slice(&(bytes.len() as u64).to_le_bytes()); out.extend_from_slice(bytes);
        }
        fn optional(out: &mut Vec<u8>, bytes: Option<Vec<u8>>) {
            out.push(u8::from(bytes.is_some()));
            if let Some(bytes) = bytes { part(out, &bytes); }
        }
        let mut out = b"dm-declaration-meaning-v1\0".to_vec();
        optional(&mut out, self.inherited_opaque.as_ref().map(|v| v.canonical_bytes()));
        for value in [self.declared_type, self.list_element_type, self.display_name] {
            optional(&mut out, value.map(|v| v.bits().to_le_bytes().to_vec()));
        }
        out.extend_from_slice(&self.flags.to_le_bytes());
        optional(&mut out, self.procedure.as_ref().map(|v| v.canonical_bytes()));
        optional(&mut out, self.array.as_ref().map(|v| v.canonical_bytes()));
        optional(&mut out, self.initializer.as_ref().map(|v| v.canonical_bytes()));
        optional(&mut out, self.declared_initializer.as_ref().map(|v| v.canonical_bytes()));
        optional(&mut out, self.resolved_constant.as_ref().map(|v| v.canonical_bytes()));
        part(&mut out, &self.canonical);
        out
    }
}
impl Default for DeclarationMeaning {
    fn default() -> Self {
        Self {
            inherited_opaque: None,
            declared_type: None,
            list_element_type: None,
            display_name: None,
            flags: 0,
            procedure: None,
            array: None,
            initializer: None,
            declared_initializer: None,
            resolved_constant: None,
            canonical: Arc::from([]),
        }
    }
}
