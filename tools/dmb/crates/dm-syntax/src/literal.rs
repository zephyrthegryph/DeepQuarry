//! Authoritative DM literal syntax and text-template decoding.
//! Both native emission and analysis borrow the interpolation expressions retained
//! by the issuing literal. No analyzer-specific expression parser is involved.
#[path="original_template_literal.rs"]mod original_template_literal;
pub(crate) use original_template_literal::OriginalTemplateBuilder;
use crate::{parse_expression, Expr, ExprKind, Span};
use std::{
    fmt,
    ops::Deref,
    sync::{Arc, OnceLock},
};

/// Lexical facts needed by the pinned checker, before runtime text escapes.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct LiteralLexicalShape {
    pub interpolated: bool,
    pub pinned_segment_nonempty: bool,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LiteralLexicalError {
    /// Removing CR changed an escape/interpolation boundary. The runtime
    /// expression roster cannot certify the pinned lexical structure.
    InterpolationBoundaryNormalization,
}

#[derive(Clone,Debug,Eq,PartialEq)]
pub(crate) struct LiteralFragment{pub(crate) range:Span,pub(crate) expression:Option<usize>,pub(crate) tokens:Vec<crate::SpanToken>,pub(crate) original:Option<crate::OriginalLiteralData>}
#[derive(Clone)]
pub struct LiteralParts {
    // Immutable completion DATA from this SAME admitted literal/child traversal.
    pub(crate) native_parser_facts:crate::expression_parser::NativeExpressionParserState,
    // Native runtime refusal is distinct from primary lexical/child syntax.
    pub(crate) runtime_error: Option<String>,
    pub(crate) fragments: Vec<LiteralFragment>,
    pub template: Vec<u8>,
    pub expressions: Vec<Expr>,
    pub lexical: Result<LiteralLexicalShape, LiteralLexicalError>,
}
impl fmt::Debug for LiteralParts{fn fmt(&self,f:&mut fmt::Formatter<'_>)->fmt::Result{f.debug_struct("LiteralParts").field("runtime_error",&self.runtime_error).field("fragments",&self.fragments).field("template",&self.template).field("expressions",&self.expressions).field("lexical",&self.lexical).finish()}}
impl PartialEq for LiteralParts{fn eq(&self,other:&Self)->bool{self.runtime_error==other.runtime_error&&self.fragments==other.fragments&&self.template==other.template&&self.expressions==other.expressions&&self.lexical==other.lexical}}
impl Eq for LiteralParts{}
#[derive(Debug)]
struct LiteralState {
    raw: String,
    origin: usize,
    parts: OnceLock<Result<Option<LiteralParts>, String>>,
    // LAST: raw/retained syntax and their physical allocations must die before
    // the same source-free quota anchor can release its final lease.
    retention: OnceLock<crate::SharedSettingRetention>,
    original_prepared:bool,
}
/// Clones of a string literal in one issued syntax tree share its parsed
/// leaves. Numbers and resource paths do not allocate a parse cache.
#[derive(Clone, Debug)]
pub struct LiteralText(Backing);
#[derive(Clone, Debug)]
enum Backing {
    Plain(String),
    Text(LiteralOwner),
    // Scalar/static Original value: no template parser or lazy parts cache.
    Original { data: crate::OriginalLiteralData, origin: usize },
}
/// Sealed standard-Arc owner. No Arc/Weak aliases escape; EVERY drop consumes
/// Arc::into_inner, so the last owner frees control allocation before payload
/// buffers and the final retained-source credit are released.
#[derive(Debug)]
struct LiteralOwner(Option<Arc<LiteralState>>);
impl LiteralOwner {
    fn new(value: LiteralState) -> Self {
        Self(Some(Arc::new(value)))
    }
    fn address(&self) -> usize {
        Arc::as_ptr(self.0.as_ref().expect("live literal owner")) as usize
    }
    fn get_mut(&mut self) -> Option<&mut LiteralState> { Arc::get_mut(self.0.as_mut().expect("live literal owner")) }
    fn into_payload(mut self) -> Option<LiteralState> {
        Arc::into_inner(self.0.take().expect("live literal owner"))
    }
}
impl Clone for LiteralOwner {
    fn clone(&self) -> Self {
        Self(Some(Arc::clone(
            self.0.as_ref().expect("live literal owner"),
        )))
    }
}
impl Deref for LiteralOwner {
    type Target = LiteralState;
    fn deref(&self) -> &LiteralState {
        self.0.as_deref().expect("live literal owner")
    }
}
fn release_literal_payload(
    state: LiteralState,
) -> (Option<LiteralParts>, Option<crate::SharedSettingRetention>) {
    let LiteralState {
        raw,
        origin: _,
        parts,
        retention,original_prepared:_,
    } = state;
    drop(raw);
    let anchor = retention.into_inner();
    let parts = match parts.into_inner() {
        Some(Ok(parts)) => parts,
        Some(Err(error)) => {
            drop(error);
            None
        }
        None => None,
    };
    (parts, anchor)
}
impl Drop for LiteralOwner {
    fn drop(&mut self) {
        let Some(owner) = self.0.take() else {
            return;
        };
        if let Some(payload) = Arc::into_inner(owner) {
            let (parts, anchor) = release_literal_payload(payload);
            if let Some(parts) = parts {
                crate::setting_drop::drop_literal_parts(parts, anchor);
            } else {
                drop(anchor);
            }
        }
    }
}
/// Failure to borrow a complete original lexical String token. Output failure
/// may leave a prefix in a generic fmt sink; callers discard failed buffers.
#[derive(Debug)]
pub enum PinnedStaticTextError{Unprepared,DeferredSyntax,UnsupportedDelimiter,Lexical(LiteralLexicalError),Output(fmt::Error)}
impl LiteralParts{
    /// Borrowed storage accounting only; not a runtime decoding result.
    pub fn runtime_error_storage(&self)->Option<&String>{self.runtime_error.as_ref()}
}
impl LiteralText {
    /// Emit the pinned lexer's STATIC String token spelling from already-issued
    /// original parts. Escapes remain lexical bytes; only the existing pinned
    /// splice scanner removes escaped newline/indentation. Never parses children.
    pub fn write_pinned_static_text(&self,out:&mut impl fmt::Write)->Result<bool,PinnedStaticTextError>{
        if let Some(data)=self.original_data(){return match data.value(){crate::OriginalTokenValue::String(value)=>{out.write_str(value).map_err(PinnedStaticTextError::Output)?;Ok(true)},_=>Ok(false)}}
        let Some((is_raw,value))=literal_content(self.as_str())else{
            return if self.as_str().starts_with('@'){Err(PinnedStaticTextError::UnsupportedDelimiter)}else{Ok(false)}
        };
        let parts=match self.prepared_syntax_parts(){Some(Ok(Some(parts)))=>parts,Some(Err(_))=>return Err(PinnedStaticTextError::DeferredSyntax),_=>return Err(PinnedStaticTextError::Unprepared)};
        let shape=parts.lexical.map_err(PinnedStaticTextError::Lexical)?;
        if shape.interpolated{return Ok(false)}
        if is_raw{out.write_str(value).map_err(PinnedStaticTextError::Output)?;return Ok(true)}
        let mut observed=LiteralLexicalShape{interpolated:false,pinned_segment_nonempty:false};let mut error=None;
        visit_pinned_segment(value.as_bytes(),&mut observed,&mut error,|bytes|out.write_str(std::str::from_utf8(bytes).expect("literal ranges end at original ASCII splice boundaries"))).map_err(PinnedStaticTextError::Output)?;
        if let Some(error)=error{return Err(PinnedStaticTextError::Lexical(error))}
        Ok(true)
    }


    /// Pinned read_resource lexical spelling of an already-issued resource
    /// token. No resource loading, runtime path interpretation, lexer or parse.
    /// Backslash quotes exactly the next character; it is not a string escape.
    /// This data writer does not issue source authority.
    pub fn write_pinned_resource_text(&self,out:&mut impl fmt::Write)->Result<bool,PinnedStaticTextError>{
        if let Some(data)=self.original_data(){return match data.value(){crate::OriginalTokenValue::Resource(value)=>{out.write_str(value).map_err(PinnedStaticTextError::Output)?;Ok(true)},_=>Ok(false)}}
        let raw=self.as_str();if !raw.starts_with('\''){return Ok(false)}
        let body=raw.strip_prefix('\'').and_then(|raw|raw.strip_suffix('\'')).ok_or(PinnedStaticTextError::UnsupportedDelimiter)?;
        if !visit_pinned_resource_bytes(body.as_bytes(),false,|part|out.write_str(std::str::from_utf8(part).expect("actual UTF8 resource ranges end at ASCII escape boundaries"))).map_err(PinnedStaticTextError::Output)?{return Err(PinnedStaticTextError::UnsupportedDelimiter)}Ok(true)
    }

    /// Preferred header/code recipe route: share immutable source-free DATA,
    /// never the AST-specific lazy literal/parts owner. No allocation or credit
    /// transfer follows a loan (the original data owner keeps its own lease).
    pub fn from_original_data(data:&crate::OriginalLiteralData,origin:usize,a:&crate::SettingAdmission<'_>)->std::io::Result<Self>{
        Self::from_original_view(data.as_view(), origin, a)
    }
    pub(crate) fn from_original_view(data: crate::OriginalLiteralRef<'_>, origin: usize, a: &crate::SettingAdmission<'_>) -> std::io::Result<Self> {
        a.checkpoint()?;if matches!(data.value()?,crate::OriginalTokenValue::InterpBegin(_)|crate::OriginalTokenValue::InterpPart(_)|crate::OriginalTokenValue::InterpEnd(_)){return Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"an interpolation part is not a complete literal"))}Ok(Self(Backing::Original{data:data.detach_using(a)?,origin}))
    }
    /// Non-retaining caller fallback. raw is adopted but explicitly funded by
    /// the actual immutable owner; Token.text scratch is not an escaping lease.
    pub fn from_original_value_data(raw:String,origin:usize,value:crate::OriginalTokenValue<&str>,a:&crate::SettingAdmission<'_>)->std::io::Result<Self>{
        let data=crate::OriginalLiteralData::from_value_using(raw,value,a)?;
        Self::from_original_data(&data,origin,a)
    }
    /// Mode is actual producer DATA; no delimiter/value inference.
    pub fn original_string_mode(&self)->Option<crate::OriginalStringMode>{self.original_data().map(crate::OriginalLiteralData::string_mode)}
    pub fn from_original_value_with_mode_data(raw:String,origin:usize,value:crate::OriginalTokenValue<&str>,mode:crate::OriginalStringMode,a:&crate::SettingAdmission<'_>)->std::io::Result<Self>{
        let data=crate::OriginalLiteralData::from_value_with_mode_using(raw,value,mode,a)?;
        Self::from_original_data(&data,origin,a)
    }
    pub fn original_data(&self)->Option<&crate::OriginalLiteralData>{match &self.0{Backing::Original{data,..}=>Some(data),_=>None}}
    /// Runtime bytes from an actual scalar/static token, never its displayed
    /// grammar spelling. Unknown producer mode remains an explicit refusal.
    /// Normal shares the ONE escape/text-macro kernel with templates while
    /// disabling interpolation grammar; Raw/Generated share its raw byte path.
    pub fn decode_original_static_text(&self)->Result<Option<Vec<u8>>,String>{
        let Some(crate::OriginalTokenValue::String(value))=self.original_value()else{return Ok(None)};
        let mode=self.original_string_mode().unwrap_or(crate::OriginalStringMode::Unknown);
        let mut parts=match mode{
            crate::OriginalStringMode::Unknown=>return Err("Original static String runtime decoder entry is not yet issued".into()),
            crate::OriginalStringMode::Raw|crate::OriginalStringMode::Generated=>raw_static_parts(value,Ok(LiteralLexicalShape{interpolated:false,pinned_segment_nonempty:!value.is_empty()})),
            crate::OriginalStringMode::Normal=>{
                if value.contains('\r'){
                    let(cooked,positions)=without_cr(value);
                    parse_text_content_clean(&cooked,RawProjection{original:value,positions:Some(&positions),base:0},None,false)?
                }else{parse_text_content_clean(value,RawProjection::identity(value),None,false)?}
            },
        };
        if let Some(error)=parts.runtime_error.take(){crate::setting_drop::drop_literal_parts(parts,None);return Err(error)}
        debug_assert!(parts.expressions.is_empty());
        Ok(Some(std::mem::take(&mut parts.template)))
    }
    /// Borrow only producer kind from this SAME already prepared Original owner.
    /// Never populates caches/parses children/rebinds geometry/grants source access.
    pub fn original_template_lexical_shape(&self)->Option<LiteralLexicalShape>{let Backing::Text(state)=&self.0 else{return None};if !state.original_prepared{return None}let Ok(Some(parts))=state.parts.get()?.as_ref()else{return None};parts.lexical.as_ref().ok().copied()}
    /// Borrow the already issued template AST and typed fragments at the
    /// exact Pratt geometry. This does not populate an ordinary literal cache
    /// or treat runtime byte decoding as a grammar outcome.
    pub(crate) fn original_prepared_body_parts(&self, span: Span) -> Option<&LiteralParts> {
        let Backing::Text(state) = &self.0 else { return None };
        if !state.original_prepared || state.retention.get().is_none()
            || span.start != state.origin || span.end.checked_sub(span.start) != Some(state.raw.len())
        {
            return None;
        }
        let Ok(Some(parts)) = state.parts.get()?.as_ref() else { return None };
        parts.lexical.as_ref().ok().filter(|shape| shape.interpolated)?;
        Some(parts)
    }
    pub fn original_value(&self)->Option<crate::OriginalTokenValue<&str>>{self.original_data().map(crate::OriginalLiteralData::value)}
    pub fn original_origin(&self)->Option<usize>{match &self.0{Backing::Original{origin,..}=>Some(*origin),_=>None}}
    /// Operation-admitted geometry rebind; never clones source, parts or raw.
    pub fn rebind_original_using(&self,origin:usize,a:&crate::SettingAdmission<'_>)->std::io::Result<Self>{
        let data=self.original_data().ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"literal is not issued Original DATA"))?;
        Self::from_original_data(data,origin,a)
    }
    pub fn visit_original_literal_storage(&self,visit:impl FnMut(usize,usize,usize)){if let Some(data)=self.original_data(){data.visit_storage(visit)}}
    /// Borrows only the completion DATA already retained by this literal. No parse/upgrade.
    pub fn native_parser_facts(&self)->Option<crate::NativeExpressionParserFacts>{match &self.0{Backing::Text(owner)=>owner.parts.get().and_then(|parts|parts.as_ref().ok()).and_then(|parts|parts.as_ref()).and_then(|parts|parts.native_parser_facts.facts(None)),_=>None}}
    pub fn at(raw: String, origin: usize) -> Self {
        if raw.starts_with('"')
            || raw.starts_with("{\"")
            || raw.starts_with("@\"")
            || raw.starts_with("@'")
            || raw.starts_with("@{\"")
        {
            Self(Backing::Text(LiteralOwner::new(LiteralState {
                raw,
                origin,
                parts: OnceLock::new(),
                retention: OnceLock::new(),original_prepared:false,
            })))
        } else {
            Self(Backing::Plain(raw))
        }
    }
    pub fn raw_storage(&self) -> crate::LiteralRawStorage<'_> {
        match &self.0 {
            Backing::Original{data,..} => data.raw_storage(),
            Backing::Plain(raw) => crate::LiteralRawStorage::from_string(raw),
            Backing::Text(state) => crate::LiteralRawStorage::from_string(&state.raw),
        }
    }
    pub fn as_str(&self) -> &str {
        self.raw_storage().as_str()
    }
    /// Read-only census; never computes or retains additional syntax.
    pub fn shared_storage(&self) -> Option<(usize, usize)> {
        match &self.0 {
            Backing::Original{..} | Backing::Plain(_) => None,
            Backing::Text(state) => Some((
                state.address(),
                std::mem::size_of::<LiteralState>() + 2 * std::mem::size_of::<usize>(),
            )),
        }
    }
    pub fn retained_parts(&self) -> Option<Result<Option<&LiteralParts>, &String>> {
        self.prepared_syntax_parts().map(|parsed|parsed.and_then(|parts|match parts{Some(parts)if parts.runtime_error.is_some()=>Err(parts.runtime_error.as_ref().unwrap()),other=>Ok(other)}))
    }
    /// Already-prepared primary syntax DATA, even when native runtime text
    /// decoding explicitly refuses. Never decodes, lexes or parses on demand.
    /// Runtime consumers must keep using parts()/retained_parts().
    /// Literal grammar ownership, not cache readiness or source authority.
    pub fn owns_template_syntax(&self)->bool{matches!(&self.0,Backing::Text(_))}
    pub fn prepared_syntax_parts(&self) -> Option<Result<Option<&LiteralParts>, &String>> {
        match &self.0 {
            Backing::Original{..} | Backing::Plain(_) => None,
            Backing::Text(state) => state.parts.get().map(|p| p.as_ref().map(Option::as_ref)),
        }
    }
    /// Runtime decoding keeps its original explicit refusal. Syntax consumers
    /// use the SAME cache through syntax_parts/prepared_syntax_parts.
    pub fn parts(&self)->Result<Option<&LiteralParts>,&str>{
        // Typed lexical String is NOT an already-decoded runtime template.
        // Until the SAME runtime decoder has an already-static value entry,
        // refuse explicitly rather than raw-parsing '[' as interpolation or
        // returning an invented runtime String. Original syntax_parts remains
        // no children, and pinned static writers use the genuine value above.
        if matches!(self.original_value(),Some(crate::OriginalTokenValue::String(_))){return Err("Original static String runtime decoder entry is not yet issued")}
        self.syntax_parts().and_then(|parts|match parts{Some(parts)if parts.runtime_error.is_some()=>Err(parts.runtime_error.as_ref().unwrap().as_str()),other=>Ok(other)})
    }
    /// The one original literal parser's child syntax, independent of runtime
    /// text-template support. This compatibility demand computes only this cache.
    pub fn syntax_parts(&self) -> Result<Option<&LiteralParts>, &str> {
        let Backing::Text(state) = &self.0 else {
            return Ok(None);
        };
        state
            .parts
            .get_or_init(|| {
                retained_string_literal_parts(&state.raw).map(|parts| {
                    parts.map(|mut parts| {
                        for expression in &mut parts.expressions {
                            shift_expression(expression, state.origin);
                        }
                        parts
                    })
                })
            })
            .as_ref()
            .map(|parts|parts.as_ref())
            .map_err(String::as_str)
    }
    /// True identifies an independently admitted Original template whose
    /// interpolation syntax has already been produced by this counter.
    pub(crate) fn require_fresh_body_owner(&self,a:&crate::SettingAdmission<'_>)->std::io::Result<bool>{
        let Backing::Text(state)=&self.0 else{return a.checkpoint().map(|()| false)};
        if state.original_prepared{
            return if state.retention.get().is_some_and(|r|r.is_admitted_by(a)){
                a.checkpoint().map(|()| true)
            }else{
                Err(std::io::ErrorKind::InvalidInput.into())
            }
        }
        if Arc::strong_count(state.0.as_ref().expect("live literal owner"))!=1||state.parts.get().is_some()||state.retention.get().is_some(){
            a.record_operational_error(std::io::Error::new(std::io::ErrorKind::InvalidInput,"native body literal requires its fresh unpublished original owner"));
            return Err(std::io::ErrorKind::InvalidInput.into());
        }
        a.checkpoint().map(|()| false)
    }
    /// Prepare the SAME issuing literal caches while a native root is still
    /// unpublished and its canonical slot is serialized. Caller pre-admits the
    /// full overlapping raw/projection/child syntax footprint; no new lease or
    /// source authority is issued here. Syntax failures remain deferred strings.
    pub(crate) fn prepare_parts_admitted(
        &self,
        admission: &crate::SettingAdmission<'_>,
    ) -> std::io::Result<()> {
        admission.checkpoint()?;
        let Backing::Text(state) = &self.0 else {
            return Ok(());
        };
        if let Some(cached) = state.parts.get() {
            let _ = cached;
            return admission.checkpoint();
        }
        let mut parsed = retained_string_literal_parts_using(&state.raw, Some(admission));
        admission.checkpoint()?; // NEVER cache an operational failure as syntax.
        if let Ok(Some(parts)) = &mut parsed {
            for expression in &mut parts.expressions {
                admission.checkpoint()?;
                shift_expression(expression, state.origin);
            }
        }
        admission.checkpoint()?;
        // Native unpublished/serialized callers have no competing parts()
        // consumer. OnceLock still preserves an already-issued compatibility
        // value if a lower-level caller violates that synchronization contract.
        let _ = state.parts.set(parsed);
        // No fallible work after this internal syntax commit. The owning root
        // producer's final checkpoint decides whether that whole unpublished
        // root can be exposed. Its ONE worklist prepares nested literal parts.
        Ok(())
    }
    /// Attach only the SAME original source-free lease anchor. A second root
    /// cannot silently claim a literal cache already held by another lease.
    // Set only by the typed builder after all private child payload and cleanup
    // storage is retained by this immutable template's SAME existing anchor.
    pub(crate) fn independently_owned_original_template(&self)->bool{matches!(&self.0,Backing::Text(owner)if owner.original_prepared)}
    pub(crate) fn attach_setting_retention(
        &self,
        anchor: &crate::SharedSettingRetention,
    ) -> std::io::Result<()> {
        let Backing::Text(state) = &self.0 else {
            return Ok(());
        };
        if state.original_prepared&&state.retention.get().is_some(){return Ok(())} // Independently paid SAME template owner; never graft a body lease.
        if let Some(issued) = state.retention.get() {
            return if issued.same_owner(anchor) {
                Ok(())
            } else {
                Err(std::io::ErrorKind::InvalidInput.into())
            };
        }
        if let Err(other) = state.retention.set(anchor.clone()) {
            if !state
                .retention
                .get()
                .is_some_and(|issued| issued.same_owner(&other))
            {
                return Err(std::io::ErrorKind::InvalidInput.into());
            }
        }
        Ok(())
    }
    pub(crate) fn visit_setting_retention_storage(&self, mut visit: impl FnMut(usize, usize)) {
        if let Backing::Text(state) = &self.0 {
            if let Some(anchor) = state.retention.get() {
                anchor.visit_storage(&mut visit);
            }
        }
    }
    /// Last-owner cleanup consumes ORIGINAL cached child Exprs, not clones.
    /// Arc/control storage is already free before returning the actual parts.
    pub(crate) fn into_drop_parts(
        self,
    ) -> (Option<LiteralParts>, Option<crate::SharedSettingRetention>) {
        match self.0 {
            Backing::Original{data,..} => {drop(data);(None,None)},
            Backing::Plain(raw) => {
                drop(raw);
                (None, None)
            }
            Backing::Text(owner) => owner
                .into_payload()
                .map_or((None, None), release_literal_payload),
        }
    }
    pub(crate) fn shift(&mut self, offset: usize) {
        if let Backing::Original{origin,..}=&mut self.0 {
            // Inline geometry only: SAME immutable data and credit stay owned.
            // The enclosing geometry operation already admits its actual work.
            *origin=origin.checked_add(offset).expect("issued Original literal geometry overflow");
            return;
        }
        if let Backing::Text(owner) = &mut self.0 {
            if owner.original_prepared {
                if offset == 0 { return; }
                // Original callers preflight the entire unpublished root below.
                // Shared immutable roots use current projection, never an uncharged copy.
                let state = owner.get_mut().expect("Original geometry requires a unique admitted root");
                state.origin = state.origin.checked_add(offset).expect("preflighted Original geometry");
                if let Some(Ok(Some(parts))) = state.parts.get_mut() {
                    for expression in &mut parts.expressions { shift_expression(expression, offset); }
                }
                return;
            }
        }
        if let Backing::Text(state) = &self.0 {
            if offset != 0 {
                let anchor = state.retention.get().cloned();
                let shifted = Self::at(state.raw.clone(),state.origin+offset);
                if let Some(anchor) = anchor {
                    shifted
                        .attach_setting_retention(&anchor)
                        .expect("fresh shifted literal has no other anchor");
                }
                *self = shifted;
            }
        }
    }
}
impl Deref for LiteralText {
    type Target = str;
    fn deref(&self) -> &str {
        self.as_str()
    }
}
impl AsRef<str> for LiteralText {
    fn as_ref(&self) -> &str {
        self.as_str()
    }
}
impl From<String> for LiteralText {
    fn from(raw: String) -> Self {
        Self::at(raw, 0)
    }
}
impl From<&str> for LiteralText {
    fn from(raw: &str) -> Self {
        raw.to_owned().into()
    }
}
impl PartialEq for LiteralText {
    fn eq(&self, other: &Self) -> bool {
        if let (Backing::Text(a),Backing::Text(b))=(&self.0,&other.0){if a.original_prepared||b.original_prepared{return a.original_prepared==b.original_prepared&&a.raw==b.raw&&a.parts.get()==b.parts.get()}}
        match(self.original_data(),other.original_data()){
            (Some(a),Some(b))=>a==b,
            (None,None)=>self.as_str()==other.as_str(),
            _=>false, // equal raw spelling is not equal typed static/template DATA
        }
    }
}
impl Eq for LiteralText {}
impl PartialEq<String> for LiteralText {
    fn eq(&self, other: &String) -> bool {
        self.as_str() == other
    }
}
impl PartialEq<str> for LiteralText {
    fn eq(&self, other: &str) -> bool {
        self.as_str() == other
    }
}
impl PartialEq<&str> for LiteralText {
    fn eq(&self, other: &&str) -> bool {
        self.as_str() == *other
    }
}
impl fmt::Display for LiteralText {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.as_str().fmt(f)
    }
}

