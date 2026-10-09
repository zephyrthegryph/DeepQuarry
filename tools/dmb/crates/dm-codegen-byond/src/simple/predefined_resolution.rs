//! Existing compiler observation/error boundary for shared constant selection.
use super::*;
use dm_ir::predefined_resolution::{PredefinedContext, PredefinedValueError};

pub(super) struct PredefinedCompiler<'a, 'compiler>(pub(super) &'a Compiler<'compiler>);
impl PredefinedContext for PredefinedCompiler<'_, '_> {
    type Error = LowerError;
    fn numeric_candidate(&self, name: &str) -> Result<Option<u32>, LowerError> {
        self.0.numeric_constant(name)
    }
    fn text_candidate(&self, name: &str) -> Result<Option<String>, LowerError> {
        self.0.string_constant(name)
    }
}

impl Compiler<'_> {
    pub(super) fn predefined_projection<T>(
        &self,
        lookup: &crate::lower_resolver::ProjectResolver<'_>,
        name: &str,
        result: Result<T, PredefinedValueError>,
    ) -> Result<T, LowerError> {
        self.semantic(result.map_err(|failure| {
            lookup.error(
                dm_ir::ResolveQuery::PredefinedConstant(SymbolId::of(name)),
                match failure {
                    PredefinedValueError::UnsupportedValue => {
                        "unsupported predefined constant value"
                    }
                    PredefinedValueError::InvalidUtf8 => "predefined constant is not UTF-8",
                },
            )
        }))
    }
}
