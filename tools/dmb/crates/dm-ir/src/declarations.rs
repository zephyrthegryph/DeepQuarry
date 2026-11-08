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
        self.canonical_bytes_using(&mut crate::canonical_encoding::Unmetered)
            .expect("unmetered native canonical allocation failed")
    }
    /// SAME byte encoder; transient allocations are funded before growth.
    pub fn canonical_bytes_using(&self, work: &mut dyn crate::CanonicalWork) -> std::io::Result<Vec<u8>> {
        crate::canonical_encoding::encode(crate::canonical_encoding::Root::Expression(self), work)
    }
    pub fn canonical_len(&self) -> usize {
        // Each canonical token has adjacency/kind bytes and one u64 SymbolId.
        self.try_canonical_len().expect("canonical symbolic length overflow")
    }
    pub(crate) fn try_canonical_len(&self) -> std::io::Result<usize> {
        self.tokens.len().checked_mul(10).and_then(|n| n.checked_add(b"dm-symbolic-expression-v1\0".len()))
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::OutOfMemory,"canonical symbolic length overflow"))
    }
    pub fn write_canonical(&self, mut write: impl FnMut(&[u8])) {
        self.try_write_canonical(&mut |bytes| { write(bytes); Ok(()) })
            .expect("infallible canonical token sink failed");
    }
    pub(crate) fn try_write_canonical(&self, write: &mut dyn FnMut(&[u8]) -> std::io::Result<()>) -> std::io::Result<()> {
        write(b"dm-symbolic-expression-v1\0")?;
        let mut previous = None;
        for token in self.tokens.iter() {
            let sensitive =
                previous.is_some_and(|(kind, _)| {
                    matches!(kind, TokenKind::Operator | TokenKind::Punctuation)
                }) && matches!(token.kind, TokenKind::Operator | TokenKind::Punctuation);
            write(&[
                if sensitive {
                    if previous.is_some_and(|(_, end)| end == token.relative_span.start) {
                        1
                    } else {
                        2
                    }
                } else {
                    0
                },
            ])?;
            previous = Some((token.kind, token.relative_span.end));
            write(&[token.kind as u8])?;
            write(&token.text.bits().to_le_bytes())?;
        }
            Ok(())
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

impl ProcedureSignature {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        self.canonical_bytes_using(&mut crate::canonical_encoding::Unmetered)
            .expect("unmetered native canonical allocation failed")
    }
    /// SAME byte encoder; transient allocations are funded before growth.
    pub fn canonical_bytes_using(&self, work: &mut dyn crate::CanonicalWork) -> std::io::Result<Vec<u8>> {
        crate::canonical_encoding::encode(crate::canonical_encoding::Root::Signature(self), work)
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
        self.canonical_bytes_using(&mut crate::canonical_encoding::Unmetered)
            .expect("unmetered native canonical allocation failed")
    }
    /// SAME byte encoder; transient allocations are funded before growth.
    pub fn canonical_bytes_using(&self, work: &mut dyn crate::CanonicalWork) -> std::io::Result<Vec<u8>> {
        crate::canonical_encoding::encode(crate::canonical_encoding::Root::Procedure(self), work)
    }

    /// Append the identical encoding into the caller's funded final buffer.
    #[doc(hidden)]
    pub fn append_canonical_using(
        &self, out: &mut dyn crate::CanonicalByteSink, work: &mut dyn crate::CanonicalWork,
    ) -> std::io::Result<()> {
        crate::canonical_encoding::append_procedure(self, out, work)
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
        self.canonical_bytes_using(&mut crate::canonical_encoding::Unmetered)
            .expect("unmetered native canonical allocation failed")
    }
    /// SAME byte encoder; transient allocations are funded before growth.
    pub fn canonical_bytes_using(&self, work: &mut dyn crate::CanonicalWork) -> std::io::Result<Vec<u8>> {
        crate::canonical_encoding::encode(crate::canonical_encoding::Root::Array(self), work)
    }
    pub fn canonical_len(&self) -> usize {
        b"dm-array-declaration-v1\0".len()
            + 1
            + 8
            + 8
            + self
                .dimensions
                .iter()
                .map(|dimension| {
                    1 + dimension
                        .as_ref()
                        .map_or(0, |expression| 8 + expression.canonical_len())
                })
                .sum::<usize>()
    }
    pub fn write_canonical(&self, mut write: impl FnMut(&[u8])) {
        self.try_write_canonical(&mut|bytes|{write(bytes);Ok(())}).expect("infallible array canonical sink failed");
    }
    pub(crate) fn try_write_canonical(&self,write:&mut dyn FnMut(&[u8])->std::io::Result<()>)->std::io::Result<()> {
        write(b"dm-array-declaration-v1\0")?;
        write(&[u8::from(self.element_type.is_some())])?;
        write(
            &self
                .element_type
                .map(SymbolId::bits)
                .unwrap_or(0)
                .to_le_bytes(),
        )?;
        write(&(self.dimensions.len() as u64).to_le_bytes())?;
        for dimension in self.dimensions.iter() {
            write(&[u8::from(dimension.is_some())])?;
            if let Some(expression) = dimension {
                write(&(expression.try_canonical_len()? as u64).to_le_bytes())?;
                expression.try_write_canonical(write)?;
            }
        }
            Ok(())
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
        self.canonical_bytes_using(&mut crate::canonical_encoding::Unmetered)
            .expect("unmetered native canonical allocation failed")
    }
    /// SAME byte encoder; transient allocations are funded before growth.
    pub fn canonical_bytes_using(&self, work: &mut dyn crate::CanonicalWork) -> std::io::Result<Vec<u8>> {
        crate::canonical_encoding::encode(crate::canonical_encoding::Root::Semantic(self), work)
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
        self.canonical_bytes_using(&mut crate::canonical_encoding::Unmetered)
            .expect("unmetered native canonical allocation failed")
    }
    /// SAME byte encoder; transient allocations are funded before growth.
    pub fn canonical_bytes_using(&self, work: &mut dyn crate::CanonicalWork) -> std::io::Result<Vec<u8>> {
        crate::canonical_encoding::encode(crate::canonical_encoding::Root::Opaque(self), work)
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
    /// Variable masks for fields; PROC_FLAG_FINAL for procedure/verb declarations.
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
        self.canonical_bytes_using(&mut crate::canonical_encoding::Unmetered)
            .expect("unmetered native canonical allocation failed")
    }
    /// SAME byte encoder; transient allocations are funded before growth.
    pub fn canonical_bytes_using(&self, work: &mut dyn crate::CanonicalWork) -> std::io::Result<Vec<u8>> {
        crate::canonical_encoding::encode(crate::canonical_encoding::Root::Declaration(self), work)
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
