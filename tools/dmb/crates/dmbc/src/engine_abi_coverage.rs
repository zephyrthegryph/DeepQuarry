//! Pinned ABI policy: physical engine coverage alone is not a certificate
//! that the VM has no additional named intrinsic procedures.
use crate::{driver_facts::unit_members, engine::EngineSnapshot, lowering::UnitIdentity};
use dm_ir::SymbolId;
use dm_tree::{frontend::ColdFrontend, DefinitionMode, MemberId, MemberKind};
use std::collections::{BTreeMap, HashSet};
/// Shared finite native receipts; unknown names remain uncertified.
pub(crate) fn callback_spelling(owner: SymbolId, name: SymbolId) -> Option<&'static str> {
    crate::native_callbacks::lookup(owner, name).map(|fact| fact.name)
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum BoundarySelection {
    SourcePrevious(MemberId),
    CapturedEngine {
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
    },
    CertifiedFormalDefault,
    CertifiedCallback {
        owner: SymbolId,
        name: SymbolId,
    },
    KnownVmIntrinsicWithoutLayout {
        owner: SymbolId,
        name: SymbolId,
    },
    /// These actual records cannot be assigned a semantic name from their ABI.
    UnmappedUnnamed {
        owner: SymbolId,
        wire_procedures: Vec<u32>,
    },
    /// No physical named record is not proof of VM semantic absence.
    UncertifiableAbsence {
        name: SymbolId,
        kind: MemberKind,
    },
}

