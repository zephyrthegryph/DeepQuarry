//! Original setting coordinates live on SAME existing declaration token owner.
//! No Expr roots, independent parser/model, or transferable frame authority.
use super::{AdapterRows, HeaderAllocationRow, OriginalProcedureHeaders};
use crate::{
    procedure::{header::HeaderView, ParsedSetting},
    ProcedureMetadata,
};
use dm_syntax::{Item, ItemKind, SettingAdmission, SettingRootLease, Span};
use std::{collections::BTreeMap, sync::Arc};
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct SettingFootprint {
    pub(crate) header: Span,
    pub(crate) value: Span,
    pub(crate) ordinal: usize,
}
#[derive(Debug)]
pub(super) struct OriginalSettingsBody {
    body: Span,
    owner: Arc<ProcedureMetadata>,
    footprints: Arc<[SettingFootprint]>,
    roots: dm_syntax::SettingExpressionSlots,
    return_roots: dm_syntax::SettingExpressionSlots,
}
impl OriginalSettingsBody {
    pub(super) fn owner(&self) -> &Arc<ProcedureMetadata> {
        &self.owner
    }
}
/// The original header owns the private roster. Any RelativeBody footprint
/// aliases are owned by RelativeSyntax, which keeps this same header alive and
/// drops those aliases before the header. No standalone footprint escapes.
#[derive(Default)]
pub(super) struct SettingsRoster {
    rows: Vec<OriginalSettingsBody>,
    credit: Option<SettingRootLease>,
}
impl std::fmt::Debug for SettingsRoster {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SettingsRoster").field("rows", &self.rows).finish()
    }
}
impl std::ops::Deref for SettingsRoster {
    type Target = [OriginalSettingsBody];
    fn deref(&self) -> &Self::Target {
        &self.rows
    }
}

impl SettingsRoster {
    // Observation only: repeated references may share one retained grant.
    pub(super) fn resource_summary(&self)->(usize,usize,usize,usize){
        let(mut roots,mut grants)=(0usize,0usize);
        for row in &self.rows{for slots in [&row.roots,&row.return_roots]{slots.visit_storage(|_,_,_|{},|root|{roots+=1;grants=grants.saturating_add(root.retained_charge().unwrap_or(0));});}}
        (self.rows.len(),self.credit.as_ref().map_or(0,SettingRootLease::bytes),roots,grants)
    }
    fn fund(&mut self, bytes: usize, a: &SettingAdmission<'_>) -> std::io::Result<()> {
        if let Some(credit) = &mut self.credit {
            a.grow(credit, bytes).map_err(|e| a.take_operational_error().unwrap_or(e))
        } else {
            self.credit = Some(a.reserve(bytes).map_err(|e| a.take_operational_error().unwrap_or(e))?);
            Ok(())
        }
    }
}

fn relative(span: Span, offset: usize) -> Result<Span, String> {
    Ok(Span::new(
        span.start
            .checked_sub(offset)
            .ok_or("setting body before original chunk")?,
        span.end
            .checked_sub(offset)
            .ok_or("setting body end before original chunk")?,
    ))
}
fn checked_row<E: From<String> + From<&'static str>>(
    body: Span,
    owner: Arc<ProcedureMetadata>,
    rows: AdapterRows<SettingFootprint>,
    source: &str,
    fund: impl FnOnce(usize) -> Result<(), E>,
) -> Result<OriginalSettingsBody, E> {
    if rows.len() != owner.settings.len() {
        return Err("original setting count differs from actual metadata".into());
    }
    source
        .get(body.range())
        .ok_or("setting body is outside original source")?;
    if rows.windows(2).any(|p| p[0].header.end > p[1].header.start) {
        return Err("original setting directive spans overlap or reorder".into());
    }
    for (index, row) in rows.iter().enumerate() {
        if row.ordinal != index
            || row.header.start < body.start
            || row.header.end > body.end
            || row.value.start < row.header.start
            || row.value.end > row.header.end
        {
            return Err("original setting footprint ordinal or containment differs".into());
        }
        source
            .get(row.header.range())
            .ok_or("setting directive is not original UTF8 source")?;
        source
            .get(row.value.range())
            .ok_or("setting RHS is not original UTF8 source")?;
    }
    use std::{alloc::Layout, sync::atomic::AtomicUsize};
    let payload = Layout::array::<SettingFootprint>(rows.len())
        .map_err(|_| "setting footprint storage overflow")?;
    let (layout, _) = Layout::new::<[AtomicUsize; 2]>()
        .extend(payload)
        .map_err(|_| "setting footprint storage overflow")?;
    fund(layout.pad_to_align().size())?;
    Ok(OriginalSettingsBody {
        body,
        owner,
        footprints: rows.into_shared(),
        roots: Default::default(),
        return_roots: Default::default(),
    })
}
fn push(out: &mut Vec<OriginalSettingsBody>, row: OriginalSettingsBody) -> Result<(), String> {
    push_using(
        out,
        row,
        |_| "original setting row allocation refused".to_owned(),
        || "original setting row capacity overflow".to_owned(),
    )
}
fn push_using<E>(
    out: &mut Vec<OriginalSettingsBody>,
    row: OriginalSettingsBody,
    allocation: impl FnOnce(std::collections::TryReserveError) -> E,
    capacity: impl FnOnce() -> E,
) -> Result<(), E> {
    out.len()
        .checked_add(1)
        .and_then(|n| n.checked_mul(std::mem::size_of::<OriginalSettingsBody>()))
        .ok_or_else(capacity)?;
    out.try_reserve_exact(1).map_err(allocation)?;
    out.push(row);
    Ok(())
}
fn push_checked(
    roster: &mut SettingsRoster,
    row: OriginalSettingsBody,
    expected_rows: usize,
    a: &SettingAdmission<'_>,
) -> Result<(), super::OriginalHeaderFailure> {
    use std::io::ErrorKind;
    if roster.rows.len() >= expected_rows {
        return Err(std::io::Error::new(ErrorKind::InvalidData, "setting roster exceeds its checked row count").into());
    }
    if roster.rows.capacity() == 0 {
        // The actual adapter roster has already issued all setting tails.
        // Allocate exactly once after validating the first row, without
        // speculative capacity or a second live backing allocation.
        let (rows, mut storage) =
            crate::procedure::original_primary_signatures::allocate_funded_rows(expected_rows, a)?;
        let credit = roster.credit.as_mut().expect("checked footprint is funded before its row");
        a.absorb(credit, &mut storage)?;
        roster.rows = rows;
    }
    roster.rows.push(row);
    Ok(())
}

