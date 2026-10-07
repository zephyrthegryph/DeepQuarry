//! Positive receiver-method inventory from the pinned native compiler catalog.
//! SourceInfo, argument annotations/default presence and raw records are kept
//! opaque. None is converted to source signature flags or output procedure IDs.
use dm_ir::{ResolveQuery, ResolvedMeaning, SymbolId, SymbolTable};
use std::{collections::BTreeMap, sync::Arc};

#[derive(Clone, Debug)]
pub(super) struct IntrinsicMethods {
    source: Arc<dm_tree::SemanticTree>,
    methods: BTreeMap<(SymbolId, SymbolId), Arc<[u8]>>,
}
impl IntrinsicMethods {
    pub(super) fn capture(
        source: Arc<dm_tree::SemanticTree>,
        catalog: &serde_json::Value,
    ) -> Result<Self, String> {
        let types = catalog["Types"]
            .as_array()
            .ok_or("native type catalog absent")?;
        let procs = catalog["Procs"]
            .as_array()
            .ok_or("native callable catalog absent")?;
        let mut methods = BTreeMap::new();
        let mut spellings = SymbolTable::overlay(source.shared_symbols());
        for record in procs {
            if record
                .get("IsVerb")
                .and_then(|value| value.as_bool())
                .unwrap_or(false)
                || record["Bytecode"].as_str() != Some("")
                || !record["SourceInfo"]
                    .as_array()
                    .is_some_and(|source| source.is_empty())
            {
                continue;
            }
            let Some(owner_index) = record["OwningTypeId"].as_u64() else {
                // No explicit receiver owner is positive method evidence.
                // Free/anonymous catalog records remain outside this domain.
                continue;
            };
            let owner_index =
                usize::try_from(owner_index).map_err(|_| "native method owner overflow")?;
            let owner = types
                .get(owner_index)
                .and_then(|ty| ty["Path"].as_str())
                .ok_or("native method owner path absent")?;
            // Free compiler builtins are a different lowering domain.
            if owner == "/" {
                continue;
            }
            let name = record["Name"].as_str().ok_or("native method name absent")?;
            let owner = spellings
                .intern(owner)
                .map_err(|error| format!("native owner symbol {error:?}"))?;
            let name = spellings
                .intern(name)
                .map_err(|error| format!("native method symbol {error:?}"))?;
            let key = (owner, name);
            let bytes: Arc<[u8]> = serde_json::to_vec(record)
                .map_err(|error| error.to_string())?
                .into();
            if methods
                .insert(key, Arc::clone(&bytes))
                .is_some_and(|old| old != bytes)
            {
                return Err(format!(
                    "conflicting native method catalog {owner:?}/{name:?}"
                ));
            }
        }
        Ok(Self { source, methods })
    }
    pub(super) fn resolve(&self, query: ResolveQuery) -> Option<ResolvedMeaning> {
        let (owner, name, verb) = match query {
            ResolveQuery::Proc { owner, name, verb } => (owner, name, Some(verb)),
            ResolveQuery::HasMemberProc { owner, name } => (owner, name, None),
            _ => return None,
        };
        if owner == SymbolId::of("/") {
            return None;
        }
        let mut current = self.source.lookup_type(owner)?;
        loop {
            let declaring_owner = self.source.type_node(current)?.path;
            if declaring_owner == SymbolId::of("/") {
                return None;
            }
            if self.methods.contains_key(&(declaring_owner, name)) {
                return Some(match verb {
                    None => ResolvedMeaning::Presence(true),
                    Some(false) => ResolvedMeaning::IntrinsicProc {
                        declaring_owner,
                        name,
                    },
                    // The captured record is in the procedure namespace. The
                    // caller has already preserved positive source verb answers.
                    Some(true) => ResolvedMeaning::Missing,
                });
            }
            current = self.source.parent(current)?;
        }
    }
}
