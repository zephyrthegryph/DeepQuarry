//! One successful image per existing immutable symbolic artifact. Every use
//! first authenticates all current relocation answers in ordinary error order.
use super::*;
#[derive(Default)]
pub(crate) struct LatestImage {
    value: std::sync::Mutex<Option<Linked>>,
    wire: super::wire_image::WireImage,
}
struct Linked {
    frozen: Arc<FrozenProc>,
    answers: dm_link::BindingAnswers,
    image: ProcedureImage,
}
impl LatestImage {
    /// Drop numeric projections only. Every future use follows ordinary binding
    /// validation and reconstructs the image from the immutable symbolic code.
    pub(crate) fn release_bound_images(&self) -> usize {
        let retired = self.value.lock().unwrap_or_else(|e| e.into_inner()).take();
        let linked = usize::from(retired.is_some());
        drop(retired);
        linked + usize::from(self.wire.release())
    }
    pub(super) fn link(
        &self,
        frozen: &Arc<FrozenProc>,
        origins: &crate::debug_sources::FrozenDebugOrigins,
        tables: &LinkTables,
    ) -> Result<ProcedureImage, IntegrationError> {
        let source = origins.source_bindings();
        let bound = tables
            .bind_relocations(frozen.code(), &source)
            .map_err(IntegrationError::Link)?;
        let mut latest = self.value.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(hit) = latest
            .as_ref()
            .filter(|hit| Arc::ptr_eq(&hit.frozen, frozen) && bound.matches(&hit.answers))
        {
            return Ok(hit.image.clone());
        }
        let (image, answers) = bound
            .encode_with_answers()
            .map_err(IntegrationError::Link)?;
        *latest = Some(Linked {
            frozen: Arc::clone(frozen),
            answers,
            image: image.clone(),
        });
        Ok(image)
    }
    #[cfg(test)]
    pub(crate) fn wire_words(
        owner: &Arc<Self>,
        image: ProcedureImage,
        code: &dm_ir::SymbolicCode,
        tables: &LinkTables,
        mobs: &dm_link::MobBindings,
    ) -> Result<Vec<u32>, IntegrationError> {
        Self::wire_image(owner, image, code, tables, mobs).map(ProcedureImage::into_words)
    }
    pub(crate) fn wire_image(
        owner: &Arc<Self>,
        image: ProcedureImage,
        code: &dm_ir::SymbolicCode,
        tables: &LinkTables,
        mobs: &dm_link::MobBindings,
    ) -> Result<ProcedureImage, IntegrationError> {
        if Arc::strong_count(owner) > 1 {
            owner.wire.image(image, code, tables, mobs)
        } else {
            let mut words = image.into_words();
            dm_link::admit_type_path_words(&mut words, code, tables, mobs)
                .map_err(IntegrationError::WireDomain)?;
            Ok(ProcedureImage {
                words: Arc::new(words),
            })
        }
    }
    pub(crate) fn visit_retained_wire(
        &self,
        visitor: impl FnMut(&ProcedureImage, &dm_link::TypePathAnswers, &ProcedureImage),
    ) {
        self.wire.visit_retained(visitor);
    }
    pub(crate) fn visit_retained(
        &self,
        mut visitor: impl FnMut(&Arc<FrozenProc>, &dm_link::BindingAnswers, &ProcedureImage),
    ) {
        let latest = self.value.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(linked) = latest.as_ref() {
            visitor(&linked.frozen, &linked.answers, &linked.image);
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_image_reuses_but_source_shift_reencodes_and_missing_origin_fails() {
        use byond_dmb::bytecode::opcode;
        use dm_codegen_byond::{Instruction, Item, SymbolicProc, Word};
        let code = SymbolicProc {
            items: vec![
                Item::Instruction(Instruction {
                    opcode: opcode::DBG_LINE,
                    operands: vec![Word::Reference(SymRef::SourceLine(0))],
                }),
                Item::Instruction(Instruction {
                    opcode: opcode::RET,
                    operands: vec![],
                }),
            ],
        };
        let frozen = Arc::new(dm_codegen_byond::encoder::freeze_proc(&code).unwrap());
        let owner = LatestImage::default();
        let tables = LinkTables::build(Default::default()).unwrap();
        let origins = crate::debug_sources::DebugOrigins {
            entries: vec![crate::debug_sources::DebugOrigin {
                semantic_path: Arc::from("current.dm"),
                line: 7,
            }],
        };
        let current = origins.clone().into();
        let first = owner.link(&frozen, &current, &tables).unwrap();
        let hit = owner.link(&frozen, &current, &tables).unwrap();
        assert!(Arc::ptr_eq(&first.words, &hit.words));
        let code_owner = frozen.shared_code();
        assert_eq!(owner.release_bound_images(), 1);
        assert_eq!(owner.release_bound_images(), 0);
        let rebuilt = owner.link(&frozen, &current, &tables).unwrap();
        assert_eq!(rebuilt, first);
        assert!(!Arc::ptr_eq(&rebuilt.words, &first.words));
        assert!(Arc::ptr_eq(&code_owner, &frozen.shared_code()));
        let mut shifted = origins;
        shifted.entries[0].line = 500;
        let shifted = shifted.into();
        let next = owner.link(&frozen, &shifted, &tables).unwrap();
        assert!(!Arc::ptr_eq(&first.words, &next.words));
        assert_eq!(
            next,
            tables
                .link(frozen.code(), &shifted.source_bindings())
                .unwrap()
        );
        assert!(owner.link(&frozen, &Default::default(), &tables).is_err());
    }
}

#[cfg(test)]
#[path = "latest_image_census_tests.rs"]
mod census_tests;
