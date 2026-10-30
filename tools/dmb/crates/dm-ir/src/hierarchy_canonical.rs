//! Shared canonical BYTES only. This writer is not semantic authority or a
//! second hierarchy model; original ResolvedMeaning/native hierarchy use it.
use crate::SymbolId;
use std::io;
const PREFIX: &[u8] = b"dm-resolved-meaning-v1\0";
pub struct Writer<F> {
    sink: F,
}
impl<F: FnMut(&[u8]) -> io::Result<()>> Writer<F> {
    pub fn new(sink: F) -> Self {
        Self { sink }
    }
    pub fn missing(&mut self) -> io::Result<()> {
        (self.sink)(PREFIX)?;
        (self.sink)(&[0])
    }
    pub fn symbol(&mut self, symbol: SymbolId) -> io::Result<()> {
        (self.sink)(PREFIX)?;
        (self.sink)(&[7])?;
        self.symbol_item(symbol)
    }
    pub fn symbols_start(&mut self, count: usize) -> io::Result<()> {
        (self.sink)(PREFIX)?;
        (self.sink)(&[8])?;
        (self.sink)(&(count as u64).to_le_bytes())
    }
    pub fn symbol_item(&mut self, symbol: SymbolId) -> io::Result<()> {
        (self.sink)(&symbol.bits().to_le_bytes())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ResolvedMeaning as M;
    #[test]
    fn original_v1_hierarchy_tags_and_prefix_are_preserved_independently() {
        let symbol = SymbolId::of("/datum");
        let mut expected = b"dm-resolved-meaning-v1\0".to_vec();
        expected.push(0);
        assert_eq!(M::Missing.canonical_bytes(), expected);
        let mut expected = b"dm-resolved-meaning-v1\0".to_vec();
        expected.push(7);
        expected.extend_from_slice(&symbol.bits().to_le_bytes());
        assert_eq!(M::Symbol(symbol).canonical_bytes(), expected);
        let mut expected = b"dm-resolved-meaning-v1\0".to_vec();
        expected.push(8);
        expected.extend_from_slice(&1u64.to_le_bytes());
        expected.extend_from_slice(&symbol.bits().to_le_bytes());
        assert_eq!(M::Symbols(vec![symbol].into()).canonical_bytes(), expected);
    }
}
