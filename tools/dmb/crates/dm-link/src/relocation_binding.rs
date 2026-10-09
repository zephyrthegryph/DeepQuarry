//! Ordered current relocation binding, separated from symbolic word encoding.
use super::*;

/// A successful binding borrows exactly the symbolic code whose relocations
/// were checked. No caller can inject answers or encode a different body.
pub struct BoundRelocations<'code> {
    code: &'code SymbolicCode,
    resolved: HashMap<SymRef, u32>,
}
/// Complete successful current answers, immutable and privately issued.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BindingAnswers(Arc<HashMap<SymRef, u32>>);
impl BindingAnswers {
    pub fn storage(&self) -> (&Arc<HashMap<SymRef, u32>>, usize) {
        (&self.0, self.0.capacity())
    }
}
impl BoundRelocations<'_> {
    pub fn matches(&self, answers: &BindingAnswers) -> bool {
        self.resolved == *answers.0
    }
    pub fn encode_with_answers(self) -> Result<(ProcedureImage, BindingAnswers), LinkError> {
        let words = self
            .code
            .link(|reference| self.resolved.get(&reference).copied())
            .map_err(LinkError::Relocation)?;
        Ok((
            ProcedureImage {
                words: Arc::new(words),
            },
            BindingAnswers(Arc::new(self.resolved)),
        ))
    }

    pub fn encode(self) -> Result<ProcedureImage, LinkError> {
        let words = self
            .code
            .link(|reference| self.resolved.get(&reference).copied())
            .map_err(LinkError::Relocation)?;
        Ok(ProcedureImage {
            words: Arc::new(words),
        })
    }
}
impl LinkTables {
    pub fn bind_relocations<'code>(
        &self,
        code: &'code SymbolicCode,
        source: &SourceBindings,
    ) -> Result<BoundRelocations<'code>, LinkError> {
        let mut resolved = HashMap::new();
        for relocation in code.relocations() {
            let reference = relocation.reference;
            let std::collections::hash_map::Entry::Vacant(entry) = resolved.entry(reference) else {
                continue;
            };
            let index = match reference {
                SymRef::LineDelta(delta) => source
                    .first_line
                    .checked_add(delta)
                    .ok_or(LinkError::SourceLineOverflow(delta))?,
                SymRef::SourceLine(origin) => *source
                    .lines
                    .get(&origin)
                    .ok_or(LinkError::MissingSourceLine(origin))?,
                SymRef::SourceFile(origin) => {
                    let symbol = *source
                        .files
                        .get(&origin)
                        .ok_or(LinkError::MissingSourceFile(origin))?;
                    self.index(Key::String(symbol))
                        .ok_or(LinkError::UnknownKey(Key::String(symbol)))?
                }
                _ => {
                    let key = reference_key(reference, self.bindings.slots())
                        .ok_or(LinkError::UnknownReference(reference))?;
                    self.index(key)
                        .ok_or(LinkError::UnknownReference(reference))?
                }
            };
            entry.insert(index);
        }
        Ok(BoundRelocations { code, resolved })
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn code(references: &[SymRef]) -> SymbolicCode {
        SymbolicCode::new(
            vec![0; references.len()],
            references
                .iter()
                .enumerate()
                .map(|(offset, reference)| dm_ir::Relocation {
                    offset: offset as u32,
                    reference: *reference,
                    encoding: dm_ir::RelocationEncoding::Direct,
                })
                .collect(),
        )
        .unwrap()
    }
    #[test]
    fn ordered_answers_match_exact_current_debug_values_and_encode() {
        let tables = LinkTables::build(Default::default()).unwrap();
        let code = code(&[
            SymRef::SourceLine(0),
            SymRef::SourceLine(0),
            SymRef::LineDelta(9),
        ]);
        let mut source = SourceBindings {
            first_line: 10,
            ..Default::default()
        };
        source.lines.insert(0, 7);
        let (image, answers) = tables
            .bind_relocations(&code, &source)
            .unwrap()
            .encode_with_answers()
            .unwrap();
        assert_eq!(image.words.as_slice(), &[7, 7, 19]);
        assert!(tables
            .bind_relocations(&code, &source)
            .unwrap()
            .matches(&answers));
        source.lines.insert(0, 500);
        assert!(!tables
            .bind_relocations(&code, &source)
            .unwrap()
            .matches(&answers));
        assert_eq!(
            tables.link(&code, &source).unwrap().words.as_slice(),
            &[500, 500, 19]
        );
    }
    #[test]
    fn first_missing_source_error_precedes_later_unknown_reference() {
        let tables = LinkTables::build(Default::default()).unwrap();
        let code = code(&[SymRef::SourceLine(2), SymRef::Type(SymbolId::of("/absent"))]);
        assert!(matches!(
            tables.bind_relocations(&code, &Default::default()),
            Err(LinkError::MissingSourceLine(2))
        ));
    }
}
