//! Positive receiver-method inventory from the pinned native compiler catalog.
//! SourceInfo, argument annotations/default presence and raw records are kept
//! opaque. None is converted to source signature flags or output procedure IDs.
use dm_ir::{ResolveQuery, ResolvedMeaning, SymbolId, SymbolTable};
use std::{collections::BTreeMap, sync::Arc};

#[path = "intrinsic_methods/closed_namespace.rs"]
mod closed_namespace;
pub(super) use closed_namespace::ClosedNamespace;
pub(super) use closed_namespace::EVIDENCE as CLOSED_NAMESPACE_POLICY;

pub(super) type NativeMethods = Arc<BTreeMap<(SymbolId, SymbolId), Arc<[u8]>>>;
#[derive(Clone, Debug)]
pub(super) struct IntrinsicMethods {
    source: Arc<dm_tree::SemanticTree>,
    methods: NativeMethods,
    closed: Option<Arc<ClosedNamespace>>,
}

impl IntrinsicMethods {
    pub(super) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        if let Some(closed) = &self.closed {
            closed.census(census);
        }
        let owner = "host.intrinsic_methods";
        if census.arc_object(owner, &self.methods) {
            census.collection_entries::<((SymbolId, SymbolId), Arc<[u8]>)>(
                owner,
                self.methods.as_ref() as *const _ as usize,
                self.methods.len(),
            );
            for bytes in self.methods.values() {
                census.slice(owner, bytes, true);
            }
        }
    }

    #[cfg(test)]
    pub(super) fn capture(
        source: Arc<dm_tree::SemanticTree>,
        catalog: &serde_json::Value,
    ) -> Result<Self, String> {
        let (methods, spellings) = Self::capture_payload(catalog)?;
        let mut current = SymbolTable::overlay(source.shared_symbols());
        current
            .merge_from(&spellings)
            .map_err(|error| format!("native symbol {error:?}"))?;
        Ok(Self {
            source,
            methods,
            closed: None,
        })
    }
    pub(super) fn from_payload(
        source: Arc<dm_tree::SemanticTree>,
        methods: NativeMethods,
        closed: Arc<ClosedNamespace>,
    ) -> Self {
        Self {
            source,
            methods,
            closed: Some(closed),
        }
    }
    pub(super) fn capture_payload(
        catalog: &serde_json::Value,
    ) -> Result<(NativeMethods, SymbolTable), String> {
        let types = catalog["Types"]
            .as_array()
            .ok_or("native type catalog absent")?;
        let procs = catalog["Procs"]
            .as_array()
            .ok_or("native callable catalog absent")?;
        let mut methods = BTreeMap::new();
        let mut spellings = SymbolTable::default();
        for record in procs {
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
            // These exact native receiver-call controls certify procedure
            // presence even though the catalog retains opaque implementation
            // bytes. Those bytes are never lowered or used as an ABI signature.
            let observed_receiver =
                matches!(
                    (owner, name),
                    ("/client", "MeasureText") | ("/atom", "Enter" | "Uncross")
                ) || crate::native_callbacks::lookup(SymbolId::of(owner), SymbolId::of(name))
                    .is_some_and(|fact| fact.kind == dm_tree::MemberKind::Proc);
            if !observed_receiver
                && (record["Bytecode"].as_str() != Some("")
                    || !record["SourceInfo"]
                        .as_array()
                        .is_some_and(|source| source.is_empty()))
            {
                continue;
            }
            // A catalog verb label is not a native namespace certificate.
            // The finite native controls positively certify directional
            // callbacks as Proc; retain the existing decline for other verbs.
            if record
                .get("IsVerb")
                .and_then(|value| value.as_bool())
                .unwrap_or(false)
                && !crate::native_callbacks::lookup(SymbolId::of(owner), SymbolId::of(name))
                    .is_some_and(|fact| fact.kind == dm_tree::MemberKind::Proc)
            {
                continue;
            }
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
        Ok((Arc::new(methods), spellings))
    }
    pub(super) fn resolve(&self, query: ResolveQuery) -> Option<ResolvedMeaning> {
        if let ResolveQuery::MemberCallableVerbName(name) = query {
            return self.closed.as_ref()?.verb_selector(&self.source, name);
        }
        if let ResolveQuery::MemberCallableName(name) = query {
            return self.closed.as_ref()?.member_name(&self.source, name);
        }
        let (owner, name, verb) = match query {
            ResolveQuery::Proc { owner, name, verb }
            | ResolveQuery::MethodProcedureValue { owner, name, verb } => (owner, name, Some(verb)),
            ResolveQuery::HasMemberProc { owner, name } => (owner, name, None),
            _ => return None,
        };
        if owner == SymbolId::of("/") {
            return None;
        }
        let excludes = self
            .closed
            .as_ref()
            .is_some_and(|closed| closed.excludes(&self.source, owner, name));
        let negative = || {
            excludes.then(|| match verb {
                None => ResolvedMeaning::Presence(false),
                Some(_) => ResolvedMeaning::Missing,
            })
        };
        let mut current = self.source.lookup_type(owner)?;
        loop {
            let declaring_owner = self.source.type_node(current)?.path;
            if declaring_owner == SymbolId::of("/") {
                return negative();
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
            let Some(parent) = self.source.parent(current) else {
                return negative();
            };
            current = parent;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn certified_callbacks_admit_opaque_bodies_without_source_occurrences() {
        let engine = crate::engine::EngineSnapshot::from_bytes(
            include_bytes!("../../../fixtures/native_template.bin"),
            1,
        )
        .unwrap()
        .with_bootstrap_catalog()
        .unwrap();
        let source = Arc::new(engine.build_tree(engine.symbols().clone(), &[]).unwrap());
        let catalog = serde_json::from_slice(include_bytes!(
            "../../../fixtures/native_template_nativebuiltins_5161687.json"
        ))
        .unwrap();
        let methods = IntrinsicMethods::capture(source, &catalog).unwrap();
        for (owner, name) in [
            ("/atom/movable", "Move"),
            ("/client", "Click"),
            ("/atom", "Exit"),
            ("/atom", "Cross"),
        ] {
            let owner = SymbolId::of(owner);
            let name = SymbolId::of(name);
            assert!(
                matches!(methods.resolve(ResolveQuery::MethodProcedureValue { owner, name, verb: false }),
                Some(ResolvedMeaning::IntrinsicProc { declaring_owner, name: selected }) if declaring_owner == owner && selected == name)
            );
            assert!(methods
                .resolve(ResolveQuery::ProcedureValue {
                    owner,
                    name,
                    verb: false,
                    formal: true
                })
                .is_none());
        }
    }
    #[test]
    fn native_receiver_calls_admit_only_exact_opaque_catalog_methods() {
        use sha2::{Digest, Sha256};
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures/phase1/native_receiver_methods");
        let receipt: serde_json::Value =
            serde_json::from_slice(&std::fs::read(root.join("receipt.json")).unwrap()).unwrap();
        assert_eq!(
            receipt["compiler_sha256"],
            "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"
        );
        assert_eq!(receipt["exit_code"], 0);
        for (path, hash) in receipt["files"].as_object().unwrap() {
            assert_eq!(
                format!(
                    "{:x}",
                    Sha256::digest(std::fs::read(root.join(path)).unwrap())
                ),
                hash.as_str().unwrap()
            );
        }
        let engine = crate::engine::EngineSnapshot::from_bytes(
            include_bytes!("../../../fixtures/native_template.bin"),
            1,
        )
        .unwrap()
        .with_bootstrap_catalog()
        .unwrap();
        let source = Arc::new(engine.build_tree(engine.symbols().clone(), &[]).unwrap());
        let catalog = serde_json::from_slice(include_bytes!(
            "../../../fixtures/native_template_nativebuiltins_5161687.json"
        ))
        .unwrap();
        let methods = IntrinsicMethods::capture(source, &catalog).unwrap();
        let image =
            byond_dmb::dmb::Dmb::from_bytes(&std::fs::read(root.join("probe.native.bin")).unwrap())
                .unwrap();
        for (index, owner, name, selector, expected_owner) in [
            (0, "/client", "MeasureText", 293, "/client"),
            (1, "/atom", "Enter", 2, "/atom"),
            (2, "/atom/movable", "Uncross", 232, "/atom"),
        ] {
            assert_eq!(image.string(selector), Some(name.as_bytes()));
            let words = image.proc_code_words(index).unwrap();
            assert_eq!(
                &words[3..],
                &[0x29, 65500, 65486, 65501, selector, 1, 0x12, 0]
            );
            assert!(matches!(
                methods.resolve(ResolveQuery::Proc {
                    owner: SymbolId::of(owner),
                    name: SymbolId::of(name),
                    verb: false
                }),
                Some(ResolvedMeaning::IntrinsicProc { .. })
            ));
            assert!(matches!(
                methods.resolve(ResolveQuery::MethodProcedureValue {
                    owner: SymbolId::of(owner),
                    name: SymbolId::of(name),
                    verb: false
                }),
                Some(ResolvedMeaning::IntrinsicProc { declaring_owner, name: captured })
                    if declaring_owner == SymbolId::of(expected_owner) && captured == SymbolId::of(name)
            ));
            // Source literal paths cannot acquire an invented native body.
            assert!(methods
                .resolve(ResolveQuery::ProcedureValue {
                    owner: SymbolId::of(owner),
                    name: SymbolId::of(name),
                    verb: false,
                    formal: true
                })
                .is_none());
        }
    }
    #[test]
    fn only_observed_proc_receipts_override_catalog_verb_annotation() {
        let mut symbols = SymbolTable::default();
        let owner = symbols.intern("/client").unwrap();
        let known = symbols.intern("Northeast").unwrap();
        let unknown = symbols.intern("UnobservedVerb").unwrap();
        let source = Arc::new(
            dm_tree::build(
                symbols,
                &[dm_tree::Skeleton::Type {
                    path: owner,
                    explicit_parent: None,
                }],
            )
            .unwrap(),
        );
        let catalog = serde_json::json!({"Types": [{"Path": "/client"}], "Procs": [
            {"Name": "Northeast", "OwningTypeId": 0, "IsVerb": true, "Bytecode": "", "SourceInfo": []},
            {"Name": "UnobservedVerb", "OwningTypeId": 0, "IsVerb": true, "Bytecode": "", "SourceInfo": []}
        ]});
        let methods = IntrinsicMethods::capture(source, &catalog).unwrap();
        assert!(matches!(
            methods.resolve(ResolveQuery::Proc {
                owner,
                name: known,
                verb: false
            }),
            Some(ResolvedMeaning::IntrinsicProc { .. })
        ));
        assert!(matches!(
            methods.resolve(ResolveQuery::Proc {
                owner,
                name: known,
                verb: true
            }),
            Some(ResolvedMeaning::Missing)
        ));
        assert!(methods
            .resolve(ResolveQuery::Proc {
                owner,
                name: unknown,
                verb: false
            })
            .is_none());
    }
}

#[cfg(test)]
#[path = "intrinsic_methods/closed_namespace_tests.rs"]
mod closed_namespace_tests;
