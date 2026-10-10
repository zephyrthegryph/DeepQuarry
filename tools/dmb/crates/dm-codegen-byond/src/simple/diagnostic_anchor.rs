/// Source origins are borrowed per occurrence; reusable code retains only ordinals.
pub trait DebugSourceProvider {
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
