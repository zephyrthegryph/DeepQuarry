//! Source distinctions authenticated by the existing typed selection traversal.
//! Pinned 516.1687 cpu_access/graphics_access specimens distinguish these facts
//! from identical field opcodes. They are not reconstructed from linked words.
use super::*;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct SourceFeatures {
    pub world_cpu: bool,
    pub native_graphics: bool,
}
impl SourceFeatures {
    pub fn union(&mut self, other: Self) {
        self.world_cpu |= other.world_cpu;
        self.native_graphics |= other.native_graphics;
    }
}
/// Admit and observe one reference selected by the constant evaluator. This uses
/// the same typed selection context as executable expressions; it neither walks
/// the enclosing expression nor emits a synthetic procedure.
pub fn observe_reference_source_features(
    expression: &Expr,
    bindings: &LowerBindings,
    symbols: &dm_ir::SymbolTable,
    resolver: &dyn dm_ir::Resolver,
) -> Result<SourceFeatures, LowerError> {
    observe_reference_source_features_with_lexical_locals(
        expression,
        bindings,
        symbols,
        resolver,
        &[],
    )
}
/// The supplied locals must be issued from the same current parsed lexical scope.
/// They license names only; no local runtime values or bytecode operands are read.
pub fn observe_reference_source_features_with_lexical_locals(
    expression: &Expr,
    bindings: &LowerBindings,
    symbols: &dm_ir::SymbolTable,
    resolver: &dyn dm_ir::Resolver,
    locals: &[(String, Option<String>)],
) -> Result<SourceFeatures, LowerError> {
    let lookup = crate::lower_resolver::ProjectResolver {
        modified_instances: Default::default(),
        procedure_values: Default::default(),
        procedure_statics: Default::default(),
        resolver,
        symbols,
        slots: Default::default(),
        resources: Default::default(),
        instances: Default::default(),
        runtime_types: Default::default(),
        resource_search_context: None,
    };
    let mut compiler = super::compiler_context::compiler_context(bindings, Some(&lookup));
    for (index, (name, declared_type)) in locals.iter().enumerate() {
        let index = u32::try_from(index)
            .map_err(|_| error("nameof reference", "too many lexical locals"))?;
        compiler.local_slots.insert(name.clone(), index);
        if let Some(path) = declared_type {
            compiler.local_types.insert(name.clone(), path.clone());
        }
    }
    compiler.admit_nameof_reference(expression, "nameof reference")?;
    if let Some(error) = compiler.resolver_failure.take() {
        return Err(error);
    }
    Ok(compiler.result.source_features)
}
impl Compiler<'_> {
    fn feature_inherits(&self, path: &str, roots: &[&str]) -> Result<bool, LowerError> {
        if let Some(lookup) = self.lookup {
            // Header metadata consumes semantic ancestry, not a runtime operand.
            // Native value types may exist without an issued runtime class tag.
            let type_query = dm_ir::ResolveQuery::Type(SymbolId::of(path));
            let owner = match self.semantic(lookup.answer(type_query))? {
                dm_ir::ResolvedMeaning::Symbol(owner) if owner == SymbolId::of(path) => owner,
                dm_ir::ResolvedMeaning::Missing => return Ok(false),
                _ => {
                    return self.semantic(Err(
                        lookup.error(type_query, "feature type is not positively captured")
                    ))
                }
            };
            let query = dm_ir::ResolveQuery::Ancestry(owner);
            return match self.semantic(lookup.answer(query))? {
                dm_ir::ResolvedMeaning::Symbols(owners) => Ok(owners
                    .iter()
                    .any(|owner| roots.iter().any(|root| *owner == SymbolId::of(root)))),
                dm_ir::ResolvedMeaning::Missing => Ok(false),
                _ => self.semantic(Err(lookup.error(query, "invalid feature ancestry answer"))),
            };
        }
        // Standalone callers supply the existing captured binding graph. Do not
        // use lexical path prefixes: parent_type can change native ancestry.
        let mut at = path;
        for _ in 0..=self
            .bindings
            .shared
            .as_ref()
            .map_or(0, |s| s.parent_types.len())
        {
            if roots.contains(&at) {
                return Ok(true);
            }
            let Some(parent) = self
                .bindings
                .shared
                .as_ref()
                .and_then(|s| s.parent_types.get(at))
            else {
                return Ok(false);
            };
            at = parent;
        }
        Err(error(path, "feature ancestry cycle"))
    }
    pub(super) fn source_feature_reference(
        &mut self,
        expr: &Expr,
        used: bool,
        statement: &str,
    ) -> Result<(), LowerError> {
        let (name, owner, computed) = match &expr.kind {
            ExprKind::Group(inner) => return self.source_feature_reference(inner, used, statement),
            ExprKind::Ident(name)
                if matches!(name.as_str(), "cpu" | "icon" | "overlays" | "underlays") =>
            {
                if self.lookup.is_none() && self.bindings.current_type_path.is_none() {
                    return Ok(());
                }
                let meaning = self.variable_meaning(name, statement)?;
                let dm_ir::SelectedMeaning::InstanceField { .. } = meaning else {
                    return Ok(());
                };
                (
                    name.as_str(),
                    self.bindings.current_type_path.clone(),
                    false,
                )
            }
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember {
                object, selector, ..
            } => {
                if !matches!(selector.as_str(), "cpu" | "icon" | "overlays" | "underlays") {
                    return Ok(());
                }
                (
                    selector.as_str(),
                    dm_ir::receiver_resolution::infer_receiver_type(
                        &receiver_resolution::ReceiverContext(self, true),
                        object,
                    )?,
                    !matches!(&object.kind, ExprKind::Ident(_)),
                )
            }
            ExprKind::StaticMember { object, selector } => {
                if !matches!(selector.as_str(), "cpu" | "icon" | "overlays" | "underlays") {
                    return Ok(());
                }
                let ExprKind::TypePath(path) = &object.kind else {
                    return Ok(());
                };
                (selector.as_str(), Some(path.clone()), false)
            }
            _ => return Ok(()),
        };
        if name == "cpu" {
            // Used untyped CPU operands also enable negotiation in the pinned
            // compiler. Plain discarded reads do not; computed receivers do.
            if used || computed {
                let observed = match owner {
                    Some(owner) => self.feature_inherits(&owner, &["/world"])?,
                    None => true,
                };
                self.result.source_features.world_cpu |= observed;
            }
        } else if let Some(owner) = owner {
            let observed = self.feature_inherits(
                &owner,
                &[
                    "/atom",
                    "/obj",
                    "/mob",
                    "/turf",
                    "/area",
                    "/image",
                    "/mutable_appearance",
                ],
            )?;
            self.result.source_features.native_graphics |= observed;
        }
        Ok(())
    }
}

#[cfg(test)]
#[path = "source_features_tests.rs"]
mod tests;