/// Rebase only a fresh unpublished Original root under its existing operation.
/// A shared template is immutable: callers must keep its current projection.
/// The funded preflight validates every nested owner and coordinate before ANY
/// mutation, so quota, foreign-owner and first-IO refusals leave the root intact.
pub(crate) fn shift_unpublished_expression_using(expression: &mut Expr, offset: usize, a: &crate::SettingAdmission<'_>) -> std::io::Result<()> {
    // Retain only disjoint geometry fields, not mutable parent+child aliases.
    // All allocation, polling and checked arithmetic precede the infallible
    // commit. A deep member chain uses funded worklists rather than recursion.
    let result = (move || {
        let _current_limit = a.reserve(0)?;
        let mut changes = crate::admitted_worklist::Worklist::new(a)?;
        let mut pending = crate::admitted_worklist::Worklist::new(a)?;
        pending.push(expression)?;
        while let Some(node) = pending.pop() {
            a.checkpoint()?;
            let start=node.span.start.checked_add(offset).ok_or(std::io::ErrorKind::InvalidInput)?;
            let end=node.span.end.checked_add(offset).ok_or(std::io::ErrorKind::InvalidInput)?;
            changes.push((&mut node.span.start,start))?;
            changes.push((&mut node.span.end,end))?;
            match &mut node.kind {
                ExprKind::Literal(value) => match &mut value.0 {
                    Backing::Original { data, origin } => {
                        let next=origin.checked_add(offset).ok_or(std::io::ErrorKind::InvalidInput)?;
                        // Neutral immutable VALUE keeps its independent original credit.
                        let _=data;
                        changes.push((origin,next))?;
                    }
                    Backing::Text(owner) => {
                        let arc=owner.0.as_ref().expect("live literal owner");
                        if !owner.original_prepared || Arc::strong_count(arc)!=1 || Arc::weak_count(arc)!=0 || !owner.retention.get().is_some_and(|r|r.is_admitted_by(a)) {
                            return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"shared, foreign or unissued Original template requires its immutable current projection"));
                        }
                        let state=owner.get_mut().ok_or(std::io::ErrorKind::InvalidInput)?;
                        let next=state.origin.checked_add(offset).ok_or(std::io::ErrorKind::InvalidInput)?;
                        changes.push((&mut state.origin,next))?;
                        let Some(Ok(Some(parts)))=state.parts.get_mut() else { return Err(std::io::ErrorKind::InvalidData.into()); };
                        pending.extend(parts.expressions.iter_mut())?;
                    }
                    Backing::Plain(_) => (),
                },
                ExprKind::Unary { value, .. } | ExprKind::Group(value) | ExprKind::TypeFilter { value, .. } => pending.push(value.as_mut())?,
                ExprKind::Member { object, .. } | ExprKind::StaticMember { object, .. } | ExprKind::SafeMember { object, .. } => pending.push(object.as_mut())?,
                ExprKind::Binary { lhs, rhs, .. } => { pending.push(lhs.as_mut())?; pending.push(rhs.as_mut())?; }
                ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => { pending.push(object.as_mut())?; pending.push(index.as_mut())?; }
                ExprKind::Conditional { condition, then_value, else_value } => { pending.push(condition.as_mut())?; pending.push(then_value.as_mut())?; pending.push(else_value.as_mut())?; }
                ExprKind::Call { callee, args } => { pending.push(callee.as_mut())?; pending.extend(args.iter_mut())?; }
                ExprKind::ObjectInitializer { object, fields } => { pending.push(object.as_mut())?; pending.extend(fields.iter_mut().map(|(_,value)|value))?; }
                ExprKind::Ident(_) | ExprKind::TypePath(_) => (),
            }
        }
        Ok(changes)
    })();
    if let Some(first)=a.take_operational_error() { return Err(first); }
    let mut changes=result?;
    while let Some((field,value))=changes.pop() { *field=value; }
    Ok(())
}

