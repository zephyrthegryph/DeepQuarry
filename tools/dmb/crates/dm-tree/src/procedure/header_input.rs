//! Private original header input on the EXISTING declaration syntax owner.
//! Never serialized, never a filesystem receipt, never an alternate DM parser.
use super::{adapter_rows::AdapterRows, header::HeaderView, ParsedSignature, SignatureError};
use dm_ir::SymbolTable;
use dm_preprocess::SourceText;
use dm_syntax::{Item, ItemKind, OriginalItems, Span, SpanToken, TokenKind};
use std::sync::{Arc, OnceLock};
#[path = "setting_input.rs"]
mod setting_input;
#[path="original_default_roots.rs"]mod default_roots;
pub(crate) use default_roots::OriginalDefaultRoots;
pub(crate) use setting_input::SettingFootprint;
struct HeaderParameterSignatures{rows:Vec<dm_syntax::SharedParameterSignature>,_credit:dm_syntax::SettingRootLease}
impl std::fmt::Debug for HeaderParameterSignatures{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("HeaderParameterSignatures").field("rows",&self.rows).finish_non_exhaustive()}}
struct HeaderLiteralSourceHold(Option<dm_preprocess::regions::OriginalLiteralSourceView>);
impl std::fmt::Debug for HeaderLiteralSourceHold{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str(if self.0.is_some(){"issued neutral primary literal view"}else{"unissued neutral primary literal view"})}}
#[derive(Debug)]
pub(crate) struct OriginalProcedureHeaders {
    source: SourceText,
    headers: Vec<Span>,
    first_outer_block: Option<usize>,
    tokens: dm_syntax::SpanTokenStorage,
    settings: OnceLock<setting_input::SettingsRoster>,
    checker_diagnostic_settings: bool,
    initializer_coordinates: Option<OriginalInitializerCoordinates>,
    initializer_roots: dm_syntax::SettingExpressionSlots,
    initializer_facts: OnceLock<OriginalInitializerFactsAdmission>,
    demanded_defaults:OnceLock<OriginalDefaultRoots>,
    parameter_signatures:OnceLock<HeaderParameterSignatures>,
    formal_notices:OnceLock<(super::original_formal_notices::FormalNotices,bool)>,
    original_literal_source:OnceLock<HeaderLiteralSourceHold>,
    // Last: actual token/header payload drops before its SAME resource credit.
    original_primary_resource:OnceLock<OriginalPrimaryResourceHold>,
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
#[derive(Debug)]
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
#[cfg(test)]
thread_local! {
    pub(crate) static PLAIN_EMPTY_PARAMETER_SIGNATURES: std::cell::Cell<usize> =
        const { std::cell::Cell::new(0) };
}
fn original_checkpoint(a: &dm_syntax::SettingAdmission<'_>) -> std::io::Result<()> {
    a.checkpoint()
        .map_err(|proxy| a.take_operational_error().unwrap_or(proxy))
}
struct OriginalInitializerCoordinates {
    // Actual source coordinates only, never variable/type/namespace semantics.
    // Physical buffer release precedes quota credit.
    spans: Vec<Span>,
    buffer_credit: Option<dm_syntax::SettingRootLease>,
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
            buffer_credit: None,
            lease: a.reserve(
                std::mem::size_of::<Self>()
                    + std::mem::size_of::<OnceLock<OriginalInitializerFactsAdmission>>()
                    + std::mem::size_of::<OnceLock<OriginalPrimaryResourceHold>>(),
            )?,
        })
    }
    fn push(&mut self, span: Span, a: &dm_syntax::SettingAdmission<'_>) -> std::io::Result<()> {
        original_checkpoint(a)?;
        if !a.matches_lease_domain(&self.lease) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "initializer coordinate storage uses another admission",
            ));
        }
        if self.spans.len() == self.spans.capacity() {
            // The exact-layout allocator pays the new Vec before allocation.
            // It drops the old Vec before returning its separate buffer credit.
            super::original_primary_signatures::grow_funded_rows(
                &mut self.spans, &mut self.buffer_credit, a,
            )?;
        }
        self.spans.push(span);
        Ok(())
    }
}
fn spans(
    items: OriginalItems<'_>,
    offset: usize,
    source: &str,
    tokens: dm_syntax::TokenWindow<'_>,
    procedure_namespace: bool,
    out: &mut Vec<Span>,
    coordinates: &mut Option<OriginalInitializerCoordinates>,
    admission: Option<&dm_syntax::SettingAdmission<'_>>,
) -> Result<(), OriginalHeaderFailure> {
    for item in items.iter() {
        let wants_header =
            coordinates.is_some() || procedure_namespace || matches!(item.kind(), ItemKind::Proc | ItemKind::Verb);
        let span = if wants_header {
            let span = Span::new(
                item.header_span()
                    .start
                    .checked_sub(offset)
                    .ok_or("header starts before chunk")?,
                item.header_span()
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
        // Proc/verb namespaces themselves have no parameter opening. The
        // normalizer promotes their actual child callable, so the original
        // recipe inventory must continue to that SAME child's primary tokens.
        let procedure_context=procedure_namespace||matches!(item.kind(),ItemKind::Proc|ItemKind::Verb);
        let callable=if procedure_context{
            if span.start>span.end{return Err("original procedure header bounds differ".into())}
            let first=tokens.partition_point(|token|token.span.start<span.start);
            let last=tokens.partition_point(|token|token.span.start<span.end);
            let header=tokens.range(first,last).ok_or("original procedure token interval unavailable")?;
            let view=HeaderView::original_window(source,header,span)?;
            view.token_window().iter().any(|token|token.kind==TokenKind::Punctuation&&view.spelling(&token)=="(")
        }else{false};
        if callable {
            if source.get(span.range()) != Some(item.header()) {
                return Err("original procedure header differs from its declaration source".into());
            }
            reserve(out, 1)?;
            out.push(span);
        } else {
            spans(item.children(), offset, source, tokens, procedure_context, out, coordinates, admission)?;
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
#[cfg(test)]thread_local!{static OUTER_PRIMARY_REISSUES:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
impl OriginalProcedureHeaders {
    /// Move the ORIGINAL cold lexer Vec into the EXISTING declaration input.
    /// Header and body consumers borrow ranges; no separate per-body token owner.
    pub(crate) fn from_primary(
        source: SourceText,
        items: &[Item],
        offset: usize,
        tokens: Vec<SpanToken>,
    ) -> Result<Arc<Self>, String> {
        Self::from_primary_inner(source, OriginalItems::from_items(items), offset, tokens.into(), None, false).map_err(|failure| {
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
        let result = Self::from_primary_inner(source, OriginalItems::from_items(items), offset, tokens.into(), Some(admission), false);
        finish_original_admission(result, admission)
    }
    fn from_primary_inner(
        source: SourceText,
        items: OriginalItems<'_>,
        offset: usize,
        tokens: dm_syntax::SpanTokenStorage,
        admission: Option<&dm_syntax::SettingAdmission<'_>>,
        checker_diagnostic_settings: bool,
    ) -> Result<Arc<Self>, OriginalHeaderFailure> {
        let window = tokens.window();
        if window.iter().any(|t| source.get(t.span.range()).is_none())
            || window.iter().zip(window.iter().skip(1)).any(|(left, right)| left.span.end > right.span.start)
        {
            return Err("original declaration token ranges differ".into());
        }
        // Cold primary Items own genuine events before BODY compaction. Portable
        // descriptors are UNKNOWN and must reissue through the SAME primary
        // lexical/layout routine over this exact current source/token lease.
        fn events(
            items: OriginalItems<'_>,
            offset: usize,
            known: &mut bool,
            first: &mut Option<usize>,
            admission: Option<&dm_syntax::SettingAdmission<'_>>,
        ) -> Result<(), OriginalHeaderFailure> {
            for item in items.iter() {
                if let Some(admission) = admission {
                    original_checkpoint(admission)?;
                }
                if matches!(item.kind(), ItemKind::Proc | ItemKind::Verb) {
                    match item.original_outer_terminator() {
                        Some(true) => {
                            let at = item.header_span().end.checked_sub(offset)
                                .ok_or("outer terminator header before current source")?;
                            *first = Some(first.map_or(at, |old| old.min(at)));
                        }
                        Some(false) => {}
                        None => *known = false,
                    }
                } else {
                    events(item.children(), offset, known, first, admission)?;
                }
            }
            Ok(())
        }
        let mut events_known=true;let mut first_outer_block=None;events(items,offset,&mut events_known,&mut first_outer_block,admission)?;
        let mut headers = Vec::new();
        let mut coordinates = admission
            .map(OriginalInitializerCoordinates::new)
            .transpose()?;
        spans(
            items,
            offset,
            &source,
            window,
            false,
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
        if !events_known{
         #[cfg(test)]OUTER_PRIMARY_REISSUES.with(|count|count.set(count.get()+1));
         let geometry_bytes=source.len().checked_mul(512).and_then(|n|n.checked_add(8192)).ok_or_else(||OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"outer terminator geometry peak overflow")))?;
         let geometry_lease=admission.map(|a|a.reserve(geometry_bytes)).transpose()?;
         let checkpoint=||match admission{Some(a)=>original_checkpoint(a),None=>Ok(())};
         let observation=dm_syntax::original_outer_terminator_observation_in_window_using(&source,window,&headers,&checkpoint)??;
         first_outer_block=observation.first_block_probe();drop(geometry_lease);
        }
        if let Some(a) = admission {
            a.checkpoint()?;
        }
        Ok(Arc::new(Self {
            source,
            headers,
            first_outer_block,
            tokens,
            settings: OnceLock::new(),
            checker_diagnostic_settings,
            initializer_coordinates: coordinates,
            initializer_roots: Default::default(),
            initializer_facts: OnceLock::new(),
            demanded_defaults:OnceLock::new(),parameter_signatures:OnceLock::new(),formal_notices:OnceLock::new(),
            original_literal_source:OnceLock::new(),
            original_primary_resource:OnceLock::new(),
        }))
    }
    /// Compatibility for ordinary/portable Item owners.
    pub(crate) fn for_declaration_profile_tokens(source:SourceText,items:&[Item],offset:usize,tokens:dm_syntax::SpanTokenStorage,a:&dm_syntax::SettingAdmission<'_>,checker:bool)->Result<Arc<Self>,OriginalHeaderFailure>{
        Self::for_declaration_profile_item_view(source,OriginalItems::from_items(items),offset,tokens,a,checker)
    }
    /// Final Original ownership handoff. Borrow only Item geometry and
    /// header slices. The owner retains actual source/tokens and selectors,
    /// never the Item view, expanded strings, or a reconstructed Item tree.
    pub(crate) fn for_declaration_profile_item_view(source:SourceText,items:OriginalItems<'_>,offset:usize,tokens:dm_syntax::SpanTokenStorage,a:&dm_syntax::SettingAdmission<'_>,checker:bool)->Result<Arc<Self>,OriginalHeaderFailure>{
        if tokens.shared().is_some_and(|shared|!shared.admitted_by(a)){return Err(OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"shared header tokens use another resource owner")))}
        let result=Self::from_primary_inner(source,items,offset,tokens,Some(a),checker);finish_original_admission(result,a)
    }
    pub(crate) fn shared_span_tokens(&self)->Option<&dm_syntax::SharedSpanTokens>{self.tokens.shared()}
    pub(crate) fn first_outer_block(&self)->Option<usize>{self.first_outer_block}
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
            .window()
            .partition_point(|t| t.span.start < relative.start);
        let last = self.tokens.window().partition_point(|t| t.span.start < relative.end);
        let view = HeaderView::original_window(&self.source, self.token_window(first, last)?, relative)?;
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
        let first = self.tokens.window().partition_point(|t| t.span.start < header.start);
        let last = self.tokens.window().partition_point(|t| t.span.start < header.end);
        let view = HeaderView::original_window(&self.source, self.token_window(first, last)?, header)?;
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
        if self.initializer_coordinates.is_none(){return Ok(fallback)}
        self.required_initializer_slot_coordinate(header)
    }
    pub(crate) fn required_initializer_slot_coordinate(&self,header:Span)->Result<(usize,usize),String>{
        let row=self.initializer_coordinates.as_ref().ok_or("actual Original initializer coordinates are unissued")?;
        let ordinal = row
            .spans
            .binary_search_by_key(&header.start, |s| s.start)
            .map_err(|_| "original initializer coordinate unavailable")?;
        if row.spans[ordinal] != header {
            return Err("original initializer coordinate extent differs".into());
        }
        Ok((ordinal, row.spans.len()))
    }
    pub(crate) fn checker_body_profile(&self)->bool{self.checker_diagnostic_settings}
    pub(crate) fn initializer_slots(&self) -> &dm_syntax::SettingExpressionSlots {
        &self.initializer_roots
    }
    pub(super) fn install_original_formal_notices(&self,notices:super::original_formal_notices::FormalNotices,complete:bool,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{original_checkpoint(a)?;if !notices.is_admitted_by(a){return Err(std::io::ErrorKind::InvalidInput.into())}self.formal_notices.set((notices,complete)).map_err(|_|std::io::Error::new(std::io::ErrorKind::AlreadyExists,"actual formal parser notices were already installed"))}
    pub(crate) fn formal_notices_for(&self,header:Span)->Result<impl Iterator<Item=super::OriginalFormalNotice>+'_,&'static str>{let(notices,complete)=self.formal_notices.get().ok_or("actual original formal parser notice coverage is unissued")?;if !complete{return Err("actual original formal clause notice coverage is unissued")}Ok(notices.for_header(header.start).iter().map(|entry|entry.notice))}
    pub(crate) fn formal_source_matches(&self,parent:&SourceText,offset:usize)->bool{offset.checked_add(self.source.len()).and_then(|end|parent.checked_view(offset..end)).is_some_and(|view|view.same_view(&self.source))}
    pub(crate) fn all_formal_notices(&self)->Result<impl Iterator<Item=super::OriginalFormalNotice>+'_,&'static str>{let(notices,complete)=self.formal_notices.get().ok_or("actual original formal parser notice coverage is unissued")?;if !complete{return Err("actual original formal clause notice coverage is unissued")}Ok(notices.all().iter().map(|entry|entry.notice))}
    pub(crate) fn formal_notice_text(&self,notice:super::OriginalFormalNotice)->Result<Option<&str>,&'static str>{if notice.needs_rendered_message(){let(notices,_)=self.formal_notices.get().ok_or("actual rendered formal notice owner absent")?;return notices.rendered_message(notice).map(Some)}notice.value_span().map(|span|self.source.get(span.range()).ok_or("actual formal notice value escaped its producer source")).transpose()}
    pub(crate) fn visit_default_roots(&self,visit:impl FnMut(&dm_syntax::SettingExpression)){if let Some(roots)=self.demanded_defaults.get(){roots.visit_roots(visit)}}
    pub(crate) fn new_default_roots(&self,count:usize,binding:&dm_preprocess::regions::OriginalLiteralSourceBinding,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<OriginalDefaultRoots>{
     let roots=OriginalDefaultRoots::new(count,binding,a)?;if !roots.matches(self,a){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"default roots belong to another actual primary/source owner"))}Ok(roots)
    }
    pub(crate) fn add_default_root(&self,roots:&mut OriginalDefaultRoots,header:Span,argument_offset:usize,parameter:&dm_ir::Parameter,symbols:&SymbolTable,root:super::DemandedFormalRoot,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{if !roots.matches(self,a){return Err(std::io::ErrorKind::InvalidInput.into())}roots.add(self,header,argument_offset,parameter,symbols,root,a)}
    pub(crate) fn add_produced_clauses(&self,roots:&mut OriginalDefaultRoots,header:Span,argument_offset:usize,parameters:&[dm_ir::Parameter],clauses:super::FormalClauseRows,lease:Arc<dm_syntax::SettingRootLease>,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{if !roots.matches(self,a){return Err(std::io::ErrorKind::InvalidInput.into())}roots.add_clauses(self,header,argument_offset,parameters,clauses,lease,a)}
    pub(crate) fn add_input_root(&self,roots:&mut OriginalDefaultRoots,header:Span,argument_offset:usize,parameter:&dm_ir::Parameter,symbols:&SymbolTable,ordinal:usize,marker:Span,input:dm_syntax::RetainedParameterInput,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{if !roots.matches(self,a){return Err(std::io::ErrorKind::InvalidInput.into())}roots.add_input(self,header,argument_offset,parameter,symbols,ordinal,marker,input,a)}
    pub(crate) fn install_default_roots(&self,roots:OriginalDefaultRoots,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{
      original_checkpoint(a)?;if !roots.matches(self,a){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"cannot publish foreign actual default root cohort"))}self.demanded_defaults.set(roots).map_err(|_|std::io::Error::new(std::io::ErrorKind::AlreadyExists,"actual default roots were already published"))
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
            tokens.with_dense_using(a,|dense|Ok(dm_syntax::prepare_setting_expression_with_original_literal_facts(source,dense,value,a,self.original_literal_facts()?)))
                .map_err(dm_syntax::SettingSyntaxFailure::Operational)?
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
    ) -> Result<(&'a SourceText, dm_syntax::TokenWindow<'a>, Span), String> {
        let rhs = self.initializer_rhs(header, variable)?;
        self.original_expression_tokens(rhs,expression,symbols)
    }
    fn original_expression_tokens<'a>(&'a self,rhs:HeaderView<'a>,expression:&dm_ir::SymbolicExpression,symbols:&SymbolTable)->Result<(&'a SourceText,dm_syntax::TokenWindow<'a>,Span),String>{
        let mut symbolic = expression.tokens.iter();
        for token in rhs.token_window().iter().filter(|t| {
            !matches!(
                t.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        }) {
            let expected = symbolic
                .next()
                .ok_or("original initializer primary token count differs")?;
            if expected.kind != token.kind
                || expected.relative_span != rhs.relative_span(&token)
                || symbols.text(expected.text) != Some(rhs.spelling(&token))
            {
                return Err("initializer differs from its original primary token geometry".into());
            }
        }
        if symbolic.next().is_some() || expression.tokens.is_empty() {
            return Err("original initializer primary token count differs".into());
        }
        Ok((&self.source, rhs.token_window(), rhs.span()))
    }
    /// Exact issued dimension subview from the SAME array declaration grammar
    /// used by metadata production. Empty suffixes have no expression root.
    pub(crate) fn initializer_dimension_views(&self,header:Span)->Result<super::ArrayDimensions<'_>,String>{
        self.source.get(header.range()).ok_or("dimension header outside original source")?;
        let first=self.tokens.window().partition_point(|t|t.span.start<header.start);let last=self.tokens.window().partition_point(|t|t.span.start<header.end);
        let whole=HeaderView::original_window(&self.source,self.token_window(first,last)?,header)?;
        let end=whole.assignment_index().unwrap_or(whole.text().len());let declaration=whole.slice(0,end).trim();
        let end=declaration.text().find(" as ").unwrap_or(declaration.text().len());
        Ok(super::array_dimensions(declaration.slice(0,end).trim()))
    }
    pub(super) fn token_window(&self, first: usize, end: usize) -> Result<dm_syntax::TokenWindow<'_>, String> {
        self.tokens.window().range(first, end).ok_or_else(|| "invalid original token interval".into())
    }
    pub(crate) fn dimension_tokens_view<'a>(&'a self,view:HeaderView<'a>,expression:Option<&dm_ir::SymbolicExpression>,symbols:&SymbolTable)->Result<Option<(&'a SourceText,dm_syntax::TokenWindow<'a>,Span)>,String>{
        let span=view.span();let source=self.source.get(span.range()).ok_or("original dimension view outside source")?;
        let first=self.tokens.window().partition_point(|t|t.span.start<span.start);let last=self.tokens.window().partition_point(|t|t.span.start<span.end);
        if !std::ptr::eq(source,view.text())||!view.token_window().same_interval(self.token_window(first,last)?){return Err("dimension view is not original token/source owner".into())}
        match expression{
          None if view.text().is_empty()=>Ok(None),
          Some(expression) if !view.text().is_empty()=>self.original_expression_tokens(view,expression,symbols).map(Some),
          _=>Err("dimension empty/source expression differs from original metadata".into()),
        }
    }
    pub(crate) fn initializer_dimension_tokens<'a>(&'a self,header:Span,index:usize,count:usize,expression:&dm_ir::SymbolicExpression,symbols:&SymbolTable)->Result<(&'a SourceText,dm_syntax::TokenWindow<'a>,Span),String>{
        let mut selected=None;let mut actual=0;
        for view in self.initializer_dimension_views(header)?{let view=view?;if actual==index{selected=Some(view)}actual+=1;}
        if actual!=count{return Err("dimension source count differs from original metadata".into())}
        self.original_expression_tokens(selected.ok_or("original dimension ordinal unavailable")?,expression,symbols)
    }
    /// Borrow actual primary occurrences from this SAME installed source view.
    /// The scalar facts remain with their neutral owner; only AST-local inline
    /// origins are produced by the one native parser invocation.
    pub(crate) fn original_body_expression(&self,source:&str,original_start:usize,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Option<dm_syntax::ParsedExpr>>{
      let Some(facts)=self.original_literal_facts()?else{return Ok(None)};
      let end=original_start.checked_add(source.len()).ok_or(std::io::ErrorKind::InvalidInput)?;
      if self.source.get(original_start..end)!=Some(source){return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,"current BODY expression differs from actual original source view"))}
      let first=self.tokens.window().partition_point(|token|token.span.end<=original_start);let last=self.tokens.window().partition_point(|token|token.span.start<end);
      let cut=||std::io::Error::new(std::io::ErrorKind::InvalidInput,"current BODY expression cuts actual primary token occurrence");
      let tokens=self.tokens.window().range(first,last).ok_or_else(cut)?;
      if tokens.iter().any(|token|token.span.start<original_start||token.span.end>end){return Err(cut())}
      tokens.with_dense_using(a,|dense|Ok(Some(dm_syntax::parse_expression_original_token_view(&self.source,dense,original_start,a,Some(facts)))))
    }
    /// Publish header DATA after the genuine streaming observer has installed
    /// its actual default/source/dimension/input roots and clause partitions.
    pub(crate) fn install_parameter_signatures(
        &self, a: &dm_syntax::SettingAdmission<'_>,
        mut empty_formals: impl FnMut(Span) -> Option<usize>,
    ) -> std::io::Result<()> {
      original_checkpoint(a)?;
      if !self.checker_diagnostic_settings{return Ok(())}
      let Some(roots)=self.demanded_defaults.get()else{return Ok(())};
      if self.parameter_signatures.get().is_some(){return Err(std::io::Error::new(std::io::ErrorKind::AlreadyExists,"actual parameter metadata was already published"))}
      let bytes=self.headers.len().checked_mul(std::mem::size_of::<dm_syntax::SharedParameterSignature>()).ok_or(std::io::ErrorKind::OutOfMemory)?;
      let credit=a.reserve(bytes)?;let mut rows=Vec::new();rows.try_reserve_exact(self.headers.len()).map_err(|actual|std::io::Error::new(std::io::ErrorKind::OutOfMemory,actual))?;
      for &header in &self.headers{
       original_checkpoint(a)?;let width=header.end.checked_sub(header.start).ok_or(std::io::ErrorKind::InvalidData)?;
       let header_tokens = || {
        let tape = self.tokens.window();
        let first = tape.partition_point(|token| token.span.end <= header.start);
        let end = tape.partition_point(|token| token.span.start < header.end);
        tape.range(first, end).ok_or_else(|| std::io::Error::from(std::io::ErrorKind::InvalidData))
       };
       let mut inspected = None;
       if let Some(argument_start) = empty_formals(header) {
        let tokens = header_tokens()?;
        if let Some(signature) = dm_syntax::parameter_signature_original_plain_empty(
            &self.source, tokens, header, argument_start,
        ) {
         // The empty slices own no allocations. Reserve the same exact
         // shared retention before publishing, with no parser scratch.
         let retained = dm_syntax::SharedParameterSignature::retention_envelope()
             .checked_add(signature.retained_bytes()).ok_or(std::io::ErrorKind::OutOfMemory)?;
         let lease = a.reserve(retained)?;
         for _ in (0..tokens.len()).step_by(64) { original_checkpoint(a)?; }
         original_checkpoint(a)?;
         rows.push(dm_syntax::SharedParameterSignature::retained_using(signature, lease, a)?);
         #[cfg(test)]
         PLAIN_EMPTY_PARAMETER_SIGNATURES.with(|count| count.set(count.get() + 1));
         continue;
        }
        inspected = Some(tokens);
       }
       let allowance=width.checked_mul(128).and_then(|n|n.checked_add(1024)).ok_or(std::io::ErrorKind::OutOfMemory)?;
       // One conservative envelope precedes all metadata vectors and scratch.
       // Existing root aliases retain their own original shared root credit.
       let envelope=width.checked_mul(512).and_then(|n|n.checked_add(8192)).and_then(|n|n.checked_add(dm_syntax::SharedParameterSignature::retention_envelope())).ok_or(std::io::ErrorKind::OutOfMemory)?;
       let lease=a.reserve(envelope)?;
       let tokens = match inspected { Some(tokens) => tokens, None => header_tokens()? };
       for _ in (0..tokens.len()).step_by(64){original_checkpoint(a)?;}
       let mut loan=roots.loan(header,self.formal_notices.get().filter(|(_,complete)|*complete).map(|(notices,_)|notices));
       let mut signature=tokens.with_dense_using(a,|dense|Ok(dm_syntax::parameter_signature_original_with_default_roots(&self.source,dense,header,0,&mut Some(&mut loan))))?;
       original_checkpoint(a)?;signature.admit_optional_expressions(allowance);
       if signature.retained_bytes()>allowance{return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"actual header metadata exceeded its original allowance"))}
       rows.push(dm_syntax::SharedParameterSignature::retained_using(signature,lease,a)?);
      }
      original_checkpoint(a)?;
      self.parameter_signatures.set(HeaderParameterSignatures{rows,_credit:credit}).map_err(|_|std::io::Error::new(std::io::ErrorKind::AlreadyExists,"actual parameter metadata was already published"))
    }
    pub(crate) fn parameter_signature(&self,body:Span)->Result<&dm_syntax::SharedParameterSignature,&'static str>{
      let index=self.headers.binary_search_by_key(&body.start,|header|header.start).map_err(|_|"actual original header is absent")?;
      self.parameter_signatures.get().and_then(|cohort|cohort.rows.get(index)).ok_or("actual original parameter metadata is unissued")
    }
    pub(crate) fn parse_body(
        &self,
        span: Span,
        offset: usize,
    ) -> Result<dm_syntax::ProcedureWithOrigins, dm_syntax::Diagnostic> {
        let local_tokens = || {
            let failure = |message: &str| dm_syntax::Diagnostic {
                span, kind: dm_syntax::DiagnosticKind::Unsupported, message: message.into(),
            };
            if self.source.get(span.range()).is_none() || span.end.checked_add(offset).is_none() {
                return Err(failure("original procedure token range is outside source"));
            }
            let tokens = self.tokens.window();
            let first = tokens.partition_point(|token| token.span.end <= span.start);
            let last = tokens.partition_point(|token| token.span.start < span.end);
            tokens.range(first, last).ok_or_else(|| failure("original procedure token range differs"))
        };
        if self.parameter_signatures.get().is_some(){
          if offset!=0{return Err(dm_syntax::Diagnostic{span,kind:dm_syntax::DiagnosticKind::Unsupported,message:"shared parameter metadata requires its canonical original source window".into()})}
          let signature=self.parameter_signature(span).map_err(|message|dm_syntax::Diagnostic{span,kind:dm_syntax::DiagnosticKind::Unsupported,message:message.into()})?;
          // The existing header binding reauthenticates its exact SourceText
          // view before lending sealed TU-coordinate interpolation facts.
          let facts=self.original_literal_facts().map_err(|error|dm_syntax::Diagnostic{span,kind:dm_syntax::DiagnosticKind::Unsupported,message:error.to_string()})?;
          return dm_syntax::parse_original_proc_with_shared_parameters_from_window(&self.source,span,local_tokens()?,offset,signature.clone(),facts)
        }
        let dense_tokens = || local_tokens()?.as_dense_slice().ok_or_else(||dm_syntax::Diagnostic {
            span, kind: dm_syntax::DiagnosticKind::Unsupported,
            message: "actual original parameter metadata is unissued".into(),
        });
        if let Some(roots)=self.demanded_defaults.get(){
          // Genuine joined Original stream inputs own the zero-based source
          // view. Current reuse then goes through the existing CodeID binder;
          // it never copies/rebases an old absolute default AST by equal bytes.
          if offset!=0{return Err(dm_syntax::Diagnostic{span,kind:dm_syntax::DiagnosticKind::Unsupported,message:"streamed default root requires its canonical original source window".into()})}
          let at=self.headers.binary_search_by_key(&span.start,|header|header.start).map_err(|_|dm_syntax::Diagnostic{span,kind:dm_syntax::DiagnosticKind::Unsupported,message:"actual default header owner is absent".into()})?;
          let mut loan=roots.loan(self.headers[at],self.formal_notices.get().filter(|(_,complete)|*complete).map(|(notices,_)|notices));if self.checker_diagnostic_settings{dm_syntax::parse_original_proc_with_origins_and_default_roots_from_spans(&self.source,span,dense_tokens()?,offset,Some(&mut loan))}else{dm_syntax::parse_proc_with_origins_and_default_roots_from_spans(&self.source,span,dense_tokens()?,offset,Some(&mut loan))}
        }else if self.checker_diagnostic_settings{dm_syntax::parse_original_proc_with_origins_and_default_roots_from_spans(&self.source,span,dense_tokens()?,offset,None)}else{dm_syntax::parse_proc_with_origins_from_spans(&self.source,span,dense_tokens()?,offset)}
    }
    pub(crate) fn visit_source(&self, mut visit: impl FnMut(&SourceText)) {
        visit(&self.source)
    }
    pub(crate) fn same_source(&self, source: &SourceText) -> bool {
        self.source.same_view(source)
    }
    pub(crate) fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        if let Some(HeaderLiteralSourceHold(Some(facts)))=self.original_literal_source.get(){facts.visit_storage(&mut visit);}
        if let Some(roots)=self.demanded_defaults.get(){roots.visit_storage(&mut visit);}
        if let Some((notices,_))=self.formal_notices.get(){notices.visit_storage(&mut visit);}
        if let Some(root)=self.original_primary_resource.get(){let bytes=std::mem::size_of::<dm_syntax::SettingRootLease>()+2*std::mem::size_of::<usize>();visit(Arc::as_ptr(&root.0)as usize,bytes,bytes);root.0.visit_counter_storage(|address,bytes|visit(address,bytes,bytes));}

        if let Some(cohort)=self.parameter_signatures.get(){
         let bytes=cohort.rows.capacity()*std::mem::size_of::<dm_syntax::SharedParameterSignature>();if bytes!=0{visit(cohort.rows.as_ptr()as usize,cohort.rows.len()*std::mem::size_of::<dm_syntax::SharedParameterSignature>(),bytes)}
         cohort._credit.visit_counter_storage(|p,n|visit(p,n,n));
         for signature in &cohort.rows{signature.visit_owner_storage(&mut visit);signature.visit_storage(|p,n|visit(p,n,n));}
        }
        self.initializer_roots.visit_storage(&mut visit, |_| {});
        if let Some(row) = &self.initializer_coordinates {
            visit(
                row.spans.as_ptr() as usize,
                row.spans.len() * std::mem::size_of::<Span>(),
                row.spans.capacity() * std::mem::size_of::<Span>(),
            );
            row.lease.visit_counter_storage(|p, n| visit(p, n, n));
            if let Some(buffer_credit) = &row.buffer_credit {
                buffer_credit.visit_counter_storage(|p, n| visit(p, n, n));
            }
        }

        visit(
            self as *const Self as usize,
            std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>(),
            std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>(),
        );
        self.tokens.visit_storage(&mut visit);
        for (p, n, c, size) in [
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
            for row in rows.iter() {
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
        let first = self.tokens.window().partition_point(|t| t.span.start < span.start);
        let end = self.tokens.window().partition_point(|t| t.span.start < span.end);
        HeaderView::original_window(&self.source, self.token_window(first, end)?, span)
    }
    /// Select the retained primary opening token. No lexer/parser, parameter
    /// expressions or statement grammar is invoked by this source projection.
    pub(crate) fn callable_opening(&self,body:Span,offset:usize)->Result<usize,String>{
        let header=self.headers.binary_search_by_key(&body.start,|h|h.start).ok()
            .and_then(|i|self.headers.get(i)).copied().ok_or("callable original header absent")?;
        if header.end>body.end{return Err("callable header escapes original body".into());}
        let view=self.original(header,0)?;
        let token=view.token_window().iter().find(|token|view.spelling(token)=="(")
            .ok_or("callable original opening token absent")?;
        token.span.start.checked_add(offset).ok_or_else(||"callable current header projection overflow".into())
    }
    pub(crate) fn parts<'a,'n>(&'a self,header:Span,offset:usize,normalized:&'n str)->Result<IssuedHeaderParts<'a,'n>,String>{
        parts_from_primary_view(self.original(header,offset)?,offset,normalized,self.first_outer_block)
    }

    pub(crate) fn prefix<'a>(
        &'a self,
        header: Span,
        offset: usize,
    ) -> Result<impl Iterator<Item = &'a str> + 'a, String> {
        let view = self.original(header, offset)?;
        let tokens = view.token_window();
        let end = tokens.iter().position(|t| view.spelling(&t) == "(")
            .ok_or("original signature opening missing")?;
        Ok(tokens.iter().take(end)
            .filter(|t| {
                !matches!(
                    t.kind,
                    TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
                )
            })
            .map(move |t| view.spelling(&t)))
    }
}
pub(super) fn parts_from_primary_view<'a,'n>(view:HeaderView<'a>,offset:usize,normalized:&'n str,first_outer_block:Option<usize>)->Result<IssuedHeaderParts<'a,'n>,String>{
        let mut depth = 0usize;
        let mut open = None;
        for token in view.token_window().iter() {
            match view.spelling(&token) {
                "(" => {
                    if depth == 0 {
                        open = Some(view.relative_span(&token).start);
                    }
                    depth += 1;
                }
                ")" => {
                    depth = depth
                        .checked_sub(1)
                        .ok_or("unmatched original signature parenthesis")?;
                    if depth == 0 {
                        let open = open.ok_or("original signature opening missing")?;
                        let close = view.relative_span(&token);
                        let suffix = &view.text()[open..];
                        let prefix = normalized
                            .strip_suffix(suffix)
                            .ok_or("normalized signature suffix differs from original tokens")?;
                        return Ok(IssuedHeaderParts {
                            prefix,
                            arguments: view.slice(open + 1, close.start),
                            trailing: view.slice(close.end, view.text().len()),
                            argument_offset: open + 1,
                            closing: token,
                            first_outer_block,
                            offset,
                        });
                    }
                }
                _ => (),
            }
        }
        Err("unterminated original procedure signature".into())
 }
