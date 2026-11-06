//! One actual final-token projection with retained producer state, independent
//! of parser scheduling. No source/model or EOF grant follows these DATA.
use super::original_native_projection::{project_output_token_using,Adjacency,OriginalNativeProjection,OutputSpelling,needs_separator};
use crate::{SourceProvider,macro_expansion::{OriginalMacroToken as Token,OriginalMacroValue as Value}};
use dm_syntax::{SettingAdmission,SettingRootLease,Span,SpanToken};use std::{io,sync::Arc};
#[derive(Clone,Copy)]struct CursorState{last:Option<Adjacency>,offset:usize,line:usize,failed:bool}
struct Payload{credit:SettingRootLease}
/// The identity is the actual producer-issued output allocation. Receipts
/// borrow only that owner; they never read or advance the producer frontier.
/// No nonce/hash/Weak or counter detached from the producing operation exists.
pub(super) struct OriginalOutputIdentity(Option<Arc<Payload>>);
impl Clone for OriginalOutputIdentity{fn clone(&self)->Self{Self(Some(Arc::clone(self.0.as_ref().expect("live actual output cursor"))))}}
impl Drop for OriginalOutputIdentity{fn drop(&mut self){if let Some(owner)=self.0.take(){if let Some(payload)=Arc::into_inner(owner){drop(payload)}}}}
impl OriginalOutputIdentity{
 /// Exact live cursor/control allocations only. The retained lease's size
 /// is a resource reservation and is deliberately never reported as storage.
 pub(super) fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
  let owner=self.0.as_ref().expect("live actual output cursor");let bytes=std::mem::size_of::<Payload>()+2*std::mem::size_of::<usize>();visit(Arc::as_ptr(owner)as usize,bytes,bytes);
  owner.credit.visit_counter_storage(|pointer,n|{let bytes=n+2*std::mem::size_of::<usize>();visit(pointer,bytes,bytes)});
 }
 pub(super) fn same(&self,other:&Self)->bool{Arc::ptr_eq(self.0.as_ref().unwrap(),other.0.as_ref().unwrap())}
 pub(super) fn admitted_by(&self,a:&SettingAdmission<'_>)->bool{a.matches_lease_domain(&self.0.as_ref().unwrap().credit)}
}
pub(super) struct OriginalOutputCursor{
 // The actual cursor is already exclusively borrowed for all advancement.
 // Receipts carry their own immutable issued frontier beside the owner Arc.
 state:CursorState,
 owner:OriginalOutputIdentity,
 literals:dm_syntax::OriginalLiteralPool,
}
/// Fields are private to this issuing module. The receiver may only adopt the
/// SAME issued chunk; no caller can supply arbitrary padding, line or identity.
pub(super) struct OriginalPreparedOutputToken{
 token:SpanToken,literal:Option<dm_syntax::OriginalLiteralData>,actual:Option<Token<'static>>,
 delivered_value:Option<OriginalDeliveredValue>,
 leading:bool,trailing:bool,cover:Span,line:usize,owner:OriginalOutputIdentity,
 spelling:DeliverySpelling,
}
/// Actual value variants retained alongside their projected token. Text
/// lives in the adopted arena or the primary's same issued literal owner.
#[derive(Clone, Copy)]
pub(super) enum OriginalDeliveredValue {
    Ident { whitespace: bool },
    Punctuation { spelling: &'static str, close_colon: bool },
    Literal,
    DocComment { kind: dm_syntax::OriginalCommentKind, content: Span },
}
impl OriginalDeliveredValue {
    fn from_projection(actual: &Token<'static>, projected: &str, span: Span, has_literal: bool) -> io::Result<Self> {
        match &actual.value {
            Value::Ident { spelling, whitespace } if spelling.get() == projected && !has_literal => {
                Ok(Self::Ident { whitespace: *whitespace })
            }
            Value::Punct(spelling) if *spelling == projected && !has_literal => {
                Ok(Self::Punctuation { spelling: *spelling, close_colon: actual.punctuation_close })
            }
            Value::DocComment { kind, text } if !has_literal => {
                // Projection emitted the actual comment delimiters and text.
                // Keep only that checked content extent and the issued kind.
                const PREFIX: usize = 3;
                let end = PREFIX.checked_add(text.get().len()).ok_or(io::ErrorKind::InvalidData)?;
                if projected.get(PREFIX..end) != Some(text.get()) {
                    return Err(io::ErrorKind::InvalidData.into());
                }
                Ok(Self::DocComment { kind: *kind, content: Span::new(span.start + PREFIX, span.start + end) })
            }
            Value::Int(_) | Value::Float(_) | Value::String(_) | Value::Resource(_)
                | Value::InterpBegin(_) | Value::InterpPart(_) | Value::InterpEnd(_) if has_literal => {
                Ok(Self::Literal)
            }
            _ => Err(io::Error::new(io::ErrorKind::InvalidData, "Original value differs from its issued token projection")),
        }
    }
}

/// Queue payload for one actual emitted token. Source origin, raw spelling
/// and lexer frame remain on the producer side of the mapping callback.
pub(super) struct OriginalPreparedDeliveryToken {
    token: SpanToken,
    literal: Option<dm_syntax::OriginalLiteralData>,
    actual: Option<OriginalDeliveredValue>,
    leading: bool,
    trailing: bool,
    end: usize,
    owner: OriginalOutputIdentity,
    spelling: DeliverySpelling,
}

enum DeliverySpelling {
    Owned { text: String, credit: SettingRootLease },
    Arena { owner: BatchSpelling, span: Span },
    Static(&'static str),
    Literal,
}

impl From<OutputSpelling> for DeliverySpelling {
    fn from(spelling: OutputSpelling) -> Self {
        match spelling {
            OutputSpelling::Static(text) => Self::Static(text),
            OutputSpelling::Literal => Self::Literal,
            OutputSpelling::Owned(text) => {
                let (text, credit) = text.into_parts();
                Self::Owned { text, credit }
            }
        }
    }
}

impl DeliverySpelling {
    fn text<'a>(&'a self, literal: Option<&'a dm_syntax::OriginalLiteralData>, a: &SettingAdmission<'_>) -> io::Result<&'a str> {
        match self {
            Self::Owned { text, credit } if a.matches_lease_domain(credit) && credit.bytes() == text.capacity() => Ok(text),
            Self::Arena { owner, span } if a.matches_lease_domain(&owner.payload().fixed) => {
                owner.payload().text.as_str().get(span.range()).ok_or_else(|| io::ErrorKind::InvalidData.into())
            }
            Self::Static(text) => Ok(text),
            Self::Literal => literal.map(dm_syntax::OriginalLiteralData::raw).ok_or_else(|| io::ErrorKind::InvalidData.into()),
            _ => Err(io::ErrorKind::InvalidInput.into()),
        }
    }
}

