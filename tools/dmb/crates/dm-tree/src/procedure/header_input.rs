//! Private original header input on the EXISTING declaration syntax owner.
//! Never serialized, never a filesystem receipt, never an alternate DM parser.
use super::{header::HeaderView, ParsedSignature, SignatureError};
use dm_ir::SymbolTable;
use dm_preprocess::SourceText;
use dm_syntax::{Item, ItemKind, Span, SpanToken, TokenKind};
use std::sync::{Arc, OnceLock};
#[path = "setting_input.rs"]
mod setting_input;
pub(crate) use setting_input::SettingFootprint;
#[derive(Debug)]
pub(crate) struct OriginalProcedureHeaders {
    source: SourceText,
    headers: Vec<Span>,
    tokens: Vec<SpanToken>,
    settings: OnceLock<Vec<setting_input::OriginalSettingsBody>>,
    checker_diagnostic_settings: bool,
    initializer_coordinates: Option<OriginalInitializerCoordinates>,
    initializer_roots: dm_syntax::SettingExpressionSlots,
    initializer_facts: OnceLock<OriginalInitializerFactsAdmission>,
}
fn reserve<T>(v: &mut Vec<T>, n: usize) -> Result<(), OriginalHeaderFailure> {
    n.checked_mul(std::mem::size_of::<T>()).ok_or_else(|| {
        OriginalHeaderFailure::Operational(std::io::Error::new(
            std::io::ErrorKind::OutOfMemory,
            "header recipe capacity overflow",
        ))
    })?;
    v.try_reserve_exact(n).map_err(|actual| {
        OriginalHeaderFailure::Operational(std::io::Error::new(
            std::io::ErrorKind::OutOfMemory,
            HeaderAllocationRefusal(actual),
        ))
    })
}
#[derive(Debug)]
struct HeaderAllocationRefusal(std::collections::TryReserveError);
impl std::fmt::Display for HeaderAllocationRefusal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("header recipe allocation refused")
    }
}
impl std::error::Error for HeaderAllocationRefusal {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.0)
    }
}
/// Early declaration resource refusal is operational, never an AdapterError.
/// The existing compatibility constructor continues returning its original text.
pub(crate) enum OriginalHeaderFailure {
    Source(String),
    Operational(std::io::Error),
}
impl From<String> for OriginalHeaderFailure {
    fn from(value: String) -> Self {
        Self::Source(value)
    }
}
impl From<&str> for OriginalHeaderFailure {
    fn from(value: &str) -> Self {
        Self::Source(value.into())
    }
}
impl From<std::io::Error> for OriginalHeaderFailure {
    fn from(value: std::io::Error) -> Self {
        Self::Operational(value)
    }
}
/// Private completed-producer witness; source/facts authority still comes from
/// the SAME original contribution/header join. Portable cached facts cannot set
/// this by source equality, and coordinates alone are insufficient.
#[derive(Debug, PartialEq, Eq)]
struct OriginalInitializerFactsAdmission {
    coordinates: usize,
    declarations: usize,
}
fn finish_original_admission<T>(
    result: Result<T, OriginalHeaderFailure>,
    a: &dm_syntax::SettingAdmission<'_>,
) -> Result<T, OriginalHeaderFailure> {
    match result {
        Err(OriginalHeaderFailure::Operational(actual)) => Err(OriginalHeaderFailure::Operational(
            a.take_operational_error().unwrap_or(actual),
        )),
        result => {
            let status = a.checkpoint();
            if let Some(actual) = a.take_operational_error() {
                return Err(OriginalHeaderFailure::Operational(actual));
            }
            status?;
            result
        }
    }
}
fn original_checkpoint(a: &dm_syntax::SettingAdmission<'_>) -> std::io::Result<()> {
    a.checkpoint()
        .map_err(|proxy| a.take_operational_error().unwrap_or(proxy))
}
struct OriginalInitializerCoordinates {
    // Actual source coordinates only, never variable/type/namespace semantics.
    // Physical buffer release precedes quota credit.
    spans: Vec<Span>,
    lease: dm_syntax::SettingRootLease,
}
impl std::fmt::Debug for OriginalInitializerCoordinates {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OriginalInitializerCoordinates")
            .field("len", &self.spans.len())
            .finish_non_exhaustive()
    }
}
impl OriginalInitializerCoordinates {
    fn new(a: &dm_syntax::SettingAdmission<'_>) -> std::io::Result<Self> {
        Ok(Self {
            spans: Vec::new(),
            lease: a.reserve(
                std::mem::size_of::<Self>()
                    + std::mem::size_of::<OnceLock<OriginalInitializerFactsAdmission>>(),
            )?,
        })
    }
    fn push(&mut self, span: Span, a: &dm_syntax::SettingAdmission<'_>) -> std::io::Result<()> {
        a.checkpoint()?;
        if self.spans.len() == self.spans.capacity() {
            let capacity = self.spans.capacity().max(4).checked_mul(2).ok_or_else(|| {
                std::io::Error::new(
                    std::io::ErrorKind::OutOfMemory,
                    "initializer coordinate capacity overflow",
                )
            })?;
            let bytes = capacity
                .checked_mul(std::mem::size_of::<Span>())
                .and_then(|n| n.checked_mul(4))
                .and_then(|n| {
                    n.checked_add(
                        std::mem::size_of::<Self>()
                            + std::mem::size_of::<OnceLock<OriginalInitializerFactsAdmission>>(),
                    )
                })
                .ok_or_else(|| {
                    std::io::Error::new(
                        std::io::ErrorKind::OutOfMemory,
                        "initializer coordinate admission overflow",
                    )
                })?;
            // Full old/new replacement overlap is reserved before allocation.
            // The retained conservative peak is never credited early.
            let additional = bytes.saturating_sub(self.lease.bytes());
            a.grow(&mut self.lease, additional)?;
            let mut next = Vec::new();
            next.try_reserve_exact(capacity).map_err(|_| {
                std::io::Error::new(
                    std::io::ErrorKind::OutOfMemory,
                    "initializer coordinate allocation refused",
                )
            })?;
            if next.capacity() > capacity * 2 {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::OutOfMemory,
                    "initializer coordinate exposed capacity exceeds admitted envelope",
                ));
            }
            next.extend_from_slice(&self.spans);
            self.spans = next;
        }
        self.spans.push(span);
        Ok(())
    }
}
fn spans(
    items: &[Item],
    offset: usize,
    source: &str,
    out: &mut Vec<Span>,
    coordinates: &mut Option<OriginalInitializerCoordinates>,
    admission: Option<&dm_syntax::SettingAdmission<'_>>,
) -> Result<(), OriginalHeaderFailure> {
    for item in items {
        let wants_header =
            coordinates.is_some() || matches!(item.kind, ItemKind::Proc | ItemKind::Verb);
        let span = if wants_header {
            let span = Span::new(
                item.header_span
                    .start
                    .checked_sub(offset)
                    .ok_or("header starts before chunk")?,
                item.header_span
                    .end
                    .checked_sub(offset)
                    .ok_or("header ends before chunk")?,
            );
            if coordinates.is_some() {
                source
                    .get(span.range())
                    .ok_or("original declaration header extent unavailable")?;
            }
            if let (Some(coordinates), Some(admission)) = (coordinates.as_mut(), admission) {
                coordinates.push(span, admission)?;
            }
            span
        } else {
            Span::new(0, 0)
        };
        if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
            if source.get(span.range()) != Some(item.header.as_str()) {
                return Err("original procedure header differs from its declaration source".into());
            }
            reserve(out, 1)?;
            out.push(span);
        } else {
            spans(&item.children, offset, source, out, coordinates, admission)?;
        }
    }
    Ok(())
}