pub(crate) struct IssuedHeaderParts<'a, 'n> {
    pub(crate) prefix: &'n str,
    arguments: HeaderView<'a>,
    trailing: HeaderView<'a>,
    pub(crate) argument_offset: usize,
    closing: SpanToken,
    first_outer_block: Option<usize>,
    offset: usize,
}
impl IssuedHeaderParts<'_, '_> {
    pub(crate) fn closing_span(&self)->Span{self.closing.span}
    pub(crate) fn parse_formals(&self,symbols:&mut SymbolTable)->Result<super::ParsedFormalParameters,SignatureError>{
      self.parse_formals_with_dialect(symbols,false)
    }
    fn parse_formals_with_dialect(&self,symbols:&mut SymbolTable,original:bool)->Result<super::ParsedFormalParameters,SignatureError>{
      let result=if original{super::parse_original_formal_parameters_views(self.arguments,symbols)}else{super::parse_formal_parameters_views(self.arguments,symbols)};
      result.map_err(|mut error|{
            if let Some(end)=error.missing_default_end{if let Some(at)=self.arguments.span().start.checked_add(end){let following=self.arguments.token_window().iter().find(|token|token.span.start>=at&&!matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment)).unwrap_or(self.closing);let spelling=self.arguments.spelling(&following);if matches!(spelling,")"|","){if let(Some(start),Some(end))=(following.span.start.checked_add(self.offset),following.span.end.checked_add(self.offset)){error.original_fatal=Some(super::OriginalParameterFatal{at:Span::new(start,end),following:super::OriginalParameterFollowing::MissingDefault(if spelling==")"{')'}else{','}),prior_outer_block:self.first_outer_block.is_some_and(|at|at<following.span.start)});}}}}
       error
      })
    }
    pub(crate) fn finish_formals(&self,formals:super::ParsedFormalParameters,symbols:&mut SymbolTable)->Result<ParsedSignature,SignatureError>{super::finish_signature_views(formals,self.trailing,symbols)}
    pub(crate) fn parse(&self,symbols:&mut SymbolTable)->Result<ParsedSignature,SignatureError>{let formals=self.parse_formals(symbols)?;self.finish_formals(formals,symbols)}
    pub(super) fn parse_original(&self,symbols:&mut SymbolTable)->Result<ParsedSignature,SignatureError>{let formals=self.parse_formals_with_dialect(symbols,true)?;self.finish_formals(formals,symbols)}
}

