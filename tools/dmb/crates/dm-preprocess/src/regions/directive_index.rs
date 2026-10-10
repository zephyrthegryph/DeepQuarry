//! Immutable sparse directive lookup with constant-time bit rank.
//! Non-directive source lines retain no pointer or syntax allocation.
use super::{directive_syntax::DirectiveSyntax, PreparedLines};
use std::sync::Arc;

#[derive(Clone, Debug)]
struct Block {
    bits: u64,
    first: usize,
}
#[derive(Clone, Debug)]
pub(super) struct DirectiveIndex {
    blocks: Arc<[Block]>,
    syntax: Arc<[DirectiveSyntax]>,
    lines: usize,
}
impl DirectiveIndex {
    pub(super) fn visit_storage(&self, visit: &mut impl FnMut(super::PreparedSourceStorage<'_>)) {
        for (address, bytes) in [
            (
                self.blocks.as_ptr() as usize,
                std::mem::size_of_val(self.blocks.as_ref()),
            ),
            (
                self.syntax.as_ptr() as usize,
                std::mem::size_of_val(self.syntax.as_ref()),
            ),
        ] {
            visit(super::PreparedSourceStorage::Buffer { address, bytes });
        }
        for syntax in self.syntax.iter() {
            syntax.visit_storage(visit);
        }
    }

    pub(super) fn new(lines: PreparedLines<'_>) -> Self {
        let mut blocks = Vec::with_capacity(lines.len().div_ceil(64));
        let mut syntax = Vec::new();
        for (index, line) in lines.iter().enumerate() {
            if index % 64 == 0 {
                blocks.push(Block {
                    bits: 0,
                    first: syntax.len(),
                });
            }
            if let Some(value) = DirectiveSyntax::new(line.text) {
                blocks.last_mut().expect("directive block exists").bits |= 1u64 << (index % 64);
                syntax.push(value);
            }
        }
        Self {
            blocks: blocks.into(),
            syntax: syntax.into(),
            lines: lines.len(),
        }
    }
    pub(super) fn get(&self, index: usize) -> Option<&DirectiveSyntax> {
        assert!(index < self.lines, "directive line index out of bounds");
        let block = &self.blocks[index / 64];
        let bit = 1u64 << (index % 64);
        if block.bits & bit == 0 {
            return None;
        }
        let rank = (block.bits & (bit - 1)).count_ones() as usize;
        Some(&self.syntax[block.first + rank])
    }
}

#[cfg(test)]
mod tests {
    use super::super::PreparedSource;
    use super::*;
    #[test]
    fn sparse_lookup_preserves_directive_syntax_across_word_boundaries() {
        let mut text = String::new();
        for index in 0..193 {
            text.push_str(match index {
                0 | 63 | 64 | 127 | 128 | 192 => "  #define VALUE 7\n",
                62 | 65 => "#undef VALUE EXTRA\n",
                126 | 129 => "#define BAD(a\n",
                _ => "var/ordinary = 4\n",
            });
        }
        let source = PreparedSource::new(Arc::from(text));
        for (index, line) in source.lines().iter().enumerate() {
            let expected = DirectiveSyntax::new(line.text);
            let actual = source.directive(index);
            assert_eq!(
                actual.map(|v| v.parts(line.text)),
                expected.as_ref().map(|v| v.parts(line.text))
            );
            assert_eq!(
                actual.map(|v| &v.definition),
                expected.as_ref().map(|v| &v.definition)
            );
            assert_eq!(
                actual.map(|v| &v.identifier),
                expected.as_ref().map(|v| &v.identifier)
            );
        }
        assert_eq!(source.directives.blocks.len(), 4);
        assert_eq!(source.directives.syntax.len(), 10);
    }
    #[test]
    #[should_panic(expected = "directive line index out of bounds")]
    fn sparse_lookup_keeps_out_of_range_access_rejected_in_partial_block() {
        let source = PreparedSource::new(Arc::from("var/a = 1\n"));
        source.directive(source.lines().len());
    }
}