/// Original variable partition after the EXISTING adapter has selected its
/// actual Var namespace. Declaration prefix is the existing normalized path;
/// RHS borrows only the original primary token owner. No scalar meaning here.
pub(crate) struct IssuedVariableParts<'owner, 'normalized> {
    owner: &'owner OriginalProcedureHeaders,
    header: Span,
    offset: usize,
    declaration: &'normalized str,
    initializer: Option<HeaderView<'owner>>,
}
impl IssuedVariableParts<'_, '_> {
    pub(crate) fn declaration(&self) -> &str {
        self.declaration
    }
    pub(crate) fn initializer_text(&self) -> Option<&str> {
        self.initializer.map(|v| v.text())
    }
    pub(crate) fn symbolic(
        &self,
        symbols: &mut SymbolTable,
    ) -> Result<Option<dm_ir::SymbolicExpression>, String> {
        self.initializer
            .map(|view| super::expression_view(view, symbols))
            .transpose()
    }
    pub(crate) fn constant(
        &self,
        expression: &dm_ir::SymbolicExpression,
        symbols: &mut SymbolTable,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<Option<dm_ir::SemanticValue>, OriginalHeaderFailure> {
        let result = (|| {
            let Some(_) = self.initializer else {
                return Ok(None);
            };
            let root = match self.owner.prepare_initializer(
                self.header,
                self.offset,
                true,
                expression,
                symbols,
                a,
            )? {
                Ok(root) => root,
                Err(_syntax) => return Ok(None), // exact old eager constant-fold policy
            };
            // SAME preserved scalar interpreter and SAME old callbacks. Unknown,
            // syntax/runtime/string/resource values stay unfurled exactly.
            crate::constants::evaluate_expr_with_resources(
                root.original_expression(),
                |_| None,
                |_| None,
                |_| None,
                |_| None,
            )
            .map(|value| value.to_semantic(symbols))
            .transpose()
            .map_err(|message| OriginalHeaderFailure::Source(message.to_string()))
        })();
        finish_original_admission(result, a)
    }
}
impl OriginalProcedureHeaders {
    /// Move the ORIGINAL cold lexer Vec into the EXISTING declaration input.
    /// Header and body consumers borrow ranges; no separate per-body token owner.
    pub(crate) fn from_primary(
        source: SourceText,
        items: &[Item],
        offset: usize,
        tokens: Vec<SpanToken>,
    ) -> Result<Arc<Self>, String> {
        Self::from_primary_inner(source, items, offset, tokens, None, false).map_err(|failure| {
            match failure {
                OriginalHeaderFailure::Source(message) => message,
                OriginalHeaderFailure::Operational(actual) => actual.to_string(),
            }
        })
    }
    /// Explicit checked builder-only source inventory. No variable namespace,
    /// expression root or scalar meaning is issued by this coordinate roster.
    /// The builder supplies its SAME existing counter/worker permit; no Db is
    /// created or entered from this original-source leaf.
    pub(crate) fn from_primary_admitted(
        source: SourceText,
        items: &[Item],
        offset: usize,
        tokens: Vec<SpanToken>,
        admission: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<Arc<Self>, OriginalHeaderFailure> {
        let result = Self::from_primary_inner(source, items, offset, tokens, Some(admission), false);
        finish_original_admission(result, admission)
    }
    fn from_primary_inner(
        source: SourceText,
        items: &[Item],
        offset: usize,
        tokens: Vec<SpanToken>,
        admission: Option<&dm_syntax::SettingAdmission<'_>>,
        checker_diagnostic_settings: bool,
    ) -> Result<Arc<Self>, OriginalHeaderFailure> {
        let mut headers = Vec::new();
        let mut coordinates = admission
            .map(OriginalInitializerCoordinates::new)
            .transpose()?;
        spans(
            items,
            offset,
            &source,
            &mut headers,
            &mut coordinates,
            admission,
        )?;
        headers.sort_unstable_by_key(|s| s.start);
        if headers.windows(2).any(|p| p[0].end > p[1].start) {
            return Err("original procedure header ranges overlap".into());
        }
        if let Some(coordinates) = coordinates.as_mut() {
            coordinates.spans.sort_unstable_by_key(|s| s.start);
            if coordinates.spans.windows(2).any(|p| p[0].end > p[1].start) {
                return Err("original declaration header coordinates overlap".into());
            }
        }
        if tokens.iter().any(|t| source.get(t.span.range()).is_none())
            || tokens.windows(2).any(|p| p[0].span.end > p[1].span.start)
        {
            return Err("original declaration token ranges differ".into());
        }
        if let Some(a) = admission {
            a.checkpoint()?;
        }
        Ok(Arc::new(Self {
            source,
            headers,
            tokens,
            settings: OnceLock::new(),
            checker_diagnostic_settings,
            initializer_coordinates: coordinates,
            initializer_roots: Default::default(),
            initializer_facts: OnceLock::new(),
        }))
    }
    pub(crate) fn initializer_coordinate(
        &self,
        header: Span,
        offset: usize,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<(usize, usize), OriginalHeaderFailure> {
        let row = self.initializer_coordinates.as_ref().ok_or_else(|| {
            OriginalHeaderFailure::Operational(std::io::Error::new(
                std::io::ErrorKind::NotConnected,
                "original initializer coordinate inventory was not admitted",
            ))
        })?;
        if !a.matches_lease_domain(&row.lease) {
            return Err(OriginalHeaderFailure::Operational(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "original initializer coordinate counter differs",
            )));
        }
        original_checkpoint(a)?;
        let relative = Span::new(
            header
                .start
                .checked_sub(offset)
                .ok_or("initializer header starts before chunk")?,
            header
                .end
                .checked_sub(offset)
                .ok_or("initializer header ends before chunk")?,
        );
        let ordinal = row
            .spans
            .binary_search_by_key(&relative.start, |span| span.start)
            .map_err(|_| "original initializer header coordinate unavailable")?;
        if row.spans[ordinal] != relative {
            return Err("original initializer header coordinate differs".into());
        }
        Ok((ordinal, row.spans.len()))
    }
    /// Portable facts never carry token authority. Reissue ONE current original
    /// token stream through the SAME primary lexer, without rereading source.
    pub(crate) fn reissue(
        source: SourceText,
        items: &[Item],
        offset: usize,
    ) -> Result<Arc<Self>, String> {
        let parsed = dm_syntax::lex_spans(&source);
        if !parsed.diagnostics.is_empty() {
            return Err("original cached declaration token reissue failed".into());
        }
        Self::from_primary(source, items, offset, parsed.tokens)
    }
    /// Portable facts supply no original producer/root admission. Their exact
    /// current token view is reissued through the existing lexer, then admitted
    /// in the SAME original header pass. Metadata still needs checked adapter.
    pub(crate) fn reissue_admitted(
        source: SourceText,
        items: &[Item],
        offset: usize,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<Arc<Self>, OriginalHeaderFailure> {
        original_checkpoint(a)?;
        let parsed = dm_syntax::lex_spans(&source);
        original_checkpoint(a)?;
        if !parsed.diagnostics.is_empty() {
            return Err("original cached declaration token reissue failed".into());
        }
        Self::from_primary_admitted(source, items, offset, parsed.tokens, a)
    }
    /// Only a successful CHECKED adapter return can construct this token. It
    /// observed the same full walk, actual facts and validated header receipt;
    /// this owner stores no copied facts/semantic index/extra Arc.
    pub(crate) fn complete_initializer_admission(
        &self,
        completed: crate::adapter::CompletedInitializerAdapter<'_, '_>,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<(), OriginalHeaderFailure> {
        if !std::ptr::eq(self, completed.header_owner()) {
            return Err(OriginalHeaderFailure::Operational(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "initializer producer completed a foreign original header",
            )));
        }
        let row = self.initializer_coordinates.as_ref().ok_or_else(|| {
            OriginalHeaderFailure::Operational(std::io::Error::new(
                std::io::ErrorKind::NotConnected,
                "initializer producer lacks admitted original coordinates",
            ))
        })?;
        if !a.matches_lease_domain(&row.lease) {
            return Err(OriginalHeaderFailure::Operational(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "initializer producer completed under foreign counter",
            )));
        }
        let facts = completed.facts();
        if facts.skeletons.len() != facts.origins.len() {
            return Err("initializer producer fact/origin roster differs".into());
        }
        let witness = OriginalInitializerFactsAdmission {
            coordinates: row.spans.len(),
            declarations: facts.skeletons.len(),
        };
        original_checkpoint(a)?;
        if let Err(witness) = self.initializer_facts.set(witness) {
            if self.initializer_facts.get() != Some(&witness) {
                return Err("completed initializer producer roster differs".into());
            }
        }
        Ok(())
    }
    /// Cache-resource check only: exact current source/contribution binding is
    /// still the caller's existing proof. Missing/foreign admission means a real
    /// producer decline; actual checkpoint failure remains operational.
    pub(crate) fn initializer_admission_matches(
        &self,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> std::io::Result<bool> {
        original_checkpoint(a)?;
        Ok(self
            .initializer_coordinates
            .as_ref()
            .zip(self.initializer_facts.get())
            .is_some_and(|(row, witness)| {
                a.matches_lease_domain(&row.lease) && row.spans.len() == witness.coordinates
            }))
    }
    pub(crate) fn variable_parts<'owner, 'normalized>(
        &'owner self,
        header: Span,
        offset: usize,
        normalized: &'normalized str,
    ) -> Result<IssuedVariableParts<'owner, 'normalized>, String> {
        let relative = Span::new(
            header
                .start
                .checked_sub(offset)
                .ok_or("variable header starts before original chunk")?,
            header
                .end
                .checked_sub(offset)
                .ok_or("variable header ends before original chunk")?,
        );
        let first = self
            .tokens
            .partition_point(|t| t.span.start < relative.start);
        let last = self.tokens.partition_point(|t| t.span.start < relative.end);
        let view = HeaderView::original(&self.source, &self.tokens[first..last], relative)?;
        let (declaration, initializer) = if let Some(at) = view.assignment_index() {
            let suffix = &view.text()[at..];
            let declaration = normalized
                .strip_suffix(suffix)
                .ok_or("normalized variable initializer suffix differs from original source")?
                .trim();
            (declaration, Some(self.initializer_rhs(relative, true)?))
        } else {
            (normalized, None)
        };
        Ok(IssuedVariableParts {
            owner: self,
            header,
            offset,
            declaration,
            initializer,
        })
    }
    fn initializer_rhs(&self,header:Span,variable:bool)->Result<HeaderView<'_>,String>{self.initializer_rhs_optional(header,variable)?.ok_or_else(||"original initializer assignment unavailable".into())}
    pub(crate) fn has_authored_initializer(&self,header:Span,variable:bool)->Result<bool,String>{Ok(self.initializer_rhs_optional(header,variable)?.is_some())}
    fn initializer_rhs_optional(&self, header: Span, variable: bool) -> Result<Option<HeaderView<'_>>, String> {
        self.source
            .get(header.range())
            .ok_or("initializer header outside original source")?;
        let first = self.tokens.partition_point(|t| t.span.start < header.start);
        let last = self.tokens.partition_point(|t| t.span.start < header.end);
        let view = HeaderView::original(&self.source, &self.tokens[first..last], header)?;
        let Some(assignment)=view.assignment_index() else{return Ok(None)};
        let mut rhs = view.slice(assignment + 1, view.text().len()).trim();
        if variable {
            let end = rhs
                .first_top_level("as")
                .map_or(rhs.text().len(), |span| span.start);
            rhs = rhs.slice(0, end).trim();
        }
        Ok(Some(rhs))
    }
    /// Same unique symbolic token projection as all other original headers;
    /// native adapter supplies its actual variable namespace/context separately.
    pub(crate) fn authored_initializer(
        &self,
        header: Span,
        offset: usize,
        variable: bool,
        symbols: &mut SymbolTable,
    ) -> Result<dm_ir::SymbolicExpression, String> {
        let relative = Span::new(
            header
                .start
                .checked_sub(offset)
                .ok_or("initializer header starts before chunk")?,
            header
                .end
                .checked_sub(offset)
                .ok_or("initializer header ends before chunk")?,
        );
        super::expression_view(self.initializer_rhs(relative, variable)?, symbols)
    }
    /// Existing post-tree compatibility issuer can keep its original arena
    /// coordinate until the explicit admitted builder is selected. Both routes
    /// use THIS one original header-owned slot family, never sibling caches.
    pub(crate) fn initializer_slot_coordinate(
        &self,
        header: Span,
        fallback: (usize, usize),
    ) -> Result<(usize, usize), String> {
        let Some(row) = &self.initializer_coordinates else {
            return Ok(fallback);
        };
        let ordinal = row
            .spans
            .binary_search_by_key(&header.start, |s| s.start)
            .map_err(|_| "original initializer coordinate unavailable")?;
        if row.spans[ordinal] != header {
            return Err("original initializer coordinate extent differs".into());
        }
        Ok((ordinal, row.spans.len()))
    }
    pub(crate) fn initializer_slots(&self) -> &dm_syntax::SettingExpressionSlots {
        &self.initializer_roots
    }
    pub(crate) fn visit_initializer_roots(&self, visit: impl FnMut(&dm_syntax::SettingExpression)) {
        self.initializer_roots.visit_storage(|_, _, _| {}, visit);
    }
    /// EARLY adapter-only original root. Syntax rejection is returned separately
    /// because old eager constant folding deliberately leaves an unfurled value
    /// on syntax failure. Real operational refusal must exit the typed builder.
    /// This method authenticates source tokens/coordinate/counter, not a variable
    /// namespace or scalar lookup context; only the existing adapter issues that.
    pub(crate) fn prepare_initializer(
        &self,
        header: Span,
        offset: usize,
        variable: bool,
        expression: &dm_ir::SymbolicExpression,
        symbols: &SymbolTable,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<Result<dm_syntax::SettingExpression, dm_syntax::Diagnostic>, OriginalHeaderFailure>
    {
        let (ordinal, count) = self.initializer_coordinate(header, offset, a)?;
        let relative = Span::new(header.start - offset, header.end - offset);
        let (source, tokens, value) =
            self.initializer_tokens(relative, variable, expression, symbols)?;
        match self.initializer_roots.obtain(ordinal, count, a, || {
            dm_syntax::prepare_setting_expression(source, tokens, value, a)
        }) {
            Ok(root) => Ok(Ok(root)),
            Err(dm_syntax::SettingSyntaxFailure::Syntax(error)) => Ok(Err(error)),
            Err(dm_syntax::SettingSyntaxFailure::Operational(actual)) => Err(
                OriginalHeaderFailure::Operational(a.take_operational_error().unwrap_or(actual)),
            ),
        }
    }
    pub(crate) fn initializer_tokens<'a>(
        &'a self,
        header: Span,
        variable: bool,
        expression: &dm_ir::SymbolicExpression,
        symbols: &SymbolTable,
    ) -> Result<(&'a SourceText, &'a [SpanToken], Span), String> {
        let rhs = self.initializer_rhs(header, variable)?;
        self.original_expression_tokens(rhs,expression,symbols)
    }
    fn original_expression_tokens<'a>(&'a self,rhs:HeaderView<'a>,expression:&dm_ir::SymbolicExpression,symbols:&SymbolTable)->Result<(&'a SourceText,&'a[SpanToken],Span),String>{
        let mut symbolic = expression.tokens.iter();
        for token in rhs.tokens().iter().filter(|t| {
            !matches!(
                t.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        }) {
            let expected = symbolic
                .next()
                .ok_or("original initializer primary token count differs")?;
            if expected.kind != token.kind
                || expected.relative_span != rhs.relative_span(token)
                || symbols.text(expected.text) != Some(rhs.spelling(token))
            {
                return Err("initializer differs from its original primary token geometry".into());
            }
        }
        if symbolic.next().is_some() || expression.tokens.is_empty() {
            return Err("original initializer primary token count differs".into());
        }
        Ok((&self.source, rhs.tokens(), rhs.span()))
    }
    /// Exact issued dimension subview from the SAME array declaration grammar
    /// used by metadata production. Empty suffixes have no expression root.
    pub(crate) fn initializer_dimension_views(&self,header:Span)->Result<super::ArrayDimensions<'_>,String>{
        self.source.get(header.range()).ok_or("dimension header outside original source")?;
        let first=self.tokens.partition_point(|t|t.span.start<header.start);let last=self.tokens.partition_point(|t|t.span.start<header.end);
        let whole=HeaderView::original(&self.source,&self.tokens[first..last],header)?;
        let end=whole.assignment_index().unwrap_or(whole.text().len());let declaration=whole.slice(0,end).trim();
        let end=declaration.text().find(" as ").unwrap_or(declaration.text().len());
        Ok(super::array_dimensions(declaration.slice(0,end).trim()))
    }
    pub(crate) fn dimension_tokens_view<'a>(&'a self,view:HeaderView<'a>,expression:Option<&dm_ir::SymbolicExpression>,symbols:&SymbolTable)->Result<Option<(&'a SourceText,&'a[SpanToken],Span)>,String>{
        let span=view.span();let source=self.source.get(span.range()).ok_or("original dimension view outside source")?;
        let first=self.tokens.partition_point(|t|t.span.start<span.start);let last=self.tokens.partition_point(|t|t.span.start<span.end);
        if !std::ptr::eq(source,view.text())||view.tokens().len()!=last-first||view.tokens().as_ptr()!=self.tokens[first..last].as_ptr(){return Err("dimension view is not original token/source owner".into())}
        match expression{
          None if view.text().is_empty()=>Ok(None),
          Some(expression) if !view.text().is_empty()=>self.original_expression_tokens(view,expression,symbols).map(Some),
          _=>Err("dimension empty/source expression differs from original metadata".into()),
        }
    }
    pub(crate) fn initializer_dimension_tokens<'a>(&'a self,header:Span,index:usize,count:usize,expression:&dm_ir::SymbolicExpression,symbols:&SymbolTable)->Result<(&'a SourceText,&'a[SpanToken],Span),String>{
        let mut selected=None;let mut actual=0;
        for view in self.initializer_dimension_views(header)?{let view=view?;if actual==index{selected=Some(view)}actual+=1;}
        if actual!=count{return Err("dimension source count differs from original metadata".into())}
        self.original_expression_tokens(selected.ok_or("original dimension ordinal unavailable")?,expression,symbols)
    }
    pub(crate) fn parse_body(
        &self,
        span: Span,
        offset: usize,
    ) -> Result<dm_syntax::ProcedureWithOrigins, dm_syntax::Diagnostic> {
        dm_syntax::parse_proc_with_origins_from_spans(&self.source, span, &self.tokens, offset)
    }
    pub(crate) fn visit_source(&self, mut visit: impl FnMut(&SourceText)) {
        visit(&self.source)
    }
    pub(crate) fn same_source(&self, source: &SourceText) -> bool {
        self.source.same_view(source)
    }
    pub(crate) fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        self.initializer_roots.visit_storage(&mut visit, |_| {});
        if let Some(row) = &self.initializer_coordinates {
            visit(
                row.spans.as_ptr() as usize,
                row.spans.len() * std::mem::size_of::<Span>(),
                row.spans.capacity() * std::mem::size_of::<Span>(),
            );
            row.lease.visit_counter_storage(|p, n| visit(p, n, n));
        }

        visit(
            self as *const Self as usize,
            std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>(),
            std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>(),
        );
        for (p, n, c, size) in [
            (
                self.tokens.as_ptr() as usize,
                self.tokens.len(),
                self.tokens.capacity(),
                std::mem::size_of::<SpanToken>(),
            ),
            (
                self.headers.as_ptr() as usize,
                self.headers.len(),
                self.headers.capacity(),
                std::mem::size_of::<Span>(),
            ),
        ] {
            if c != 0 {
                visit(p, n * size, c * size);
            }
        }
        self.visit_settings_storage(&mut visit);
    }
    pub(crate) fn visit_setting_owners(
        &self,
        mut visit: impl FnMut(&Arc<dm_ir::ProcedureMetadata>),
    ) {
        if let Some(rows) = self.settings.get() {
            for row in rows {
                visit(row.owner());
            }
        }
    }
    fn original(&self, header: Span, offset: usize) -> Result<HeaderView<'_>, String> {
        let span = Span::new(
            header
                .start
                .checked_sub(offset)
                .ok_or("header before current binding")?,
            header
                .end
                .checked_sub(offset)
                .ok_or("header before current binding")?,
        );
        if self
            .headers
            .binary_search_by_key(&span.start, |s| s.start)
            .ok()
            .and_then(|i| self.headers.get(i))
            != Some(&span)
        {
            return Err("procedure has no exact original header recipe".into());
        }
        let first = self.tokens.partition_point(|t| t.span.start < span.start);
        let end = self.tokens.partition_point(|t| t.span.start < span.end);
        HeaderView::original(&self.source, &self.tokens[first..end], span)
    }
    /// Select the retained primary opening token. No lexer/parser, parameter
    /// expressions or statement grammar is invoked by this source projection.
    pub(crate) fn callable_opening(&self,body:Span,offset:usize)->Result<usize,String>{
        let header=self.headers.binary_search_by_key(&body.start,|h|h.start).ok()
            .and_then(|i|self.headers.get(i)).copied().ok_or("callable original header absent")?;
        if header.end>body.end{return Err("callable header escapes original body".into());}
        let view=self.original(header,0)?;
        let token=view.tokens().iter().find(|token|view.spelling(token)=="(")
            .ok_or("callable original opening token absent")?;
        token.span.start.checked_add(offset).ok_or_else(||"callable current header projection overflow".into())
    }
    pub(crate) fn parts<'a, 'n>(
        &'a self,
        header: Span,
        offset: usize,
        normalized: &'n str,
    ) -> Result<IssuedHeaderParts<'a, 'n>, String> {
        let view = self.original(header, offset)?;
        let mut depth = 0usize;
        let mut open = None;
        for token in view.tokens() {
            match view.spelling(token) {
                "(" => {
                    if depth == 0 {
                        open = Some(view.relative_span(token).start);
                    }
                    depth += 1;
                }
                ")" => {
                    depth = depth
                        .checked_sub(1)
                        .ok_or("unmatched original signature parenthesis")?;
                    if depth == 0 {
                        let open = open.ok_or("original signature opening missing")?;
                        let close = view.relative_span(token);
                        let suffix = &view.text()[open..];
                        let prefix = normalized
                            .strip_suffix(suffix)
                            .ok_or("normalized signature suffix differs from original tokens")?;
                        return Ok(IssuedHeaderParts {
                            prefix,
                            arguments: view.slice(open + 1, close.start),
                            trailing: view.slice(close.end, view.text().len()),
                            argument_offset: open + 1,
                        });
                    }
                }
                _ => (),
            }
        }
        Err("unterminated original procedure signature".into())
    }
    pub(crate) fn prefix<'a>(
        &'a self,
        header: Span,
        offset: usize,
    ) -> Result<impl Iterator<Item = &'a str> + 'a, String> {
        let view = self.original(header, offset)?;
        let end = view
            .tokens()
            .iter()
            .position(|t| view.spelling(t) == "(")
            .ok_or("original signature opening missing")?;
        Ok(view.tokens()[..end]
            .iter()
            .filter(|t| {
                !matches!(
                    t.kind,
                    TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
                )
            })
            .map(move |t| view.spelling(t)))
    }
}
pub(crate) struct IssuedHeaderParts<'a, 'n> {
    pub(crate) prefix: &'n str,
    arguments: HeaderView<'a>,
    trailing: HeaderView<'a>,
    pub(crate) argument_offset: usize,
}
impl IssuedHeaderParts<'_, '_> {
    pub(crate) fn parse(
        &self,
        symbols: &mut SymbolTable,
    ) -> Result<ParsedSignature, SignatureError> {
        super::parse_signature_views(self.arguments, self.trailing, symbols)
    }
}
/// Temporary consuming adapter-to-ledger bridge, never retained or serialized.
pub(crate) struct HeaderAllocationReceipt<'a> {
    items: &'a [Item],
    pub(crate) inputs: &'a OriginalProcedureHeaders,
    pub(crate) offset: usize,
    rows: Vec<HeaderAllocationRow>,
}
pub(crate) struct HeaderAllocationRow {
    pub(crate) header: Span,
    pub(crate) argument_offset: usize,
    pub(crate) declarations: Vec<super::HeaderTypeDeclaration>,
    pub(crate) body: Span,
    pub(crate) settings_owner: Option<Arc<dm_ir::ProcedureMetadata>>,
    pub(crate) settings_footprints: Vec<SettingFootprint>,
}
impl<'a> HeaderAllocationReceipt<'a> {
    pub(crate) fn from_rows(
        items: &'a [Item],
        inputs: &'a OriginalProcedureHeaders,
        offset: usize,
        rows: Vec<HeaderAllocationRow>,
    ) -> Result<Self, String> {
        Self::from_rows_using(items, inputs, offset, rows, |inputs, rows, offset| {
            inputs.install_settings(rows, offset)
        })
    }
    pub(crate) fn from_rows_checked(
        items: &'a [Item],
        inputs: &'a OriginalProcedureHeaders,
        offset: usize,
        rows: Vec<HeaderAllocationRow>,
    ) -> Result<Self, OriginalHeaderFailure> {
        Self::from_rows_using(items, inputs, offset, rows, |inputs, rows, offset| {
            inputs.install_settings_checked(rows, offset)
        })
    }
    fn from_rows_using<E: From<String>>(
        items: &'a [Item],
        inputs: &'a OriginalProcedureHeaders,
        offset: usize,
        rows: Vec<HeaderAllocationRow>,
        install: impl FnOnce(
            &OriginalProcedureHeaders,
            &mut [HeaderAllocationRow],
            usize,
        ) -> Result<(), E>,
    ) -> Result<Self, E> {
        let mut value = Self {
            items,
            inputs,
            offset,
            rows,
        };
        value.finish()?;
        for row in &value.rows {
            inputs.original(row.header, offset)?;
        }
        install(inputs, &mut value.rows, offset)?;
        Ok(value)
    }
    pub(crate) fn finish(&mut self) -> Result<(), String> {
        self.rows.sort_unstable_by_key(|r| r.header.start);
        if self
            .rows
            .windows(2)
            .any(|p| p[0].header.start == p[1].header.start)
        {
            return Err("duplicate original header allocation receipt".into());
        }
        Ok(())
    }
    pub(crate) fn require_items(&self, items: &[Item]) -> Result<(), String> {
        if !std::ptr::eq(items, self.items) {
            return Err("allocation receipt belongs to another original declaration owner".into());
        }
        Ok(())
    }
    pub(crate) fn row(&self, header: Span) -> Result<&HeaderAllocationRow, String> {
        let i = self
            .rows
            .binary_search_by_key(&header.start, |r| r.header.start)
            .map_err(|_| "procedure has no runtime header allocation receipt")?;
        let row = &self.rows[i];
        if row.header != header {
            return Err("runtime header allocation extent differs".into());
        }
        Ok(row)
    }
    pub(crate) fn has(&self, header: Span) -> bool {
        self.row(header).is_ok()
    }
}