type Rows<T> = crate::macro_expansion::OriginalMacroRows<T>;
type Text = crate::macro_expansion::OriginalMacroText;

struct BatchSpellingPayload {
    text: Text,
    fixed: SettingRootLease,
}

/// The single batch-local spelling allocation may be loaned to a delivered
/// row. All rows refer to it by walking its byte frontier in issuance order.
#[derive(Clone)]
struct BatchSpelling(Option<Arc<BatchSpellingPayload>>);

impl BatchSpelling {
    fn new(a: &SettingAdmission<'_>) -> io::Result<Self> {
        let bytes = std::mem::size_of::<BatchSpellingPayload>() + 2 * std::mem::size_of::<usize>();
        let fixed = a.reserve(bytes).map_err(|e| a.take_operational_error().unwrap_or(e))?;
        let text = Text::new(a)?;
        Ok(Self(Some(Arc::new(BatchSpellingPayload { text, fixed }))))
    }

    fn payload(&self) -> &BatchSpellingPayload {
        self.0.as_deref().expect("live batch spelling")
    }

    fn append(&mut self, text: &str, a: &SettingAdmission<'_>) -> io::Result<()> {
        let payload = Arc::get_mut(self.0.as_mut().expect("live batch spelling")).expect("unsealed batch spelling");
        payload.text.push_str(text, a)
    }
}

impl Drop for BatchSpelling {
    fn drop(&mut self) {
        if let Some(owner) = self.0.take() {
            if let Some(payload) = Arc::into_inner(owner) {
                drop(payload);
            }
        }
    }
}

const LEADING: u8 = 1;
const TRAILING: u8 = 2;
const EXTRA: u8 = 4;
const ROLE_MASK: u8 = !7;
const DEFAULT: u8 = 0;
const IDENT: u8 = 8;
const PUNCTUATION: u8 = 16;
const LITERAL: u8 = 24;
const DOC: u8 = 32;
const WIDE: u32 = u32::MAX;

/// An issued row retains only kind, width, and packed flags in the hot
/// sequence. No token is re-lexed or recovered from an origin provider.
#[repr(C)]
#[derive(Clone, Copy)]
struct QueuedDeliveryToken {
    width: u32,
    detail: u16,
    flags: u8,
    kind: dm_syntax::TokenKind,
}

struct QueuedDoc {
    kind: dm_syntax::OriginalCommentKind,
    content_width: usize,
}

pub(super) struct OriginalDeliveryBatch {
    rows: Rows<QueuedDeliveryToken>,
    spellings: BatchSpelling,
    punctuation: Rows<&'static str>,
    literals: Rows<Option<dm_syntax::OriginalLiteralData>>,
    docs: Rows<QueuedDoc>,
    wide: Rows<usize>,
    first: Option<usize>,
    end: usize,
    owner: OriginalOutputIdentity,
}

