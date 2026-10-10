//! Source-independent procedure spelling/selectors on the existing artifact.
use super::*;
use crate::lowering::UnitIdentity;
use dm_codegen_byond::procedure_abi::ArgumentSource;
use std::sync::Arc;

pub(crate) struct ProcedureMetadataRecipe {
    frame: std::sync::Mutex<Option<Arc<super::frame_contribution::FrameContribution>>>,
    identity: UnitIdentity,
    formal_path: Arc<str>,
    implicit_path: Arc<str>,
    display: Arc<str>,
    selectors: Arc<[ArgumentSource]>,
    locals: std::sync::Mutex<Option<emission_lists::LocalList>>,
    arguments: std::sync::Mutex<Option<emission_lists::ArgumentList>>,
}
impl ProcedureMetadataRecipe {
    pub(crate) fn capture(
        identity: UnitIdentity,
        symbols: &SymbolTable,
        abi: Option<&crate::procedure_policy::PreparedAbi>,
    ) -> Result<Self, CompositionError> {
        let formal_path: Arc<str> = proc_path(
            symbols,
            identity.owner,
            identity.name,
            identity.namespace,
            true,
        )?
        .into();
        let implicit_path = if text(symbols, identity.owner)? == "/" {
            Arc::clone(&formal_path)
        } else {
            proc_path(
                symbols,
                identity.owner,
                identity.name,
                identity.namespace,
                false,
            )?
            .into()
        };
        Ok(Self {
            frame: Default::default(),
            identity,
            formal_path,
            implicit_path,
            display: text(symbols, identity.name)?.replace('_', " ").into(),
            selectors: abi.map_or_else(|| Arc::from([]), |abi| abi.argument_sources.clone().into()),
            locals: Default::default(),
            arguments: Default::default(),
        })
    }
    pub(super) fn frame_owner(
        &self,
    ) -> &std::sync::Mutex<Option<Arc<super::frame_contribution::FrameContribution>>> {
        &self.frame
    }
    pub(crate) fn path(
        &self,
        symbols: &SymbolTable,
        declared: bool,
    ) -> Result<Arc<str>, CompositionError> {
        // Current catalog presence is still authoritative. SymbolTable's checked
        // ID/spelling invariant certifies equal immutable spellings across owners.
        text(symbols, self.identity.owner)?;
        text(symbols, self.identity.name)?;
        Ok(Arc::clone(if declared {
            &self.formal_path
        } else {
            &self.implicit_path
        }))
    }
    pub(crate) fn display(&self, symbols: &SymbolTable) -> Result<Arc<str>, CompositionError> {
        text(symbols, self.identity.name)?;
        Ok(Arc::clone(&self.display))
    }
    pub(crate) fn selectors<'a>(&'a self, current: &'a [ArgumentSource]) -> &'a [ArgumentSource] {
        if self.selectors.as_ref() == current {
            &self.selectors
        } else {
            current
        }
    }
    pub(crate) fn census(recipe: &Arc<Self>, census: &mut crate::heap_census::HeapCensus) {
        if census.arc_object("procedure_metadata.recipe", recipe) {
            if let Some(frame) = recipe
                .frame
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .as_ref()
            {
                if census.arc_object("procedure_metadata.frame", frame) {
                    frame.census(census);
                }
            }
            census.arc_text("procedure_metadata.paths", &recipe.formal_path);
            census.arc_text("procedure_metadata.paths", &recipe.implicit_path);
            census.arc_text("procedure_metadata.display", &recipe.display);
            census.slice("procedure_metadata.selectors", &recipe.selectors, true);
            recipe.census_emission_lists(census);
            census.unknown(
                "procedure_metadata.recipe",
                "Arc control block and allocator overhead are unavailable",
            );
        }
    }
}

mod emission_lists;

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn metadata_recipe_keeps_namespace_forms_and_requires_current_spelling_presence() {
        let mut symbols = SymbolTable::default();
        let owner = symbols.intern("/datum/probe").unwrap();
        let name = symbols.intern("café_name").unwrap();
        let identity = UnitIdentity {
            owner,
            name,
            namespace: Namespace::Verb,
            occurrence: 3,
        };
        let recipe = ProcedureMetadataRecipe::capture(identity, &symbols, None).unwrap();
        assert_eq!(
            &*recipe.path(&symbols, true).unwrap(),
            "/datum/probe/verb/café_name"
        );
        assert_eq!(
            &*recipe.path(&symbols, false).unwrap(),
            "/datum/probe/café_name"
        );
        assert_eq!(&*recipe.display(&symbols).unwrap(), "café name");
        let first = recipe.path(&symbols, true).unwrap();
        assert!(Arc::ptr_eq(&first, &recipe.path(&symbols, true).unwrap()));
        let mut missing_owner = SymbolTable::default();
        missing_owner.intern("café_name").unwrap();
        assert!(
            matches!(recipe.path(&missing_owner,true), Err(CompositionError::MissingSymbol(id)) if id == owner)
        );
        assert_eq!(&*recipe.display(&missing_owner).unwrap(), "café name");
        assert!(
            matches!(recipe.display(&SymbolTable::default()), Err(CompositionError::MissingSymbol(id)) if id == name)
        );
    }
    #[test]
    fn changed_current_argument_selector_is_not_replaced_by_retained_selector() {
        let mut symbols = SymbolTable::default();
        let identity = UnitIdentity {
            owner: symbols.intern("/").unwrap(),
            name: symbols.intern("run").unwrap(),
            namespace: Namespace::Proc,
            occurrence: 0,
        };
        let recipe = ProcedureMetadataRecipe::capture(identity, &symbols, None).unwrap();
        let current = [ArgumentSource::Helper { argument: 7 }];
        assert_eq!(recipe.selectors(&current), &current);
        assert!(std::ptr::eq(
            recipe.selectors(&current).as_ptr(),
            current.as_ptr()
        ));
    }
}