#[cfg(test)]
#[path = "header_input_tests.rs"]
mod tests;

#[cfg(test)]
mod initializer_coordinate_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    #[test]
    fn original_header_capacity_refusal_is_typed_operational_with_legacy_text() {
        let mut spans: Vec<Span> = Vec::new();
        let error = reserve(&mut spans, usize::MAX)
            .err()
            .expect("actual capacity overflow");
        assert!(
            matches!(error,OriginalHeaderFailure::Operational(ref actual) if actual.kind()==std::io::ErrorKind::OutOfMemory && actual.to_string()=="header recipe capacity overflow")
        );
        assert!(spans.is_empty());
    }
    const TEXT:&str="/datum/probe\n    var\n        const/value=1+2\n/proc/p()\n    var/local=4\n    return local\n";
    fn parsed() -> dm_syntax::DeclarationSkeleton {
        dm_syntax::parse_declaration_skeleton(TEXT)
    }
    #[test]
    fn admitted_initializer_coordinate_inventory_shares_original_header_pass_without_body_or_meaning(
    ) {
        let ast = parsed();
        assert!(ast.diagnostics.is_empty());
        let counter = Arc::new(AtomicUsize::new(0));
        let checkpoint = || Ok(());
        let a = dm_syntax::SettingAdmission::new(&counter, 1024 * 1024, &checkpoint);
        let owner = OriginalProcedureHeaders::from_primary_admitted(
            TEXT.into(),
            &ast.items,
            0,
            ast.tokens,
            &a,
        )
        .ok()
        .expect("actual original primary headers");
        let coordinates = owner.initializer_coordinates.as_ref().unwrap();
        assert!(coordinates
            .spans
            .iter()
            .any(|s| &TEXT[s.range()] == "const/value=1+2"));
        assert!(
            !coordinates
                .spans
                .iter()
                .any(|s| TEXT[s.range()].contains("var/local")),
            "procedure children are not declaration coordinates"
        );
        for (i, span) in coordinates.spans.iter().copied().enumerate() {
            assert_eq!(
                owner.initializer_coordinate(span, 0, &a).ok(),
                Some((i, coordinates.spans.len()))
            );
        }
        let foreign = Arc::new(AtomicUsize::new(0));
        let other = dm_syntax::SettingAdmission::new(&foreign, 1024 * 1024, &checkpoint);
        assert!(
            matches!(owner.initializer_coordinate(coordinates.spans[0],0,&other),Err(OriginalHeaderFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::InvalidInput)
        );
        assert!(counter.load(Ordering::Acquire) > 0);
        drop(owner);
        assert_eq!(counter.load(Ordering::Acquire), 0);
        let ast = parsed();
        let old =
            OriginalProcedureHeaders::from_primary(TEXT.into(), &ast.items, 0, ast.tokens).unwrap();
        assert!(
            old.initializer_coordinates.is_none(),
            "existing compatibility does not allocate/admit new roster"
        );
    }
    #[test]
    fn original_header_initial_admission_restores_actual_checkpoint_cause_before_slot_work() {
        let ast = parsed();
        let counter = Arc::new(AtomicUsize::new(0));
        let stop = || Err(std::io::Error::from_raw_os_error(1450));
        let admission = dm_syntax::SettingAdmission::new(&counter, 1024 * 1024, &stop);
        let error = OriginalProcedureHeaders::from_primary_admitted(
            TEXT.into(),
            &ast.items,
            0,
            ast.tokens,
            &admission,
        )
        .err()
        .expect("actual initial checkpoint");
        assert!(
            matches!(error,OriginalHeaderFailure::Operational(ref actual)if actual.raw_os_error()==Some(1450))
        );
        assert_eq!(counter.load(Ordering::Acquire), 0);
    }
    #[test]
    fn original_header_coordinate_quota_and_checkpoint_are_typed_retryable_before_owner_publication(
    ) {
        let ast = parsed();
        let counter = Arc::new(AtomicUsize::new(0));
        let checkpoint = || Ok(());
        let a = dm_syntax::SettingAdmission::new(&counter, 0, &checkpoint);
        let error = OriginalProcedureHeaders::from_primary_admitted(
            TEXT.into(),
            &ast.items,
            0,
            ast.tokens,
            &a,
        )
        .err()
        .expect("real same-counter quota");
        assert!(
            matches!(error,OriginalHeaderFailure::Operational(ref e)if e.kind()==std::io::ErrorKind::OutOfMemory)
        );
        assert_eq!(counter.load(Ordering::Acquire), 0);
        let ast = parsed();
        let calls = std::cell::Cell::new(0);
        let stop = || {
            calls.set(calls.get() + 1);
            if calls.get() == 3 {
                Err(std::io::Error::from_raw_os_error(1450))
            } else {
                Ok(())
            }
        };
        let a = dm_syntax::SettingAdmission::new(&counter, 1024 * 1024, &stop);
        let error = OriginalProcedureHeaders::from_primary_admitted(
            TEXT.into(),
            &ast.items,
            0,
            ast.tokens,
            &a,
        )
        .err()
        .expect("actual admitted worker checkpoint after partial coordinate work");
        assert!(
            matches!(error,OriginalHeaderFailure::Operational(ref e)if e.raw_os_error()==Some(1450))
        );
        assert_eq!(counter.load(Ordering::Acquire), 0);
        let ast = parsed();
        let a = dm_syntax::SettingAdmission::new(&counter, 1024 * 1024, &checkpoint);
        let owner = OriginalProcedureHeaders::from_primary_admitted(
            TEXT.into(),
            &ast.items,
            0,
            ast.tokens,
            &a,
        )
        .ok()
        .expect("fresh operation retries same source/counter");
        drop(owner);
        assert_eq!(counter.load(Ordering::Acquire), 0);
    }
}