/// Temporary consuming adapter-to-ledger bridge, never retained or serialized.
pub(crate) struct HeaderAllocationReceipt<'a> {
    items: OriginalItems<'a>,
    pub(crate) inputs: &'a OriginalProcedureHeaders,
    pub(crate) offset: usize,
    rows: AdapterRows<HeaderAllocationRow>,
}
pub(crate) struct HeaderAllocationRow {
    pub(crate) header: Span,
    pub(crate) argument_offset: usize,
    pub(crate) declarations: Vec<super::HeaderTypeDeclaration>,
    pub(crate) body: Span,
    pub(crate) settings_owner: Option<Arc<dm_ir::ProcedureMetadata>>,
    pub(crate) settings_footprints: AdapterRows<SettingFootprint>,
}
impl<'a> HeaderAllocationReceipt<'a> {
    pub(crate) fn from_rows(
        items: &'a [Item],
        inputs: &'a OriginalProcedureHeaders,
        offset: usize,
        rows: AdapterRows<HeaderAllocationRow>,
    ) -> Result<Self, String> {
        Self::from_rows_using(OriginalItems::from_items(items), inputs, offset, rows, |inputs, rows, offset| {
            inputs.install_settings(rows, offset)
        })
    }
    pub(crate) fn from_rows_checked(
        items: &'a [Item],
        inputs: &'a OriginalProcedureHeaders,
        offset: usize,
        rows: AdapterRows<HeaderAllocationRow>,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<Self, OriginalHeaderFailure> {
        Self::from_original_rows_checked(OriginalItems::from_items(items), inputs, offset, rows, a)
    }
    pub(crate) fn from_original_rows_checked(
        items: OriginalItems<'a>,
        inputs: &'a OriginalProcedureHeaders,
        offset: usize,
        rows: AdapterRows<HeaderAllocationRow>,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<Self, OriginalHeaderFailure> {
        Self::from_rows_using(items, inputs, offset, rows, |inputs, rows, offset| {
            inputs.install_settings_checked(rows, offset, a)
        })
    }
    fn from_rows_using<E: From<String>>(
        items: OriginalItems<'a>,
        inputs: &'a OriginalProcedureHeaders,
        offset: usize,
        rows: AdapterRows<HeaderAllocationRow>,
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
        for row in value.rows.iter() {
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
        self.require_original_items(OriginalItems::from_items(items))
    }
    pub(crate) fn require_original_items(&self, items: OriginalItems<'_>) -> Result<(), String> {
        if !self.items.same_interval(items) {
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
mod original_item_receipt_tests {
    use super::*;

    #[test]
    fn allocation_receipt_requires_the_same_borrowed_item_interval() {
        let source = "/datum/first\n/datum/second\n";
        let parsed = dm_syntax::parse_declaration_skeleton(source);
        let foreign = parsed.items.clone();
        let headers = OriginalProcedureHeaders::from_primary(source.into(), &parsed.items, 0, parsed.tokens).unwrap();
        let receipt = HeaderAllocationReceipt::from_rows(&parsed.items, &headers, 0, AdapterRows::default()).unwrap();
        assert!(receipt.require_original_items(OriginalItems::from_items(&parsed.items)).is_ok());
        assert!(receipt.require_original_items(OriginalItems::from_items(&foreign)).is_err());
        assert!(receipt.require_original_items(OriginalItems::from_items(&parsed.items[..1])).is_err());
    }
}

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
    fn initializer_coordinate_growth_funds_overlap_and_settles_exact_buffer() {
        use std::mem::size_of;
        let used = Arc::new(AtomicUsize::new(0));
        let peak = AtomicUsize::new(0);
        let poll = || {
            peak.fetch_max(used.load(Ordering::Acquire), Ordering::AcqRel);
            Ok(())
        };
        let a = dm_syntax::SettingAdmission::new(&used, 1 << 20, &poll);
        let mut coordinates = OriginalInitializerCoordinates::new(&a).unwrap();
        let fixed = coordinates.lease.bytes();
        assert!(coordinates.buffer_credit.is_none());
        for index in 0..1025 {
            let old = coordinates.spans.capacity();
            peak.store(0, Ordering::Release);
            coordinates.push(Span::new(index, index + 1), &a).unwrap();
            let new = coordinates.spans.capacity();
            assert_eq!(coordinates.buffer_credit.as_ref().unwrap().bytes(), new * size_of::<Span>());
            assert_eq!(used.load(Ordering::Acquire), fixed + new * size_of::<Span>());
            if old != new {
                assert_eq!(peak.load(Ordering::Acquire), fixed + (old + new) * size_of::<Span>());
            }
        }
        assert!(coordinates.spans.iter().copied().enumerate().all(|(index, span)| span == Span::new(index, index + 1)));
        drop(coordinates);
        assert_eq!(used.load(Ordering::Acquire), 0);
    }

    #[test]
    fn initializer_coordinate_growth_failure_preserves_rows_and_old_credit() {
        use std::mem::size_of;
        let used = Arc::new(AtomicUsize::new(0));
        let a = dm_syntax::SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
        let mut coordinates = OriginalInitializerCoordinates::new(&a).unwrap();
        coordinates.push(Span::new(0, 1), &a).unwrap();
        let old = coordinates.spans.capacity();
        for index in 1..old {
            coordinates.push(Span::new(index, index + 1), &a).unwrap();
        }
        let before = used.load(Ordering::Acquire);
        let pointer = coordinates.spans.as_ptr();
        let next = Span::new(old, old + 1);

        let limit = before + old * 2 * size_of::<Span>() - 1;
        let low = dm_syntax::SettingAdmission::new(&used, limit, &|| Ok(()));
        assert_eq!(coordinates.push(next, &low).unwrap_err().kind(), std::io::ErrorKind::OutOfMemory);
        assert_eq!(coordinates.spans.as_ptr(), pointer);
        assert_eq!(coordinates.spans.len(), old);
        assert_eq!(used.load(Ordering::Acquire), before);

        let fail_after_new_credit = || {
            if used.load(Ordering::Acquire) > before {
                Err(std::io::Error::from_raw_os_error(1450))
            } else {
                Ok(())
            }
        };
        let stopped = dm_syntax::SettingAdmission::new(&used, 1 << 20, &fail_after_new_credit);
        assert_eq!(coordinates.push(next, &stopped).unwrap_err().raw_os_error(), Some(1450));
        assert_eq!(coordinates.spans.as_ptr(), pointer);
        assert_eq!(coordinates.spans.len(), old);
        assert_eq!(coordinates.buffer_credit.as_ref().unwrap().bytes(), old * size_of::<Span>());
        assert_eq!(used.load(Ordering::Acquire), before);

        coordinates.push(next, &a).unwrap();
        assert_eq!(coordinates.spans.last(), Some(&next));
        drop(coordinates);
        assert_eq!(used.load(Ordering::Acquire), 0);
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
  let result=(||{if let Some(a)=admission{original_checkpoint(a)?;}let tokens=if let Some(tokens)=tokens{tokens}else{let parsed=dm_syntax::lex_spans(&source);if let Some(a)=admission{original_checkpoint(a)?;}if !parsed.diagnostics.is_empty(){return Err("original cached declaration token reissue failed".into())}parsed.tokens};Self::from_primary_inner(source,OriginalItems::from_items(items),offset,tokens.into(),admission,checker)})();if let Some(a)=admission{finish_original_admission(result,a)}else{result}
 }
}

/// Borrowed original primary tokens for ONE authenticated current body. This
/// is diagnostic text/location DATA; it issues no parser or semantic receipt.
pub struct OriginalBodyTokens<'source>{owner:&'source OriginalProcedureHeaders,body:Span,offset:usize}
impl OriginalProcedureHeaders{
 pub(crate) fn body_tokens(&self,body:Span,offset:usize)->Result<OriginalBodyTokens<'_>,&'static str>{
  if self.headers.binary_search_by_key(&body.start,|span|span.start).is_err()||body.start>body.end||body.end>self.source.len()||body.end.checked_add(offset).is_none(){return Err("original body primary token bounds differ")}
  Ok(OriginalBodyTokens{owner:self,body,offset})
 }
}
impl<'source> OriginalBodyTokens<'source>{
 pub fn current_span(&self)->Span{Span::new(self.body.start+self.offset,self.body.end+self.offset)}
 pub fn tokens(&self,current:Span)->Result<impl Iterator<Item=(TokenKind,Span,&'source str)>+'source,&'static str>{
  let body=self.current_span();if current.start>current.end||current.start<body.start||current.end>body.end{return Err("requested primary tokens escape original body")}
  let relative=Span::new(current.start-self.offset,current.end-self.offset);let owner=self.owner;
  let tokens=owner.tokens.window();
  let first=tokens.partition_point(|token|token.span.end<=relative.start);let last=tokens.partition_point(|token|token.span.start<relative.end);
  let tokens=tokens.range(first,last).ok_or("requested primary token boundary splits a token")?;
  if tokens.get(0).is_some_and(|token|token.span.start<relative.start)||tokens.last().is_some_and(|token|token.span.end>relative.end){return Err("requested primary token boundary splits a token")}
  let source:&'source str=&owner.source;let offset=self.offset;
  Ok(tokens.iter().map(move|token|(token.kind,Span::new(token.span.start+offset,token.span.end+offset),token.text(source))))
 }
}

#[cfg(test)]mod callable_namespace_original_headers_tests{
 use super::*;
 #[test]fn original_callable_recipe_descends_proc_and_verb_namespaces_without_recording_them_as_bodies(){
  for source in["/datum/flags\n    proc/final\n        probe()\n            return 0\n","/datum/flags\n    proc\n        final\n            probe()\n                return 0\n","/datum/flags\n    verb\n        present()\n            return 0\n"]{
   let ast=dm_syntax::parse_declaration_skeleton(source);assert!(ast.diagnostics.is_empty(),"{:?}",ast.diagnostics);
   let owner=OriginalProcedureHeaders::from_primary(source.into(),&ast.items,0,ast.tokens).unwrap();assert_eq!(owner.headers.len(),1,"namespace is not a callable header");let span=owner.headers[0];assert!(source[span.range()].ends_with("()"));assert!(owner.original(span,0).is_ok());assert!(owner.headers.iter().all(|span|source[span.range()].contains('(')));
  }
 }
}

#[derive(Clone,Copy,Eq,PartialEq)]enum OriginalCaseContinuation{Block,If,Try,Do}
impl OriginalBodyTokens<'_>{

 // Project only layout delimiters from the retained primary tokens. This is the
 // original indentation state machine; it does not lex or parse expressions.
 // The pinned checker CLI leaves parser annotations disabled, so block-local
 // annotation replay cannot move this cursor after the consumed delimiter.
 fn original_case_block_cursor_using<E:From<&'static str>>(&self,after:usize,continuation_mode:OriginalCaseContinuation,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<Option<dm_syntax::OriginalCaseCursor>,E>{
  let mut current:Option<(usize,usize)>=None;let mut spaces:Option<usize>=None;let mut parentheses=0usize;let mut eol:Option<Span>=None;let active=std::cell::Cell::new(false);let mut depth=0usize;let decided=std::cell::Cell::new(false);let waiting=std::cell::Cell::new(false);let else_mode=std::cell::Cell::new(0u8);let else_parens=std::cell::Cell::new(0usize);let else_if=std::cell::Cell::new(false);let final_else=std::cell::Cell::new(false);let continuation=std::cell::Cell::new(0u8);let continuation_depth=std::cell::Cell::new(0usize);
  let mut emit=|text:&str,at:Span,terminal:bool|->Result<Option<dm_syntax::OriginalCaseCursor>,E>{
   match continuation.get(){
    10=>{if text==";"{return Ok(None)}if text!="catch"{return Err("inline try continuation lacks actual catch".into())}continuation.set(11);return Ok(None)},
    11=>{if text=="("{continuation.set(12);continuation_depth.set(1);return Ok(None)}if text=="{"{continuation.set(13);active.set(true);depth=1;return Ok(None)}if !matches!(text,";"|"}"){return Err("inline catch simple statement continuation unavailable".into())}},
    12=>{match text{"("=>continuation_depth.set(continuation_depth.get().checked_add(1).ok_or("catch header depth overflow")?),")"=>{let n=continuation_depth.get().checked_sub(1).ok_or("catch header opening unavailable")?;continuation_depth.set(n);if n==0{continuation.set(11)}},_=>()}return Ok(None)},
    20=>{if text==";"{return Ok(None)}if text!="while"{return Err("inline do continuation lacks actual while".into())}continuation.set(21);return Ok(None)},
    21=>{if text!="("{return Err("inline do condition opening unavailable".into())}continuation.set(22);continuation_depth.set(1);return Ok(None)},
    22=>{match text{"("=>continuation_depth.set(continuation_depth.get().checked_add(1).ok_or("do condition depth overflow")?),")"=>{let n=continuation_depth.get().checked_sub(1).ok_or("do condition opening unavailable")?;continuation_depth.set(n);if n==0{continuation.set(23)}},_=>()}return Ok(None)},
    23=>{if !matches!(text,";"|"}"){return Err("inline do condition terminator unavailable".into())}},_=>()
   }
   if continuation.get()==11||continuation.get()==23{return Ok(Some(if terminal{dm_syntax::OriginalCaseCursor::SourceEnd{offset:self.owner.source.len().checked_add(self.offset).ok_or("case terminal cursor overflow")?,fallback:Span::new(at.start+self.offset,at.end+self.offset)}}else{dm_syntax::OriginalCaseCursor::Token(Span::new(at.start+self.offset,at.end+self.offset))}))}
   if else_mode.get()==2{match text{"("=>else_parens.set(else_parens.get().checked_add(1).ok_or("inline else-if depth overflow")?),")"=>{let n=else_parens.get().checked_sub(1).ok_or("inline else-if opening unavailable")?;else_parens.set(n);if n==0{else_mode.set(1)}},_=>()}return Ok(None)}
   if else_mode.get()==1{match text{"if"=>{else_if.set(true);else_mode.set(2);return Ok(None)},"{"=>{else_mode.set(0);active.set(true);depth=1;final_else.set(!else_if.get());return Ok(None)},_=>return Err("inline else simple statement continuation unavailable".into())}}
   if waiting.get(){if text=="else"{waiting.set(false);else_if.set(false);else_mode.set(1);return Ok(None)}if text==";"{return Ok(None)}return Ok(Some(if terminal{dm_syntax::OriginalCaseCursor::SourceEnd{offset:self.owner.source.len().checked_add(self.offset).ok_or("case terminal cursor overflow")?,fallback:Span::new(at.start+self.offset,at.end+self.offset)}}else{dm_syntax::OriginalCaseCursor::Token(Span::new(at.start+self.offset,at.end+self.offset))}))}
   if !active.get() {if at.start<after{return Ok(None)}if text==";"{return Ok(None)}decided.set(true);if text!="{"{return Ok(None)}active.set(true);depth=1;return Ok(None)}
   if text=="{"{depth=depth.checked_add(1).ok_or("case layout depth overflow")?;}else if text=="}"{depth=depth.checked_sub(1).ok_or("case layout close underflow")?;if depth==0{if continuation_mode==OriginalCaseContinuation::Try&&continuation.get()==0{continuation.set(10);return Ok(None)}if continuation_mode==OriginalCaseContinuation::Do&&continuation.get()==0{continuation.set(20);return Ok(None)}if continuation_mode==OriginalCaseContinuation::If&&!final_else.get(){waiting.set(true);return Ok(None)}return Ok(Some(if terminal{dm_syntax::OriginalCaseCursor::SourceEnd{offset:self.owner.source.len().checked_add(self.offset).ok_or("case terminal cursor overflow")?,fallback:Span::new(at.start+self.offset,at.end+self.offset)}}else{dm_syntax::OriginalCaseCursor::Token(Span::new(at.start+self.offset,at.end+self.offset))}))}}Ok(None)
  };
  let source=self.owner.source.as_str();let mut last=Span::new(0,0);
  for token in self.owner.tokens.window().iter() {checkpoint()?;let text=token.text(source);last=token.span;
   let documentation=token.kind==TokenKind::Comment&&(text.starts_with("///")||text.starts_with("//!")||text.starts_with("/**")||text.starts_with("/*!"));if token.kind==TokenKind::Comment&&!documentation{continue}
   if token.kind==TokenKind::Newline{if parentheses==0{spaces=Some(0)}if eol.is_none(){eol=Some(token.span)}continue}
   if token.kind==TokenKind::Whitespace{if let Some(width)=spaces.as_mut(){*width=width.checked_add(text.len()).ok_or("case indentation width overflow")?}continue}
   if matches!(text,"{"|"}"){spaces=None}
   if let Some(width)=spaces.take(){let(old,new)=match current{None=>{if width==0{current=None;(0,0)}else{current=Some((width,1));(0,1)}},Some((unit,count))=>{if width==0{current=None;(count,0)}else{if width%unit!=0{return Err("case original indentation is inconsistent".into())}let new=width/unit;current=Some((unit,new));(count,new)}}};let at=eol.unwrap_or(token.span);if old<new{for _ in old..new{checkpoint()?;if let Some(point)=emit("{",at,false)?{return Ok(Some(point))}}}else if old>new{for _ in new..old{checkpoint()?;if let Some(point)=emit("}",at,false)?{return Ok(Some(point))}}}else if let Some(point)=emit(";",at,false)?{return Ok(Some(point))}}
   match text{"{"=>current=Some(match current{None=>(1,1),Some((unit,count))=>(unit,count.checked_add(1).ok_or("case layout indentation overflow")?)}),"}"=>current=match current{None=>return Err("case original unmatched right brace".into()),Some((_,1))=>None,Some((unit,count))=>Some((unit,count-1))},"("=>parentheses=parentheses.checked_add(1).ok_or("case parentheses overflow")?,")"=>parentheses=parentheses.saturating_sub(1),_=>()}
   eol=None;if documentation{continue}if let Some(point)=emit(text,token.span,false)?{return Ok(Some(point))}if decided.get()&&!active.get(){return Ok(None)}
  }
  if active.get(){if let Some((_,count))=current{let at=eol.unwrap_or(last);for _ in 0..count{checkpoint()?;if let Some(point)=emit("}",at,true)?{return Ok(Some(point))}}}if waiting.get(){let at=eol.unwrap_or(last);return Ok(Some(dm_syntax::OriginalCaseCursor::SourceEnd{offset:self.owner.source.len().checked_add(self.offset).ok_or("case terminal cursor overflow")?,fallback:Span::new(at.start+self.offset,at.end+self.offset)}))}return Err("case original block close unavailable".into())}Ok(None)
 }

