//! Authoritative DM literal syntax and text-template decoding.
//! Both native emission and analysis borrow the interpolation expressions retained
//! by the issuing literal. No analyzer-specific expression parser is involved.
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

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LiteralParts {
    pub template: Vec<u8>,
    pub expressions: Vec<Expr>,
    pub lexical: Result<LiteralLexicalShape, LiteralLexicalError>,
}
#[derive(Debug)]
struct LiteralState {
    raw: String,
    origin: usize,
    parts: OnceLock<Result<Option<LiteralParts>, String>>,
    // LAST: raw/retained syntax and their physical allocations must die before
    // the same source-free quota anchor can release its final lease.
    retention: OnceLock<crate::SharedSettingRetention>,
}
/// Clones of a string literal in one issued syntax tree share its parsed
/// leaves. Numbers and resource paths do not allocate a parse cache.
#[derive(Clone, Debug)]
pub struct LiteralText(Backing);
#[derive(Clone, Debug)]
enum Backing {
    Plain(String),
    Text(LiteralOwner),
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
        retention,
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
impl LiteralText {
    /// Emit the pinned lexer's STATIC String token spelling from already-issued
    /// original parts. Escapes remain lexical bytes; only the existing pinned
    /// splice scanner removes escaped newline/indentation. Never parses children.
    pub fn write_pinned_static_text(&self,out:&mut impl fmt::Write)->Result<bool,PinnedStaticTextError>{
        let Some((is_raw,value))=literal_content(self.as_str())else{
            return if self.as_str().starts_with('@'){Err(PinnedStaticTextError::UnsupportedDelimiter)}else{Ok(false)}
        };
        let parts=match self.retained_parts(){Some(Ok(Some(parts)))=>parts,Some(Err(_))=>return Err(PinnedStaticTextError::DeferredSyntax),_=>return Err(PinnedStaticTextError::Unprepared)};
        let shape=parts.lexical.map_err(PinnedStaticTextError::Lexical)?;
        if shape.interpolated{return Ok(false)}
        if is_raw{out.write_str(value).map_err(PinnedStaticTextError::Output)?;return Ok(true)}
        let mut observed=LiteralLexicalShape{interpolated:false,pinned_segment_nonempty:false};let mut error=None;
        visit_pinned_segment(value.as_bytes(),&mut observed,&mut error,|bytes|out.write_str(std::str::from_utf8(bytes).expect("literal ranges end at original ASCII splice boundaries"))).map_err(PinnedStaticTextError::Output)?;
        if let Some(error)=error{return Err(PinnedStaticTextError::Lexical(error))}
        Ok(true)
    }

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
                retention: OnceLock::new(),
            })))
        } else {
            Self(Backing::Plain(raw))
        }
    }
    pub fn raw_storage(&self) -> &String {
        match &self.0 {
            Backing::Plain(raw) => raw,
            Backing::Text(state) => &state.raw,
        }
    }
    pub fn as_str(&self) -> &str {
        self.raw_storage()
    }
    /// Read-only census; never computes or retains additional syntax.
    pub fn shared_storage(&self) -> Option<(usize, usize)> {
        match &self.0 {
            Backing::Plain(_) => None,
            Backing::Text(state) => Some((
                state.address(),
                std::mem::size_of::<LiteralState>() + 2 * std::mem::size_of::<usize>(),
            )),
        }
    }
    pub fn retained_parts(&self) -> Option<Result<Option<&LiteralParts>, &String>> {
        match &self.0 {
            Backing::Plain(_) => None,
            Backing::Text(state) => state.parts.get().map(|p| p.as_ref().map(Option::as_ref)),
        }
    }
    pub fn parts(&self) -> Result<Option<&LiteralParts>, &str> {
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
            .map(|parts| parts.as_ref())
            .map_err(String::as_str)
    }
    pub(crate) fn require_fresh_body_owner(&self,a:&crate::SettingAdmission<'_>)->std::io::Result<()>{
        let Backing::Text(state)=&self.0 else{return a.checkpoint()};
        if Arc::strong_count(state.0.as_ref().expect("live literal owner"))!=1||state.parts.get().is_some()||state.retention.get().is_some(){
            a.record_operational_error(std::io::Error::new(std::io::ErrorKind::InvalidInput,"native body literal requires its fresh unpublished original owner"));
            return Err(std::io::ErrorKind::InvalidInput.into());
        }
        a.checkpoint()
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
    pub(crate) fn attach_setting_retention(
        &self,
        anchor: &crate::SharedSettingRetention,
    ) -> std::io::Result<()> {
        let Backing::Text(state) = &self.0 else {
            return Ok(());
        };
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
        if let Backing::Text(state) = &self.0 {
            if offset != 0 {
                let anchor = state.retention.get().cloned();
                let shifted = Self::at(state.raw.clone(), state.origin + offset);
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
        self.as_str() == other.as_str()
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
     return Ok(Some(LiteralParts{template:value.as_bytes().to_vec(),expressions:Vec::new(),lexical:Ok(LiteralLexicalShape{interpolated:false,pinned_segment_nonempty:!projection.segment(value.as_ptr() as usize-raw.as_ptr() as usize,value.len()).is_empty()})}));
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
    fn segment(self, start: usize, len: usize) -> &'a [u8] {
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
        &self.original.as_bytes()[start..end]
    }
}
/// This scan never recognizes interpolation grammar. It observes only literal
/// segment ranges already issued by the one primary parser. Pinned read_string
/// retains ordinary escape bytes, but consumes an escaped CR or LF followed by
/// skip_ws(true): all CR/indentation and at most one additional LF.
fn observe_segment(raw:&[u8],shape:&mut LiteralLexicalShape,error:&mut Option<LiteralLexicalError>){
 let result=visit_pinned_segment(raw,shape,error,|_|Ok::<(),std::convert::Infallible>(()));
 match result{Ok(())=>(),Err(never)=>match never{}}
}

fn visit_pinned_segment<E>(
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

fn parse_interpolated_string_clean(
    value: &str,
    projection: RawProjection<'_>,
    admission: Option<&crate::SettingAdmission<'_>>,
) -> Result<LiteralParts, String> {
    let mut template = Vec::new();
    let mut expressions = Vec::new();
    let mut next_marker = None;
    let mut substituted = false;
    let mut lexical = LiteralLexicalShape {
        interpolated: false,
        pinned_segment_nonempty: false,
    };
    let mut segment_start = 0;
    let mut segment_error = None;
    let mut at = 0;
    while at < value.len() {
        if let Some(admission) = admission {
            admission
                .checkpoint()
                .map_err(|_| "interpolation operation stopped".to_owned())?;
        }
        let ch = value[at..].chars().next().unwrap();
        if ch == '\\' {
            at += 1;
            let rest = &value[at..];
            if rest.starts_with("\r\n") || rest.starts_with('\n') {
                at += if rest.starts_with("\r\n") { 2 } else { 1 };
                while at < value.len()
                    && matches!(value.as_bytes()[at], b' ' | b'\t' | b'\r' | b'\n')
                {
                    at += 1;
                }
                continue;
            }
            if rest.starts_with(' ') {
                at += 1;
                continue;
            }
            if let Some(consumed) = numeric_escape(rest, &mut template) {
                at += consumed;
                continue;
            }
            if rest.starts_with("...") {
                template.extend([0xff, 0x12]);
                at += 3;
                continue;
            }
            // DreamMaker reads the whole letter run after `\` as a macro name. A run
            // that names no applicable macro falls back to a one-letter escape
            // (`\n`, `\t`) followed by literal text, or is an error: `"\red"` is the
            // red formatting macro and `"\redb"` is invalid, never `\r` + "ed".
            let word_len = rest.bytes().take_while(u8::is_ascii_alphabetic).count();
            if word_len != 0 {
                let word = &rest[..word_len];
                let after = &rest[word_len..];
                if let Some(effect) = text_macro(word, after, &template, substituted)? {
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
                            next_marker = Some(0x03);
                            at += 1;
                        }
                        TextMacro::NextExpression(marker) => next_marker = Some(marker),
                        TextMacro::Ordinal => {
                            let last = template.len() - 1;
                            template[last] = 0x05;
                        }
                    }
                    continue;
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
                    return Err(format!(
                        "undefined text macro or escape sequence: \\{}",
                        &rest[..word_len]
                    ))
                }
                _ => return Err(format!("unsupported string escape: \\{escape}")),
            };
            template.extend_from_slice(escaped.as_bytes());
            at += escape.len_utf8();
            continue;
        }
        if ch == '[' {
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
            let parsed = match admission {
                Some(a) => crate::expression_parser::parse_expression_with_admission(&source, a),
                None => parse_expression(&source),
            };
            if admission.is_some_and(|a| a.is_stopped()) {
                return Err("interpolation operation stopped".into());
            }
            if !parsed.diagnostics.is_empty() {
                return Err("invalid string interpolation expression".into());
            }
            let mut expression = parsed.expr.ok_or("empty string interpolation")?;
            remap(&mut expression, &positions, raw_expression);
            shift_expression(&mut expression, start + leading);
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
        template.extend_from_slice(ch.encode_utf8(&mut bytes).as_bytes());
        at += ch.len_utf8();
    }
    observe_segment(
        projection.segment(segment_start, value.len() - segment_start),
        &mut lexical,
        &mut segment_error,
    );
    Ok(LiteralParts {
        template,
        expressions,
        lexical: segment_error.map_or(Ok(lexical), Err),
    })
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
fn remap(expression: &mut Expr, positions: &[usize], source: &str) {
    let span = expression.span;
    let start = positions.get(span.start).copied().unwrap_or(source.len());
    let end = if span.end == span.start {
        start
    } else {
        positions
            .get(span.end - 1)
            .map_or(source.len(), |at| at + 1)
    };
    expression.span = Span::new(start, end);
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
    retained_string_literal_parts(raw)
        .map(|parts| parts.map(|parts| (parts.template, parts.expressions)))
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
    use std::{
        cell::Cell,
        sync::{
            atomic::{AtomicUsize, Ordering},
            Arc,
        },
    };
    #[test]
    fn admitted_literal_parts_preserve_original_projection_anchors_and_warm_owner() {
        for raw in [
            "\"before [callee(2)] after\"",
            "\"prefix\r [outer(\\\r\n    \"[inner()]\")] end\"",
            "@\"raw [not_a_child()]\"",
            "\"é [callee(2)] \\the [name]\"",
        ] {
            let native = LiteralText::at(raw.to_owned(), 123);
            let copy = native.clone();
            let old = LiteralText::at(raw.to_owned(), 123);
            let counter = Arc::new(AtomicUsize::new(0));
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
            assert!(counter.load(Ordering::Acquire) > 0);
            drop(native);
            drop(copy);
            drop(old);
            drop(lease);
            assert_eq!(counter.load(Ordering::Acquire), 0);
        }
    }
    #[test]
    fn admitted_literal_cancellation_leaves_failed_literal_cache_unset_and_retries() {
        let text = LiteralText::at("\"[callee(1)]\"".into(), 77);
        let alias = text.clone();
        let counter = Arc::new(AtomicUsize::new(37));
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
            37,
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
            let counter = Arc::new(AtomicUsize::new(0));
            let healthy = || Ok(());
            let admission = crate::SettingAdmission::new(&counter, 1024 * 1024, &healthy);
            native.prepare_parts_admitted(&admission).unwrap();
            assert_eq!(native.parts().unwrap_err(), old.parts().unwrap_err());
            assert!(matches!(native.retained_parts(), Some(Err(_))));
            assert!(admission.take_operational_error().is_none());
        }
        let native = LiteralText::at("\"[outer(\"[inner()]\")]\"".into(), 0);
        let counter = Arc::new(AtomicUsize::new(0));
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
    use std::sync::atomic::{AtomicUsize, Ordering};
    fn anchor(counter: &Arc<AtomicUsize>, bytes: usize) -> crate::SharedSettingRetention {
        crate::SharedSettingRetention::new(
            crate::SettingRootLease::reserve(counter, 1024 * 1024, bytes).unwrap(),
        )
    }
    #[test]
    fn cloned_literal_keeps_same_credit_after_root_anchor_drops_until_last_alias() {
        let counter = Arc::new(AtomicUsize::new(0));
        let held = anchor(&counter, 4096);
        let text = LiteralText::at("\"[callee(1)]\"".into(), 0);
        let alias = text.clone();
        text.attach_setting_retention(&held).unwrap();
        assert_eq!(text.parts().unwrap().unwrap().expressions.len(), 1);
        drop(held);
        drop(text);
        assert_eq!(counter.load(Ordering::Acquire), 4096);
        drop(alias);
        assert_eq!(counter.load(Ordering::Acquire), 0);
    }
    #[test]
    fn foreign_anchor_refuses_and_last_parts_move_keep_credit_until_iterative_cleanup() {
        let counter = Arc::new(AtomicUsize::new(0));
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
        assert_eq!(counter.load(Ordering::Acquire), 2048);
        crate::setting_drop::drop_literal_parts(parts, retention);
        assert_eq!(counter.load(Ordering::Acquire), 0);
    }
    #[test]
    fn shifted_surviving_literal_alias_does_not_lose_original_retention() {
        let counter = Arc::new(AtomicUsize::new(0));
        let held = anchor(&counter, 1024);
        let text = LiteralText::at("\"[x]\"".into(), 0);
        text.attach_setting_retention(&held).unwrap();
        let mut alias = text.clone();
        drop(text);
        drop(held);
        alias.shift(10);
        assert_eq!(counter.load(Ordering::Acquire), 1024);
        drop(alias);
        assert_eq!(counter.load(Ordering::Acquire), 0);
    }
    #[test]
    fn concurrent_literal_aliases_release_credit_exactly_once() {
        let counter = Arc::new(AtomicUsize::new(0));
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
        assert_eq!(counter.load(Ordering::Acquire), 0);
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
  for(source,expected)in[(r#""é\n\[text]""#,r"é\n\[text]"),("\"left\\\r\n \t right\"","leftright"),("\"left\\\n\n  right\"","leftright"),("{\"first\nsecond\"}","first\nsecond"),("@\"[raw]\\n\"","[raw]\\n"),("@{\"é\r\n[raw]\"}","é\r\n[raw]")]{
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