impl OriginalDeliveryBatch {
    pub(super) fn new(owner: &OriginalOutputIdentity, a: &SettingAdmission<'_>) -> io::Result<Self> {
        if !owner.admitted_by(a) {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        Ok(Self {
            rows: Rows::new(a)?, spellings: BatchSpelling::new(a)?,
            punctuation: Rows::new(a)?, literals: Rows::new(a)?, docs: Rows::new(a)?, wide: Rows::new(a)?,
            first: None, end: 0, owner: owner.clone(),
        })
    }

    pub(super) fn len(&self) -> usize { self.rows.len() }

    pub(super) fn push(&mut self, row: OriginalPreparedDeliveryToken, a: &SettingAdmission<'_>) -> io::Result<()> {
        let start = row.token.span.start.checked_sub(usize::from(row.leading)).ok_or(io::ErrorKind::InvalidData)?;
        if !row.owner.same(&self.owner) || !row.owner.admitted_by(a)
            || self.first.is_some() && self.end != start
            || row.token.span.end.checked_add(usize::from(row.trailing)) != Some(row.end)
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "prepared token cannot join this actual output batch"));
        }
        let text = row.spelling.text(row.literal.as_ref(), a)?;
        let width = row.token.span.end.checked_sub(row.token.span.start).ok_or(io::ErrorKind::InvalidData)?;
        if width != text.len() {
            return Err(io::ErrorKind::InvalidData.into());
        }
        let mut detail = 0;
        let flags = match row.actual {
            None if row.literal.is_none() && text == ";" => DEFAULT,
            Some(OriginalDeliveredValue::Ident { whitespace }) if row.literal.is_none() => {
                self.spellings.append(text, a)?;
                IDENT | if whitespace { EXTRA } else { 0 }
            }
            Some(OriginalDeliveredValue::Punctuation { spelling, close_colon })
                if row.literal.is_none() && spelling == text =>
            {
                let at = if let Some(at) = self.punctuation.as_slice().iter().position(|entry| *entry == spelling) {
                    at
                } else {
                    let at = self.punctuation.len();
                    self.punctuation.push(spelling, a)?;
                    at
                };
                detail = u16::try_from(at).map_err(|_| io::ErrorKind::InvalidData)?;
                PUNCTUATION | if close_colon { EXTRA } else { 0 }
            }
            Some(OriginalDeliveredValue::Literal) if row.literal.as_ref().is_some_and(|data| data.raw() == text) => {
                self.literals.push(row.literal, a)?;
                LITERAL
            }
            Some(OriginalDeliveredValue::DocComment { kind, content })
                if row.literal.is_none() && row.token.span.start.checked_add(3) == Some(content.start)
                    && content.start <= content.end && content.end <= row.token.span.end =>
            {
                self.spellings.append(text, a)?;
                self.docs.push(QueuedDoc { kind, content_width: content.end - content.start }, a)?;
                DOC
            }
            _ => return Err(io::ErrorKind::InvalidData.into()),
        } | if row.leading { LEADING } else { 0 } | if row.trailing { TRAILING } else { 0 };
        let width = u32::try_from(width).unwrap_or(WIDE);
        if width == WIDE {
            self.wide.push(row.token.span.end - row.token.span.start, a)?;
        }
        self.rows.push(QueuedDeliveryToken { width, detail, flags, kind: row.token.kind }, a)?;
        self.first.get_or_insert(start);
        self.end = row.end;
        Ok(())
    }

    pub(super) fn seal_using(mut self, a: &SettingAdmission<'_>) -> io::Result<Self> {
        dm_syntax::OriginalLiteralData::pack_delivery_batch_using(self.literals.as_mut_slice(), a)?;
        Ok(self)
    }

    pub(super) fn cursor(self) -> OriginalDeliveryBatchCursor {
        let output_at = self.first.unwrap_or(0);
        OriginalDeliveryBatchCursor { batch: self, row_at: 0, output_at, text_at: 0, literal_at: 0, doc_at: 0, wide_at: 0 }
    }

    #[cfg(test)]
    pub(super) fn row_bytes() -> usize { std::mem::size_of::<QueuedDeliveryToken>() }
}

pub(super) struct OriginalDeliveryBatchCursor {
    batch: OriginalDeliveryBatch,
    row_at: usize,
    output_at: usize,
    text_at: usize,
    literal_at: usize,
    doc_at: usize,
    wide_at: usize,
}

impl OriginalDeliveryBatchCursor {
    fn arena_spelling(&mut self, width: usize) -> io::Result<DeliverySpelling> {
        let end = self.text_at.checked_add(width).ok_or(io::ErrorKind::InvalidData)?;
        let span = Span::new(self.text_at, end);
        self.batch.spellings.payload().text.as_str().get(span.range()).ok_or(io::ErrorKind::InvalidData)?;
        self.text_at = end;
        Ok(DeliverySpelling::Arena { owner: self.batch.spellings.clone(), span })
    }