 pub(crate) fn switch_case_cursor_using<E:From<&'static str>>(&self,header:Span,case:Span,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<dm_syntax::OriginalCaseCursor,E>{
  checkpoint()?;let start=header.start.checked_sub(self.offset).ok_or("case header before current source")?;let end=header.end.checked_sub(self.offset).ok_or("case header end before current source")?;let case_end=case.end.checked_sub(self.offset).ok_or("case body before current source")?;if start<self.body.start||start>=end||end>case_end||case_end>self.body.end||case_end>self.owner.source.len(){return Err("case cursor escapes original body/header".into())}
  let tokens=self.owner.tokens.window();let source=self.owner.source.as_str();let mut i=tokens.partition_point(|token|token.span.end<=start);let trivia=|token:SpanToken|matches!(token.kind,TokenKind::Whitespace|TokenKind::Newline|TokenKind::Comment);while tokens.get(i).is_some_and(trivia){checkpoint()?;i+=1;}if tokens.get(i).is_none_or(|token|token.span.start!=start||token.text(source)!="if"){return Err("case cursor lacks original if token".into())}i+=1;while tokens.get(i).is_some_and(trivia){checkpoint()?;i+=1;}if tokens.get(i).is_none_or(|token|token.text(source)!="("){return Err("case cursor lacks original opening token".into())}let mut depth=1usize;i+=1;while let Some(token)=tokens.get(i){checkpoint()?;if token.span.end>end{return Err("case condition escapes original header".into())}match token.text(source){"("=>depth=depth.checked_add(1).ok_or("case condition depth overflow")?,")"=>{depth-=1;if depth==0{break}},_=>()}i+=1;}if depth!=0{return Err("case condition close unavailable".into())}let condition_end=tokens.get(i).ok_or("case condition close unavailable")?.span.end;i+=1;let mut newline=false;while let Some(token)=tokens.get(i){checkpoint()?;if token.kind==TokenKind::Newline{newline=true;}if !trivia(token){break}i+=1;}
  if let Some(cursor)=self.original_case_block_cursor_using(condition_end,OriginalCaseContinuation::Block,checkpoint)?{return Ok(cursor)}
  if !newline&&tokens.get(i).is_some_and(|token|matches!(token.text(source),"if"|"for"|"while"|"switch"|"spawn")){
   let follow=tokens.get(i).ok_or("inline compound keyword unavailable")?.text(source)=="if";i+=1;while tokens.get(i).is_some_and(trivia){checkpoint()?;i+=1;}if tokens.get(i).is_none_or(|token|token.text(source)!="("){return Err("inline compound case opening condition unavailable".into())}let mut nested=1usize;i+=1;while let Some(token)=tokens.get(i){checkpoint()?;if token.span.end>case_end{return Err("inline compound condition escapes case".into())}match token.text(source){"("=>nested=nested.checked_add(1).ok_or("inline condition depth overflow")?,")"=>{nested-=1;if nested==0{break}},_=>()}i+=1;}if nested!=0{return Err("inline compound close unavailable".into())}let after=tokens.get(i).ok_or("inline compound close unavailable")?.span.end;if let Some(cursor)=self.original_case_block_cursor_using(after,if follow{OriginalCaseContinuation::If}else{OriginalCaseContinuation::Block},checkpoint)?{return Ok(cursor)}return Err("inline compound simple statement continuation unavailable".into())
  }
  if !newline&&tokens.get(i).is_some_and(|token|matches!(token.text(source),"do"|"try")){let token=tokens.get(i).ok_or("inline compound keyword unavailable")?;let mode=if token.text(source)=="try"{OriginalCaseContinuation::Try}else{OriginalCaseContinuation::Do};if let Some(cursor)=self.original_case_block_cursor_using(token.span.end,mode,checkpoint)?{return Ok(cursor)}return Err("inline try/do simple statement continuation unavailable".into())}
  // Inline primary items end before their delimiter. Recover only the real
  // following semicolon of this body. Its final Item (and enclosing body)
  // excludes that delimiter; never cross a physical newline/other statement.
  if !newline{let after=tokens.partition_point(|token|token.span.end<=case_end);for token in tokens.iter().skip(after){checkpoint()?;if (token.span.start>=self.body.end&&case_end!=self.body.end)||token.kind==TokenKind::Newline{break}if matches!(token.kind,TokenKind::Whitespace|TokenKind::Comment){if token.text(source).contains(['\r','\n']){break}continue}if token.span.start>=case_end&&token.text(source)==";"{let at=token.span;let start=at.start.checked_add(self.offset).ok_or("case terminator cursor overflow")?;let end=at.end.checked_add(self.offset).ok_or("case terminator cursor overflow")?;return Ok(dm_syntax::OriginalCaseCursor::Token(Span::new(start,end)))}break}}
  if !newline{let before=tokens.partition_point(|token|token.span.start<case_end);let mut significant=None;for token in tokens.iter().take(before).rev(){checkpoint()?;if !trivia(token){significant=Some(token);break}}if let Some(token)=significant{if token.text(source)==";"{let at=token.span;return Ok(dm_syntax::OriginalCaseCursor::Token(Span::new(at.start+self.offset,at.end+self.offset)))}}}
  let after=tokens.partition_point(|token|token.span.end<=case_end);let mut has_after=false;for token in tokens.iter().skip(after){checkpoint()?;if !trivia(token){has_after=true;break}}if !has_after{let before=tokens.partition_point(|token|token.span.start<case_end);let mut newline=None;for token in tokens.iter().take(before).rev(){checkpoint()?;if token.span.start<start{break}if token.kind==TokenKind::Newline{newline=Some(token.span);break}}let newline=newline.ok_or("case terminal newline token unavailable")?;return Ok(dm_syntax::OriginalCaseCursor::SourceEnd{offset:self.owner.source.len().checked_add(self.offset).ok_or("case terminal cursor overflow")?,fallback:Span::new(newline.start+self.offset,newline.end+self.offset)})}
  let before=tokens.partition_point(|token|token.span.start<case_end);let mut last=None;for token in tokens.iter().take(before).rev(){checkpoint()?;if token.span.end<=start{break}if token.kind==TokenKind::Newline{let at=token.span;return Ok(dm_syntax::OriginalCaseCursor::Token(Span::new(at.start+self.offset,at.end+self.offset)))}if !trivia(token)&&last.is_none(){last=Some(token);if !newline&&token.text(source)==";"{let at=token.span;return Ok(dm_syntax::OriginalCaseCursor::Token(Span::new(at.start+self.offset,at.end+self.offset)))}}}Err("case original line boundary unavailable".into())
 }
}