pub fn shift_expression(expression: &mut Expr, offset: usize) {
    expression.span.start += offset;
    expression.span.end += offset;
    match &mut expression.kind {
        ExprKind::Literal(text) => text.shift(offset),
        ExprKind::Ident(_) | ExprKind::TypePath(_) => (),
        ExprKind::Unary { value, .. }
        | ExprKind::Group(value)
        | ExprKind::TypeFilter { value, .. } => shift_expression(value, offset),
        ExprKind::Member { object, .. }
        | ExprKind::StaticMember { object, .. }
        | ExprKind::SafeMember { object, .. } => shift_expression(object, offset),
        ExprKind::Binary { lhs, rhs, .. } => {
            shift_expression(lhs, offset);
            shift_expression(rhs, offset);
        }
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            shift_expression(object, offset);
            shift_expression(index, offset);
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            shift_expression(condition, offset);
            shift_expression(then_value, offset);
            shift_expression(else_value, offset);
        }
        ExprKind::Call { callee, args } => {
            shift_expression(callee, offset);
            for arg in args {
                shift_expression(arg, offset);
            }
        }
        ExprKind::ObjectInitializer { object, fields } => {
            shift_expression(object, offset);
            for (_, value) in fields {
                shift_expression(value, offset);
            }
        }
    }
}
/// One shared literal parser for emission and source registration. Expression
/// nodes exist only for this literal's interpolation leaves, never a whole body.
/// Exact delimiter policy shared by retained syntax and pinned text spelling.
fn literal_content(raw:&str)->Option<(bool,&str)>{
 if raw.starts_with("@{\"")&&raw.ends_with("\"}")&&raw.len()>=5{Some((true,&raw[3..raw.len()-2]))}
 else if ((raw.starts_with("@\"")&&raw.ends_with('"'))||(raw.starts_with("@'")&&raw.ends_with('\'')))&&raw.len()>=3{Some((true,&raw[2..raw.len()-1]))}
 else if raw.starts_with("{\"")&&raw.ends_with("\"}")&&raw.len()>=4{Some((false,&raw[2..raw.len()-2]))}
 else if raw.starts_with('"')&&raw.ends_with('"')&&raw.len()>=2{Some((false,&raw[1..raw.len()-1]))}
 else{None}
}
fn string_literal_parts_clean(
    raw: &str,
    projection: RawProjection<'_>,
    admission: Option<&crate::SettingAdmission<'_>>,
) -> Result<Option<LiteralParts>, String> {
    let Some((is_raw,value))=literal_content(raw) else{return Ok(None)};
    if is_raw{
     let mut parts=raw_static_parts(value,Ok(LiteralLexicalShape{interpolated:false,pinned_segment_nonempty:!projection.segment(value.as_ptr() as usize-raw.as_ptr() as usize,value.len()).is_empty()}));
     parts.native_parser_facts=crate::expression_parser::NativeExpressionParserState::aggregate(admission.map(|_|crate::NativeExpressionParserFacts::aggregate(parts.lexical.is_ok(),false,parts.lexical.is_err())));
     return Ok(Some(parts));
    }
    let offset = value.as_ptr() as usize - raw.as_ptr() as usize;
    let mut parts = parse_interpolated_string_clean(value, projection.offset(offset), admission)?;
    for expression in &mut parts.expressions {
        shift_expression(expression, offset);
    }
    Ok(Some(parts))
}

/// Projection of ranges issued by the primary interpolation parser onto the
/// original literal. A start includes removed CR bytes after the preceding
/// delimiter; an end includes removed CR bytes before the following delimiter.
#[derive(Clone, Copy)]
struct RawProjection<'a> {
    original: &'a str,
    positions: Option<&'a [usize]>,
    base: usize,
}
impl<'a> RawProjection<'a> {
    fn identity(original: &'a str) -> Self {
        Self {
            original,
            positions: None,
            base: 0,
        }
    }
    fn offset(self, offset: usize) -> Self {
        Self {
            base: self.base + offset,
            ..self
        }
    }
    fn segment_span(self, start: usize, len: usize) -> Span {
        let start = self.base + start;
        let end = start + len;
        let (start, end) = match self.positions {
            Some(positions) => (
                if start == 0 {
                    0
                } else {
                    positions[start - 1] + 1
                },
                positions.get(end).copied().unwrap_or(self.original.len()),
            ),
            None => (start, end),
        };
        Span::new(start,end)
    }
    fn segment(self,start:usize,len:usize)->&'a[u8]{&self.original.as_bytes()[self.segment_span(start,len).range()]}
    fn token_span(self,start:usize,len:usize)->Span{let span=Span::new(self.base+start,self.base+start+len);match self.positions{Some(positions)=>remapped_span(span,positions,self.original.len()),None=>span}}
}
/// This scan never recognizes interpolation grammar. It observes only literal
/// segment ranges already issued by the one primary parser. Pinned read_string
/// retains ordinary escape bytes, but consumes an escaped CR or LF followed by
/// skip_ws(true): all CR/indentation and at most one additional LF.
fn observe_segment(raw:&[u8],shape:&mut LiteralLexicalShape,error:&mut Option<LiteralLexicalError>){
 let result=visit_pinned_segment(raw,shape,error,|_|Ok::<(),std::convert::Infallible>(()));
 match result{Ok(())=>(),Err(never)=>match never{}}
}

pub(crate) fn visit_pinned_segment<E>(
    raw: &[u8],
    shape: &mut LiteralLexicalShape,
    error: &mut Option<LiteralLexicalError>,
    mut emit:impl FnMut(&[u8])->Result<(),E>,
)->Result<(),E> {
    let mut at = 0;let mut start=0;
    while at < raw.len() {
        match raw[at] {
            b'\\' => {
                let escape=at;at += 1;
                match raw.get(at) {
                    Some(b'\r' | b'\n') => {
                        emit(&raw[start..escape])?;at += 1;
                        let mut additional_lf = false;
                        while at < raw.len() {
                            match raw[at] {
                                b'\r' | b' ' | b'\t' => at += 1,
                                b'\n' if !additional_lf => {
                                    additional_lf = true;
                                    at += 1;
                                }
                                _ => break,
                            }
                        }
                        start=at;
                    }
                    Some(_) => {
                        shape.pinned_segment_nonempty = true;
                        at += 1;
                    }
                    None => {
                        *error = Some(LiteralLexicalError::InterpolationBoundaryNormalization);
                    }
                }
            }
            b'[' => {
                *error = Some(LiteralLexicalError::InterpolationBoundaryNormalization);
                at += 1;
            }
            _ => {
                shape.pinned_segment_nonempty = true;
                at += 1;
            }
        }
    }
    emit(&raw[start..])?;Ok(())
}