/// The snapshot constructor has validated every class proc/verb list and the
/// world/global proc list. Keep that exact snapshot borrowed: a catalog identity
/// or a newly decoded unrelated template cannot replace this authority.
pub struct NamedEngineCoverage<'a> {
    engine: &'a EngineSnapshot,
    native_names: HashSet<(SymbolId, SymbolId)>,
}
impl<'a> NamedEngineCoverage<'a> {
    /// Captured host configuration must include this value. It binds the finite
    /// native language policy and exact exclusion inventory, not just DMB bytes.
    pub fn policy_identity(&self) -> u128 {
        let mut bytes = b"named-engine-abi-policy-v3;formal-default;observed-callbacks-5161687;conservative-cross-namespace-exclusions".to_vec();
        crate::native_callbacks::append_fingerprint(&mut bytes);
        bytes.extend_from_slice(&self.engine.identity().to_le_bytes());
        bytes.extend_from_slice(&self.engine.interpretation_schema().to_le_bytes());
        bytes.extend_from_slice(include_bytes!(
            "../../../fixtures/native_template_nativebuiltins_5161687.json"
        ));
        xxhash_rust::xxh3::xxh3_128(&bytes)
    }
    pub fn boundaries(
        &self,
        frontend: &ColdFrontend,
    ) -> Result<BTreeMap<UnitIdentity, crate::driver_facts::BoundaryAbi>, String> {
        if frontend.engine.as_ref().map(|status| status.identity) != Some(self.engine.identity()) {
            return Err("ABI coverage belongs to another captured frontend engine".into());
        }
        let units = unit_members(frontend).map_err(|error| error.to_string())?;
        self.boundaries_with_units(frontend, &units)
    }
    pub(crate) fn boundaries_with_units(
        &self,
        frontend: &ColdFrontend,
        units: &BTreeMap<UnitIdentity, MemberId>,
    ) -> Result<BTreeMap<UnitIdentity, crate::driver_facts::BoundaryAbi>, String> {
        let mut result = BTreeMap::new();
        for (unit, selection) in self.select_with_units(frontend, units)? {
            match selection {
                BoundarySelection::SourcePrevious(_) => {}
                BoundarySelection::CapturedEngine { owner, name, kind } => {
                    result.insert(
                        unit,
                        crate::driver_facts::BoundaryAbi::Engine { owner, name, kind },
                    );
                }
                BoundarySelection::CertifiedFormalDefault => {
                    result.insert(unit, crate::driver_facts::BoundaryAbi::Fresh);
                }
                BoundarySelection::CertifiedCallback { owner, name } => {
                    let receipt = crate::driver_facts::CertifiedIntrinsicAbi::callback(
                        self.engine,
                        owner,
                        name,
                    )
                    .map_err(|e| e.to_string())?;
                    result.insert(
                        unit,
                        crate::driver_facts::BoundaryAbi::CertifiedIntrinsic(receipt),
                    );
                }
                other => {
                    let symbols = frontend.snapshot.tree.symbols();
                    let owner = symbols.text(unit.owner).unwrap_or("<unknown owner>");
                    let name = symbols.text(unit.name).unwrap_or("<unknown name>");
                    let member = units.get(&unit).copied();
                    // An override of a name that neither the source nor any
                    // built-in of the owner declares is the author's error.
                    if let BoundarySelection::UncertifiableAbsence { name: missing, kind } = &other {
                        let tree = &frontend.snapshot.tree;
                        let plain = tree
                            .lookup_type(unit.owner)
                            .is_some_and(|owner| crate::lowering::wording::plain_datum(tree, owner));
                        let builtin = symbols.text(*missing).is_none_or(|missing| match kind {
                            MemberKind::Var => dm_ir::builtin_names::is_builtin_var_in(plain, missing),
                            MemberKind::Proc | MemberKind::Verb => {
                                dm_ir::builtin_names::is_builtin_proc_in(plain, missing)
                            }
                        });
                        let body = frontend.bodies.iter().find(|body| Some(body.member) == member);
                        if let (false, Some(body), Some(missing)) = (builtin, body, symbols.text(*missing)) {
                            let undefined = if *kind == MemberKind::Var { "undefined var" } else { "undefined proc" };
                            return Err(format!(
                                "{}{}:{}:error: {missing}: {undefined}",
                                crate::diagnostics::CARRIED_SOURCE_ERROR,
                                body.source.semantic_path,
                                body.source.line
                            ));
                        }
                    }
                    let origin = frontend
                        .bodies
                        .iter()
                        .find(|body| Some(body.member) == member)
                        .map(|body| {
                            format!(
                                "{}:{} (include occurrence {}, encounter {}, expanded {}..{})",
                                body.source.path.display(),
                                body.source.line,
                                body.source.include_occurrence,
                                body.source.encounter_ordinal,
                                body.expanded_span.start,
                                body.expanded_span.end
                            )
                        })
                        .unwrap_or_else(|| "<source origin unavailable>".into());
                    return Err(format!(
                        "{origin}: procedure {owner}/{name} ({:?}, occurrence {}) requires unsupported engine ABI: {other:?}", unit.namespace, unit.occurrence
                    ));
                }
            }
        }
        Ok(result)
    }
    pub fn pinned(engine: &'a EngineSnapshot) -> Result<Self, String> {
        const TEMPLATE: &[u8] = include_bytes!("../../../fixtures/native_template.bin");
        if !engine.matches_template(TEMPLATE, 1) {
            return Err("named ABI coverage requires the exact pinned template".into());
        }
        // Pinned OpenDream native-bootstrap name inventory is a conservative
        // exclusion catalog, never a source of ABI layout. OD-only names also
        // remain Unsupported. Fresh applies to explicit formal declarations
        // outside this catalog, under the native language control receipts.
        let catalog: serde_json::Value = serde_json::from_slice(include_bytes!(
            "../../../fixtures/native_template_nativebuiltins_5161687.json"
        ))
        .map_err(|e| e.to_string())?;
        let types = catalog["Types"]
            .as_array()
            .ok_or("native type catalog missing")?;
        let procedures = catalog["Procs"]
            .as_array()
            .ok_or("native proc catalog missing")?;
        let mut native_names = HashSet::new();
        for proc in procedures {
            let name = proc["Name"].as_str().ok_or("native proc name missing")?;
            if name.starts_with('<') {
                continue;
            }
            let owner = match proc["OwningTypeId"].as_u64() {
                Some(id) => types
                    .get(usize::try_from(id).map_err(|_| "native owner overflow")?)
                    .and_then(|ty| ty["Path"].as_str())
                    .ok_or("native owner missing")?,
                None => "/",
            };
            native_names.insert((SymbolId::of(owner), SymbolId::of(name)));
        }
        Ok(Self {
            engine,
            native_names,
        })
    }