#[cfg(test)]mod original_switch_case_cursor_tests{
 use super::*;
 #[test]fn original_case_cursor_uses_primary_newline_explicit_close_and_terminal_marker(){
  for(source,expected)in[("/proc/probe(value)\n    switch(value)\n        if(1 || 2)\n            return 0\n        if(3)\n            return 0\n",Some((4,21))),("/proc/probe(value)\n    switch(value)\n        if(1 || 2)\n            return 0\n    return 1\n",Some((4,21))),("/proc/probe(value) { switch(value) { if(1 || 2) { return 0; } } }\n",Some((1,61))),("/proc/probe(value) {\n switch(value) {\n  if(1 || 2)\n   return 0\n }\n}\n",Some((5,2))),("/proc/probe(value)\n    switch(value)\n        if(1 || 2) {\n            return 0\n        }\n",Some((5,9))),("/proc/probe(value) { switch(value) { if(1 || 2) return 0; } }\n",Some((1,57))),("/proc/probe(value)\n    switch(value)\n        if(1 || 2) if(value)\n            return 0\n        if(3)\n            return 1\n",Some((5,9))),("/proc/probe(value)\n    switch(value)\n        if(1 || 2) while(value)\n            return 0\n        if(3)\n            return 1\n",Some((4,21))),("/proc/probe(value)\n    switch(value)\n        if(1 || 2) if(value)\n            return 0\n        else if(value == 2)\n            return 1\n        else\n            return 2\n        if(3)\n            return 3\n",Some((8,21))),("/proc/probe(value)\n    switch(value)\n        if(1 || 2) if(value)\n            return 0\n        else\n            return 1\n        else\n            return 2\n",Some((6,21))),("/proc/probe(value)\n    switch(value)\n        if(1 || 2) try\n            return 0\n        catch(var/error)\n            return 1\n        if(3)\n            return 2\n",Some((6,21))),("/proc/probe(value)\n    switch(value)\n        if(1 || 2) do\n            return 0\n        while(value)\n        if(3)\n            return 2\n",Some((5,21))),("/proc/probe(value)\n    switch(value)\n        if(1 || 2)\n            return 0\n",None)]{
   let ast=dm_syntax::parse(source);assert!(ast.diagnostics.is_empty(),"{:?}",ast.diagnostics);let procedure=&ast.items[0];let case=&procedure.children[0].children[0];let owner=OriginalProcedureHeaders::from_primary(source.into(),&ast.items,0,ast.tokens.iter().map(|token|SpanToken{kind:token.kind,span:token.span}).collect()).unwrap();let tokens=owner.body_tokens(procedure.span,0).unwrap();let cursor=tokens.switch_case_cursor_using(case.header_span,case.span,&mut||Ok::<(),&'static str>(())).unwrap();match(cursor,expected){(dm_syntax::OriginalCaseCursor::Token(at),Some(expected))=>{let prefix=&source[..at.start];let line=prefix.bytes().filter(|byte|*byte==b'\n').count()+1;let column=prefix.rsplit('\n').next().unwrap().len()+1;assert_eq!((line,column),expected);},(dm_syntax::OriginalCaseCursor::SourceEnd{offset,fallback},None)=>{assert_eq!(offset,source.len());assert_eq!(&source[fallback.range()],"\n");},_=>panic!("unexpected actual cursor {cursor:?}")}
  }
 }
}