fn raw_static_parts(value:&str,lexical:Result<LiteralLexicalShape,LiteralLexicalError>)->LiteralParts{
    LiteralParts{native_parser_facts:Default::default(),runtime_error:None,fragments:Vec::new(),template:value.as_bytes().to_vec(),expressions:Vec::new(),lexical}
}
fn parse_interpolated_string_clean(
    value: &str,
    projection: RawProjection<'_>,
    admission: Option<&crate::SettingAdmission<'_>>,
) -> Result<LiteralParts, String> {
    parse_text_content_clean(value,projection,admission,true)
}
// ONE escape/text-macro transition. The ordinary string scanner and actual
// typed-template segments share state; neither transport parses child syntax.
fn decode_text_escape(value:&str,cursor:&mut usize,template:&mut Vec<u8>,runtime_error:&mut Option<String>,next_marker:&mut Option<u8>,substituted:bool)->Result<(),String>{
 let mut at=*cursor;
            at += 1;
            let rest = &value[at..];
            if rest.starts_with("\r\n") || rest.starts_with('\n') {
                at += if rest.starts_with("\r\n") { 2 } else { 1 };
                while at < value.len()
                    && matches!(value.as_bytes()[at], b' ' | b'\t' | b'\r' | b'\n')
                {
                    at += 1;
                }
                return { *cursor=at;Ok(()) };
            }
            if rest.starts_with(' ') {
                at += 1;
                return { *cursor=at;Ok(()) };
            }
            if runtime_error.is_some(){let escape=rest.chars().next().ok_or("trailing string escape")?;at+=escape.len_utf8();return { *cursor=at;Ok(()) };}
            if let Some(consumed) = numeric_escape(rest, template) {
                at += consumed;
                return { *cursor=at;Ok(()) };
            }
            if rest.starts_with("...") {
                template.extend([0xff, 0x12]);
                at += 3;
                return { *cursor=at;Ok(()) };
            }
            // DreamMaker reads the whole letter run after `\` as a macro name. A run
            // that names no applicable macro falls back to a one-letter escape
            // (`\n`, `\t`) followed by literal text, or is an error: `"\red"` is the
            // red formatting macro and `"\redb"` is invalid, never `\r` + "ed".
            let word_len = rest.bytes().take_while(u8::is_ascii_alphabetic).count();
            if word_len != 0 {
                let word = &rest[..word_len];
                let after = &rest[word_len..];
                let effect=match text_macro(word, after, template, substituted){Ok(effect)=>effect,Err(error)=>{*runtime_error=Some(error);template.clear();at+=word_len;return { *cursor=at;Ok(()) };}};
                if let Some(effect) = effect {
                    at += word_len;
                    match effect {
                        TextMacro::Emit(marker, consume_space) => {
                            // `\font` absorbs one preceding space, not a following one.
                            if marker == 0x1d && template.last() == Some(&b' ') {
                                template.pop();
                            }
                            template.extend([0xff, marker]);
                            if consume_space && value[at..].starts_with(' ') {
                                at += 1;
                            }
                        }
                        TextMacro::Article(marker) => {
                            template.extend([0xff, marker]);
                            *next_marker = Some(0x03);
                            at += 1;
                        }
                        TextMacro::NextExpression(marker) => *next_marker = Some(marker),
                        TextMacro::Ordinal => {
                            let last = template.len() - 1;
                            template[last] = 0x05;
                        }
                    }
                    return { *cursor=at;Ok(()) };
                }
            }
            let escape = value[at..].chars().next().ok_or("trailing string escape")?;
            let escaped = match escape {
                'n' => "\n",
                't' => "\t",
                '\\' => "\\",
                '"' => "\"",
                '\'' => "'",
                '[' => "[",
                ']' => "]",
                '<' => "&lt;",
                '>' => "&gt;",
                '&' => "&amp;",
                _ if word_len != 0 => {
                    *runtime_error=Some(format!("undefined text macro or escape sequence: \\{}",&rest[..word_len]));template.clear();at+=word_len;return { *cursor=at;Ok(()) };
                }
                _ => {*runtime_error=Some(format!("unsupported string escape: \\{escape}"));template.clear();at+=escape.len_utf8();return { *cursor=at;Ok(()) };},
            };
            template.extend_from_slice(escaped.as_bytes());
            at += escape.len_utf8();
            return { *cursor=at;Ok(()) };
}
fn parse_text_content_clean(
    value: &str,
    projection: RawProjection<'_>,
    admission: Option<&crate::SettingAdmission<'_>>,
    allow_interpolation:bool,
) -> Result<LiteralParts, String> {
    let mut template = Vec::new();
    let mut runtime_error=None;
    let mut fragments=Vec::new();
    let mut preceding_expression=None;
    let mut preceding_tokens=Vec::new();
    let mut expressions = Vec::new();
    let(mut native_complete,mut native_recovered,mut native_deferred)=(true,false,false);
    let mut next_marker = None;
    let mut substituted = false;
    let mut lexical = LiteralLexicalShape {
        interpolated: false,
        pinned_segment_nonempty: false,
    };
    let mut segment_start = 0;
    let mut segment_error = None;
    let mut at = 0;
    let parsed=(||->Result<LiteralParts,String>{
    while at < value.len() {
        if let Some(admission) = admission {
            admission
                .checkpoint()
                .map_err(|_| "interpolation operation stopped".to_owned())?;
        }
        let ch = value[at..].chars().next().unwrap();
        if ch == '\\' {
            decode_text_escape(value,&mut at,&mut template,&mut runtime_error,&mut next_marker,substituted)?;
            continue;
        }
        if ch == '[' && allow_interpolation {
            if fragments.capacity()==0{
                let count=value.bytes().filter(|b|*b==b'[').count().checked_add(1).ok_or_else(||{if let Some(a)=admission{a.record_operational_error(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"literal fragment count overflow"));}"literal fragment count overflow".to_owned()})?;
                fragments.try_reserve_exact(count).map_err(|_|{if let Some(a)=admission{a.record_operational_error(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"literal fragment allocation refused"));}"literal fragment allocation refused".to_owned()})?;
                if fragments.capacity()>count.saturating_mul(4){if let Some(a)=admission{a.record_operational_error(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"literal fragment allocation exposed excess"));}return Err("literal fragment allocation exposed excess".into())}
            }
            fragments.push(LiteralFragment{range:projection.segment_span(segment_start,at-segment_start),expression:preceding_expression,tokens:std::mem::take(&mut preceding_tokens),original:None});
            observe_segment(
                projection.segment(segment_start, at - segment_start),
                &mut lexical,
                &mut segment_error,
            );
            lexical.interpolated = true;
            let start = at + 1;
            let mut cursor = None;
            let mut depth = 1usize;
            let diagnostics = crate::visit_tokens_while(&value[start..], |token| {
                if admission.is_some_and(|a| a.checkpoint().is_err()) {
                    return false;
                }

                if token.kind == crate::TokenKind::Punctuation {
                    match token.text(&value[start..]) {
                        "[" => depth += 1,
                        "]" => {
                            depth -= 1;
                            if depth == 0 {
                                cursor = Some(start + token.span.start);
                                return false;
                            }
                        }
                        _ => (),
                    }
                }
                true
            });
            if admission.is_some_and(|a| a.is_stopped()) {
                return Err("interpolation operation stopped".into());
            }
            if !diagnostics.is_empty() {
                return Err("invalid string interpolation tokens".into());
            }
            let cursor = cursor.ok_or("unclosed string interpolation")?;
            substituted = true;
            if value[start..cursor].trim().is_empty() {
                preceding_expression=None;
                template.extend([0xff, next_marker.take().unwrap_or(1)]);
                at = cursor + 1;
                segment_start = at;
                continue;
            }
            let raw_expression = &value[start..cursor];
            let leading = raw_expression.len() - raw_expression.trim_start().len();
            let raw_expression = raw_expression.trim();
            let (source, positions) = splice_with_positions(raw_expression);
            #[cfg(test)] LITERAL_CHILD_PARSES.with(|n|n.set(n.get()+1));
            let(parsed,mut primary_tokens,native)=crate::expression_parser::parse_optional_interpolation_with_primary_tokens_and_native_facts(&source,admission)?;
            if admission.is_some_and(|a| a.is_stopped()) {
                return Err("interpolation operation stopped".into());
            }
            if !parsed.diagnostics.is_empty() {
                return Err("invalid string interpolation expression".into());
            }
            let Some(mut expression)=parsed.expr else{
                if primary_tokens.iter().any(|token|!matches!(token.kind,crate::TokenKind::Whitespace|crate::TokenKind::Newline|crate::TokenKind::Comment)){return Err("empty string interpolation".into())}
                if !native.is_some_and(|facts|facts.exhausted()&&!facts.recovered()&&!facts.deferred()){native_complete=false;native_deferred=true;}
                // The SAME primary lexer proved a trivia-only empty child.
                // Pinned interpolation expressions are optional, like [ ].
                for token in &mut primary_tokens{let span=remapped_span(token.span,&positions,raw_expression.len());token.span=projection.token_span(start+leading+span.start,span.end-span.start);}
                preceding_expression=None;preceding_tokens=primary_tokens;
                template.extend([0xff,next_marker.take().unwrap_or(1)]);at=cursor+1;segment_start=at;continue;
            };
            if let Some(facts)=native{
                native_recovered|=facts.recovered();native_deferred|=facts.deferred();
                native_complete&=facts.is_complete()&&facts.complete_span()==Some(expression.span);
            }else{native_complete=false;native_deferred=true;}
            remap(&mut expression, &positions, raw_expression);
            shift_expression(&mut expression, start + leading);
            for token in &mut primary_tokens{let span=remapped_span(token.span,&positions,raw_expression.len());token.span=projection.token_span(start+leading+span.start,span.end-span.start);}
            preceding_tokens=primary_tokens;
            preceding_expression=Some(expressions.len());
            expressions.push(expression);
            let marker = next_marker.take().unwrap_or_else(|| {
                if interpolation_starts_sentence(&template) {
                    2
                } else {
                    1
                }
            });
            template.extend([0xff, marker]);
            at = cursor + 1;
            segment_start = at;
            continue;
        }
        let mut bytes = [0; 4];
        if runtime_error.is_none(){template.extend_from_slice(ch.encode_utf8(&mut bytes).as_bytes());}
        at += ch.len_utf8();
    }
    observe_segment(
        projection.segment(segment_start, value.len() - segment_start),
        &mut lexical,
        &mut segment_error,
    );
    if lexical.interpolated{fragments.push(LiteralFragment{range:projection.segment_span(segment_start,value.len()-segment_start),expression:preceding_expression,tokens:std::mem::take(&mut preceding_tokens),original:None});}
    let native_lexical=segment_error.is_none()&&runtime_error.is_none();
    Ok(LiteralParts {
        native_parser_facts:crate::expression_parser::NativeExpressionParserState::aggregate(admission.map(|_|crate::NativeExpressionParserFacts::aggregate(native_complete&&native_lexical,native_recovered,native_deferred||!native_complete||!native_lexical))),
        runtime_error:runtime_error.take(),
        fragments,
        template,
        expressions,
        lexical: segment_error.map_or(Ok(lexical), Err),
    })
    })();
    // An earlier native decoding refusal remains the runtime failure even if
    // later lexical children also fail; no partial primary syntax is exposed.
    parsed.map_err(|error|runtime_error.take().unwrap_or(error))
}

enum TextMacro {
    /// `0xff marker` in place; the flag consumes one following space.
    Emit(u8, bool),
    /// Article (`\the`, `\a`, ...): marker in place, the next substitution is its
    /// noun (marker 3), and the mandatory following space is consumed.
    Article(u8),
    /// The next substitution is emitted with this marker (`\ref`, `\icon`, ...).
    NextExpression(u8),
    /// `\th` rewrites the marker of the substitution it directly follows.
    Ordinal,
}

/// `\xHH` (two hex digits) and `\uHHHH` (four) code points, UTF-8 encoded.
fn numeric_escape(rest: &str, template: &mut Vec<u8>) -> Option<usize> {
    let digits = match rest.as_bytes().first()? {
        b'x' => 2,
        b'u' => 4,
        _ => return None,
    };
    let hex = rest.get(1..1 + digits)?;
    if !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    let code = char::from_u32(u32::from_str_radix(hex, 16).ok()?)?;
    let mut encoded = [0; 4];
    template.extend_from_slice(code.encode_utf8(&mut encoded).as_bytes());
    Some(1 + digits)
}