#[cfg(test)]
mod initializer_first_root_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    #[test]
    fn original_early_constant_fold_and_later_rhs_obtain_share_one_root_and_exact_old_scalar_policy(
    ) {
        for rhs in [
            "1+2",
            "(1 + 2) * 3",
            "unknown+1",
            "list(1)",
            "1 +",
            "\"plain literal\"",
            "\"[unknown]\"",
        ] {
            let source = format!("var/const/value = {rhs} as num\n");
            let parsed = dm_syntax::parse_declaration_skeleton(&source);
            assert!(parsed.diagnostics.is_empty());
            let normalized = crate::normalize::declarations_in_scope(&parsed.items, "/");
            let item = &normalized[0];
            let counter = Arc::new(AtomicUsize::new(0));
            let checkpoint = || Ok(());
            let a = dm_syntax::SettingAdmission::new(&counter, 4 * 1024 * 1024, &checkpoint);
            let owner = OriginalProcedureHeaders::from_primary_admitted(
                source.clone().into(),
                &parsed.items,
                0,
                parsed.tokens,
                &a,
            )
            .ok()
            .expect("original header source");
            let parts = owner
                .variable_parts(item.header_span, 0, item.header.trim())
                .unwrap();
            assert_eq!(parts.initializer_text(), Some(rhs));
            let mut symbols = SymbolTable::default();
            let symbolic = parts.symbolic(&mut symbols).unwrap().unwrap();
            let legacy = super::super::expression(rhs, &mut symbols).unwrap();
            assert_eq!(
                symbolic, legacy,
                "exact original symbolic token policy: {rhs}"
            );
            let expected = crate::constants::evaluate_with(rhs, |_| None, |_| None, |_| None)
                .map(|v| v.to_semantic(&mut symbols))
                .transpose()
                .unwrap();
            let native = parts
                .constant(&symbolic, &mut symbols, &a)
                .ok()
                .expect("same scalar fold policy");
            assert_eq!(native, expected, "{rhs}");
            let (ordinal, count) = owner
                .initializer_coordinate(item.header_span, 0, &a)
                .ok()
                .unwrap();
            assert_eq!(
                owner
                    .initializer_slot_coordinate(item.header_span, (usize::MAX, 0))
                    .unwrap(),
                (ordinal, count)
            );
            match owner
                .prepare_initializer(item.header_span, 0, true, &symbolic, &symbols, &a)
                .ok()
                .unwrap()
            {
                Ok(first) => {
                    let second = owner
                        .prepare_initializer(item.header_span, 0, true, &symbolic, &symbols, &a)
                        .ok()
                        .unwrap()
                        .unwrap();
                    assert!(first.same_root(&second));
                    assert!(owner.initializer_slots().contains_original(ordinal, &first));
                    assert_eq!(&source[first.original_expression().span.range()], rhs);
                }
                Err(_syntax) => assert!(
                    native.is_none(),
                    "old syntax fold remains unfurled metadata, not frontend rejection"
                ),
            }
            drop(parts);
            drop(owner);
            assert_eq!(counter.load(Ordering::Acquire), 0);
        }
    }
    #[test]
    fn original_early_initializer_folding_operational_failure_is_not_a_semantic_none_and_retries() {
        for fail_at in [1, 3] {
            let source = "var/const/value=1+2\n";
            let parsed = dm_syntax::parse_declaration_skeleton(source);
            let normalized = crate::normalize::declarations_in_scope(&parsed.items, "/");
            let item = &normalized[0];
            let counter = Arc::new(AtomicUsize::new(0));
            let checkpoint = || Ok(());
            let a = dm_syntax::SettingAdmission::new(&counter, 1024 * 1024, &checkpoint);
            let owner = OriginalProcedureHeaders::from_primary_admitted(
                source.into(),
                &parsed.items,
                0,
                parsed.tokens,
                &a,
            )
            .ok()
            .unwrap();
            let parts = owner
                .variable_parts(item.header_span, 0, item.header.trim())
                .unwrap();
            let mut symbols = SymbolTable::default();
            let expression = parts.symbolic(&mut symbols).unwrap().unwrap();
            let calls = std::cell::Cell::new(0);
            let stop = || {
                calls.set(calls.get() + 1);
                if calls.get() == fail_at {
                    Err(std::io::Error::from_raw_os_error(1450))
                } else {
                    Ok(())
                }
            };
            let failed = dm_syntax::SettingAdmission::new(&counter, 1024 * 1024, &stop);
            let error = parts
                .constant(&expression, &mut symbols, &failed)
                .err()
                .expect("actual early producer failure cannot become unresolved constant");
            assert!(
                matches!(error,OriginalHeaderFailure::Operational(ref actual)if actual.raw_os_error()==Some(1450))
            );
            assert!(parts
                .constant(&expression, &mut symbols, &a)
                .ok()
                .unwrap()
                .is_some());
            let first = owner
                .prepare_initializer(item.header_span, 0, true, &expression, &symbols, &a)
                .ok()
                .unwrap()
                .unwrap();
            let second = owner
                .prepare_initializer(item.header_span, 0, true, &expression, &symbols, &a)
                .ok()
                .unwrap()
                .unwrap();
            assert!(first.same_root(&second));
        }
    }
}

impl OriginalProcedureHeaders{
 pub(crate) fn for_declaration_profile(source:SourceText,items:&[Item],offset:usize,tokens:Option<Vec<SpanToken>>,admission:Option<&dm_syntax::SettingAdmission<'_>>,checker:bool)->Result<Arc<Self>,OriginalHeaderFailure>{
  let result=(||{if let Some(a)=admission{original_checkpoint(a)?;}let tokens=if let Some(tokens)=tokens{tokens}else{let parsed=dm_syntax::lex_spans(&source);if let Some(a)=admission{original_checkpoint(a)?;}if !parsed.diagnostics.is_empty(){return Err("original cached declaration token reissue failed".into())}parsed.tokens};Self::from_primary_inner(source,items,offset,tokens,admission,checker)})();if let Some(a)=admission{finish_original_admission(result,a)}else{result}
 }
}