    pub fn select(
        &self,
        frontend: &ColdFrontend,
    ) -> Result<BTreeMap<UnitIdentity, BoundarySelection>, String> {
        if frontend.engine.as_ref().map(|status| status.identity) != Some(self.engine.identity()) {
            return Err("ABI coverage belongs to another captured frontend engine".into());
        }
        let units = unit_members(frontend).map_err(|error| error.to_string())?;
        self.select_with_units(frontend, &units)
    }
    fn select_with_units(
        &self,
        frontend: &ColdFrontend,
        units: &BTreeMap<UnitIdentity, MemberId>,
    ) -> Result<BTreeMap<UnitIdentity, BoundarySelection>, String> {
        if frontend.engine.as_ref().map(|status| status.identity) != Some(self.engine.identity()) {
            return Err("ABI coverage belongs to another captured frontend engine".into());
        }
        let tree = &frontend.snapshot.tree;
        let mut selections = BTreeMap::new();
        for (&identity, &member) in units {
            let node = tree
                .member(member)
                .ok_or("current procedure member missing")?;
            if let Some(previous) = node.previous {
                selections.insert(identity, BoundarySelection::SourcePrevious(previous));
                continue;
            }
            let mut cursor = Some(node.owner);
            let mut selected = None;
            let mut unnamed = None;
            let mut known_vm = None;
            while let Some(owner) = cursor {
                let path = tree
                    .type_node(owner)
                    .ok_or("procedure ancestry missing")?
                    .path;
                if self.native_names.contains(&(path, node.name)) && known_vm.is_none() {
                    known_vm = Some(BoundarySelection::KnownVmIntrinsicWithoutLayout {
                        owner: path,
                        name: node.name,
                    });
                }
                if node.definition == DefinitionMode::Declare && known_vm.is_some() {
                    // Native explicit /proc/New() is a duplicate definition,
                    // not an inherited ABI request. Keep catalog collisions
                    // unsupported even when a physical layout is available.
                    break;
                }
                if self
                    .engine
                    .procedure_layout(path, node.name, node.kind)
                    .map_err(|e| format!("engine ABI: {e:?}"))?
                    .is_some()
                {
                    selected = Some(BoundarySelection::CapturedEngine {
                        owner: path,
                        name: node.name,
                        kind: node.kind,
                    });
                    break;
                }
                if known_vm.is_some() {
                    // A nearer known VM name with unavailable ABI must not be
                    // replaced by an ancestor's differently inherited layout.
                    if node.kind == MemberKind::Proc
                        && node.definition != DefinitionMode::Declare
                        && callback_spelling(path, node.name).is_some()
                    {
                        selected = Some(BoundarySelection::CertifiedCallback {
                            owner: path,
                            name: node.name,
                        });
                    }
                    break;
                }
                let unknown = self
                    .engine
                    .procedure_layouts()
                    .iter()
                    .filter(|row| row.owner == path && row.kind == node.kind && row.name.is_none())
                    .map(|row| row.wire_proc)
                    .collect::<Vec<_>>();
                if !unknown.is_empty() && unnamed.is_none() {
                    unnamed = Some(BoundarySelection::UnmappedUnnamed {
                        owner: path,
                        wire_procedures: unknown,
                    });
                }
                cursor = tree.parent(owner);
            }
            selections.insert(
                identity,
                selected
                    .or(known_vm)
                    .or_else(|| {
                        (node.definition == DefinitionMode::Declare)
                            .then_some(BoundarySelection::CertifiedFormalDefault)
                    })
                    .or(unnamed)
                    .unwrap_or(BoundarySelection::UncertifiableAbsence {
                        name: node.name,
                        kind: node.kind,
                    }),
            );
        }
        Ok(selections)
    }
}