/// DreamMaker 516.1687 text macros by full name (oracle:
/// `fixtures/native_compiler/text_macros`). `Ok(None)` means the word is not an
/// applicable macro here and falls back to a one-letter escape.
fn text_macro(
    word: &str,
    after: &str,
    template: &[u8],
    substituted: bool,
) -> Result<Option<TextMacro>, String> {
    let pronoun = |marker| {
        if substituted {
            Ok(Some(TextMacro::Emit(marker, false)))
        } else {
            Err(format!("macro \\{word} requires preceding expression"))
        }
    };
    let article = |marker| Ok(after.starts_with(' ').then_some(TextMacro::Article(marker)));
    match word {
        "the" => article(0x08),
        "The" => article(0x09),
        "a" | "an" => article(0x06),
        "A" | "An" => article(0x07),
        "he" | "she" => pronoun(0x0a),
        "He" | "She" => pronoun(0x0b),
        "his" => pronoun(0x0c),
        "His" => pronoun(0x0d),
        "hers" => pronoun(0x0e),
        "Hers" => pronoun(0x0f),
        "him" => pronoun(0x10),
        "himself" | "herself" => pronoun(0x11),
        "s" => pronoun(0x14),
        "th" => {
            if substituted && template.len() >= 2 && template[template.len() - 2] == 0xff {
                Ok(Some(TextMacro::Ordinal))
            } else {
                Err("macro \\th must follow a substituted expression (like []\\th)".into())
            }
        }
        "proper" | "improper" => {
            if template.is_empty() {
                let marker = if word == "proper" { 0x15 } else { 0x16 };
                Ok(Some(TextMacro::Emit(marker, true)))
            } else {
                Err(format!("\\{word} must be at beginning of word"))
            }
        }
        "ref" => Ok(Some(TextMacro::NextExpression(0x2a))),
        "icon" => Ok(Some(TextMacro::NextExpression(0x2b))),
        "roman" => Ok(Some(TextMacro::NextExpression(0x2c))),
        "Roman" => Ok(Some(TextMacro::NextExpression(0x2d))),
        "bold" | "b" => Ok(Some(TextMacro::Emit(0x17, true))),
        "italic" | "i" => Ok(Some(TextMacro::Emit(0x18, true))),
        "underline" | "u" => Ok(Some(TextMacro::Emit(0x19, true))),
        "o" => Ok(Some(TextMacro::Emit(0x1a, true))),
        "font" => Ok(Some(TextMacro::Emit(0x1d, false))),
        "red" => Ok(Some(TextMacro::Emit(0x1f, true))),
        "green" => Ok(Some(TextMacro::Emit(0x20, true))),
        "blue" => Ok(Some(TextMacro::Emit(0x21, true))),
        "black" => Ok(Some(TextMacro::Emit(0x22, true))),
        "white" => Ok(Some(TextMacro::Emit(0x23, true))),
        _ => Ok(None),
    }
}

fn interpolation_starts_sentence(mut prefix: &[u8]) -> bool {
    loop {
        while prefix
            .last()
            .is_some_and(|byte| matches!(byte, b' ' | b'\n' | b'\t' | b'\'' | b'"' | 0xff))
        {
            prefix = &prefix[..prefix.len() - 1];
        }
        match prefix.last() {
            None | Some(b'.' | b'!' | b'?') => return true,
            Some(b'>') => {
                if let Some(opening) = prefix.iter().rposition(|byte| *byte == b'<') {
                    prefix = &prefix[..opening];
                } else {
                    return true;
                }
            }
            _ => return false,
        }
    }
}