#[cfg(test)]mod original_switch_cursor_control_tests{use super::*;#[derive(Debug)]enum Failure{Source(&'static str),Io(std::io::Error)}impl From<&'static str>for Failure{fn from(value:&'static str)->Self{Self::Source(value)}}#[test]fn actual_primary_case_cursor_propagates_first_typed_io_inside_its_token_walk(){let source="/proc/probe(value)\n    switch(value)\n        if(1 || 2)\n            return 0\n    return 1\n";let ast=dm_syntax::parse(source);let procedure=&ast.items[0];let case=&procedure.children[0].children[0];let owner=OriginalProcedureHeaders::from_primary(source.into(),&ast.items,0,ast.tokens.iter().map(|token|SpanToken{kind:token.kind,span:token.span}).collect()).unwrap();let tokens=owner.body_tokens(procedure.span,0).unwrap();let mut calls=0;let result=tokens.switch_case_cursor_using(case.header_span,case.span,&mut||{calls+=1;if calls==3{Err(Failure::Io(std::io::Error::from_raw_os_error(1450)))}else{Ok(())}});match result{Err(Failure::Io(actual))=>assert_eq!(actual.raw_os_error(),Some(1450)),other=>panic!("first actual token-walk IO lost: {other:?}")};assert_eq!(calls,3);}}

