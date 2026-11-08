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
/// Optional authored expression and array data. Plain parameters share the
/// empty static view and retain no tail allocation.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ParameterTail {
    pub array: Option<Arc<ArrayDeclaration>>,
    pub default: Option<SymbolicExpression>,
    pub input_annotation: Option<SymbolicExpression>,
    pub source_expression: Option<SymbolicExpression>,
}
static EMPTY_PARAMETER_TAIL: ParameterTail = ParameterTail {
    array: None,
    default: None,
    input_annotation: None,
    source_expression: None,
};

impl ParameterTail {
    /// Includes the physical Arc control, excluding separately shared children.
    pub const fn arc_allocation_bytes() -> usize {
        let control = 2 * std::mem::size_of::<usize>();
        let align = std::mem::align_of::<Self>();
        control.div_ceil(align) * align + std::mem::size_of::<Self>()
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Parameter {
    pub name: SymbolId,
    // Absent IDs are normalized to zero; presence is independent
    // from all possible 64-bit symbol IDs, including zero.
    type_ids: [SymbolId; 2],
    /// Declaration modifiers, using the shared variable declaration flag masks.
    pub flags: u32,
    type_presence: u8,
    /// Location in this signature's argument text for the occurrence mapper.
    pub relative_span: Span,
    tail: Option<Arc<ParameterTail>>,
}

impl Parameter {
    pub fn new(
        name: SymbolId, declared_type: Option<SymbolId>, list_element_type: Option<SymbolId>,
        flags: u32, relative_span: Span,
    ) -> Self {
        Self {
            name, flags, relative_span, tail: None,
            type_ids: [declared_type.unwrap_or(SymbolId::ZERO), list_element_type.unwrap_or(SymbolId::ZERO)],
            type_presence: u8::from(declared_type.is_some()) | (u8::from(list_element_type.is_some()) << 1),
        }
    }

    pub fn declared_type(&self) -> Option<SymbolId> {
        (self.type_presence & 1 != 0).then_some(self.type_ids[0])
    }

    /// Authored list/T element hint, distinct from the runtime /list container.
    pub fn list_element_type(&self) -> Option<SymbolId> {
        (self.type_presence & 2 != 0).then_some(self.type_ids[1])
    }

    pub fn with_tail(mut self, tail: ParameterTail) -> Self {
        self.tail = (tail != EMPTY_PARAMETER_TAIL).then(|| Arc::new(tail));
        self
    }

    /// Borrow only the actual physical tail, for allocation accounting and
    /// detached-resource observation.
    pub fn tail_allocation(&self) -> Option<&Arc<ParameterTail>> {
        self.tail.as_ref()
    }
}

impl std::ops::Deref for Parameter {
    type Target = ParameterTail;
    fn deref(&self) -> &Self::Target {
        self.tail.as_deref().unwrap_or(&EMPTY_PARAMETER_TAIL)
    }
}

#[cfg(test)]
mod parameter_storage_tests {
    use super::*;

    #[test]
    fn compact_parameter_keeps_zero_type_ids_wide_spans_and_the_exact_tail_alias() {
        let zero: SymbolId = serde_json::from_str("0").unwrap();
        let span = Span::new(usize::MAX - 2, usize::MAX - 1);
        let name = SymbolId::of("name");
        let empty = Parameter::new(name, None, None, u32::MAX, span);
        let typed = Parameter::new(name, Some(zero), Some(zero), u32::MAX, span);
        assert_ne!(empty, typed);
        assert_eq!(typed.declared_type(), Some(zero));
        assert_eq!(typed.list_element_type(), Some(zero));
        assert_eq!(typed.relative_span, span);
        assert_eq!(typed.flags, u32::MAX);
        assert!(typed.tail_allocation().is_none());
        assert_eq!(typed.clone().with_tail(ParameterTail::default()), typed);
        let value = typed.with_tail(ParameterTail {
            default: Some(SymbolicExpression { tokens: Arc::from([]) }),
            ..Default::default()
        });
        let alias = value.clone();
        assert_eq!(value, alias);
        assert!(Arc::ptr_eq(value.tail_allocation().unwrap(), alias.tail_allocation().unwrap()));
        #[cfg(target_pointer_width = "64")]
        {
            assert_eq!(std::mem::size_of::<Parameter>(), 56);
            assert_eq!(ParameterTail::arc_allocation_bytes(), 72);
        }
    }
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

/// Fields used by variable values and declarations. A procedure meaning
/// normally has none of these facts and retains no field allocation.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct DeclarationFieldMeaning {
    /// Authored overrides preserve their exact initializer, but flags, array
    /// shape and formal default are unknown when this inherited base is opaque.
    pub inherited_opaque: Option<OpaqueFieldBase>,
    pub declared_type: Option<SymbolId>,
    /// Formal authored list/T hint. Inherited opaque metadata leaves it unknown.
    pub list_element_type: Option<SymbolId>,
    pub array: Option<Arc<ArrayDeclaration>>,
    pub initializer: Option<SymbolicExpression>,
    /// Formal field declaration default, retained apart from class overrides.
    pub declared_initializer: Option<SymbolicExpression>,
    pub resolved_constant: Option<SemanticValue>,
}

static EMPTY_FIELD_MEANING: DeclarationFieldMeaning = DeclarationFieldMeaning {
    inherited_opaque: None,
    declared_type: None,
    list_element_type: None,
    array: None,
    initializer: None,
    declared_initializer: None,
    resolved_constant: None,
};

impl DeclarationFieldMeaning {
    /// Exact additional allocation made by with_field_tail.
    pub fn allocation_bytes(&self) -> usize {
        if self == &EMPTY_FIELD_MEANING { 0 } else { std::mem::size_of::<Self>() }
    }
}

#[derive(Clone, Debug)]
pub struct DeclarationMeaning {
    display_name: SymbolId,
    has_display_name: bool,
    /// Variable masks for fields; PROC_FLAG_FINAL for procedure/verb declarations.
    pub flags: u32,
    pub procedure: Option<Arc<ProcedureMetadata>>,
    pub canonical: crate::CanonicalBytes,
    fields: Option<Box<DeclarationFieldMeaning>>,
}
impl DeclarationMeaning {
    pub fn new(
        display_name: Option<SymbolId>,
        flags: u32,
        procedure: Option<Arc<ProcedureMetadata>>,
        canonical: crate::CanonicalBytes,
    ) -> Self {
        Self {
            display_name: display_name.unwrap_or(SymbolId::ZERO),
            has_display_name: display_name.is_some(),
            flags,
            procedure,
            canonical,
            fields: None,
        }
    }

    pub fn display_name(&self) -> Option<SymbolId> {
        self.has_display_name.then_some(self.display_name)
    }

    pub fn set_display_name(&mut self, display_name: Option<SymbolId>) {
        self.display_name = display_name.unwrap_or(SymbolId::ZERO);
        self.has_display_name = display_name.is_some();
    }

    /// Install the actual value tail, allocating exactly allocation_bytes().
    pub fn with_field_tail(mut self, fields: DeclarationFieldMeaning) -> Self {
        self.fields = (fields.allocation_bytes() != 0).then(|| Box::new(fields));
        self
    }

    /// The physical allocation, absent for ordinary procedures and empty data.
    pub fn field_tail_allocation(&self) -> Option<&DeclarationFieldMeaning> {
        self.fields.as_deref()
    }

    /// Explicit mutation may allocate a tail. A metered writer must admit
    /// size_of::<DeclarationFieldMeaning>() first if the tail is absent.
    pub fn field_tail_mut(&mut self) -> &mut DeclarationFieldMeaning {
        self.fields.get_or_insert_with(|| Box::new(DeclarationFieldMeaning::default()))
    }

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
        Self::new(None, 0, None, crate::CanonicalBytes::default())
    }
}

impl std::ops::Deref for DeclarationMeaning {
    type Target = DeclarationFieldMeaning;
    fn deref(&self) -> &Self::Target {
        self.field_tail_allocation().unwrap_or(&EMPTY_FIELD_MEANING)
    }
}

impl PartialEq for DeclarationMeaning {
    fn eq(&self, other: &Self) -> bool {
        self.display_name() == other.display_name() && self.flags == other.flags
            && self.procedure == other.procedure && self.canonical == other.canonical
            && **self == **other
    }
}
impl Eq for DeclarationMeaning {}