fn without_cr(source: &str) -> (String, Vec<usize>) {
    let positions: Vec<_> = source
        .bytes()
        .enumerate()
        .filter_map(|(at, byte)| (byte != b'\r').then_some(at))
        .collect();
    let bytes: Vec<_> = positions.iter().map(|&at| source.as_bytes()[at]).collect();
    (
        String::from_utf8(bytes).expect("removing CR preserves UTF-8"),
        positions,
    )
}
fn splice_with_positions(source: &str) -> (String, Vec<usize>) {
    let protected: Vec<_> = crate::lex_spans(source)
        .tokens
        .into_iter()
        .filter(|t| {
            matches!(
                t.kind,
                crate::TokenKind::String | crate::TokenKind::Resource
            )
        })
        .map(|t| t.span.range())
        .collect();
    let mut positions = Vec::new();
    let mut at = 0;
    let mut token = 0;
    while at < source.len() {
        while token < protected.len() && protected[token].end <= at {
            token += 1;
        }
        let in_literal = protected.get(token).is_some_and(|r| r.contains(&at));
        let tail = &source.as_bytes()[at..];
        let skip = if in_literal {
            0
        } else if tail.starts_with(b"\\\r\n") {
            3
        } else if tail.starts_with(b"\\\n") {
            2
        } else {
            0
        };
        if skip != 0 {
            at += skip;
        } else {
            positions.push(at);
            at += 1;
        }
    }
    let bytes = positions.iter().map(|&at| source.as_bytes()[at]).collect();
    (
        String::from_utf8(bytes).expect("splicing preserves UTF-8"),
        positions,
    )
}
fn remapped_span(span:Span,positions:&[usize],source_len:usize)->Span{
    let start = positions.get(span.start).copied().unwrap_or(source_len);
    let end = if span.end == span.start {
        start
    } else {
        positions
            .get(span.end - 1)
            .map_or(source_len, |at| at + 1)
    };
    Span::new(start,end)
}
fn remap(expression:&mut Expr,positions:&[usize],source:&str){
    let span=remapped_span(expression.span,positions,source.len());let(start,end)=(span.start,span.end);expression.span=span;
    match &mut expression.kind {
        ExprKind::Literal(text) => *text = LiteralText::at(source[start..end].to_owned(), start),
        ExprKind::Ident(_) | ExprKind::TypePath(_) => (),
        ExprKind::Unary { value, .. }
        | ExprKind::Group(value)
        | ExprKind::TypeFilter { value, .. } => remap(value, positions, source),
        ExprKind::Member { object, .. }
        | ExprKind::StaticMember { object, .. }
        | ExprKind::SafeMember { object, .. } => remap(object, positions, source),
        ExprKind::Binary { lhs, rhs, .. } => {
            remap(lhs, positions, source);
            remap(rhs, positions, source);
        }
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            remap(object, positions, source);
            remap(index, positions, source);
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            remap(condition, positions, source);
            remap(then_value, positions, source);
            remap(else_value, positions, source);
        }
        ExprKind::Call { callee, args } => {
            remap(callee, positions, source);
            for arg in args {
                remap(arg, positions, source);
            }
        }
        ExprKind::ObjectInitializer { object, fields } => {
            remap(object, positions, source);
            for (_, value) in fields {
                remap(value, positions, source);
            }
        }
    }
}
fn retained_string_literal_parts(raw: &str) -> Result<Option<LiteralParts>, String> {
    retained_string_literal_parts_using(raw, None)
}
fn retained_string_literal_parts_using(
    raw: &str,
    admission: Option<&crate::SettingAdmission<'_>>,
) -> Result<Option<LiteralParts>, String> {
    if !raw.contains('\r') {
        return string_literal_parts_clean(raw, RawProjection::identity(raw), admission);
    }
    let (cooked, positions) = without_cr(raw);
    let mut parts = string_literal_parts_clean(
        &cooked,
        RawProjection {
            original: raw,
            positions: Some(&positions),
            base: 0,
        },
        admission,
    )?;
    if let Some(parts) = &mut parts {
        for expr in &mut parts.expressions {
            remap(expr, &positions, raw);
        }
    }
    Ok(parts)
}
/// Compatibility tuple projection; the single retained parser also issues
/// lexical policy facts, which runtime-only tuple callers need not retain.
pub fn string_literal_parts(raw: &str) -> Result<Option<(Vec<u8>, Vec<Expr>)>, String> {
    let Some(mut parts)=retained_string_literal_parts(raw)? else{return Ok(None)};
    if let Some(error)=parts.runtime_error.take(){crate::setting_drop::drop_literal_parts(parts,None);return Err(error)}
    Ok(Some((parts.template,parts.expressions)))
}
pub fn parse_interpolated_string(value: &str) -> Result<(Vec<u8>, Vec<Expr>), String> {
    let mut parts = if value.contains('\r') {
        let (cooked, positions) = without_cr(value);
        let mut parts = parse_interpolated_string_clean(
            &cooked,
            RawProjection {
                original: value,
                positions: Some(&positions),
                base: 0,
            },
            None,
        )?;
        for expr in &mut parts.expressions {
            remap(expr, &positions, value);
        }
        parts
    } else {
        parse_interpolated_string_clean(value, RawProjection::identity(value), None)?
    };
    if let Some(error)=parts.runtime_error.take(){crate::setting_drop::drop_literal_parts(parts,None);return Err(error)}
    Ok((
        std::mem::take(&mut parts.template),
        std::mem::take(&mut parts.expressions),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{NodeStep, TypedVisitor, VisitDecision};
    #[test]
    fn literal_clones_share_issued_interpolation_nodes() {
        let parsed = parse_expression(r#""before [callee(2)] after""#);
        assert!(parsed.diagnostics.is_empty());
        let expression = parsed.expr.unwrap();
        let ExprKind::Literal(text) = expression.kind else {
            panic!()
        };
        let copy = text.clone();
        let parts = text.parts().unwrap().unwrap();
        assert!(std::ptr::eq(parts, copy.parts().unwrap().unwrap()));
        assert_eq!(parts.expressions.len(), 1);
        assert!(matches!(parts.expressions[0].kind, ExprKind::Call { .. }));
        assert_eq!(parts.expressions[0].span, Span::new(9, 18));
        assert!(LiteralText::from("42").shared_storage().is_none());
    }
    #[test]
    fn interpolation_visits_nested_calls_once_with_physical_spans() {
        let source = "\"prefix\r [outer(\\\r\n    \"[inner()]\")] end\"";
        let parsed = parse_expression(source);
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        struct Calls<'a> {
            source: &'a str,
            calls: Vec<String>,
        }
        impl TypedVisitor for Calls<'_> {
            fn projected_expression(
                &mut self,
                view: crate::ProjectedExprView<'_>,
                path: &[crate::NodeStep],
            ) -> crate::VisitDecision {
                let expression = view.original();
                if let ExprKind::Call { callee, .. } = &expression.kind {
                    let ExprKind::Ident(name) = &callee.kind else {
                        panic!()
                    };
                    let span = view.current_span_of(callee).unwrap();
                    assert_eq!(&self.source[span.range()], name);
                    self.calls.push(name.clone());
                }
                let _ = path;
                VisitDecision::Descend
            }

            fn expression(&mut self, expression: &Expr, _: &[NodeStep]) -> VisitDecision {
                if let ExprKind::Call { callee, .. } = &expression.kind {
                    let ExprKind::Ident(name) = &callee.kind else {
                        panic!()
                    };
                    assert_eq!(&self.source[callee.span.range()], name);
                    self.calls.push(name.clone());
                }
                VisitDecision::Descend
            }
        }
        let mut calls = Calls {
            source,
            calls: Vec::new(),
        };
        crate::visit_expression(&parsed.expr.unwrap(), &mut calls);
        assert_eq!(calls.calls, ["outer", "inner"]);
    }
    #[test]
    fn rebasing_cached_literal_children_preserves_the_original_issuance() {
        let mut expression = parse_expression(r#""[nested()]""#).expr.unwrap();
        let original = expression.clone();
        let ExprKind::Literal(text) = &original.kind else {
            panic!()
        };
        let original_start = text.parts().unwrap().unwrap().expressions[0].span.start;
        shift_expression(&mut expression, 100);
        let ExprKind::Literal(shifted) = &expression.kind else {
            panic!()
        };
        assert_eq!(
            shifted.parts().unwrap().unwrap().expressions[0].span.start,
            original_start + 100
        );
        assert_eq!(
            text.parts().unwrap().unwrap().expressions[0].span.start,
            original_start
        );
    }
    #[test]
    fn nested_escaped_quotes_resources_and_brackets_use_native_lexer_boundaries() {
        let source = r#""[f("a\"b]", 'icons/a]b.dmi', "]")] trailing""#;
        let parsed = parse_expression(source);
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let ExprKind::Literal(text) = parsed.expr.unwrap().kind else {
            panic!()
        };
        let parts = text.parts().unwrap().unwrap();
        assert_eq!(parts.expressions.len(), 1);
        let ExprKind::Call { args, .. } = &parts.expressions[0].kind else {
            panic!()
        };
        assert_eq!(args.len(), 3);
        assert_eq!(&source[args[1].span.range()], "'icons/a]b.dmi'");
    }
    #[test]
    fn raw_and_escaped_brackets_have_no_expression_children() {
        for source in [r#"@"[not_a_call()]""#, r#""\[not_a_call()]""#] {
            let parsed = parse_expression(source);
            assert!(parsed.diagnostics.is_empty());
            let ExprKind::Literal(text) = parsed.expr.unwrap().kind else {
                panic!()
            };
            assert!(text.parts().unwrap().unwrap().expressions.is_empty());
        }
    }
    #[test]
    fn malformed_interpolation_remains_an_explicit_failure() {
        let text = LiteralText::from(r#""[broken(]""#);
        assert_eq!(
            text.parts().unwrap_err(),
            "invalid string interpolation expression"
        );
    }
}

#[cfg(test)]
#[path = "literal_lexical_shape_tests.rs"]
mod lexical_shape_tests;

#[cfg(test)]
mod admitted_interpolation_tests {
    use super::*;
    use std::{cell::Cell, sync::{atomic::{Ordering}, Arc}};
    #[test]
    fn admitted_literal_parts_preserve_original_projection_anchors_and_warm_owner() {
        for raw in [
            "\"before [callee(2)] after\"",
            "\"prefix\r [outer(\\\r\n    \"[inner()]\")] end\"",
            "@\"raw [not_a_child()]\"",
            "\"ÃƒÂ© [callee(2)] \\the [name]\"",
        ] {
            let native = LiteralText::at(raw.to_owned(), 123);
            let copy = native.clone();
            let old = LiteralText::at(raw.to_owned(), 123);
            let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
            let calls = Cell::new(0);
            let checkpoint = || {
                calls.set(calls.get() + 1);
                Ok(())
            };
            let admission = crate::SettingAdmission::new(&counter, 1024 * 1024, &checkpoint);
            // A tiny known fixture's caller owns the existing reservation until all
            // aliases drop; the literal helper neither creates nor resets any quota.
            let lease = admission.reserve(65536).unwrap();
            native.prepare_parts_admitted(&admission).unwrap();
            assert_eq!(native.parts(), old.parts());
            assert!(std::ptr::eq(
                native.parts().unwrap().unwrap(),
                copy.parts().unwrap().unwrap()
            ));
            let before = calls.get();
            copy.prepare_parts_admitted(&admission).unwrap();
            assert_eq!(
                calls.get() - before,
                2,
                "warm literal checks operation but does not reparse children"
            );
            assert!(counter.load(Ordering::Acquire) > crate::SettingChargeCounter::root_allocation_bytes());
            drop(native);
            drop(copy);
            drop(old);
            drop(lease);
            assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
        }
    }
    #[test]
    fn admitted_literal_cancellation_leaves_failed_literal_cache_unset_and_retries() {
        let text = LiteralText::at("\"[callee(1)]\"".into(), 77);
        let alias = text.clone();
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap(); counter.add_soft_estimate(37);
        let calls = Cell::new(0);
        let interrupted = || {
            let n = calls.get() + 1;
            calls.set(n);
            if n >= 9 {
                Err(std::io::Error::new(
                    std::io::ErrorKind::Interrupted,
                    "actual literal child cancellation",
                ))
            } else {
                Ok(())
            }
        };
        let admission = crate::SettingAdmission::new(&counter, 1024 * 1024, &interrupted);
        let error = text.prepare_parts_admitted(&admission).unwrap_err();
        assert_eq!(error.kind(), std::io::ErrorKind::Interrupted);
        assert!(calls.get() >= 9);
        assert!(text.retained_parts().is_none());
        assert!(alias.retained_parts().is_none());
        let original = admission.take_operational_error().unwrap();
        assert_eq!(original.kind(), std::io::ErrorKind::Interrupted);
        assert_eq!(original.to_string(), "actual literal child cancellation");
        assert_eq!(
            counter.load(Ordering::Acquire),
            crate::SettingChargeCounter::root_allocation_bytes() + (37),
            "helper cannot reset shared root credit"
        );
        let healthy = || Ok(());
        let next = crate::SettingAdmission::new(&counter, 1024 * 1024, &healthy);
        text.prepare_parts_admitted(&next).unwrap();
        assert_eq!(text.parts().unwrap().unwrap().expressions.len(), 1);
        assert!(next.take_operational_error().is_none());
    }
    #[test]
    fn admitted_literal_keeps_syntax_errors_deferred_and_does_not_rewalk_nested_ast() {
        for raw in ["\"[1 +]\"", "\"\\undefined_escape\""] {
            let native = LiteralText::at(raw.into(), 0);
            let old = LiteralText::at(raw.into(), 0);
            let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
            let healthy = || Ok(());
            let admission = crate::SettingAdmission::new(&counter, 1024 * 1024, &healthy);
            native.prepare_parts_admitted(&admission).unwrap();
            assert_eq!(native.parts().unwrap_err(), old.parts().unwrap_err());
            assert!(matches!(native.retained_parts(), Some(Err(_))));
            assert!(admission.take_operational_error().is_none());
        }
        let native = LiteralText::at("\"[outer(\"[inner()]\")]\"".into(), 0);
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let healthy = || Ok(());
        let admission = crate::SettingAdmission::new(&counter, 1024 * 1024, &healthy);
        native.prepare_parts_admitted(&admission).unwrap();
        let parts = native.parts().unwrap().unwrap();
        let ExprKind::Call { args, .. } = &parts.expressions[0].kind else {
            panic!()
        };
        let ExprKind::Literal(child) = &args[0].kind else {
            panic!()
        };
        assert!(
            child.retained_parts().is_none(),
            "owning root's single admitted worklist handles grandchildren"
        );
    }
}

#[cfg(test)]
mod setting_retention_owner_tests {
    use super::*;
    use std::sync::atomic::{Ordering};
    fn anchor(counter: &Arc<crate::SettingChargeCounter>, bytes: usize) -> crate::SharedSettingRetention {
        crate::SharedSettingRetention::new(
            crate::SettingRootLease::reserve(counter, 1024 * 1024, bytes).unwrap(),
        )
    }
    #[test]
    fn cloned_literal_keeps_same_credit_after_root_anchor_drops_until_last_alias() {
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let held = anchor(&counter, 4096);
        let text = LiteralText::at("\"[callee(1)]\"".into(), 0);
        let alias = text.clone();
        text.attach_setting_retention(&held).unwrap();
        assert_eq!(text.parts().unwrap().unwrap().expressions.len(), 1);
        drop(held);
        drop(text);
        assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (4096));
        drop(alias);
        assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }
    #[test]
    fn foreign_anchor_refuses_and_last_parts_move_keep_credit_until_iterative_cleanup() {
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let first = anchor(&counter, 2048);
        let foreign = anchor(&counter, 1024);
        let text = LiteralText::at("\"[callee(1)]\"".into(), 0);
        text.attach_setting_retention(&first).unwrap();
        text.attach_setting_retention(&first).unwrap();
        assert_eq!(
            text.attach_setting_retention(&foreign).unwrap_err().kind(),
            std::io::ErrorKind::InvalidInput
        );
        drop(foreign);
        let pointer = text.parts().unwrap().unwrap().expressions.as_ptr() as usize;
        drop(first);
        let (parts, retention) = text.into_drop_parts();
        let parts = parts.unwrap();
        assert_eq!(
            parts.expressions.as_ptr() as usize,
            pointer,
            "move existing children without clone/reparse"
        );
        assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (2048));
        crate::setting_drop::drop_literal_parts(parts, retention);
        assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }
    #[test]
    fn shifted_surviving_literal_alias_does_not_lose_original_retention() {
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let held = anchor(&counter, 1024);
        let text = LiteralText::at("\"[x]\"".into(), 0);
        text.attach_setting_retention(&held).unwrap();
        let mut alias = text.clone();
        drop(text);
        drop(held);
        alias.shift(10);
        assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes() + (1024));
        drop(alias);
        assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }
    #[test]
    fn concurrent_literal_aliases_release_credit_exactly_once() {
        let counter = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let held = anchor(&counter, 4096);
        let text = LiteralText::at("\"[x]\"".into(), 0);
        text.attach_setting_retention(&held).unwrap();
        text.parts().unwrap();
        let a = text.clone();
        let b = text.clone();
        drop(text);
        drop(held);
        std::thread::scope(|scope| {
            scope.spawn(move || drop(a));
            scope.spawn(move || drop(b));
        });
        assert_eq!(counter.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
    }
}

#[cfg(test)]
thread_local!{static LITERAL_CHILD_PARSES:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
#[cfg(test)]
pub(crate) fn literal_child_parses_for_test()->usize{LITERAL_CHILD_PARSES.with(|n|n.get())}

#[cfg(test)]
mod pinned_writer_tests{
 use super::*;
 fn literal(source:&str)->LiteralText{
  let parsed=crate::parse_expression(source);assert!(parsed.diagnostics.is_empty(),"{source:?}: {:?}",parsed.diagnostics);
  let Expr{kind:ExprKind::Literal(value),..}=parsed.expr.unwrap()else{panic!("original literal")};value
 }
 #[test]
 fn static_text_writer_borrows_prepared_parts_and_preserves_lexical_escapes(){
  for(source,expected)in[(r#""ÃƒÂ©\n\[text]""#,r"ÃƒÂ©\n\[text]"),("\"left\\\r\n \t right\"","leftright"),("\"left\\\n\n  right\"","leftright"),("{\"first\nsecond\"}","first\nsecond"),("@\"[raw]\\n\"","[raw]\\n"),("@{\"ÃƒÂ©\r\n[raw]\"}","ÃƒÂ©\r\n[raw]")]{
   let value=literal(source);value.parts().unwrap();let before=literal_child_parses_for_test();let mut text=String::new();assert!(value.write_pinned_static_text(&mut text).unwrap());assert_eq!(text,expected,"{source:?}");assert_eq!(literal_child_parses_for_test(),before,"writer cannot lex/parse child expressions");
  }
 }
 #[test]
 fn writer_never_prepares_missing_parts_and_never_reports_interpolation_as_static(){
  let value=literal("\"[f()]\"");let before=literal_child_parses_for_test();let mut text=String::new();assert!(matches!(value.write_pinned_static_text(&mut text),Err(PinnedStaticTextError::Unprepared)));assert!(text.is_empty());assert_eq!(literal_child_parses_for_test(),before);
  value.parts().unwrap();let before=literal_child_parses_for_test();assert!(!value.write_pinned_static_text(&mut text).unwrap());assert!(text.is_empty());assert_eq!(literal_child_parses_for_test(),before);
 }
 #[test]
 fn writer_propagates_output_refusal_without_a_completed_static_result(){
  struct Refuse;impl fmt::Write for Refuse{fn write_str(&mut self,_:&str)->fmt::Result{Err(fmt::Error)}}
  let value=literal("\"key\"");value.parts().unwrap();assert!(matches!(value.write_pinned_static_text(&mut Refuse),Err(PinnedStaticTextError::Output(_))));
 }
}

/// One lexical segment and the optional actual interpolation child BEFORE it.
/// The first segment has no child; later empty [] segments also carry None.
/// No AST/source ownership or constructor is exposed.
pub struct PinnedLiteralFragment<'a>{raw:&'a[u8],expression:Option<&'a Expr>,tokens:&'a[crate::SpanToken],origin:usize,literal:&'a str,original:Option<&'a crate::OriginalLiteralData>}
impl<'a> PinnedLiteralFragment<'a>{
 pub fn expression(&self)->Option<&'a Expr>{self.expression}
 /// Exact borrowed physical token spelling. Primary splices may lie inside
 /// this raw range; consumers use the SAME primary splice projection only.
 pub fn token_text(&self,canonical:Span)->Result<&'a str,PinnedStaticTextError>{let start=canonical.start.checked_sub(self.origin).ok_or(PinnedStaticTextError::DeferredSyntax)?;let end=canonical.end.checked_sub(self.origin).ok_or(PinnedStaticTextError::DeferredSyntax)?;let index=self.tokens.binary_search_by_key(&start,|token|token.span.start).map_err(|_|PinnedStaticTextError::DeferredSyntax)?;if self.tokens[index].span.end!=end{return Err(PinnedStaticTextError::DeferredSyntax)}self.literal.get(start..end).ok_or(PinnedStaticTextError::DeferredSyntax)}
 /// Canonical coordinates, like the same original child Expr. A current
 /// setting reborrow must apply its existing current offset before source use.
 pub fn tokens(&self)->impl Iterator<Item=Result<(crate::TokenKind,Span),PinnedStaticTextError>>+'_ {self.tokens.iter().map(move|token|{let start=token.span.start.checked_add(self.origin).ok_or(PinnedStaticTextError::DeferredSyntax)?;let end=token.span.end.checked_add(self.origin).ok_or(PinnedStaticTextError::DeferredSyntax)?;Ok((token.kind,Span::new(start,end)))})}
 pub fn tokens_between(&self,span:Span)->Result<impl Iterator<Item=Result<(crate::TokenKind,Span),PinnedStaticTextError>>+'_,PinnedStaticTextError>{
  let expression=self.expression.ok_or(PinnedStaticTextError::DeferredSyntax)?;if span.start>span.end||span.start<expression.span.start||span.end>expression.span.end{return Err(PinnedStaticTextError::DeferredSyntax)}
  let start=span.start.checked_sub(self.origin).ok_or(PinnedStaticTextError::DeferredSyntax)?;let end=span.end.checked_sub(self.origin).ok_or(PinnedStaticTextError::DeferredSyntax)?;let first=self.tokens.partition_point(|token|token.span.end<=start);let last=self.tokens.partition_point(|token|token.span.start<end);if first>last{return Err(PinnedStaticTextError::DeferredSyntax)}let tokens=&self.tokens[first..last];if tokens.first().is_some_and(|token|token.span.start<start)||tokens.last().is_some_and(|token|token.span.end>end){return Err(PinnedStaticTextError::DeferredSyntax)}
  Ok(tokens.iter().map(move|token|{let start=token.span.start.checked_add(self.origin).ok_or(PinnedStaticTextError::DeferredSyntax)?;let end=token.span.end.checked_add(self.origin).ok_or(PinnedStaticTextError::DeferredSyntax)?;Ok((token.kind,Span::new(start,end)))}))
 }
 pub fn write_text(&self,out:&mut impl fmt::Write)->Result<(),PinnedStaticTextError>{if let Some(data)=self.original{let text=match data.value(){crate::OriginalTokenValue::InterpBegin(s)|crate::OriginalTokenValue::InterpPart(s)|crate::OriginalTokenValue::InterpEnd(s)=>s,_=>return Err(PinnedStaticTextError::DeferredSyntax)};return out.write_str(text).map_err(PinnedStaticTextError::Output)}let mut shape=LiteralLexicalShape{interpolated:false,pinned_segment_nonempty:false};let mut error=None;visit_pinned_segment(self.raw,&mut shape,&mut error,|bytes|out.write_str(std::str::from_utf8(bytes).expect("issued literal fragment ends at primary UTF8 boundary"))).map_err(PinnedStaticTextError::Output)?;if let Some(error)=error{return Err(PinnedStaticTextError::Lexical(error))}Ok(())}
}
impl LiteralText{
 /// Existing PRIMARY literal partition only. Never scans interpolation syntax,
 /// invokes the lexer, or parses a child; a missing prepared owner stays Err.
 pub fn pinned_fragments(&self)->Result<Option<impl Iterator<Item=Result<PinnedLiteralFragment<'_>,PinnedStaticTextError>>+'_>,PinnedStaticTextError>{
  let parts=match self.prepared_syntax_parts(){Some(Ok(Some(parts)))=>parts,Some(Err(_))=>return Err(PinnedStaticTextError::DeferredSyntax),_=>return Err(PinnedStaticTextError::Unprepared)};
  let shape=parts.lexical.map_err(PinnedStaticTextError::Lexical)?;if !shape.interpolated{return Ok(None)}if parts.fragments.len()<2{return Err(PinnedStaticTextError::DeferredSyntax)}
  let origin=match &self.0{Backing::Text(state)=>state.origin,Backing::Original{origin,..}=>*origin,Backing::Plain(_)=>0};
  Ok(Some(parts.fragments.iter().map(move|row|{let raw=self.as_str().get(row.range.range()).ok_or(PinnedStaticTextError::DeferredSyntax)?;let expression=match row.expression{Some(index)=>Some(parts.expressions.get(index).ok_or(PinnedStaticTextError::DeferredSyntax)?),None=>None};Ok(PinnedLiteralFragment{raw:raw.as_bytes(),expression,tokens:&row.tokens,origin,literal:self.as_str(),original:row.original.as_ref()})})))
 }
 pub fn visit_pinned_fragment_storage(&self,mut visit:impl FnMut(usize,usize,usize)){if let Some(Ok(Some(parts)))=self.prepared_syntax_parts(){visit(parts.fragments.as_ptr()as usize,parts.fragments.len()*std::mem::size_of::<LiteralFragment>(),parts.fragments.capacity()*std::mem::size_of::<LiteralFragment>());for row in &parts.fragments{if let Some(data)=&row.original{data.visit_storage(&mut visit)}visit(row.tokens.as_ptr()as usize,row.tokens.len()*std::mem::size_of::<crate::SpanToken>(),row.tokens.capacity()*std::mem::size_of::<crate::SpanToken>());}}}
}

#[cfg(test)]mod pinned_fragment_tests{
 use super::*;
 fn literal(text:&str)->LiteralText{match crate::parse_expression(text).expr.unwrap().kind{ExprKind::Literal(value)=>value,_=>panic!("literal fixture")}}
 #[test]fn primary_literal_fragments_keep_empty_children_comments_and_exact_pinned_text_without_reparse(){
  let source="\"before[ ]middle[x /* ] */]tail[f(1)]end\"";let text=literal(source);let before=literal_child_parses_for_test();assert!(matches!(text.pinned_fragments(),Err(PinnedStaticTextError::Unprepared)));assert_eq!(literal_child_parses_for_test(),before);
  let parts=text.parts().unwrap().unwrap();assert_eq!(parts.expressions.len(),2);let before=literal_child_parses_for_test();
  let mut observed=Vec::new();for fragment in text.pinned_fragments().unwrap().unwrap(){let fragment=fragment.unwrap();let mut value=String::new();fragment.write_text(&mut value).unwrap();observed.push((value,fragment.expression().map(|e|e as *const Expr as usize)));}
  assert_eq!(observed.iter().map(|row|row.0.as_str()).collect::<Vec<_>>(),["before","middle","tail","end"]);assert_eq!(observed[0].1,None);assert_eq!(observed[1].1,None);assert_eq!(observed[2].1,Some(&parts.expressions[0]as *const Expr as usize));assert_eq!(observed[3].1,Some(&parts.expressions[1]as *const Expr as usize));assert_eq!(literal_child_parses_for_test(),before);
  let text=literal("\"a\\\r\n  b[x]c\"");text.parts().unwrap();let mut fragments=text.pinned_fragments().unwrap().unwrap();let mut first=String::new();fragments.next().unwrap().unwrap().write_text(&mut first).unwrap();assert_eq!(first,"ab");
  let plain=literal("\"plain\"");plain.parts().unwrap();assert!(plain.pinned_fragments().unwrap().is_none());let mut bytes=0;plain.visit_pinned_fragment_storage(|_,_,capacity|bytes+=capacity);assert_eq!(bytes,0);
 }
 #[test]fn native_fragment_rows_share_original_literal_lease_until_last_alias_and_survive_output_failure(){
  use std::sync::{Arc, atomic::{Ordering}};let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,8*1024*1024,&poll);let source="\"a[][x]b\"";let tokens=crate::lex_spans(source);let root=crate::prepare_setting_expression(source,&tokens.tokens,Span::new(0,source.len()),&a).unwrap();let ExprKind::Literal(text)=&root.kind else{panic!("original literal")};let alias=text.clone();let retained=counter.load(Ordering::Acquire);assert!(retained>0);let mut bytes=0;alias.visit_pinned_fragment_storage(|_,_,capacity|bytes+=capacity);assert!(bytes>=3*std::mem::size_of::<LiteralFragment>());
  struct Refused;impl fmt::Write for Refused{fn write_str(&mut self,_:&str)->fmt::Result{Err(fmt::Error)}}let fragment=alias.pinned_fragments().unwrap().unwrap().next().unwrap().unwrap();assert!(matches!(fragment.write_text(&mut Refused),Err(PinnedStaticTextError::Output(_))));drop(fragment);drop(root);assert_eq!(counter.load(Ordering::Acquire),retained);assert_eq!(alias.pinned_fragments().unwrap().unwrap().count(),3);drop(alias);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
  let tiny=crate::SettingAdmission::new(&counter,crate::SettingChargeCounter::root_allocation_bytes() + (1),&poll);assert!(matches!(crate::prepare_setting_expression(source,&tokens.tokens,Span::new(0,source.len()),&tiny),Err(crate::SettingSyntaxFailure::Operational(ref error))if error.kind()==std::io::ErrorKind::OutOfMemory));assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod pinned_child_token_tests{
 use super::*;
 #[test]fn primary_interpolation_tokens_keep_operator_points_through_comments_and_splices_without_relex(){
  let source="\"a[value /* fake.dot */ . /* fake.dot */ field]b\"";let expression=crate::parse_expression(source).expr.unwrap();let ExprKind::Literal(literal)=&expression.kind else{panic!("literal")};literal.parts().unwrap();let before=literal_child_parses_for_test();let fragments=literal.pinned_fragments().unwrap().unwrap().map(Result::unwrap).collect::<Vec<_>>();let child=fragments[1].expression().unwrap();assert!(matches!(child.kind,ExprKind::Member{..}));let tokens=fragments[1].tokens().map(Result::unwrap).filter(|(kind,_)|!matches!(kind,crate::TokenKind::Whitespace|crate::TokenKind::Newline|crate::TokenKind::Comment)).collect::<Vec<_>>();let dot=tokens.iter().find(|(_,span)|&source[span.range()]==".").unwrap();let ExprKind::Member{object,selector,..}=&child.kind else{unreachable!()};let range=Span::new(object.span.end,child.span.end-selector.len());assert!(fragments[1].tokens_between(range).unwrap().map(Result::unwrap).any(|(_,span)|span==dot.1));assert!(fragments[1].tokens_between(Span::new(child.span.start+1,child.span.start+2)).is_err());assert_eq!(dot.1.start,source.find(". /* fake.dot").unwrap());assert_eq!(literal_child_parses_for_test(),before);
  let source="\"a[value \\\n . field]b\"";let expression=crate::parse_expression(source).expr.unwrap();let ExprKind::Literal(literal)=&expression.kind else{panic!("literal")};literal.parts().unwrap();let fragment=literal.pinned_fragments().unwrap().unwrap().nth(1).unwrap().unwrap();let before=literal_child_parses_for_test();assert!(fragment.tokens().map(Result::unwrap).any(|(_,span)|span.start==source.find(". field").unwrap()));assert_eq!(literal_child_parses_for_test(),before);
 }
 #[test]fn nested_literal_children_keep_their_own_primary_geometry_under_same_native_root_lease(){
  use std::sync::{Arc, atomic::{Ordering}};let source="\"a[\"b[x . field]\"]c\"";let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=crate::SettingAdmission::new(&counter,8*1024*1024,&poll);let lexical=crate::lex_spans(source);let root=crate::prepare_setting_expression(source,&lexical.tokens,Span::new(0,source.len()),&a).unwrap();let ExprKind::Literal(outer)=&root.kind else{panic!("outer")};let first=outer.pinned_fragments().unwrap().unwrap().nth(1).unwrap().unwrap();let ExprKind::Literal(inner)=&first.expression().unwrap().kind else{panic!("inner")};let last=inner.pinned_fragments().unwrap().unwrap().nth(1).unwrap().unwrap();let before=literal_child_parses_for_test();let point=source.find(". field").unwrap();assert!(last.tokens().map(Result::unwrap).any(|(_,span)|span.start==point));assert_eq!(literal_child_parses_for_test(),before);drop(last);drop(first);drop(root);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod pinned_empty_comment_child_tests{
 use super::*;
 #[test]fn primary_comment_only_interpolation_is_an_actual_optional_empty_child(){
  let source="\"a[/* ] in a genuine comment */]b\"";let expr=crate::parse_expression(source).expr.unwrap();let ExprKind::Literal(literal)=&expr.kind else{panic!("literal")};let parts=literal.parts().unwrap().unwrap();assert!(parts.expressions.is_empty());assert_eq!(parts.template,b"a\xff\x01b");let before=literal_child_parses_for_test();let rows=literal.pinned_fragments().unwrap().unwrap().map(Result::unwrap).collect::<Vec<_>>();assert_eq!(rows.len(),2);assert!(rows.iter().all(|row|row.expression().is_none()));let mut texts=Vec::new();for row in &rows{let mut text=String::new();row.write_text(&mut text).unwrap();texts.push(text)}assert_eq!(texts,["a","b"]);assert!(rows[1].tokens().map(Result::unwrap).all(|(kind,_)|matches!(kind,crate::TokenKind::Comment|crate::TokenKind::Whitespace|crate::TokenKind::Newline)));assert_eq!(literal_child_parses_for_test(),before);
 }
}