// Bare implicit procedures are deliberately not Fresh: the native negative
// control rejects an arbitrary bare /datum/.../name() as undefined. The formal
// /proc/name() control emits flags4/source(0,255) with empty desc/category.

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    struct Source;
    struct IntrinsicSource;
    struct VerbSource;
    impl dm_preprocess::SourceProvider for VerbSource {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/base/verb/coverage_fixture_only()\n    return 1\n/datum/child\n    parent_type = /datum/base\n/datum/child/coverage_fixture_only()\n    return 2\n".into())
        }
    }
    #[test]
    fn inherited_verb_body_keeps_verb_unit_identity_and_source_abi() {
        let engine =
            EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
                .unwrap();
        let seed = engine.frontend_seed();
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("verb_fixture.dme"),
            &VerbSource,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let index = unit_members(&frontend).unwrap();
        assert!(index
            .keys()
            .all(|unit| unit.namespace == crate::lowering::Namespace::Verb));
        let base = index
            .iter()
            .find(|(unit, _)| unit.owner == SymbolId::of("/datum/base"))
            .unwrap();
        let child = index
            .iter()
            .find(|(unit, _)| unit.owner == SymbolId::of("/datum/child"))
            .unwrap();
        let coverage = NamedEngineCoverage::pinned(&engine).unwrap();
        assert_eq!(
            coverage.select(&frontend).unwrap()[child.0],
            BoundarySelection::SourcePrevious(*base.1)
        );
        assert!(coverage.boundaries(&frontend).is_ok());
        assert_eq!(
            coverage.select(&frontend).unwrap(),
            coverage.select_with_units(&frontend, &index).unwrap()
        );
        let legacy = coverage.boundaries(&frontend).unwrap();
        let indexed = coverage.boundaries_with_units(&frontend, &index).unwrap();
        assert_eq!(
            legacy.keys().collect::<Vec<_>>(),
            indexed.keys().collect::<Vec<_>>()
        );
        assert!(legacy
            .values()
            .chain(indexed.values())
            .all(|value| matches!(value, crate::driver_facts::BoundaryAbi::Fresh)));
    }
    impl dm_preprocess::SourceProvider for IntrinsicSource {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/abi_probe/New()\n    return ..()\n/datum/abi_probe/Del()\n    return ..()\n".into())
        }
    }
    #[test]
    fn positive_new_del_receipts_are_known_layouts_not_fresh_absence() {
        let engine =
            EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
                .unwrap();
        let seed = engine.frontend_seed();
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("fixture.dme"),
            &IntrinsicSource,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let policy = NamedEngineCoverage::pinned(&engine).unwrap();
        let boundaries = policy.boundaries(&frontend).unwrap();
        assert_eq!(boundaries.len(), 2);
        assert!(boundaries.values().all(|boundary| matches!(
            boundary,
            crate::driver_facts::BoundaryAbi::CertifiedIntrinsic(_)
                | crate::driver_facts::BoundaryAbi::Engine { .. }
        )));
        assert!(crate::driver_facts::CertifiedIntrinsicAbi::callback(
            &engine,
            SymbolId::of("/datum"),
            SymbolId::of("Other")
        )
        .is_err());
        assert!(crate::driver_facts::CertifiedIntrinsicAbi::callback(
            &engine,
            SymbolId::of("/unproven"),
            SymbolId::of("New")
        )
        .is_err());
        assert_ne!(policy.policy_identity(), engine.template_identity());
    }
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/base\n/datum/base/proc/coverage_fixture_only()\n    return 1\n/datum/child\n    parent_type = /datum/base\n/datum/child/coverage_fixture_only()\n    return 2\n".into())
        }
    }
    #[test]
    fn source_previous_is_exact_and_new_formal_uses_certified_default() {
        let engine =
            EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
                .unwrap();
        let seed = engine.frontend_seed();
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("fixture.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let selections = NamedEngineCoverage::pinned(&engine)
            .unwrap()
            .select(&frontend)
            .unwrap();
        let index = unit_members(&frontend).unwrap();
        let base = index
            .iter()
            .find(|(unit, _)| unit.owner == SymbolId::of("/datum/base"))
            .unwrap();
        let child = index
            .iter()
            .find(|(unit, _)| unit.owner == SymbolId::of("/datum/child"))
            .unwrap();
        assert_eq!(
            selections[child.0],
            BoundarySelection::SourcePrevious(*base.1)
        );
        assert_eq!(
            selections[base.0],
            BoundarySelection::CertifiedFormalDefault
        );
    }
}

#[cfg(test)]
mod callback_control_tests {
    use super::*;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(
                "/turf/callback_probe/Crossed()\n    return\n/client/Northeast()\n    return\n"
                    .into(),
            )
        }
    }
    #[test]
    fn certified_seed_and_abi_share_native_proc_namespace() {
        let engine =
            EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
                .unwrap()
                .with_bootstrap_catalog()
                .unwrap();
        let seed = engine.frontend_seed();
        assert!(seed
            .intrinsics
            .iter()
            .any(|member| member.owner == SymbolId::of("/client")
                && member.name == SymbolId::of("Northeast")
                && member.kind == MemberKind::Proc));
        assert!(!seed
            .intrinsics
            .iter()
            .any(|member| member.owner == SymbolId::of("/client")
                && member.name == SymbolId::of("Northeast")
                && member.kind == MemberKind::Verb));
        let frontend = dm_tree::frontend::build_with_config(
            std::path::Path::new("callbacks.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let coverage = NamedEngineCoverage::pinned(&engine).unwrap();
        let boundaries = coverage.boundaries(&frontend).unwrap();
        assert_eq!(boundaries.len(), 2);
        assert!(boundaries.values().all(|boundary| matches!(
            boundary,
            crate::driver_facts::BoundaryAbi::CertifiedIntrinsic(_)
                | crate::driver_facts::BoundaryAbi::Engine { .. }
        )));
        assert!(unit_members(&frontend)
            .unwrap()
            .keys()
            .all(|unit| unit.namespace == crate::lowering::Namespace::Proc));
    }
    #[test]
    fn finite_callbacks_do_not_certify_other_owner_or_name() {
        assert_eq!(
            callback_spelling(SymbolId::of("/client"), SymbolId::of("AllowUpload")),
            Some("AllowUpload")
        );
        assert_eq!(
            callback_spelling(SymbolId::of("/datum"), SymbolId::of("Topic")),
            Some("Topic")
        );
        assert_eq!(
            callback_spelling(SymbolId::of("/datum"), SymbolId::of("AllowUpload")),
            None
        );
        assert_eq!(
            callback_spelling(SymbolId::of("/client"), SymbolId::of("unknown_callback")),
            None
        );
        assert_eq!(
            callback_spelling(SymbolId::of("/client/child"), SymbolId::of("Topic")),
            None
        );
    }
}