    pub(super) fn next(&mut self, a: &SettingAdmission<'_>) -> io::Result<Option<OriginalPreparedDeliveryToken>> {
        let Some(row) = self.batch.rows.as_slice().get(self.row_at).copied() else {
            if self.output_at != self.batch.end || self.text_at != self.batch.spellings.payload().text.len()
                || self.literal_at != self.batch.literals.len() || self.doc_at != self.batch.docs.len()
                || self.wide_at != self.batch.wide.len()
            {
                return Err(io::ErrorKind::InvalidData.into());
            }
            return Ok(None);
        };
        // Keep the same active row cancellation/typed-error checkpoint even
        // when the spelling itself needs no transfer or allocation.
        a.checkpoint().map_err(|e| a.take_operational_error().unwrap_or(e))?;
        if !self.batch.owner.admitted_by(a) {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        let width = if row.width == WIDE {
            let width = *self.batch.wide.as_slice().get(self.wide_at).ok_or(io::ErrorKind::InvalidData)?;
            self.wide_at += 1;
            width
        } else {
            row.width as usize
        };
        let leading = row.flags & LEADING != 0;
        let trailing = row.flags & TRAILING != 0;
        let start = self.output_at.checked_add(usize::from(leading)).ok_or(io::ErrorKind::InvalidData)?;
        let token_end = start.checked_add(width).ok_or(io::ErrorKind::InvalidData)?;
        let end = token_end.checked_add(usize::from(trailing)).ok_or(io::ErrorKind::InvalidData)?;
        let token = SpanToken { kind: row.kind, span: Span::new(start, token_end) };
        let extra = row.flags & EXTRA != 0;
        let mut literal = None;
        let (spelling, actual) = match row.flags & ROLE_MASK {
            DEFAULT => (DeliverySpelling::Static(";"), None),
            IDENT => (self.arena_spelling(width)?, Some(OriginalDeliveredValue::Ident { whitespace: extra })),
            PUNCTUATION => {
                let spelling = *self.batch.punctuation.as_slice().get(usize::from(row.detail)).ok_or(io::ErrorKind::InvalidData)?;
                (DeliverySpelling::Static(spelling), Some(OriginalDeliveredValue::Punctuation { spelling, close_colon: extra }))
            }
            LITERAL => {
                let data = self.batch.literals.as_mut_slice().get_mut(self.literal_at).and_then(Option::take).ok_or(io::ErrorKind::InvalidData)?;
                self.literal_at += 1;
                literal = Some(data);
                (DeliverySpelling::Literal, Some(OriginalDeliveredValue::Literal))
            }
            DOC => {
                let doc = self.batch.docs.as_slice().get(self.doc_at).ok_or(io::ErrorKind::InvalidData)?;
                let content_start = start.checked_add(3).ok_or(io::ErrorKind::InvalidData)?;
                let content_end = content_start.checked_add(doc.content_width).ok_or(io::ErrorKind::InvalidData)?;
                if content_end > token_end {
                    return Err(io::ErrorKind::InvalidData.into());
                }
                let actual = OriginalDeliveredValue::DocComment { kind: doc.kind, content: Span::new(content_start, content_end) };
                self.doc_at += 1;
                (self.arena_spelling(width)?, Some(actual))
            }
            _ => return Err(io::ErrorKind::InvalidData.into()),
        };
        self.row_at += 1;
        self.output_at = end;
        Ok(Some(OriginalPreparedDeliveryToken { token, spelling, literal, actual, leading, trailing, end, owner: self.batch.owner.clone() }))
    }
}

#[derive(Clone)]pub(super) struct OriginalDeliveryFrontier{owner:OriginalOutputIdentity,end:usize}
impl OriginalDeliveryFrontier{
 pub(super) fn belongs_to(&self,owner:&OriginalOutputIdentity)->bool{self.owner.same(owner)}
 pub(super) fn end(&self)->usize{self.end}
 pub(super) fn owner(&self)->&OriginalOutputIdentity{&self.owner}
}
/// Issued only after the driver reaches ActualEnd. This aliases the existing
/// funded output cursor and carries no token or declaration-completeness claim.
#[derive(Clone)]
pub(super) struct OriginalProducedEnd(OriginalDeliveryFrontier);
impl OriginalProducedEnd {
    pub(super) fn validate(&self, delivered: &OriginalDeliveryFrontier, a: &SettingAdmission<'_>) -> io::Result<()> {
        a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
        if !self.0.owner.admitted_by(a) || !self.0.owner.same(&delivered.owner) || self.0.end != delivered.end {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "logical end does not close the actual delivered frontier"));
        }
        Ok(())
    }
    pub(super) fn end(&self) -> usize { self.0.end }
}
/// Borrowed actual production record; top metadata uses this SAME line/state.
pub(super) struct OriginalProducedSpan<'a>{token:&'a OriginalPreparedOutputToken}
impl OriginalProducedSpan<'_>{
 pub(super) fn is_default_semicolon(&self)->bool{self.token.actual.is_none()&&self.token.token.kind==dm_syntax::TokenKind::Punctuation&&matches!(&self.token.spelling,DeliverySpelling::Static(";"))&&self.token.literal.is_none()}
 pub(super) fn output_line(&self)->usize{self.token.line}
 pub(super) fn actual(&self)->io::Result<&Token<'static>>{self.token.actual()}
 pub(super) fn owner(&self)->&OriginalOutputIdentity{&self.token.owner}
 pub(super) fn token(&self)->SpanToken{SpanToken{kind:self.token.token.kind,span:self.token.token.span}}
 pub(super) fn cover(&self)->Span{self.token.cover}
}
impl OriginalOutputCursor{
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{a.checkpoint()?;let credit=a.reserve(std::mem::size_of::<Payload>()+2*std::mem::size_of::<usize>())?;Ok(Self{state:CursorState{last:None,offset:0,line:1,failed:false},owner:OriginalOutputIdentity(Some(Arc::new(Payload{credit}))),literals:dm_syntax::OriginalLiteralPool::new(a)?})}
 pub(super) fn identity(&self)->OriginalOutputIdentity{self.owner.clone()}
 pub(super) fn initial_delivery(&self)->io::Result<OriginalDeliveryFrontier>{let state=self.state;if state.offset!=0||state.failed{return Err(io::ErrorKind::InvalidInput.into())}Ok(OriginalDeliveryFrontier{owner:self.owner.clone(),end:0})}
 pub(super) fn seal_actual_end(&self, a: &SettingAdmission<'_>) -> io::Result<OriginalProducedEnd> {
    a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
    let state = self.state;
    if state.failed || !self.owner.admitted_by(a) { return Err(io::ErrorKind::InvalidInput.into()); }
    Ok(OriginalProducedEnd(OriginalDeliveryFrontier { owner: self.owner.clone(), end: state.offset }))
 }
 pub(super) fn prepare(&mut self,actual:Token<'static>,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<OriginalPreparedOutputToken>{
  let result=self.prepare_inner(actual,provider,a);if result.is_err(){self.state.failed=true}result
 }
 fn prepare_inner(&mut self,actual:Token<'static>,provider:&dyn SourceProvider,a:&SettingAdmission<'_>)->io::Result<OriginalPreparedOutputToken>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;
  if !self.owner.admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
  // The macro stream can place a following doc immediately before the
  // declaration. End the projected comment line so its masked columns
  // cannot indent the declaration or absorb a logical delimiter.
  let trailing=matches!(&actual.value,
   Value::Punct("{"|"}"|";") |
   Value::DocComment{kind:dm_syntax::OriginalCommentKind::LineFollowing|dm_syntax::OriginalCommentKind::LineEnclosing,..});
  let projection=project_output_token_using(&actual,provider,a,Some(&mut self.literals))?;
  self.prepare_projection(Some(actual),projection,trailing,a)
 }
 /// Only the actual logical default-delimiter branch calls this. No fake
 /// macro Origin/frame/acquisition is supplied for its nonphysical location.
 pub(super) fn prepare_default_semicolon(&mut self,a:&SettingAdmission<'_>)->io::Result<OriginalPreparedOutputToken>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if !self.owner.admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;let projection=OriginalNativeProjection{kind:dm_syntax::TokenKind::Punctuation,spelling:OutputSpelling::Static(";"),literal:None,adjacency:Adjacency::Punct};let result=self.prepare_projection(None,projection,true,a);if result.is_err(){self.state.failed=true}result}
 fn prepare_projection(&mut self,actual:Option<Token<'static>>,projection:OriginalNativeProjection<OutputSpelling>,trailing:bool,a:&SettingAdmission<'_>)->io::Result<OriginalPreparedOutputToken>{
  a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))?;if !self.owner.admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}
  let state=self.state;if state.failed{return Err(io::ErrorKind::InvalidInput.into())}
  let OriginalNativeProjection{kind,spelling,literal,adjacency}=projection;
  let spelling=DeliverySpelling::from(spelling);
  let text=spelling.text(literal.as_ref(),a)?;
  // A block doc projected at an existing line boundary can finish on
  // another line. Keep its masked closing columns away from the next
  // header, while leaving block docs within a token sequence inline.
  let trailing=trailing || matches!(state.last,None|Some(Adjacency::Whitespace))
   && actual.as_ref().is_some_and(|token|matches!(&token.value,
    Value::DocComment{kind:dm_syntax::OriginalCommentKind::BlockFollowing|dm_syntax::OriginalCommentKind::BlockEnclosing,..}));
  let leading=needs_separator(state.last,adjacency);
  let start=state.offset.checked_add(usize::from(leading)).ok_or(io::ErrorKind::OutOfMemory)?;let end=start.checked_add(text.len()).ok_or(io::ErrorKind::OutOfMemory)?;
  let frontier=end.checked_add(usize::from(trailing)).ok_or(io::ErrorKind::OutOfMemory)?;
  let mut line=state.line;for(at,byte)in text.bytes().enumerate(){if at%1024==0{a.checkpoint()?;}if byte==b'\n'{line=line.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;}}line=line.checked_add(usize::from(trailing)).ok_or(io::ErrorKind::OutOfMemory)?;
  let span=Span::new(start,end);
  let delivered_value=actual.as_ref().map(|actual|OriginalDeliveredValue::from_projection(actual,text,span,literal.is_some())).transpose()?;
  a.checkpoint()?;
  self.state=CursorState{last:Some(if trailing{Adjacency::Whitespace}else{adjacency}),offset:frontier,line,failed:false};
  Ok(OriginalPreparedOutputToken{token:SpanToken{kind,span},literal,actual,delivered_value,leading,trailing,cover:Span::new(start,frontier),line:state.line,owner:self.owner.clone(),spelling})
 }
}
impl OriginalPreparedOutputToken{
 pub(super) fn produced(&self)->OriginalProducedSpan<'_>{OriginalProducedSpan{token:self}}
 pub(super) fn actual(&self)->io::Result<&Token<'static>>{self.actual.as_ref().ok_or_else(||io::ErrorKind::InvalidData.into())}
 pub(super) fn token(&self)->SpanToken{self.produced().token()}
 pub(super) fn cover(&self)->Span{self.cover}
 pub(super) fn into_delivery(self) -> OriginalPreparedDeliveryToken {
    let Self { token, literal, delivered_value, leading, trailing, cover, owner, spelling, .. } = self;
    OriginalPreparedDeliveryToken {
        token, literal, actual: delivered_value, leading, trailing, end: cover.end, owner, spelling,
    }
 }
}