#[cfg(test)]mod lexical_runtime_separation_tests{
 use super::*;use std::sync::{Arc, atomic::{Ordering}};
 #[test]fn runtime_escape_refusal_keeps_same_primary_fragment_children_and_no_display_reparse(){
  for raw in [r#""a\q""#,r#""a\q[value + 1]tail""#]{
   let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let checkpoint=||Ok(());let a=crate::SettingAdmission::new(&counter,8*1024*1024,&checkpoint);let lexical=crate::lex_spans(raw);let root=crate::prepare_setting_expression(raw,&lexical.tokens,Span::new(0,raw.len()),&a).unwrap();let ExprKind::Literal(value)=&root.original_expression().kind else{panic!("primary literal")};let cached=value.prepared_syntax_parts().unwrap().unwrap().unwrap();assert!(cached.runtime_error_storage().is_some());let before=literal_child_parses_for_test();let refusal=value.parts().err().unwrap().to_owned();assert!(refusal.contains("undefined text macro or escape sequence"));assert!(matches!(value.retained_parts(),Some(Err(_))));
   if raw.contains('['){let mut observed=Vec::new();for fragment in value.pinned_fragments().unwrap().unwrap(){let fragment=fragment.unwrap();let mut text=String::new();fragment.write_text(&mut text).unwrap();observed.push((text,fragment.expression().map(|node|node as*const Expr)));}assert_eq!(cached.expressions.len(),1);assert_eq!(observed[0],(r#"a\q"#.to_owned(),None));assert_eq!(observed[1],("tail".to_owned(),Some(&cached.expressions[0]as*const Expr)));}else{let mut text=String::new();assert!(value.write_pinned_static_text(&mut text).unwrap());assert_eq!(text,r#"a\q"#);}
   assert_eq!(literal_child_parses_for_test(),before,"pinned projection borrows existing child nodes");let alias=value.clone();drop(root);assert!(counter.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());drop(alias);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes(),"all new syntax/error backing drops before same retained credit");assert_eq!(string_literal_parts(raw).unwrap_err(),refusal);
  }
 }
 #[test]fn runtime_tuple_decoder_stays_refused_and_later_valid_literal_recovers(){assert!(parse_interpolated_string(r#"a\q[value]tail"#).unwrap_err().contains("undefined text macro or escape sequence"));let valid=string_literal_parts(r#""hello\n[value]""#).unwrap().unwrap();assert_eq!(valid.1.len(),1);let early=string_literal_parts(r#""a\q""#).unwrap_err();assert_eq!(string_literal_parts(r#""a\q[1 +]""#).unwrap_err(),early,"later malformed lexical child cannot replace the original runtime refusal");}
}

