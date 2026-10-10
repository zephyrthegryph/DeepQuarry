//! Successful input warnings from the typed input producer's validated mask.
use super::*;

impl Compiler<'_> {
    pub(super) fn input_filter_warning(
        &mut self,
        types: &[String],
        choices: bool,
        mask: u32,
        source_ordinal: Option<u32>,
    ) {
        // Authenticated matrix: omitted types are silent; object/anything filters
        // suppress this warning, including constant and object mixed masks.
        const FILTERS: u32 = 1 | 2 | 32 | 256 | 4096;
        if !types.is_empty() && choices && mask & FILTERS == 0 {
            self.result.warnings.push(ProcedureWarning {
                code: dm_ir::WarningCode::ListWithoutFilter,
                name: None,
                source_ordinal,
            });
        }
        if !choices {
            return;
        }
        let mut object_seen = false;
        let mut anything_seen = false;
        for ty in types {
            let object = matches!(ty.as_str(), "mob" | "obj" | "turf" | "area");
            if object_seen && !object {
                self.result.warnings.push(ProcedureWarning {
                    code: dm_ir::WarningCode::ObjectFilterRightmost,
                    name: None,
                    source_ordinal,
                });
            }
            if anything_seen && ty != "anything" {
                self.result.warnings.push(ProcedureWarning {
                    code: dm_ir::WarningCode::AnythingFilterRightmost,
                    name: None,
                    source_ordinal,
                });
            }
            object_seen |= object;
            anything_seen |= ty == "anything";
        }
    }
}
