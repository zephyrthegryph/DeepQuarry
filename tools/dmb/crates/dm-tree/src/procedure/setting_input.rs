//! Original setting coordinates live on SAME existing declaration token owner.
//! No Expr roots, independent parser/model, or transferable frame authority.
use super::{HeaderAllocationRow, OriginalProcedureHeaders};
use crate::{
    procedure::{header::HeaderView, ParsedSetting},
    ProcedureMetadata,
};
use dm_syntax::{Item, ItemKind, Span};
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
fn checked_row(
    body: Span,
    owner: Arc<ProcedureMetadata>,
    rows: Vec<SettingFootprint>,
    source: &str,
) -> Result<OriginalSettingsBody, String> {
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
    rows.len()
        .checked_mul(std::mem::size_of::<SettingFootprint>())
        .and_then(|n| n.checked_add(2 * std::mem::size_of::<usize>()))
        .ok_or("setting footprint storage overflow")?;
    Ok(OriginalSettingsBody {
        body,
        owner,
        footprints: rows.into(),
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
#[derive(Debug)]
struct OriginalSettingAllocationFailure(std::collections::TryReserveError);
impl std::fmt::Display for OriginalSettingAllocationFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("original setting row allocation refused")
    }
}
impl std::error::Error for OriginalSettingAllocationFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.0)
    }
}
fn setting_allocation(actual: std::collections::TryReserveError) -> super::OriginalHeaderFailure {
    super::OriginalHeaderFailure::Operational(std::io::Error::new(
        std::io::ErrorKind::OutOfMemory,
        OriginalSettingAllocationFailure(actual),
    ))
}
fn push_checked(
    out: &mut Vec<OriginalSettingsBody>,
    row: OriginalSettingsBody,
) -> Result<(), super::OriginalHeaderFailure> {
    push_using(out, row, setting_allocation, || {
        super::OriginalHeaderFailure::Operational(std::io::Error::new(
            std::io::ErrorKind::OutOfMemory,
            "original setting row capacity overflow",
        ))
    })
}

impl OriginalProcedureHeaders {
    pub(crate) fn parse_setting_original(
        &self,
        header: Span,
        offset: usize,
        symbols: &mut dm_ir::SymbolTable,
    ) -> Result<ParsedSetting, String> {
        let range = relative(header, offset)?;
        self.source
            .get(range.range())
            .ok_or("setting header not in original source")?;
        let first = self.tokens.window().partition_point(|t| t.span.start < range.start);
        let last = self.tokens.window().partition_point(|t| t.span.start < range.end);
        let view = HeaderView::original_window(&self.source, self.token_window(first,last)?, range)?;
        crate::procedure::parse_setting_view_profile(view, symbols,self.checker_diagnostic_settings)
    }
    pub(super) fn install_settings(
        &self,
        rows: &mut [HeaderAllocationRow],
        offset: usize,
    ) -> Result<(), String> {
        self.install_settings_using(rows, offset, push)
    }
    pub(super) fn install_settings_checked(
        &self,
        rows: &mut [HeaderAllocationRow],
        offset: usize,
    ) -> Result<(), super::OriginalHeaderFailure> {
        self.install_settings_using(rows, offset, push_checked)
    }
    fn install_settings_using<E: From<String> + From<&'static str>>(
        &self,
        rows: &mut [HeaderAllocationRow],
        offset: usize,
        mut push_row: impl FnMut(&mut Vec<OriginalSettingsBody>, OriginalSettingsBody) -> Result<(), E>,
    ) -> Result<(), E> {
        let mut settings = Vec::new();
        for row in rows {
            let owner = row
                .settings_owner
                .as_ref()
                .ok_or("original proc metadata owner is missing")?;
            if owner.settings.is_empty() && owner.signature.return_annotation.is_none() {
                if !row.settings_footprints.is_empty() {
                    return Err("empty original settings have footprints".into());
                }
                continue;
            }
            push_row(
                &mut settings,
                checked_row(
                    relative(row.body, offset)?,
                    Arc::clone(owner),
                    std::mem::take(&mut row.settings_footprints),
                    &self.source,
                )?,
            )?;
        }
        self.finish_settings(settings).map_err(Into::into)
    }
    fn finish_settings(&self, mut settings: Vec<OriginalSettingsBody>) -> Result<(), String> {
        settings.sort_unstable_by_key(|r| r.body.start);
        if settings
            .windows(2)
            .any(|p| p[0].body.start == p[1].body.start)
        {
            return Err("duplicate original setting body".into());
        }
        if let Some(old) = self.settings.get() {
            if old.len() != settings.len()
                || old.iter().zip(&settings).any(|(a, b)| {
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
        if let Some(rows) = self.settings.get() {
            fn validate(
                input: &OriginalProcedureHeaders,
                items: &[Item],
                owners: &BTreeMap<usize, Arc<ProcedureMetadata>>,
                count: &mut usize,
            ) -> Result<(), String> {
                for item in items {
                    if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
                        input.original(item.header_span, 0)?;
                        let owner = owners
                            .get(&item.span.start)
                            .ok_or("current setting metadata owner is missing")?;
                        let issued = input.settings.get().unwrap();
                        let row = issued
                            .binary_search_by_key(&item.span.start, |r| r.body.start)
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
                            input.expression_row(item.span, owner)?;
                            *count = count.checked_add(1).ok_or("setting body count overflow")?;
                        }
                    } else {
                        validate(input, &item.children, owners, count)?;
                    }
                }
                Ok(())
            }
            let mut count = 0;
            validate(self, items, owners, &mut count)?;
            if count != rows.len() {
                return Err("current settings roster differs from original issued bodies".into());
            }
            return Ok(());
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
                            checked_row(item.span, Arc::clone(owner), footprints, &input.source)?,
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
        self.finish_settings(rows)
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
            for row in rows {
                row.roots.visit_storage(|_, _, _| {}, &mut visit);
                row.return_roots.visit_storage(|_, _, _| {}, &mut visit);
            }
        }
    }
    pub(super) fn visit_settings_storage(&self, visit: &mut impl FnMut(usize, usize, usize)) {
        if let Some(rows) = self.settings.get() {
            if rows.capacity() > 0 {
                visit(
                    rows.as_ptr() as usize,
                    rows.len() * std::mem::size_of::<OriginalSettingsBody>(),
                    rows.capacity() * std::mem::size_of::<OriginalSettingsBody>(),
                );
            }
            for row in rows {
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
    #[test]
    fn actual_setting_metadata_tryreserve_error_keeps_io_kind_cause_and_legacy_text() {
        let actual = Vec::<u8>::new()
            .try_reserve_exact(usize::MAX)
            .err()
            .expect("actual standard capacity refusal");
        let super::super::OriginalHeaderFailure::Operational(error) =
            super::setting_allocation(actual)
        else {
            panic!("allocator error is not declaration syntax")
        };
        assert_eq!(error.kind(), std::io::ErrorKind::OutOfMemory);
        assert_eq!(error.to_string(), "original setting row allocation refused");
        assert!(
            std::error::Error::source(error.get_ref().unwrap()).is_some(),
            "original TryReserveError cause retained"
        );
    }
}