#[cfg(test)]mod original_data_literal_tests{
 use super::*;use crate::{OriginalLiteralData,OriginalTokenValue,SettingAdmission};use std::sync::{Arc, atomic::{Ordering}};
 #[test]fn original_static_string_beginning_bracket_or_quote_never_becomes_template_syntax(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);
  for value in ["[danger()]", "\"[x]\"", "plain\\n"]{
   let data=OriginalLiteralData::from_value_using("\"looks[like_template]\"".into(),OriginalTokenValue::String(value),&a).unwrap();let before=literal_child_parses_for_test();let text=LiteralText::from_original_data(&data,50,&a).unwrap();assert!(!text.owns_template_syntax());assert_eq!(text.syntax_parts().unwrap(),None);assert!(text.prepared_syntax_parts().is_none());assert_eq!(literal_child_parses_for_test(),before);let mut out=String::new();assert!(text.write_pinned_static_text(&mut out).unwrap());assert_eq!(out,value);assert!(text.parts().unwrap_err().contains("runtime decoder"));let rebound=text.rebind_original_using(200,&a).unwrap();assert!(rebound.original_data().unwrap().same_owner(&data));assert_eq!(rebound.original_origin(),Some(200));
  }assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn original_value_fallback_is_funded_resource_is_not_redecoded_and_shift_does_not_clone_raw(){
  let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);let mut text=LiteralText::from_original_value_data("'raw'".into(),10,OriginalTokenValue::Resource("already\\projected"),&a).unwrap();let pointer=text.raw_storage().as_ptr();let charged=counter.load(Ordering::Acquire);let mut output=String::new();assert!(text.write_pinned_resource_text(&mut output).unwrap());assert_eq!(output,"already\\projected");text.shift(20);assert_eq!(text.original_origin(),Some(30));assert_eq!(text.raw_storage().as_ptr(),pointer);assert_eq!(counter.load(Ordering::Acquire),charged);drop(text);assert_eq!(counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn immutable_header_data_never_retains_a_setting_body_anchor_or_lazy_parts(){
  let data_counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let body_counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&data_counter,1<<20,&poll);let data=OriginalLiteralData::from_value_using("\"static\"".into(),OriginalTokenValue::String("static"),&a).unwrap();
  let text=LiteralText::from_original_data(&data,5,&a).unwrap();let body=crate::SharedSettingRetention::new(crate::SettingRootLease::reserve(&body_counter,4096,1024).unwrap());text.attach_setting_retention(&body).unwrap();drop(body);assert_eq!(body_counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes(),"scalar AST must not make header DATA hold a whole body lease");let mut retention=0;text.visit_setting_retention_storage(|_,n|retention+=n);assert_eq!(retention,0);drop(text);assert!(data_counter.load(Ordering::Acquire)>crate::SettingChargeCounter::root_allocation_bytes());assert!(matches!(data.value(),OriginalTokenValue::String("static")));drop(data);assert_eq!(data_counter.load(Ordering::Acquire),crate::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn ordinary_literal_parser_and_shift_keep_existing_template_cache_path(){let mut text=LiteralText::at("\"a[x]b\"".into(),0);assert!(text.owns_template_syntax());assert_eq!(text.parts().unwrap().unwrap().expressions.len(),1);text.shift(10);assert_eq!(text.parts().unwrap().unwrap().expressions[0].span.start,13);}
}

// SAME resource value projection: slash quotes exactly one raw byte, with no
// runtime escape decoding. Only an actual unterminated receipt may authorize
// dropping its terminal slash during the old lexer's recovering value path.
pub(crate) fn visit_pinned_resource_bytes<E>(bytes:&[u8],recovering:bool,mut emit:impl FnMut(&[u8])->Result<(),E>)->Result<bool,E>{
 let(mut at,mut run)=(0,0);while at<bytes.len(){match bytes[at]{b'\\'=>{emit(&bytes[run..at])?;if at+1==bytes.len(){return Ok(recovering)}run=at+1;at+=2;},b'\''=>{emit(&bytes[run..at])?;return Ok(false)},_=>at+=1}}emit(&bytes[run..])?;Ok(true)
}

#[cfg(test)]mod original_static_runtime_tests{
 use super::*;use crate::{OriginalTokenValue,OriginalStringMode,SettingAdmission};
 #[test]fn actual_normal_mode_uses_same_escape_kernel_without_parsing_static_brackets_or_displayed_quotes(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let before=literal_child_parses_for_test();
  let value=LiteralText::from_original_value_with_mode_data("misleading displayed grammar".into(),0,OriginalTokenValue::String(r"line\n\[static\]"),OriginalStringMode::Normal,&a).unwrap();assert_eq!(value.decode_original_static_text().unwrap().unwrap(),b"line\n[static]");
  let value=LiteralText::from_original_value_with_mode_data("another grammar".into(),0,OriginalTokenValue::String("[not an expression]\""),OriginalStringMode::Normal,&a).unwrap();assert_eq!(value.decode_original_static_text().unwrap().unwrap(),b"[not an expression]\"");assert_eq!(literal_child_parses_for_test(),before);
 }
 #[test]fn actual_raw_and_generated_modes_keep_escape_bytes_literal_and_unknown_mode_never_guesses(){
  let used=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
  for mode in [OriginalStringMode::Raw,OriginalStringMode::Generated]{let value=LiteralText::from_original_value_with_mode_data("\"looks normal\"".into(),0,OriginalTokenValue::String(r"\n[static]"),mode,&a).unwrap();assert_eq!(value.decode_original_static_text().unwrap().unwrap(),br"\n[static]");}
  let unknown=LiteralText::from_original_value_data("@\"looks raw\"".into(),0,OriginalTokenValue::String(r"\n[static]"),&a).unwrap();assert!(unknown.decode_original_static_text().unwrap_err().contains("not yet issued"));
  let number=LiteralText::from_original_value_data("\"looks text\"".into(),0,OriginalTokenValue::Int(7),&a).unwrap();assert_eq!(number.decode_original_static_text().unwrap(),None);
 }
}

#[cfg(test)]
#[test]
fn original_prepared_body_parts_require_issued_template_and_exact_span() {
    let fixed = crate::SettingChargeCounter::root_allocation_bytes();
    let counter = crate::SettingChargeCounter::try_new(fixed).unwrap();
    let admission = crate::SettingAdmission::new(&counter, 1 << 20, &|| Ok(()));
    let raw = r#""head[]tail""#;
    let span = Span::new(40, 40 + raw.len());
    let mut builder = OriginalTemplateBuilder::new(&admission).unwrap();
    for (range, value) in [
        (0..6, crate::OriginalTokenValue::InterpBegin("head")),
        (6..raw.len(), crate::OriginalTokenValue::InterpEnd("tail")),
    ] {
        let fragment = crate::OriginalLiteralData::from_value_with_mode_using(
            raw[range.clone()].to_owned(), value, crate::OriginalStringMode::Normal, &admission,
        ).unwrap();
        builder.push(fragment, Span::new(span.start + range.start, span.start + range.end),
            None, &[], &admission).unwrap();
    }
    let literal = builder.finish(raw, span.start, &admission).unwrap();
    let parts = literal.original_prepared_body_parts(span).unwrap();
    assert!(std::ptr::eq(parts, literal.prepared_syntax_parts().unwrap().unwrap().unwrap()));
    assert_eq!(parts.fragments.len(), 2);
    assert!(literal.original_prepared_body_parts(Span::new(41, span.end + 1)).is_none());
    assert!(literal.original_prepared_body_parts(Span::new(40, span.end - 1)).is_none());
    let ordinary = LiteralText::at(raw.to_owned(), span.start);
    ordinary.syntax_parts().unwrap().unwrap();
    assert!(ordinary.original_prepared_body_parts(span).is_none());
    drop(literal);
    assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire), fixed);
}

#[cfg(test)]mod native_literal_layout_controls{
 use super::*;
 struct PriorLiteralPartsShape{runtime_error:Option<String>,fragments:Vec<LiteralFragment>,template:Vec<u8>,expressions:Vec<Expr>,lexical:Result<LiteralLexicalShape,LiteralLexicalError>}
 #[test]fn native_scalar_literal_status_does_not_grow_the_prior_physical_owner(){
  assert_eq!(std::mem::size_of::<LiteralParts>(),std::mem::size_of::<PriorLiteralPartsShape>());
 }
}