impl OriginalPreparedDeliveryToken {
 pub(super) fn adopt(self,arena:&mut super::original_source_arena::OriginalSourceArena<'_>,primary:&mut dm_syntax::OriginalPrimaryDemand<'_,'_,'_>,owner:&OriginalOutputIdentity,a:&SettingAdmission<'_>)->io::Result<(super::original_final_output::OriginalEmittedToken,OriginalDeliveryFrontier)>{
  a.checkpoint().map_err(|error| a.take_operational_error().unwrap_or(error))?;
  if !self.owner.same(owner) || !self.owner.admitted_by(a)
      || self.token.span.start.checked_sub(usize::from(self.leading)) != Some(arena.as_str().len())
  {
      return Err(io::Error::new(io::ErrorKind::InvalidInput, "prepared output does not continue this SAME actual receiver"));
  }
  let text = self.spelling.text(self.literal.as_ref(), a)?;
  if self.token.span.end.checked_sub(self.token.span.start) != Some(text.len()) {
      return Err(io::ErrorKind::InvalidData.into());
  }
  if self.leading { arena.append(" ")?; }
  let span = arena.append(text)?;
  if span != self.token.span { return Err(io::ErrorKind::InvalidData.into()); }
  let native = self.token;
  if let Some(OriginalDeliveredValue::Punctuation { spelling: ":", close_colon }) = self.actual {
      if text != ":" || self.literal.is_some() { return Err(io::ErrorKind::InvalidData.into()); }
      primary.token_with_original_colon(native, close_colon)?;
  } else if let Some(data) = self.literal {
      primary.token_with_original_literal(native, data)?;
  } else {
      primary.token(native)?;
  }
  if self.trailing{arena.append("\n")?;}if arena.as_str().len()!=self.end{return Err(io::ErrorKind::InvalidData.into())}
  let delivery=OriginalDeliveryFrontier{owner:self.owner.clone(),end:self.end};
  Ok((super::original_final_output::OriginalEmittedToken{token:native,original:self.actual},delivery))
 }
}

