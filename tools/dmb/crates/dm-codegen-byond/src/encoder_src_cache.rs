//! Conservative current receiver-cache proof over one typed instruction stream.
use crate::{Item, VariableWord};
#[derive(Default)]
pub(super) struct SrcCache {
    known_src: bool,
}
impl SrcCache {
    pub(super) fn begin(&mut self, item: &Item) {
        match item {
            Item::Label(_) => self.known_src = false,
            Item::Instruction(ins)
                if matches!(ins.opcode, 0x33 | 0x34 | 0x50 | 0x60 | 0x0c | 0x84 | 0x85) => {}
            _ => self.known_src = false,
        }
    }
    pub(super) fn variable<'a>(
        &mut self,
        value: &'a VariableWord,
        opcode: u32,
    ) -> &'a VariableWord {
        // Only ordinary Get/Set consume these certified receiver operands. Other
        // compound instructions cannot establish or reuse this narrow proof.
        if !matches!(opcode, 0x33 | 0x34) {
            self.known_src = false;
            return value;
        }
        if let VariableWord::SetCache(receiver, field) = value {
            if matches!(receiver.as_ref(), VariableWord::Src)
                && matches!(field.as_ref(), VariableWord::Field(_))
            {
                let reuse = self.known_src;
                self.known_src = true;
                return if reuse { field } else { value };
            }
            self.known_src = false;
        } else if matches!(value, VariableWord::Initial(_) | VariableWord::IsSaved(_))
            || (opcode == 0x34
                && matches!(
                    value,
                    VariableWord::Cache | VariableWord::CacheKey | VariableWord::Src
                ))
        {
            self.known_src = false;
        }
        value
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Instruction, LabelId, Word};
    fn ins(opcode: u32, operands: Vec<Word>) -> Item {
        Item::Instruction(Instruction { opcode, operands })
    }
    fn qualified() -> VariableWord {
        VariableWord::SetCache(
            Box::new(VariableWord::Src),
            Box::new(VariableWord::Field(crate::SymbolId::of("field"))),
        )
    }
    #[test]
    fn src_cache_reuses_only_proven_same_receiver_and_invalidates_boundaries() {
        let field = qualified();
        let mut proof = SrcCache::default();
        proof.begin(&ins(0x33, vec![]));
        assert_eq!(proof.variable(&field, 0x33), &field);
        for opcode in [0x60, 0x0c, 0x84, 0x85] {
            proof.begin(&ins(opcode, vec![]));
        }
        assert!(matches!(
            proof.variable(&field, 0x34),
            VariableWord::Field(_)
        ));
        for boundary in [
            ins(0x30, vec![]),
            ins(0x0f, vec![]),
            Item::Label(LabelId(0)),
            ins(0x777, vec![]),
        ] {
            proof.begin(&boundary);
            proof.begin(&ins(0x33, vec![]));
            assert_eq!(proof.variable(&field, 0x33), &field);
        }
        for target in [
            VariableWord::Cache,
            VariableWord::CacheKey,
            VariableWord::Src,
            VariableWord::SetCache(
                Box::new(VariableWord::Local(0)),
                Box::new(VariableWord::Field(crate::SymbolId::of("other"))),
            ),
        ] {
            proof.begin(&ins(0x34, vec![]));
            proof.variable(&target, 0x34);
            assert_eq!(proof.variable(&field, 0x33), &field);
        }
    }
}
