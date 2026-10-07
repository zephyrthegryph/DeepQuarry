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
            let observed_receiver = matches!(
                (owner, name),
                ("/client", "MeasureText") | ("/atom", "Enter" | "Uncross")
            );
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

#[cfg(test)]
mod tests {
    use super::*;
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
        for (index, owner, name, selector) in [
            (0, "/client", "MeasureText", 293),
            (1, "/atom", "Enter", 2),
            (2, "/atom/movable", "Uncross", 232),
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
