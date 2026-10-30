//! Private original header input on the EXISTING declaration syntax owner.
//! Never serialized, never a filesystem receipt, never an alternate DM parser.
use super::{header::HeaderView, ParsedSignature, SignatureError};
use dm_ir::SymbolTable;
use dm_preprocess::SourceText;
use dm_syntax::{Item, ItemKind, Span, SpanToken, TokenKind};
use std::sync::Arc;
#[derive(Debug)]
pub(crate) struct OriginalProcedureHeaders {
    source: SourceText,
    headers: Vec<Span>,
    tokens: Vec<SpanToken>,
}
fn reserve<T>(v: &mut Vec<T>, n: usize) -> Result<(), String> {
    n.checked_mul(std::mem::size_of::<T>())
        .ok_or("header recipe capacity overflow")?;
    v.try_reserve_exact(n)
        .map_err(|_| "header recipe allocation refused".into())
}
fn spans(items: &[Item], offset: usize, source: &str, out: &mut Vec<Span>) -> Result<(), String> {
    for item in items {
        if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
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
            if source.get(span.range()) != Some(item.header.as_str()) {
                return Err("original procedure header differs from its declaration source".into());
            }
            reserve(out, 1)?;
            out.push(span);
        } else {
            spans(&item.children, offset, source, out)?;
        }
    }
    Ok(())
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
        let mut headers = Vec::new();
        spans(items, offset, &source, &mut headers)?;
        headers.sort_unstable_by_key(|s| s.start);
        if headers.windows(2).any(|p| p[0].end > p[1].start) {
            return Err("original procedure header ranges overlap".into());
        }
        if tokens.iter().any(|t| source.get(t.span.range()).is_none())
            || tokens.windows(2).any(|p| p[0].span.end > p[1].span.start)
        {
            return Err("original declaration token ranges differ".into());
        }
        Ok(Arc::new(Self {
            source,
            headers,
            tokens,
        }))
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
}
impl<'a> HeaderAllocationReceipt<'a> {
    pub(crate) fn from_rows(
        items: &'a [Item],
        inputs: &'a OriginalProcedureHeaders,
        offset: usize,
        rows: Vec<HeaderAllocationRow>,
    ) -> Result<Self, String> {
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
