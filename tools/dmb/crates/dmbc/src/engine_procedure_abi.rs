//! Positive inherited ABI facts decoded from an accepted immutable engine input.
//! This module does not infer signatures, callable names or absent ancestors.
use byond_dmb::{dmb::Proc, ids::NONE};
use dm_codegen_byond::procedure_abi::{AbiError, Category, ProcLayout};

/// Read bytes while the pinned DMB is being decoded. Missing non-sentinel
/// strings are corruption, not an absent setting. No semantic UTF-8 conversion
/// is applied to display text, description or category payloads.
pub fn capture_layout<'a>(
    record: &Proc,
    mut string: impl FnMut(u32) -> Option<&'a [u8]>,
) -> Result<ProcLayout, AbiError> {
    fn optional<'a>(
        id: u32,
        string: &mut impl FnMut(u32) -> Option<&'a [u8]>,
    ) -> Result<Option<Vec<u8>>, AbiError> {
        if id == NONE {
            Ok(None)
        } else {
            string(id)
                .map(|value| Some(value.to_vec()))
                .ok_or_else(|| AbiError(format!("engine procedure string {id} is missing")))
        }
    }
    let display_name = optional(record.strings[1], &mut string)?;
    let description = optional(record.strings[2], &mut string)?;
    let category_bytes = optional(record.strings[3], &mut string)?;
    let flags = record.effective_flags() & !0x80; // Wire extension marker, not a setting.
    let category = if flags & 0x20 != 0 {
        Category::Null
    } else {
        category_bytes.map_or(Category::Default, Category::Text)
    };
    let invisibility = record.invisibility_setting();
    if invisibility.is_some_and(|value| value > 127) {
        return Err(AbiError(
            "engine procedure invisibility is outside the ABI range".into(),
        ));
    }
    Ok(ProcLayout {
        display_name,
        description,
        category,
        source_kind: record.source_kind,
        source_parameter: record.source_parameter,
        flags,
        invisibility,
    })
}
/// Selection is a declaration/override fact, separate from decoding engine ABI.
/// A caller must derive this from its accepted immutable source+engine lineage.
pub enum SelectedProcedureBase {
    Fresh,
    Engine {
        owner: dm_ir::SymbolId,
        name: dm_ir::SymbolId,
        kind: dm_tree::MemberKind,
    },
    Source(std::sync::Arc<ProcLayout>),
    Unsupported,
}
pub trait CapturedBaseSelection: Sync {
    fn select(
        &self,
        context: &crate::procedure_policy::AbiContext<'_>,
    ) -> Result<SelectedProcedureBase, AbiError>;
}
pub struct EngineInheritedFacts<'a> {
    pub engine: &'a super::EngineSnapshot,
    pub selection: &'a dyn CapturedBaseSelection,
}
impl crate::procedure_policy::CapturedInheritedFacts for EngineInheritedFacts<'_> {
    fn inherited(
        &self,
        context: &crate::procedure_policy::AbiContext<'_>,
    ) -> Result<crate::procedure_policy::InheritedLayout, AbiError> {
        use crate::procedure_policy::InheritedLayout;
        match self.selection.select(context)? {
            SelectedProcedureBase::Fresh => Ok(InheritedLayout::Fresh),
            SelectedProcedureBase::Unsupported => Ok(InheritedLayout::Unsupported),
            SelectedProcedureBase::Source(layout) => Ok(InheritedLayout::Known((*layout).clone())),
            SelectedProcedureBase::Engine { owner, name, kind } => self
                .engine
                .procedure_layout(owner, name, kind)
                .map_err(|error| {
                    AbiError(format!("engine procedure ABI selection failed: {error:?}"))
                })?
                .cloned()
                .map(InheritedLayout::Known)
                .ok_or_else(|| {
                    AbiError(
                        "selected inherited engine procedure has no captured ABI record".into(),
                    )
                }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn captures_bytes_source_and_explicit_zero_without_inventing_signature() {
        let record = Proc {
            strings: [NONE, 1, NONE, NONE],
            source_kind: 16,
            source_parameter: 127,
            flags: 0xac,
            extended_flags: Some((0xac, 255)),
            code_locals_args: [NONE; 3],
        };
        let layout =
            capture_layout(&record, |id| (id == 1).then_some(b"exact\xff".as_slice())).unwrap();
        assert_eq!(layout.display_name, Some(b"exact\xff".to_vec()));
        assert_eq!(layout.category, Category::Null);
        assert_eq!(layout.invisibility, Some(0));
        assert_eq!(layout.encoded_flags(), (0xac, Some((0xac, 255))));
        assert_eq!((layout.source_kind, layout.source_parameter), (16, 127));
    }
    #[test]
    fn missing_text_is_not_an_absent_setting() {
        let record = Proc {
            strings: [NONE, 1, NONE, NONE],
            source_kind: 0,
            source_parameter: 255,
            flags: 4,
            extended_flags: None,
            code_locals_args: [NONE; 3],
        };
        assert!(capture_layout(&record, |_| None).is_err());
    }
}