impl OriginalProcedureHeaders {
    pub(crate) fn parse_setting_original(
        &self,
        header: Span,
        offset: usize,
        symbols: &mut dm_ir::SymbolTable,
    ) -> Result<ParsedSetting, String> {
        crate::procedure::parse_setting_view_profile(
            self.original_setting_view(header, offset)?, symbols, self.checker_diagnostic_settings,
        )
    }

    fn original_setting_view(&self, header: Span, offset: usize) -> Result<HeaderView<'_>, String> {
        let range = relative(header, offset)?;
        self.source
            .get(range.range())
            .ok_or("setting header not in original source")?;
        let first = self.tokens.window().partition_point(|t| t.span.start < range.start);
        let last = self.tokens.window().partition_point(|t| t.span.start < range.end);
        let view = HeaderView::original_window(&self.source, self.token_window(first,last)?, range)?;
        Ok(view)
    }
    pub(crate) fn parse_setting_original_admitted(
        &self,
        header: Span,
        offset: usize,
        symbols: &mut dm_ir::SymbolTable,
        prepared: &mut crate::procedure::original_primary_signatures::PreparedOriginalSignatures,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<ParsedSetting, super::OriginalHeaderFailure> {
        use std::{alloc::Layout, io::{Error, ErrorKind}, sync::atomic::AtomicUsize};
        let poll = || a.checkpoint().map_err(|proxy| a.take_operational_error().unwrap_or(proxy));
        if !std::ptr::eq(self, prepared.actual_headers()) {
            return Err(Error::new(ErrorKind::InvalidInput, "setting token credit belongs to another original header owner").into());
        }
        let view = self.original_setting_view(header, offset)?;
        crate::procedure::parse_setting_view_profile_using(
            view, symbols, self.checker_diagnostic_settings, |value, symbols| {
                let mut count = 0usize;
                for token in value.token_window().iter() {
                    poll()?;
                    if !matches!(token.kind, dm_syntax::TokenKind::Whitespace | dm_syntax::TokenKind::Newline | dm_syntax::TokenKind::Comment) {
                        count = count.checked_add(1).ok_or_else(|| Error::from(ErrorKind::OutOfMemory))?;
                    }
                }
                if count == 0 {
                    return Err("empty procedure declaration expression".into());
                }
                let payload = Layout::array::<dm_ir::ExpressionToken>(count)
                    .map_err(|_| Error::from(ErrorKind::OutOfMemory))?;
                let (mut tokens, scratch) =
                    crate::procedure::original_primary_signatures::allocate_funded_rows(count, a)?;
                for token in value.token_window().iter() {
                    poll()?;
                    if let Some(token) = crate::procedure::expression_token(value, token, symbols)? {
                        tokens.push(token);
                    }
                }
                let (layout, _) = Layout::new::<[AtomicUsize; 2]>().extend(payload)
                    .map_err(|_| Error::from(ErrorKind::OutOfMemory))?;
                prepared.admit_adapter_storage(layout.pad_to_align().size(), a)?;
                let tokens = Arc::from(tokens);
                drop(scratch);
                Ok(dm_ir::SymbolicExpression { tokens })
            },
        )
    }
    pub(super) fn install_settings<'rows>(
        &self,
        rows: impl Iterator<Item = &'rows mut HeaderAllocationRow>,
        offset: usize,
    ) -> Result<(), String> {
        self.install_settings_using(rows, offset, |roster, body, owner, footprints| {
            let row = checked_row(body, owner, footprints, &self.source, |_| Ok::<_, String>(()))?;
            push(&mut roster.rows, row)
        })
    }
    pub(super) fn install_settings_checked<'rows>(
        &self,
        rows: impl Iterator<Item = &'rows mut HeaderAllocationRow>,
        expected_rows: usize,
        offset: usize,
        a: &SettingAdmission<'_>,
    ) -> Result<(), super::OriginalHeaderFailure> {
        self.install_settings_using(rows, offset, |roster, body, owner, footprints| {
            let row = checked_row(body, owner, footprints, &self.source, |bytes| {
                roster.fund(bytes, a).map_err(super::OriginalHeaderFailure::Operational)
            })?;
            if let Some(products)=self.committed_products(){
                let index=self.headers.binary_search_by_key(&body.start,|span|span.start).map_err(|_|super::OriginalHeaderFailure::Operational(std::io::ErrorKind::InvalidInput.into()))?;
                for footprint in row.footprints.iter(){
                    super::original_checkpoint(a)?;
                    let(root,facts)=products.produced_setting(index,footprint.header,a).map_err(|error|match error{dm_syntax::SettingSyntaxFailure::Operational(actual)=>super::OriginalHeaderFailure::Operational(a.take_operational_error().unwrap_or(actual)),dm_syntax::SettingSyntaxFailure::Syntax(_)=>super::OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"committed setting first writer retained a syntax failure"))})?;
                    if root.current_offset()!=0||root.original_expression().span!=footprint.value{return Err(super::OriginalHeaderFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"committed setting root differs from final actual footprint")))}
                    row.roots.obtain_with_native_observation(footprint.ordinal,row.footprints.len(),a,||Ok((root,facts))).map_err(|error|match error{dm_syntax::SettingSyntaxFailure::Operational(actual)=>super::OriginalHeaderFailure::Operational(a.take_operational_error().unwrap_or(actual)),dm_syntax::SettingSyntaxFailure::Syntax(_)=>super::OriginalHeaderFailure::Operational(std::io::ErrorKind::InvalidData.into())})?;
                }
                products.finish_settings_transfer(index).map_err(super::OriginalHeaderFailure::Operational)?;
            }
            push_checked(roster, row, expected_rows, a)
        })
    }
    fn install_settings_using<'rows, E: From<String> + From<&'static str>>(
        &self,
        rows: impl Iterator<Item = &'rows mut HeaderAllocationRow>,
        offset: usize,
        mut push_row: impl FnMut(&mut SettingsRoster, Span, Arc<ProcedureMetadata>, AdapterRows<SettingFootprint>) -> Result<(), E>,
    ) -> Result<(), E> {
        let mut settings = SettingsRoster::default();
        for row in rows {
            let Some(mut tail) = row.settings.take() else { continue };
            push_row(
                &mut settings,
                relative(tail.payload.body, offset)?,
                Arc::clone(&tail.payload.owner),
                std::mem::take(&mut tail.payload.footprints),
            )?;
        }
        self.finish_settings(settings).map_err(Into::into)
    }
    fn finish_settings(&self, mut settings: SettingsRoster) -> Result<(), String> {
        settings.rows.sort_unstable_by_key(|r| r.body.start);
        if settings
            .windows(2)
            .any(|p| p[0].body.start == p[1].body.start)
        {
            return Err("duplicate original setting body".into());
        }
        if let Some(old) = self.settings.get() {
            if old.len() != settings.len()
                || old.iter().zip(settings.iter()).any(|(a, b)| {
                    a.body != b.body
                        || !Arc::ptr_eq(&a.owner, &b.owner)
                        || a.footprints != b.footprints
                })
            {
                return Err("original settings already belong to another metadata owner".into());
            }
            return Ok(());
        }
        self.settings
            .set(settings)
            .map_err(|_| "original setting publication raced".to_owned())
    }
    /// Portable facts do not carry coordinate authority. Reissue with SAME current
    /// original token grammar; no Expr parse, source read or copied model occurs.
    pub(crate) fn reissue_settings_if_missing(
        &self,
        items: &[Item],
        owners: &BTreeMap<usize, Arc<ProcedureMetadata>>,
    ) -> Result<(), String> {
        if self.settings.get().is_some() {
            return self.require_issued_settings_items(dm_syntax::OriginalItems::from_items(items),owners);
        }
        fn walk(
            input: &OriginalProcedureHeaders,
            items: &[Item],
            owners: &BTreeMap<usize, Arc<ProcedureMetadata>>,
            out: &mut Vec<OriginalSettingsBody>,
        ) -> Result<(), String> {
            for item in items {
                if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
                    // Existing original proc-header issuance guards the body association.
                    input.original(item.header_span, 0)?;
                    let owner = owners
                        .get(&item.span.start)
                        .ok_or("portable setting metadata owner is missing")?;
                    let mut symbols = dm_ir::SymbolTable::default();
                    let (nodes, footprints) = crate::settings::extract_settings_original(
                        &item.children,
                        &mut symbols,
                        input,
                        0,
                    )?;
                    if nodes.as_ref() != owner.settings.as_ref() {
                        return Err(
                            "portable settings differ from original current metadata".into()
                        );
                    }
                    if !nodes.is_empty() || owner.signature.return_annotation.is_some() {
                        push(
                            out,
                            checked_row(item.span, Arc::clone(owner), footprints, &input.source, |_| Ok::<_, String>(()))?,
                        )?;
                    }
                } else {
                    walk(input, &item.children, owners, out)?;
                }
            }
            Ok(())
        }
        let mut rows = Vec::new();
        walk(self, items, owners, &mut rows)?;
        self.finish_settings(SettingsRoster { rows, credit: None })
    }
    pub(crate) fn require_issued_settings_items(
        &self, items:dm_syntax::OriginalItems<'_>, owners:&BTreeMap<usize,Arc<ProcedureMetadata>>,
    )->Result<(),String>{
        let rows=self.settings.get().ok_or("original setting roster is unissued")?;
        fn validate(
            input: &OriginalProcedureHeaders,
            items: dm_syntax::OriginalItems<'_>,
            owners: &BTreeMap<usize, Arc<ProcedureMetadata>>,
            count: &mut usize,
        ) -> Result<(), String> {
            for item in items.iter() {
                if matches!(item.kind(), ItemKind::Proc | ItemKind::Verb) {
                    input.original(item.header_span(), 0)?;
                    let owner = owners
                        .get(&item.span().start)
                        .ok_or("current setting metadata owner is missing")?;
                    let issued = input.settings.get().unwrap();
                    let row = issued
                        .binary_search_by_key(&item.span().start, |r| r.body.start)
                        .ok()
                        .and_then(|i| issued.get(i));
                    if owner.settings.is_empty() && owner.signature.return_annotation.is_none()
                    {
                        if row.is_some() {
                            return Err(
                                "current empty settings differ from original nonempty body"
                                    .into(),
                            );
                        }
                    } else {
                        input.expression_row(item.span(), owner)?;
                        *count = count.checked_add(1).ok_or("setting body count overflow")?;
                    }
                } else {
                    validate(input, item.children(), owners, count)?;
                }
            }
            Ok(())
        }
        let mut count = 0;
        validate(self, items, owners, &mut count)?;
        if count != rows.len() {
            return Err("current settings roster differs from original issued bodies".into());
        }
        Ok(())
    }
    pub(crate) fn abi_source_len(&self)->usize{self.source.len()}
    pub(crate) fn cached_abi_root(&self,body:Span,owner:&Arc<ProcedureMetadata>,ordinal:usize,count:usize,returns:bool,a:&dm_syntax::SettingAdmission<'_>)->Result<dm_syntax::SettingExpression,dm_syntax::SettingSyntaxFailure>{
      let fail=|message:String|dm_syntax::SettingSyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,message));
      let row=self.expression_row(body,owner).map_err(fail)?;
      let slots=if returns{&row.return_roots}else{if count!=owner.settings.len(){return Err(fail("ABI setting source count differs".into()))}&row.roots};
      slots.obtain(ordinal,count,a,||Err(dm_syntax::SettingSyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"successful ABI source root is no longer retained"))))
    }
    fn expression_row(
        &self,
        body: Span,
        owner: &Arc<ProcedureMetadata>,
    ) -> Result<&OriginalSettingsBody, String> {
        let rows = self
            .settings
            .get()
            .ok_or("original expression metadata input is unissued")?;
        let row = rows
            .binary_search_by_key(&body.start, |r| r.body.start)
            .ok()
            .and_then(|i| rows.get(i))
            .ok_or("original expression body is unissued")?;
        if row.body != body || !Arc::ptr_eq(&row.owner, owner) {
            return Err("original expression body or metadata owner differs".into());
        }
        Ok(row)
    }
    /// Source-coordinate projection of ONE original annotation fragment. No Expr
    /// grammar is demanded here. Exact tokens/offsets are checked against the
    /// same original primary header, not reconstructed or normalized text.
    pub(crate) fn return_fragment<'a>(
        &'a self,
        body: Span,
        owner: &Arc<ProcedureMetadata>,
        fragment: &dm_ir::SymbolicExpression,
        symbols: &dm_ir::SymbolTable,
    ) -> Result<
        (
            &'a str,
            dm_syntax::TokenWindow<'a>,
            Span,
            usize,
            usize,
            &'a dm_syntax::SettingExpressionSlots,
        ),
        String,
    > {
        let row = self.expression_row(body, owner)?;
        let annotation = owner
            .signature
            .return_annotation
            .as_ref()
            .ok_or("original return annotation absent")?;
        let mut ordinal = None;
        let mut count = 0usize;
        for (i, part) in annotation
            .tokens
            .split(|t| symbols.text(t.text) == Some("|"))
            .enumerate()
        {
            count = count
                .checked_add(1)
                .ok_or("return fragment count overflow")?;
            if part == fragment.tokens.as_ref() {
                if ordinal.replace(i).is_some() {
                    return Err("original return fragment is ambiguous".into());
                }
            }
        }
        let ordinal =
            ordinal.ok_or("return fragment is not the original annotation token projection")?;
        let header = self
            .headers
            .binary_search_by_key(&body.start, |s| s.start)
            .ok()
            .and_then(|i| self.headers.get(i))
            .copied()
            .ok_or("original return procedure header unavailable")?;
        let view = self.original(header, 0)?;
        let parts = self.parts(header, 0, view.text())?;
        let annotation_view = crate::procedure::return_annotation_view(parts.trailing)?
            .ok_or("original return annotation absent from the primary header")?;
        let base = annotation_view.span().start;
        let mut expected = annotation.tokens.iter();
        for token in annotation_view.token_window().iter().filter(|t| {
            !matches!(
                t.kind,
                dm_syntax::TokenKind::Whitespace
                    | dm_syntax::TokenKind::Newline
                    | dm_syntax::TokenKind::Comment
            )
        }) {
            let actual = expected
                .next()
                .ok_or("return annotation primary token count differs")?;
            if actual.kind != token.kind
                || actual.relative_span != annotation_view.relative_span(&token)
                || symbols.text(actual.text) != Some(annotation_view.spelling(&token))
            {
                return Err("return annotation differs from original primary tokens".into());
            }
        }
        if expected.next().is_some() {
            return Err("return annotation primary token count differs".into());
        }
        let first = fragment
            .tokens
            .first()
            .ok_or("empty return annotation fragment")?;
        let last = fragment
            .tokens
            .last()
            .ok_or("empty return annotation fragment")?;
        let value = Span::new(
            base.checked_add(first.relative_span.start)
                .ok_or("return annotation span overflow")?,
            base.checked_add(last.relative_span.end)
                .ok_or("return annotation span overflow")?,
        );
        if value.end > annotation_view.span().end || value.start > value.end {
            return Err("return annotation fragment escapes original header".into());
        }
        let begin = self.tokens.window().partition_point(|t| t.span.start < value.start);
        let end = self.tokens.window().partition_point(|t| t.span.start < value.end);
        let tokens = self.token_window(begin,end)?;
        if tokens.iter().any(|t| t.span.end > value.end) {
            return Err("return annotation token escapes original fragment".into());
        }
        Ok((
            &self.source,
            tokens,
            value,
            ordinal,
            count,
            &row.return_roots,
        ))
    }
    pub(crate) fn settings_footprints(
        &self,
        body: Span,
        owner: &Arc<ProcedureMetadata>,
    ) -> Result<Option<&Arc<[SettingFootprint]>>, String> {
        if owner.settings.is_empty() {
            return Ok(None);
        }
        let rows = self
            .settings
            .get()
            .ok_or("original setting footprint input is unissued")?;
        let row = rows
            .binary_search_by_key(&body.start, |r| r.body.start)
            .ok()
            .and_then(|i| rows.get(i))
            .ok_or("original setting body is unissued")?;
        if row.body != body || !Arc::ptr_eq(&row.owner, owner) {
            return Err("original setting body or metadata owner differs".into());
        }
        Ok(Some(&row.footprints))
    }
    /// Original recipe metadata owner, NOT a possibly shared runtime tree Arc.
    /// The current caller must separately authenticate its frame/occurrence/code.
    pub(crate) fn setting_value_tokens<'a>(
        &'a self,
        body: Span,
        owner: &Arc<ProcedureMetadata>,
        footprint: &SettingFootprint,
    ) -> Result<(&'a str, dm_syntax::TokenWindow<'a>), String> {
        let rows = self
            .settings_footprints(body, owner)?
            .ok_or("setting RHS has no original body row")?;
        let issued = rows
            .get(footprint.ordinal)
            .ok_or("setting RHS ordinal differs")?;
        if !std::ptr::eq(issued, footprint) {
            return Err("setting RHS footprint is not this original owner's reference".into());
        }
        let first = self
            .tokens
            .window()
            .partition_point(|t| t.span.start < issued.value.start);
        let last = self
            .tokens
            .window()
            .partition_point(|t| t.span.start < issued.value.end);
        let tokens = self.token_window(first,last)?;
        if tokens.iter().any(|t| t.span.end > issued.value.end) {
            return Err("setting RHS token escaped original footprint".into());
        }
        Ok((&self.source, tokens))
    }
    /// Borrow original setting syntax partition without re-extracting metadata
    /// or parsing any expression. This is the SAME producer policy used when
    /// the footprint and its immutable original metadata were issued.
    pub(crate) fn setting_statement_parts<'a>(
        &'a self,
        body: Span,
        owner: &Arc<ProcedureMetadata>,
        footprint: &SettingFootprint,
    ) -> Result<(&'a str, &'static str), String> {
        self.setting_value_tokens(body, owner, footprint)?;
        let first = self
            .tokens
            .window()
            .partition_point(|t| t.span.start < footprint.header.start);
        let last = self
            .tokens
            .window()
            .partition_point(|t| t.span.start < footprint.header.end);
        let view = HeaderView::original_window(&self.source, self.token_window(first,last)?, footprint.header)?;
        let parts = crate::procedure::setting_parts(view)?;
        let value = Span::new(
            footprint.header.start + parts.value_span.start,
            footprint.header.start + parts.value_span.end,
        );
        if value != footprint.value {
            return Err("setting statement RHS partition differs from original issuer".into());
        }
        let relation = match parts.operation {
            dm_ir::SettingOperation::Assign => "=",
            dm_ir::SettingOperation::In => "in",
        };
        Ok((parts.name.text(), relation))
    }
    /// The caller already owns an exact current body/code receipt. Reuse the
    /// SAME original token/reference check before exposing its lazy root slots.
    pub(crate) fn setting_root_slots(
        &self,
        body: Span,
        owner: &Arc<ProcedureMetadata>,
        footprint: &SettingFootprint,
    ) -> Result<&dm_syntax::SettingExpressionSlots, String> {
        self.setting_value_tokens(body, owner, footprint)?;
        let rows = self
            .settings
            .get()
            .ok_or("original setting rows unavailable")?;
        let index = rows
            .binary_search_by_key(&body.start, |row| row.body.start)
            .map_err(|_| "original setting body unavailable")?;
        Ok(&rows[index].roots)
    }
    pub(crate) fn visit_setting_roots(&self, mut visit: impl FnMut(&dm_syntax::SettingExpression)) {
        if let Some(rows) = self.settings.get() {
            for row in rows.iter() {
                row.roots.visit_storage(|_, _, _| {}, &mut visit);
                row.return_roots.visit_storage(|_, _, _| {}, &mut visit);
            }
        }
    }
    pub(super) fn visit_settings_storage(&self, visit: &mut impl FnMut(usize, usize, usize)) {
        if let Some(rows) = self.settings.get() {
            if rows.rows.capacity() > 0 {
                visit(
                    rows.as_ptr() as usize,
                    rows.len() * std::mem::size_of::<OriginalSettingsBody>(),
                    rows.rows.capacity() * std::mem::size_of::<OriginalSettingsBody>(),
                );
            }
            for row in rows.iter() {
                row.roots.visit_storage(&mut *visit, |_| {});
                row.return_roots.visit_storage(&mut *visit, |_| {});
                let bytes = std::mem::size_of_val(row.footprints.as_ref())
                    + 2 * std::mem::size_of::<usize>();
                visit(row.footprints.as_ptr() as usize, bytes, bytes);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn original(source: &str) -> (dm_syntax::AstFile, Arc<OriginalProcedureHeaders>) {
        let parsed = dm_syntax::parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let input = OriginalProcedureHeaders::from_primary(
            source.to_owned().into(),
            &parsed.items,
            0,
            parsed.tokens,
        )
        .unwrap();
        (
            dm_syntax::AstFile {
                items: parsed.items,
                ..Default::default()
            },
            input,
        )
    }
    #[test]
    fn original_setting_tokens_use_exact_scratch_below_the_old_capacity_envelope() {
        use std::{alloc::Layout, sync::atomic::{AtomicUsize, Ordering}};
        let root = dm_syntax::SettingChargeCounter::root_allocation_bytes();
        let counter = dm_syntax::SettingChargeCounter::try_new(root).unwrap();
        let a = SettingAdmission::new(&counter, 8 << 20, &|| Ok(()));
        let source = "/proc/probe()\n    set name = \"issued\"\n    return 1\n";
        let site = "set name = \"issued\"";
        let start = source.find(site).unwrap();
        let mut original = crate::procedure::original_primary_signatures::parse_original_signatures_using(
            source.into(), &a,
        ).unwrap();
        let live = counter.load(Ordering::Acquire);
        let token = Layout::new::<dm_ir::ExpressionToken>();
        let arc = Layout::new::<[AtomicUsize; 2]>().extend(token).unwrap().0.pad_to_align();
        assert!(token.size() + arc.size() < 4 * token.size());
        let tight = SettingAdmission::new(&counter, live + token.size() + arc.size(), &|| Ok(()));
        let setting = original.headers.parse_setting_original_admitted(
            Span::new(start, start + site.len()), 0, &mut original.symbols, &mut original.prepared, &tight,
        ).unwrap();
        assert_eq!(setting.setting.value.tokens.len(), 1);
        assert_eq!(counter.load(Ordering::Acquire), live + arc.size());
        drop((setting, original));
        assert_eq!(counter.load(Ordering::Acquire), root);
    }

    #[test]
    fn checked_settings_roster_funds_actual_storage_and_denial_publishes_nothing() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        let source = "/proc/check()\n    set waitfor = 0\n    return 1\n";
        let used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let a = SettingAdmission::new(&used, 4 << 20, &|| Ok(()));
        let parsed = dm_syntax::parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty());
        let input = OriginalProcedureHeaders::from_primary_admitted(
            source.to_owned().into(), &parsed.items, 0, parsed.tokens, &a,
        ).unwrap();
        let ast = dm_syntax::AstFile { items: parsed.items, ..Default::default() };
        let (facts, receipt) = crate::adapter::from_ast_with_source_headers_checked(
            &ast, dm_ir::SymbolTable::default(), dm_ir::FileId(0), 0, 0, source, &input, 0, &a,
        ).unwrap().unwrap();
        let roster = input.settings.get().unwrap();
        let bytes = roster.rows.capacity() * std::mem::size_of::<OriginalSettingsBody>()
            + std::mem::size_of::<SettingFootprint>() + 2 * std::mem::size_of::<usize>();
        assert_eq!(roster.credit.as_ref().unwrap().bytes(), bytes);
        let row = &roster[0];
        let other = OriginalProcedureHeaders::reissue(input.source.clone(), &ast.items, 0).unwrap();
        let payload = super::super::HeaderSettingsPayload {
            body: ast.items[0].span, owner: Arc::clone(&row.owner),
            footprints: AdapterRows::default(),
        };
        let before_tail = used.load(Ordering::Acquire);
        let tail = super::super::HeaderSettingsTail::checked(payload, &a).unwrap();
        assert_eq!(used.load(Ordering::Acquire) - before_tail,
            std::mem::size_of::<super::super::HeaderSettingsPayload>());
        assert!(Arc::ptr_eq(&tail.payload.owner, &row.owner));
        drop(tail);
        assert_eq!(used.load(Ordering::Acquire), before_tail);
        let mut denied = [HeaderAllocationRow {
            header: ast.items[0].header_span, argument_offset: 0, declarations: Vec::new(),
            settings: Some(super::super::HeaderSettingsTail::compatibility(
                super::super::HeaderSettingsPayload {
                    body: ast.items[0].span, owner: row.owner.clone(),
                    footprints: AdapterRows::compatibility(row.footprints.to_vec()),
                },
            )),
        }];
        let denied_used = dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
        let low = SettingAdmission::new(&denied_used, dm_syntax::SettingChargeCounter::root_allocation_bytes() + (1), &|| Ok(()));
        assert!(matches!(other.install_settings_checked(denied.iter_mut(), 1, 0, &low),
            Err(super::super::OriginalHeaderFailure::Operational(e)) if e.kind() == std::io::ErrorKind::OutOfMemory));
        assert!(other.settings.get().is_none());
        assert_eq!(denied_used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
        drop((denied, facts, receipt));
        assert!(used.load(Ordering::Acquire) >= dm_syntax::SettingChargeCounter::root_allocation_bytes() + (bytes));
        drop(input);
        assert_eq!(used.load(Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
    }

    #[test]
    fn fresh_setting_footprints_reuse_first_metadata_pass_and_preserve_ordinals() {
        let source="/proc/check()\n    if(1)\n        set waitfor = 0\n    set src in world\n    return 1\n";
        let (ast, input) = original(source);
        let before = crate::procedure::original_setting_metadata_parses();
        let (facts, _receipt) = crate::adapter::from_ast_with_source_headers(
            &ast,
            dm_ir::SymbolTable::default(),
            dm_ir::FileId(0),
            0,
            0,
            source,
            &input,
            0,
        )
        .unwrap();
        assert_eq!(
            crate::procedure::original_setting_metadata_parses() - before,
            2
        );
        let mut owners = BTreeMap::new();
        for (fact, origin) in facts.skeletons.iter().zip(&facts.origins) {
            if let crate::Skeleton::Member { metadata, .. } = fact {
                if let Some(owner) = metadata.procedure.as_ref() {
                    owners.insert(origin.span.start as usize, owner.clone());
                }
            }
        }
        let owner = owners.get(&ast.items[0].span.start).unwrap();
        let rows = input
            .settings_footprints(ast.items[0].span, owner)
            .unwrap()
            .unwrap();
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].ordinal, 0);
        assert_eq!(&source[rows[0].value.range()], "0");
        assert_eq!(rows[1].ordinal, 1);
        assert_eq!(&source[rows[1].value.range()], "world");
        let (text, tokens) = input
            .setting_value_tokens(ast.items[0].span, owner, &rows[0])
            .unwrap();
        assert_eq!(text, source);
        assert_eq!(
            tokens.iter().map(|t| t.text(text)).collect::<Vec<_>>(),
            ["0"]
        );
        let copied_footprint = rows[0];
        assert!(input
            .setting_value_tokens(ast.items[0].span, owner, &copied_footprint)
            .is_err());

        let _relative = crate::frontend::RelativeSyntax::capture_with_settings_headers(
            ast.items.clone(),
            input.source.clone(),
            &owners,
            Some(input.clone()),
        )
        .unwrap();
        assert_eq!(
            crate::procedure::original_setting_metadata_parses() - before,
            2,
            "fresh relative capture must not extract metadata again"
        );
        let copied = Arc::new((**owner).clone());
        assert!(input
            .settings_footprints(ast.items[0].span, &copied)
            .is_err());
        let mut foreign = owners.clone();
        foreign.insert(ast.items[0].span.start, copied);
        assert!(
            crate::frontend::RelativeSyntax::capture_with_settings_headers(
                ast.items.clone(),
                input.source.clone(),
                &foreign,
                Some(input.clone())
            )
            .is_err()
        );
        let mut storage = Vec::new();
        input.visit_storage(|p, n, c| storage.push((p, n, c)));
        assert!(storage.iter().any(|(p, _, c)| *p == rows.as_ptr() as usize
            && *c >= rows.len() * std::mem::size_of::<SettingFootprint>()));
        let reissued =
            OriginalProcedureHeaders::reissue(input.source.clone(), &ast.items, 0).unwrap();
        let _relative = crate::frontend::RelativeSyntax::capture_with_settings_headers(
            ast.items.clone(),
            input.source.clone(),
            &owners,
            Some(reissued.clone()),
        )
        .unwrap();
        assert_eq!(
            crate::procedure::original_setting_metadata_parses() - before,
            4,
            "portable metadata reissues SAME original grammar once"
        );
        assert_eq!(
            reissued
                .settings_footprints(ast.items[0].span, owner)
                .unwrap()
                .unwrap()
                .as_ref(),
            rows.as_ref()
        );
    }
    #[test]
    fn setting_view_metadata_and_legacy_error_order_are_identical() {
        for source in [
            "/proc/check()\n    set desc = \"é\"\n    set hidden = 0\n",
            "/proc/check()\n    set na/* comment */me = 1\n",
            "/proc/check()\n    set SpacemanDMM_should_be_pure/*comment*/ = 1\n",
            "/proc/check()\n    set waitfor = 1 /* trailing comment */\n",
            "/proc/check()\n    set src in /* comment */ world\n",
            "/proc/check()\n    set imaginary = 1\n",
            "/proc/check()\n    set waitfor =\n",
            "/proc/check()\n    if(1)\n        set src in world\n",
        ] {
            let (ast, input) = original(source);
            let old = crate::adapter::from_ast(
                &ast,
                dm_ir::SymbolTable::default(),
                dm_ir::FileId(0),
                0,
                0,
            );
            let native = crate::adapter::from_ast_with_source_headers(
                &ast,
                dm_ir::SymbolTable::default(),
                dm_ir::FileId(0),
                0,
                0,
                source,
                &input,
                0,
            );
            match (old, native) {
                (Ok(old), Ok((new, _))) => assert_eq!(old.skeletons, new.skeletons),
                (Err(old), Err(new)) => assert_eq!(
                    old.iter()
                        .map(|e| (&e.kind, &e.message))
                        .collect::<Vec<_>>(),
                    new.iter()
                        .map(|e| (&e.kind, &e.message))
                        .collect::<Vec<_>>()
                ),
                other => panic!(
                    "original setting metadata acceptance differs: {:?}",
                    (other.0.is_ok(), other.1.is_ok())
                ),
            }
        }
    }
}

#[cfg(test)]
mod checked_metadata_allocation_tests {
    use super::*;
    use std::{mem::size_of, sync::atomic::Ordering};

    #[test]
    fn checked_settings_roster_admits_only_the_actual_sparse_row_count() {
        let root = dm_syntax::SettingChargeCounter::root_allocation_bytes();
        let used = dm_syntax::SettingChargeCounter::try_new(root).unwrap();
        let total = 5 * size_of::<OriginalSettingsBody>();
        let admission = SettingAdmission::new(&used, root + total, &|| Ok(()));
        let mut roster = SettingsRoster::default();
        roster.fund(0, &admission).unwrap();
        let metadata = Arc::new(ProcedureMetadata {
            signature: dm_ir::ProcedureSignature {
                parameters: Arc::from([]),
                variadic: false,
                return_annotation: None,
            },
            settings: Arc::from([]),
        });
        for start in 0..5 {
            push_checked(&mut roster, OriginalSettingsBody {
                body: Span::new(start, start + 1),
                owner: Arc::clone(&metadata),
                footprints: Arc::from([]),
                roots: Default::default(),
                return_roots: Default::default(),
            }, 5, &admission).unwrap();
            assert_eq!(used.load(Ordering::Acquire), root + total);
        }
        assert_eq!(roster.rows.capacity(), 5);
        drop(roster);
        assert_eq!(used.load(Ordering::Acquire), root);
    }
}
