//! Successful input warnings from the typed input producer's validated mask.
use super::*;

impl Compiler<'_> {
    pub(super) fn input_filter_warning(
        &mut self,
        explicit_types: bool,
        choices: bool,
        mask: u32,
        source_ordinal: Option<u32>,
    ) {
        // Authenticated matrix: omitted types are silent; object/anything filters
        // suppress this warning, including constant and object mixed masks.
        const FILTERS: u32 = 1 | 2 | 32 | 256 | 4096;
        if explicit_types && choices && mask & FILTERS == 0 {
            self.result.warnings.push(ProcedureWarning {
                code: dm_ir::WarningCode::ListWithoutFilter,
                name: None,
                source_ordinal,
            });
        }
    }
}