#[cfg(test)]
mod compact_queue_tests {
    use super::*;
    use crate::macro_expansion::{OriginalMacroOrigin as Origin, OriginalMacroTextValue as MacroTextValue};
    use dm_syntax::{OriginalCommentKind, OriginalStringMode, OriginalTokenValue, TokenKind};
    use std::{path::Path, sync::atomic::{AtomicUsize, Ordering}};

    struct NoFiles;
    impl SourceProvider for NoFiles {
        fn read(&self, _: &Path) -> Result<String, String> {
            panic!("these actual generated tokens must not reopen source")
        }
    }


    #[test]
    fn actual_output_cursor_alone_controls_future_frontier_and_failed_seal() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut output = OriginalOutputCursor::new(&a).unwrap();
        let initial = output.initial_delivery().unwrap();
        let foreign = OriginalOutputCursor::new(&a).unwrap();
        assert!(!initial.belongs_to(&foreign.identity()));
        let produced = output.prepare_default_semicolon(&a).unwrap();
        assert!(produced.produced().owner().same(initial.owner()));
        let ended = output.seal_actual_end(&a).unwrap();
        assert_eq!(ended.end(), produced.cover().end);
        assert_eq!(initial.end(), 0, "old receipts are immutable snapshots of the actual frontier");
        let failed = SettingAdmission::new(&used, 1 << 20, &|| Err(io::Error::from_raw_os_error(1450)));
        let token = Token {
            string_mode: OriginalStringMode::Unknown, punctuation_close: false,
            lexical_frame: None, lexical_span: None, raw_spelling: None, value: Value::Punct(";"),
            origin: Origin { physical: Span::new(0, 1), line: 1, byte_column: Some(0), occurrence: 0, invocation: false },
        };
        assert_eq!(output.prepare(token, &NoFiles, &failed).err().unwrap().raw_os_error(), Some(1450));
        assert_eq!(output.seal_actual_end(&a).err().unwrap().kind(), io::ErrorKind::InvalidInput);
        assert_eq!(ended.end(), produced.cover().end, "earlier published receipt survives later producer failure");
        drop((output, initial, ended, produced, foreign));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn static_output_spelling_needs_no_scratch_grant() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut output = OriginalOutputCursor::new(&a).unwrap();
        let retained = used.load(Ordering::Acquire);
        let tight = SettingAdmission::new(&used, retained, &|| Ok(()));
        let actual = Token {
            string_mode: OriginalStringMode::Unknown, punctuation_close: true,
            lexical_frame: None, lexical_span: None, raw_spelling: None,
            value: Value::Punct(":"),
            origin: Origin { physical: Span::new(0, 1), line: 1, byte_column: Some(0), occurrence: 0, invocation: false },
        };
        let row = output.prepare(actual, &NoFiles, &tight).unwrap();
        assert_eq!(row.token().span, Span::new(0, 1));
        let row = row.into_delivery();
        assert_eq!(row.spelling.text(None, &tight).unwrap(), ":");
        assert!(matches!(row.actual, Some(OriginalDeliveredValue::Punctuation { close_colon: true, .. })));
        let default = output.prepare_default_semicolon(&tight).unwrap();
        assert!(default.produced().is_default_semicolon());
        assert_eq!(default.token().span, Span::new(2, 3));
        assert_eq!(default.cover().end, 4);
        assert_eq!(used.load(Ordering::Acquire), retained);
        drop((row, default, output));
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn complete_delivery_batch_seals_actual_generated_literal_rows_before_cursor() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut output = OriginalOutputCursor::new(&a).unwrap();
        let owner = output.identity();
        let mut batch = OriginalDeliveryBatch::new(&owner, &a).unwrap();
        let mut spans = [Span::new(0, 0); 32];
        let mut backing = [std::ptr::null(); 32];
        for (at, span) in spans.iter_mut().enumerate() {
            let actual = Token {
                string_mode: OriginalStringMode::Normal, punctuation_close: false,
                lexical_frame: None, lexical_span: None, raw_spelling: None,
                value: Value::InterpPart(MacroTextValue::Borrowed("typed Ã©")),
                origin: Origin { physical: Span::new(at, at + 1), line: 1, byte_column: Some(at), occurrence: 0, invocation: false },
            };
            let prepared = output.prepare(actual, &NoFiles, &a).unwrap();
            *span = prepared.token().span;
            let literal = prepared.literal.as_ref().unwrap();
            assert!(matches!(&prepared.spelling, DeliverySpelling::Literal));
            backing[at] = literal.raw().as_ptr();
            assert_eq!(prepared.spelling.text(Some(literal), &a).unwrap().as_ptr(), backing[at]);
            batch.push(prepared.into_delivery(), &a).unwrap();
        }
        let before = used.load(Ordering::Acquire);
        let mut cursor = batch.seal_using(&a).unwrap().cursor();
        assert!(used.load(Ordering::Acquire) < before);
        let mut keep = None::<dm_syntax::OriginalLiteralData>;
        for (at, span) in spans.into_iter().enumerate() {
            let row = cursor.next(&a).unwrap().unwrap();
            assert_eq!(row.token.span, span);
            let literal = row.literal.unwrap();
            assert_eq!(literal.raw(), "]typed Ã©[");
            assert_eq!(literal.raw().as_ptr(), backing[at]);
            assert!(matches!(literal.value(), OriginalTokenValue::InterpPart("typed Ã©")));
            assert_eq!(literal.string_mode(), OriginalStringMode::Normal);
            if let Some(first) = &keep {
                assert!(!first.same_owner(&literal));
            } else {
                keep = Some(literal);
            }
        }
        assert!(cursor.next(&a).unwrap().is_none());
        assert_eq!(cursor.output_at, output.seal_actual_end(&a).unwrap().end());
        drop((cursor, owner, output));
        assert_ne!(used.load(Ordering::Acquire), 0);
        drop(keep);
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn batch_reuses_one_text_arena_and_moves_exact_sparse_issued_values() {
        let used = Arc::new(AtomicUsize::new(0));
        let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut output = OriginalOutputCursor::new(&a).unwrap();
        let owner = output.identity();
        let mut batch = OriginalDeliveryBatch::new(&owner, &a).unwrap();
        let values = [
            (Value::Ident { spelling: MacroTextValue::Borrowed("alpha"), whitespace: true }, false),
            (Value::Punct(":"), true),
            (Value::Int(i32::MAX), false),
            (Value::Punct("in"), false),
            (Value::DocComment { kind: OriginalCommentKind::LineFollowing, text: MacroTextValue::Borrowed("doc") }, false),
        ];
        let mut expected = Vec::new();
        let mut literal = None;
        for (at, (value, punctuation_close)) in values.into_iter().enumerate() {
            let actual = Token {
                string_mode: OriginalStringMode::Unknown, punctuation_close,
                lexical_frame: None, lexical_span: None, raw_spelling: None, value,
                origin: Origin { physical: Span::new(at, at + 1), line: 1, byte_column: Some(at), occurrence: 0, invocation: false },
            };
            let prepared = output.prepare(actual, &NoFiles, &a).unwrap();
            match at {
                1 => assert!(matches!(&prepared.spelling, DeliverySpelling::Static(":"))),
                2 => assert!(matches!(&prepared.spelling, DeliverySpelling::Literal)),
                3 => assert!(matches!(&prepared.spelling, DeliverySpelling::Static("in"))),
                _ => assert!(matches!(&prepared.spelling, DeliverySpelling::Owned { .. })),
            }
            let text = prepared.spelling.text(prepared.literal.as_ref(), &a).unwrap().to_owned();
            expected.push((prepared.token(), text, prepared.cover().end, prepared.leading, prepared.trailing));
            if let Some(data) = &prepared.literal {
                assert!(literal.replace(data.clone()).is_none());
            }
            batch.push(prepared.into_delivery(), &a).unwrap();
        }
        let default = output.prepare_default_semicolon(&a).unwrap();
        assert!(default.produced().is_default_semicolon());
        assert!(matches!(&default.spelling, DeliverySpelling::Static(";")));
        expected.push((default.token(), ";".to_owned(), default.cover().end, default.leading, default.trailing));
        batch.push(default.into_delivery(), &a).unwrap();
        assert_eq!(OriginalDeliveryBatch::row_bytes(), 8);
        assert_eq!(batch.spellings.payload().text.as_str(), "alpha///doc");
        assert_eq!(batch.punctuation.as_slice(), &[":", "in"]);
        assert_eq!(batch.literals.len(), 1);
        assert_eq!(batch.docs.len(), 1);
        assert_eq!(batch.wide.len(), 0);

        let mut cursor = batch.cursor();
        let mut first = None;
        for (at, (token, spelling, end, leading, trailing)) in expected.into_iter().enumerate() {
            let row = cursor.next(&a).unwrap().unwrap();
            assert!(row.owner.same(&owner));
            assert_eq!((row.token, row.end, row.leading, row.trailing), (token, end, leading, trailing));
            assert_eq!(row.spelling.text(row.literal.as_ref(), &a).unwrap(), spelling);
            match at {
                0 => {
                    assert!(matches!(row.actual, Some(OriginalDeliveredValue::Ident { whitespace: true })));
                    first = Some(row);
                }
                1 => assert!(matches!(row.actual, Some(OriginalDeliveredValue::Punctuation { spelling: ":", close_colon: true }))),
                2 => {
                    let data = row.literal.unwrap();
                    assert!(data.same_owner(literal.as_ref().unwrap()));
                    assert!(matches!(data.value(), OriginalTokenValue::Int(i32::MAX)));
                }
                3 => {
                    assert_eq!(row.token.kind, TokenKind::Ident);
                    assert!(matches!(row.actual, Some(OriginalDeliveredValue::Punctuation { spelling: "in", close_colon: false })));
                }
                4 => {
                    assert!(matches!(row.actual, Some(OriginalDeliveredValue::DocComment { kind: OriginalCommentKind::LineFollowing, content })
                        if content == Span::new(token.span.start + 3, token.span.end)));
                    let DeliverySpelling::Arena { owner: doc, .. } = &row.spelling else { panic!("doc spelling was copied"); };
                    let DeliverySpelling::Arena { owner: ident, .. } = &first.as_ref().unwrap().spelling else { panic!("identifier spelling was copied"); };
                    assert!(Arc::ptr_eq(doc.0.as_ref().unwrap(), ident.0.as_ref().unwrap()));
                }
                5 => assert!(row.actual.is_none()),
                _ => unreachable!(),
            }
        }
        assert!(cursor.next(&a).unwrap().is_none());
        assert_eq!(cursor.output_at, output.seal_actual_end(&a).unwrap().end());
        drop((cursor, literal, owner, output));
        let first = first.unwrap();
        assert_eq!(first.spelling.text(first.literal.as_ref(), &a).unwrap(), "alpha");
        assert_ne!(used.load(Ordering::Acquire), 0, "the surviving exact arena loan still owns its bytes");
        drop(first);
        assert_eq!(used.load(Ordering::Acquire), 0);
    }
}
