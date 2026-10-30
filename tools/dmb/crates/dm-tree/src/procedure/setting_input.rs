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
    })
}
fn push(out: &mut Vec<OriginalSettingsBody>, row: OriginalSettingsBody) -> Result<(), String> {
    out.len()
        .checked_add(1)
        .and_then(|n| n.checked_mul(std::mem::size_of::<OriginalSettingsBody>()))
        .ok_or("original setting row capacity overflow")?;
    out.try_reserve_exact(1)
        .map_err(|_| "original setting row allocation refused")?;
    out.push(row);
    Ok(())
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
        let first = self.tokens.partition_point(|t| t.span.start < range.start);
        let last = self.tokens.partition_point(|t| t.span.start < range.end);
        let view = HeaderView::original(&self.source, &self.tokens[first..last], range)?;
        crate::procedure::parse_setting_view(view, symbols)
    }
    pub(super) fn install_settings(
        &self,
        rows: &mut [HeaderAllocationRow],
        offset: usize,
    ) -> Result<(), String> {
        let mut settings = Vec::new();
        for row in rows {
            let owner = row
                .settings_owner
                .as_ref()
                .ok_or("original proc metadata owner is missing")?;
            if owner.settings.is_empty() {
                if !row.settings_footprints.is_empty() {
                    return Err("empty original settings have footprints".into());
                }
                continue;
            }
            push(
                &mut settings,
                checked_row(
                    relative(row.body, offset)?,
                    Arc::clone(owner),
                    std::mem::take(&mut row.settings_footprints),
                    &self.source,
                )?,
            )?;
        }
        self.finish_settings(settings)
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
                        if owner.settings.is_empty() {
                            if row.is_some() {
                                return Err(
                                    "current empty settings differ from original nonempty body"
                                        .into(),
                                );
                            }
                        } else {
                            input.settings_footprints(item.span, owner)?;
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
                    if !nodes.is_empty() {
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
    ) -> Result<(&'a str, &'a [dm_syntax::SpanToken]), String> {
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
            .partition_point(|t| t.span.start < issued.value.start);
        let last = self
            .tokens
            .partition_point(|t| t.span.start < issued.value.end);
        let tokens = &self.tokens[first..last];
        if tokens.iter().any(|t| t.span.end > issued.value.end) {
            return Err("setting RHS token escaped original footprint".into());
        }
        Ok((&self.source, tokens))
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