#[cfg(test)]mod original_inline_case_terminator_tests{
 use super::*;
 #[test]fn original_inline_case_uses_actual_following_primary_semicolon(){
  for source in ["/proc/probe(value) { switch(value) { if(1 || 2) return 0; } }\n","/proc/probe(value) { switch(value) { if(1 || 2) return 0   ; } }\n"]{
   let ast=dm_syntax::parse(source);assert!(ast.diagnostics.is_empty(),"{:?}",ast.diagnostics);let procedure=&ast.items[0];let case=&procedure.children[0].children[0];
   let semicolon=ast.tokens.iter().find(|token|token.text==";").unwrap();assert_eq!(procedure.span.end,case.span.end,"actual last primary item trims the enclosing body too");assert!(case.span.end<=semicolon.span.start);assert_eq!(&source[case.span.end..semicolon.span.start].trim(),&"");assert!(case.header_span.end<=case.span.end);
   let owner=OriginalProcedureHeaders::from_primary(source.into(),&ast.items,0,ast.tokens.iter().map(|token|SpanToken{kind:token.kind,span:token.span}).collect()).unwrap();let tokens=owner.body_tokens(procedure.span,0).unwrap();
   let cursor=tokens.switch_case_cursor_using(case.header_span,case.span,&mut||Ok::<(),&'static str>(())).unwrap();assert!(matches!(cursor,dm_syntax::OriginalCaseCursor::Token(at)if at==semicolon.span));
   let mut polls=0;let failed=tokens.switch_case_cursor_using(case.header_span,case.span,&mut||{polls+=1;Err::<(),&'static str>("actual cancellation")});assert!(matches!(failed,Err("actual cancellation")));assert_eq!(polls,1);
   let offset=usize::MAX-procedure.span.end;let shifted=owner.body_tokens(procedure.span,offset).unwrap();let header=Span::new(case.header_span.start+offset,case.header_span.end+offset);let case=Span::new(case.span.start+offset,case.span.end+offset);assert!(matches!(shifted.switch_case_cursor_using(header,case,&mut||Ok::<(),&'static str>(())),Err("case terminator cursor overflow")),"the real trailing token must not escape the admitted offset envelope");
  }
 }
}

#[cfg(test)]mod outer_terminator_primary_reissue_tests{
 use super::*;
 #[test]fn actual_primary_outer_events_survive_cold_retained_and_portable_unknown_reissue(){
  for(source,expected)in[("/proc/early()\n    return 1\n/proc/later(value=)\n    return 2\n",true),("/proc/early(){}\n/proc/later(value=)\n    return 2\n",true),("/proc/early() return 1\n/proc/later(value=)\n    return 2\n",false),("/proc/early()\n/proc/later(value=)\n    return 2\n",false)]{
   let before=OUTER_PRIMARY_REISSUES.with(|count|count.get());let parsed=dm_syntax::parse_declaration_skeleton(source);assert!(parsed.diagnostics.is_empty());let owner=OriginalProcedureHeaders::from_primary(source.into(),&parsed.items,0,parsed.tokens).unwrap();let fatal=source.find("value=").unwrap()+"value=".len();assert_eq!(owner.first_outer_block().is_some_and(|at|at<fatal),expected);let retained=owner.clone();assert_eq!(retained.first_outer_block(),owner.first_outer_block());assert_eq!(OUTER_PRIMARY_REISSUES.with(|count|count.get()),before,"cold/retained native primary events must not replay lexical/layout work");
   fn unissue(items:&mut[Item]){for item in items{item.original_outer_terminator=None;unissue(&mut item.children)}}let mut portable=parsed.items;unissue(&mut portable);let reissued=OriginalProcedureHeaders::reissue(source.into(),&portable,0).unwrap();assert_eq!(reissued.first_outer_block().is_some_and(|at|at<fatal),expected,"actual current primary geometry reissued; decoded bool is never trusted");assert_eq!(OUTER_PRIMARY_REISSUES.with(|count|count.get()),before+1,"portable unknown metadata reissues exactly once through existing owner");
  }
 }
 #[test]fn actual_portable_outer_geometry_reserves_peak_before_reissue_and_keeps_oom_identity(){
  let source="/proc/early(){}\n/proc/later(value=)\n    return 2\n";let mut parsed=dm_syntax::parse_declaration_skeleton(source);fn unissue(items:&mut[Item]){for item in items{item.original_outer_terminator=None;unissue(&mut item.children)}}unissue(&mut parsed.items);let counter=std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));let a=dm_syntax::SettingAdmission::new(&counter,16384,&||Ok(()));let failure=OriginalProcedureHeaders::from_primary_admitted(source.into(),&parsed.items,0,parsed.tokens,&a).unwrap_err();assert!(matches!(failure,OriginalHeaderFailure::Operational(ref actual)if actual.kind()==std::io::ErrorKind::OutOfMemory));assert_eq!(counter.load(std::sync::atomic::Ordering::Relaxed),0,"real failed geometry leaves no root admission outstanding");
 }

 #[test]fn real_outer_primary_event_reissue_keeps_typed_operational_error(){
  let source="/proc/early(){}\n/proc/later(value=)\n    return 2\n";let parsed=dm_syntax::parse_declaration_skeleton(source);let headers=parsed.items.iter().filter(|item|matches!(item.kind,ItemKind::Proc|ItemKind::Verb)).map(|item|item.header_span).collect::<Vec<_>>();let calls=std::cell::Cell::new(0);let result=dm_syntax::original_outer_terminator_observation_using(source,&parsed.tokens,&headers,&||{let n=calls.get()+1;calls.set(n);if n==3{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}});assert_eq!(result.unwrap_err().raw_os_error(),Some(1450));assert_eq!(calls.get(),3);
 }
}

