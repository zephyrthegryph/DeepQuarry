//! Source-neutral finite variable coverage; current source wrappers remain separate.
use super::*;
#[derive(Debug)]
pub(crate) struct VariableCoverage {
    pub(super) names: HashSet<SymbolId>,
    ordinary_globals: Arc<engine_providers::OrdinaryGlobalNames>,
    pub(super) positive_constants: BTreeMap<SymbolId, SemanticValue>,
}
impl VariableCoverage {
    pub(super) fn capture(
        frontend: &dm_tree::frontend::ColdFrontend,
        providers: &engine_providers::VariableProviders,
        constants: &ConstantCatalog,
    ) -> Arc<Self> {
        let mut names: HashSet<_> = frontend
            .snapshot
            .tree
            .host_declaration_selections()
            .flat_map(|(_, selection)| selection.declared_variable_names.iter().copied())
            .filter(|name| !providers.intrinsic.contains(name))
            .collect();
        names.insert(SymbolId::of("__TYPE__"));
        names.insert(SymbolId::of("__IMPLIED_TYPE__"));
        for (name, value) in providers.constants.values.iter() {
            if !providers.intrinsic.contains(name) && constants.values.get(name) == Some(value) {
                names.insert(*name);
            }
        }
        let positive_constants = providers
            .positive_constants
            .iter()
            .filter(|(name, value)| constants.values.get(*name) == Some(*value))
            .map(|(name, value)| (*name, value.clone()))
            .collect();
        Arc::new(Self {
            names,
            ordinary_globals: Arc::clone(&providers.ordinary_globals),
            positive_constants,
        })
    }
    pub(super) fn covers_predefined_absence(&self, name: SymbolId) -> bool {
        self.ordinary_globals.covers_predefined_absence(name)
    }
    pub(super) fn covers(&self, query: Q) -> bool {
        match query {
            // Finite source-admitted coverage predates the ordinary-name policy
            // (notably lexical __TYPE__ storage absence). Preserve it exactly;
            // exclusions constrain only the newly generalized branch.
            Q::GlobalVar(name) => self.names.contains(&name) || self.ordinary_globals.covers(name),
            Q::Var { name, .. }
            | Q::HasMemberVar { name, .. }
            | Q::DeclaredVarType { name, .. }
            | Q::VarStorage { name, .. }
            | Q::StaticVar { name, .. }
            | Q::Constant { name, .. } => self.names.contains(&name),
            _ => false,
        }
    }
    pub(crate) fn census(self: &Arc<Self>, census: &mut crate::heap_census::HeapCensus) {
        if census.arc_object("host.variable_coverage", self) {
            self.ordinary_globals.census(census);
            census.observe_items("host.variable_coverage.names", self.names.len());
            census.observe_items(
                "host.variable_coverage.constants",
                self.positive_constants.len(),
            );
            census.unknown(
                "host.variable_coverage",
                "private HashSet/BTreeMap node backing excluded",
            );
            for value in self.positive_constants.values() {
                census.semantic_value("host.variable_coverage.constants", value);
            }
        }
    }
}
