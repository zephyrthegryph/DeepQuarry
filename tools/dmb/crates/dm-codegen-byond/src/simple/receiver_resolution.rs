//! Adapter preserving the existing resolver calls and error observations.
use super::*;
use dm_ir::receiver_resolution::ReceiverTypeContext;
pub(super) struct ReceiverContext<'a, 'compiler>(
    pub(super) &'a Compiler<'compiler>,
    pub(super) bool,
);
impl ReceiverTypeContext for ReceiverContext<'_, '_> {
    type Error = LowerError;
    fn current_type_path(&self) -> Option<&str> {
        self.0.bindings.current_type_path.as_deref()
    }
    fn semantic_queries_available(&self) -> bool {
        self.0.lookup.is_some()
    }
    fn local_type(&self, name: &str) -> Option<Option<&str>> {
        self.0
            .local_slots
            .contains_key(name)
            .then(|| self.0.local_types.get(name).map(String::as_str))
    }
    fn argument_type(&self, name: &str) -> Option<Option<&str>> {
        self.0
            .bindings
            .parameters
            .iter()
            .any(|parameter| parameter == name)
            .then(|| {
                self.0
                    .bindings
                    .parameter_types
                    .get(name)
                    .map(String::as_str)
            })
    }
    fn procedure_static_type(&self, name: &str) -> Result<Option<Option<String>>, LowerError> {
        let Some(lookup) = self.0.lookup else {
            return Ok(None);
        };
        let Some(declaration) = self
            .0
            .semantic(lookup.procedure_static(self.0.bindings.procedure_identity, name))?
        else {
            return Ok(None);
        };
        let path = declaration
            .declared_type
            .map(|id| {
                self.0.semantic(lookup.text(
                    dm_ir::ResolveQuery::ProcedureStatic {
                        procedure: declaration.identity.procedure,
                        name: declaration.identity.name,
                    },
                    id,
                ))
            })
            .transpose()?;
        Ok(Some(path))
    }
    fn has_member_field(&self, owner: &str, name: &str) -> Result<bool, LowerError> {
        let Some(lookup) = self.0.lookup else {
            return Ok(false);
        };
        self.0
            .semantic(lookup.presence(dm_ir::ResolveQuery::HasMemberVar {
                owner: SymbolId::of(owner),
                name: SymbolId::of(name),
            }))
    }
    fn field_type(&self, name: &str) -> Result<Option<String>, LowerError> {
        self.0.field_type(name)
    }
    fn global_type(&self, name: &str) -> Result<Option<String>, LowerError> {
        self.0.global_type(name)
    }
    fn member_type(&self, owner: &str, name: &str) -> Result<Option<String>, LowerError> {
        self.0.member_type(owner, name)
    }
    fn is_intrinsic(&self, name: &str) -> bool {
        crate::builtin_catalog::lookup(name).is_some()
    }
    fn has_member_proc(&self, owner: &str, name: &str) -> Result<bool, LowerError> {
        self.0.has_declared_member_proc(owner, name)
    }
    fn procedure_return_type(
        &self,
        query: dm_ir::ResolveQuery,
    ) -> Result<Option<String>, LowerError> {
        self.0.procedure_return_type_text(query)
    }
    fn normalize_type(&self, path: &str) -> Result<String, LowerError> {
        if self.1 {
            if let Some(lookup) = self.0.lookup {
                let query = dm_ir::ResolveQuery::Type(SymbolId::of(path));
                return match self.0.semantic(lookup.answer(query))? {
                    dm_ir::ResolvedMeaning::Symbol(actual) if actual == SymbolId::of(path) => {
                        Ok(path.to_owned())
                    }
                    dm_ir::ResolvedMeaning::Missing => Err(LowerError {
                        kind: LowerErrorKind::SourceError,
                        ..error(path, &format!("{path}: undefined type path"))
                    }),
                    _ => {
                        self.0.semantic(Err(lookup
                            .error(query, "reflective receiver type is not positively captured")))
                    }
                };
            }
        }
        self.0.normalize_inferred_type(path)
    }
}
