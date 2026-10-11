//! Pinned documented native receiver namespaces; global builtin names stay open.
use super::*;
use std::collections::BTreeSet;
pub(crate) const EVIDENCE: &[u8] = include_bytes!(
    "../../../../fixtures/native/parameter_duplicate_diagnostics/native_receiver_namespace.json"
);
#[derive(Debug)]
pub(crate) struct ClosedNamespace {
    native_owners: BTreeSet<SymbolId>,
    datum_names: BTreeSet<SymbolId>,
    documented_names: BTreeSet<SymbolId>,
    ambiguous_names: BTreeSet<SymbolId>,
}
impl ClosedNamespace {
    pub(crate) fn capture(catalog: &serde_json::Value) -> Result<Arc<Self>, String> {
        let evidence: serde_json::Value =
            serde_json::from_slice(EVIDENCE).map_err(|e| e.to_string())?;
        if evidence["schema"] != 1
            || evidence["compiler_version"] != "516.1687"
            || evidence["compiler_sha256"]
                != "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
            || evidence["closed_owners"] != serde_json::json!(["/datum"])
            || evidence["member_name_union_closed"] != true
        {
            return Err(
                "native receiver namespace authority is not the pinned reviewed policy".into(),
            );
        }
        let types = catalog["Types"]
            .as_array()
            .ok_or("native namespace types absent")?;
        let native_owners = types
            .iter()
            .map(|ty| {
                ty["Path"]
                    .as_str()
                    .map(SymbolId::of)
                    .ok_or("native namespace path absent")
            })
            .collect::<Result<BTreeSet<_>, _>>()?;
        let datum_names = evidence["owners"]["/datum"]["documented_procs"]
            .as_array()
            .ok_or("documented datum proc namespace absent")?
            .iter()
            .map(|name| {
                name.as_str()
                    .map(SymbolId::of)
                    .ok_or("documented datum proc name malformed")
            })
            .collect::<Result<BTreeSet<_>, _>>()?;
        let mut catalog_names = BTreeSet::new();
        for record in catalog["Procs"]
            .as_array()
            .ok_or("native namespace procedures absent")?
        {
            let Some(index) = record["OwningTypeId"].as_u64() else {
                continue;
            };
            let owner = types
                .get(usize::try_from(index).map_err(|_| "native namespace index overflow")?)
                .ok_or("native namespace owner absent")?;
            if owner["Path"] == "/datum" {
                catalog_names.insert(SymbolId::of(
                    record["Name"]
                        .as_str()
                        .ok_or("native namespace name absent")?,
                ));
            }
        }
        // All documented native members, including hidden callbacks, must remain
        // in the conservative positive inventory. Missing catalog evidence declines.
        if datum_names != catalog_names || datum_names.is_empty() {
            return Err("documented datum namespace does not match pinned native inventory".into());
        }
        let mut documented_names = BTreeSet::new();
        let mut ambiguous_names = BTreeSet::new();
        for (_, owner) in evidence["owners"]
            .as_object()
            .ok_or("native reference owner namespace absent")?
        {
            for name in owner["documented_procs"]
                .as_array()
                .ok_or("documented native proc names absent")?
            {
                documented_names.insert(SymbolId::of(
                    name.as_str()
                        .ok_or("documented native proc name malformed")?,
                ));
            }
            for name in owner["catalog_only"]
                .as_array()
                .ok_or("native opaque names absent")?
            {
                ambiguous_names.insert(SymbolId::of(
                    name.as_str().ok_or("native opaque name malformed")?,
                ));
            }
            if !owner["documented_missing_from_catalog"]
                .as_array()
                .is_some_and(|values| values.is_empty())
            {
                return Err(
                    "documented native member omitted from conservative positive catalog".into(),
                );
            }
        }
        for record in catalog["Procs"]
            .as_array()
            .ok_or("native namespace procedures absent")?
        {
            let Some(index) = record["OwningTypeId"].as_u64() else {
                continue;
            };
            let owner = types
                .get(usize::try_from(index).map_err(|_| "native namespace index overflow")?)
                .ok_or("native namespace owner absent")?;
            if owner["Path"] == "/" {
                continue;
            }
            let name = SymbolId::of(
                record["Name"]
                    .as_str()
                    .ok_or("native namespace name absent")?,
            );
            if !documented_names.contains(&name) {
                ambiguous_names.insert(name);
            }
        }
        Ok(Arc::new(Self {
            native_owners,
            datum_names,
            documented_names,
            ambiguous_names,
        }))
    }
    pub(super) fn member_name(
        &self,
        source: &dm_tree::SemanticTree,
        name: SymbolId,
    ) -> Option<ResolvedMeaning> {
        match source.source_member_callable_name(name)? {
            true => Some(ResolvedMeaning::Presence(true)),
            false if self.documented_names.contains(&name) => Some(ResolvedMeaning::Presence(true)),
            false if self.ambiguous_names.contains(&name) => None,
            false => Some(ResolvedMeaning::Presence(false)),
        }
    }
    pub(super) fn verb_selector(
        &self,
        source: &dm_tree::SemanticTree,
        name: SymbolId,
    ) -> Option<ResolvedMeaning> {
        let flags = source
            .member_callable_name_storage()
            .get(&name)
            .copied()
            .unwrap_or(0);
        if flags & 1 != 0 || self.documented_names.contains(&name) {
            Some(ResolvedMeaning::Presence(false))
        } else if self.ambiguous_names.contains(&name) {
            None
        } else if flags & 2 != 0 {
            Some(ResolvedMeaning::Presence(true))
        } else {
            None
        }
    }
    pub(super) fn excludes(
        &self,
        source: &dm_tree::SemanticTree,
        owner: SymbolId,
        name: SymbolId,
    ) -> bool {
        if owner == SymbolId::of("/") || self.datum_names.contains(&name) {
            return false;
        }
        let Some(mut current) = source.lookup_type(owner) else {
            return false;
        };
        let mut seen = BTreeSet::new();
        let mut saw_datum = false;
        loop {
            if !seen.insert(current) {
                return false;
            }
            let Some(node) = source.type_node(current) else {
                return false;
            };
            if node.path == SymbolId::of("/") {
                return saw_datum;
            }
            if node.path == SymbolId::of("/datum") {
                saw_datum = true;
            }

            // Source declarations may add members, which the normal resolver
            // selected before this fallback. Unreviewed native namespaces cannot
            // inherit a datum-only negative policy (client, list, etc.).
            if node.path != SymbolId::of("/datum") && self.native_owners.contains(&node.path) {
                return false;
            }
            let Some(parent) = source.parent(current) else {
                return saw_datum;
            };
            current = parent;
        }
    }
    pub(crate) fn census(self: &Arc<Self>, census: &mut crate::heap_census::HeapCensus) {
        if census.arc_object("host.callable.closed_namespace", self) {
            census.observe_items(
                "host.callable.closed_namespace",
                self.native_owners.len()
                    + self.datum_names.len()
                    + self.documented_names.len()
                    + self.ambiguous_names.len(),
            );
            census.unknown(
                "host.callable.closed_namespace",
                "private BTreeSet node layout excluded; exact exposed owner object counted",
            );
        }
    }
}