/// Reservation only. This cannot retain a graph/header/source owner, so no
/// DiagnosticFrontend -> mapping/header -> graph cycle can be constructed.
struct OriginalPrimaryResourceHold(Arc<dm_syntax::SettingRootLease>);
impl std::fmt::Debug for OriginalPrimaryResourceHold{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalPrimaryResourceHold").field("reserved_bytes",&self.0.bytes()).finish()}}
impl OriginalProcedureHeaders{
 pub(crate) fn retain_original_primary_resource(&self,root:Arc<dm_syntax::SettingRootLease>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),OriginalHeaderFailure>{
  original_checkpoint(a)?;let coordinates=self.initializer_coordinates.as_ref().ok_or_else(||OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"unadmitted header cannot acquire a completed primary resource root")))?;if !a.matches_lease_domain(&coordinates.lease){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"primary header coordinate owner uses another native counter").into())}if !a.matches_lease_domain(&root){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual primary header resource root uses another native counter").into())}
  if let Some(held)=self.original_primary_resource.get(){return if Arc::ptr_eq(&held.0,&root){Ok(())}else{Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual primary header resource root was already issued").into())}}
  self.original_primary_resource.set(OriginalPrimaryResourceHold(root)).map_err(|_|OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual primary resource publication raced")))?;original_checkpoint(a)?;Ok(())
 }
}

impl OriginalProcedureHeaders{
 /// Installation happens once while the genuine primary outcome is being
 /// joined, before publication. The independent expected binding is carried by
 /// that actual outcome, never obtained from this numeric view or raw text.
 pub(crate) fn retain_original_literal_facts(&self,view:Option<dm_preprocess::regions::OriginalLiteralSourceView>,actual_primary:Option<&dm_preprocess::regions::OriginalLiteralSourceBinding>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),OriginalHeaderFailure>{
  original_checkpoint(a)?;
  let checked=match(view,actual_primary){
   (None,None)=>None,
   (Some(view),Some(actual))=>{
    if !view.same_producer(actual){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"header literal facts belong to another actual primary outcome").into())}
    let facts=view.checked_facts(&self.source)?;let(_,origin)=facts.raw_parts();let end=origin.checked_add(self.source.as_str().len()).ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual header source window overflow"))?;
    // Recheck the SAME binding's resource domain and actual checked source
    // view. This clones only its sealed no-Weak Arc, never the fact roster.
    Some(actual.checked_view(&self.source,Span::new(origin,end),actual,a)?)
   },
   _=>return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual header literal outcome binding is missing").into()),
  };
  self.original_literal_source.set(HeaderLiteralSourceHold(checked)).map_err(|_|OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual header literal facts were already published")))?;
  original_checkpoint(a)?;Ok(())
 }
 /// Returned row spans are in the sealed primary/TU coordinate frame. The
 /// view's TUorigin is subtracted for THIS exact header source view; no silent
 /// TU-global/chunk-local comparison or copied/rebased tuple Vec is possible.
 /// None is unissued, while any actual binding/cut error remains Err.
 pub(crate) fn original_literal_facts(&self)->std::io::Result<Option<dm_syntax::OriginalLiteralFactsView<'_>>>{
  match self.original_literal_source.get(){Some(HeaderLiteralSourceHold(Some(view)))=>view.checked_facts(&self.source).map(Some),Some(HeaderLiteralSourceHold(None))|None=>Ok(None)}
 }
}

#[cfg(test)]mod original_literal_header_state_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn header_literal_fact_unissued_state_is_not_a_completed_empty_roster_or_late_mutable_publication(){
  let source:SourceText="/proc/probe()\n    return 1\n".to_owned().into();let ast=dm_syntax::parse_declaration_skeleton(&source);let used=Arc::new(AtomicUsize::new(0));let a=dm_syntax::SettingAdmission::new(&used,1<<24,&||Ok(()));let headers=OriginalProcedureHeaders::from_primary_admitted(source,&ast.items,0,ast.tokens,&a).ok().unwrap();assert!(headers.original_literal_facts().unwrap().is_none(),"old/portable unissued parse never fabricates typed empty facts");headers.retain_original_literal_facts(None,None,&a).ok().unwrap();assert!(headers.original_literal_facts().unwrap().is_none());let error=headers.retain_original_literal_facts(None,None,&a).err().unwrap();assert!(matches!(error,OriginalHeaderFailure::Operational(actual)if actual.kind()==std::io::ErrorKind::InvalidInput));drop(headers);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod actual_shared_primary_header_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn genuine_final_primary_expanded_and_header_alias_the_same_immutable_token_allocation_and_lease(){let used=Arc::new(AtomicUsize::new(0));let a=dm_syntax::SettingAdmission::new(&used,1<<24,&||Ok(()));let source:SourceText="/proc/probe()\n    return 1\n".into();let primary=dm_syntax::parse_original_declaration_skeleton_using(&source,&a).unwrap();let ptr=primary.syntax().tokens.window().as_dense_slice().unwrap().as_ptr();let(primary,shared)=primary.into_shared_tokens_using(&a).unwrap();let mut expanded=dm_preprocess::regions::ExpandedRegions::with_text(source.clone());expanded.tokens=shared.clone().into();let headers=OriginalProcedureHeaders::for_declaration_profile_tokens(source.clone(),&primary.syntax().items,0,shared.clone().into(),&a,true).unwrap();assert_eq!(primary.syntax().tokens.window().as_dense_slice().unwrap().as_ptr(),ptr);assert_eq!(expanded.tokens.window().as_dense_slice().unwrap().as_ptr(),ptr);assert_eq!(headers.tokens.window().as_dense_slice().unwrap().as_ptr(),ptr);assert!(headers.shared_span_tokens().unwrap().same_owner(expanded.tokens.shared().unwrap()));drop((shared,primary,source));assert!(used.load(Ordering::Acquire)>0);assert_eq!(headers.tokens.window().len(),expanded.tokens.window().len());drop(expanded);assert!(used.load(Ordering::Acquire)>0);drop(headers);assert_eq!(used.load(Ordering::Acquire),0);}
}

#[cfg(test)]mod unissued_header_parameter_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]fn unissued_final_literal_default_owner_cannot_fabricate_valid_header_metadata(){
  let text:SourceText="/proc/p(datum/act/A)\n    return (1 + )\n".into();let ast=dm_syntax::parse_declaration_skeleton(&text);assert!(ast.diagnostics.is_empty());let header=ast.items[0].span;let used=Arc::new(AtomicUsize::new(0));let a=dm_syntax::SettingAdmission::new(&used,1<<20,&||Ok(()));let owner=OriginalProcedureHeaders::for_declaration_profile_tokens(text,&ast.items,0,ast.tokens.into(),&a,true).unwrap();owner.install_parameter_signatures(&a, |_| None).unwrap();assert_eq!(owner.parameter_signature(header).err(),Some("actual original parameter metadata is unissued"));drop(owner);assert_eq!(used.load(Ordering::Acquire),0);
 }
}


#[cfg(test)]
mod original_token_window_tests {
    use super::*;

    #[test]
    fn empty_dimension_requires_the_same_primary_backing_and_exact_ordinal() {
        let source: SourceText = "/datum/test\n    var/list/value[]\n".into();
        let parsed = dm_syntax::parse_declaration_skeleton(source.as_str());
        assert!(parsed.diagnostics.is_empty());
        let header = parsed.items[0].children[0].header_span;
        let owner = OriginalProcedureHeaders::from_primary(
            source, &parsed.items, 0, parsed.tokens,
        ).unwrap();
        let mut dimensions = owner.initializer_dimension_views(header).unwrap();
        let actual = dimensions.next().expect("issued array dimension").unwrap();
        assert!(actual.text().is_empty());
        let symbols = SymbolTable::default();
        assert!(owner.dimension_tokens_view(actual, None, &symbols).unwrap().is_none());

        let wrong_ordinal = HeaderView::original_window(
            &owner.source, owner.token_window(0, 0).unwrap(), actual.span(),
        ).unwrap();
        assert!(wrong_ordinal.token_window().iter().eq(actual.token_window().iter()));
        assert!(owner.dimension_tokens_view(wrong_ordinal, None, &symbols).is_err());

        let foreign = dm_syntax::SpanTokenStorage::default();
        let foreign_owner = HeaderView::original_window(&owner.source, foreign.window(), actual.span()).unwrap();
        assert!(owner.dimension_tokens_view(foreign_owner, None, &symbols).is_err());
    }
}
