/// Source origins are borrowed per occurrence; reusable code retains only ordinals.
pub trait DebugSourceProvider {
    /// Optional parser-issued current formal declaration span. Custom/standalone
    /// providers decline rather than fabricate a signature location.
    fn parameter_declaration(&self, _name: &str) -> Result<Option<super::LowerSpan>, String> {
        Ok(None)
    }
    fn entry_ordinal(&self) -> Result<u32, String>;
    fn ordinal(&self, expanded_offset: usize) -> Result<u32, String>;
    /// Optional current diagnostic cursor authority. Unsupported providers
    /// return None; ordinary instruction origins remain unchanged.
    fn diagnostic_ordinal(&self, _anchor: DiagnosticAnchor) -> Result<Option<u32>, String> {
        Ok(None)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum DiagnosticAnchor {
    AtOffset(usize),
    LexerCursorAfterOffset(usize),
    UnresolvedCursorAtOffset(usize),
}
