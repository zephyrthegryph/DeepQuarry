//! Compact disk records retain executable words, never a live source issuer.
use crate::lowering_memo::{ReplayDecline, ResolverRead};
use dm_ir::{ProcedureIdentity, ReadDomain, ResolveQuery, Resolver, SymbolId};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::{borrow::Cow, sync::Arc};
// Includes the certified src-cache operand encoding policy.
pub(crate) const SCHEMA: u32 = 0x0206_0010;
const MAX_RECORD: usize = 8 * 1024 * 1024;
const MAX_ITEMS: usize = 65536;
#[cfg(test)]
#[path = "lowering_memo_compact_tests.rs"]
mod tests;
pub(crate) fn eligible(
    unit: &crate::lowering::LoweredUnit,
    bindings: crate::lowering::DiskReplayBindings<'_>,
) -> bool {
    if unit.abi.is_none() || unit.selected_references.is_some() {
        return false;
    }
    if unit.code.instances.iter().any(|(alias, value)| {
        *alias != value.alias
            || *alias == value.runtime_type
            || unit
                .code
                .modified_instances
                .contains_key(&dm_ir::SymRef::Instance(*alias))
    }) {
        return false;
    }
    if unit.source_helpers.iter().any(|h| {
        !h.code.modified_instances.is_empty()
            || h.code.instances.iter().any(|(alias, value)| {
                *alias != value.alias
                    || *alias == value.runtime_type
                    || unit
                        .code
                        .modified_instances
                        .contains_key(&dm_ir::SymRef::Instance(*alias))
            })
    }) {
        return false;
    }
    if unit
        .code
        .modified_instances
        .iter()
        .any(|(reference, value)| {
            crate::modified_initializers::prepare_seed(*reference, value, &unit.debug_origins)
                .ok()
                .and_then(|seed| seed.source_recipe(unit.origin.expanded_span))
                .is_none()
        })
    {
        return false;
    }
    let mut selected_instances = std::collections::BTreeSet::new();
    let mut licensed = std::collections::BTreeSet::new();
    licensed.insert(dm_ir::SymRef::BuiltinGlobalVars);
    licensed.extend(
        unit.code
            .procedure
            .strings
            .iter()
            .map(|s| dm_ir::SymRef::String(s.id)),
    );
    licensed.extend(
        unit.code
            .slots
            .values()
            .map(|s| dm_ir::SymRef::VariableSlot(s.symbol)),
    );
    let mut valid = true;
    unit.code.procedure.code.for_each_reference(|reference| {
        valid &= match reference {
            dm_ir::SymRef::SourceFile(at) | dm_ir::SymRef::SourceLine(at) => {
                (at as usize) < unit.debug_origins.entries.len()
            }
            dm_ir::SymRef::Instance(_) => {
                if unit.code.modified_instances.contains_key(&reference) {
                    selected_instances.insert(reference);
                    true
                } else {
                    bindings.source.contains(&reference)
                        || bindings.external.references.contains(&reference)
                }
            }
            _ => {
                licensed.contains(&reference)
                    || bindings.source.contains(&reference)
                    || bindings.external.references.contains(&reference)
            }
        };
    });
    valid
        && unit
            .code
            .modified_instances
            .keys()
            .all(|r| selected_instances.contains(r))
        && unit.source_helpers.iter().all(|helper| {
            let mut licensed = std::collections::BTreeSet::from([dm_ir::SymRef::BuiltinGlobalVars]);
            licensed.extend(
                helper
                    .code
                    .procedure
                    .strings
                    .iter()
                    .map(|s| dm_ir::SymRef::String(s.id)),
            );
            licensed.extend(
                helper
                    .code
                    .slots
                    .values()
                    .map(|s| dm_ir::SymRef::VariableSlot(s.symbol)),
            );
            let mut valid = true;
            helper.code.procedure.code.for_each_reference(|reference| {
                valid &= match reference {
                    dm_ir::SymRef::SourceFile(at) | dm_ir::SymRef::SourceLine(at) => {
                        (at as usize) < helper.debug_origins.entries.len()
                    }
                    dm_ir::SymRef::Instance(alias) => {
                        helper.code.instances.contains_key(&alias)
                            && (bindings.source.contains(&reference)
                                || bindings.external.references.contains(&reference))
                    }
                    _ => {
                        licensed.contains(&reference)
                            || bindings.source.contains(&reference)
                            || bindings.external.references.contains(&reference)
                    }
                }
            });
            valid
        })
}

pub(crate) struct BoundedVec<T>(pub(crate) Vec<T>);
impl<T: Serialize> Serialize for BoundedVec<T> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        if self.0.len() > MAX_ITEMS {
            return Err(serde::ser::Error::custom("compact collection exceeds cap"));
        }
        self.0.serialize(serializer)
    }
}
impl<'de, T: Deserialize<'de>> Deserialize<'de> for BoundedVec<T> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct Visitor<T>(std::marker::PhantomData<T>);
        impl<'de, T: Deserialize<'de>> serde::de::Visitor<'de> for Visitor<T> {
            type Value = BoundedVec<T>;
            fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("bounded compact sequence")
            }
            fn visit_seq<A: serde::de::SeqAccess<'de>>(
                self,
                mut seq: A,
            ) -> Result<Self::Value, A::Error> {
                let hint = seq.size_hint().unwrap_or(0);
                if hint > MAX_ITEMS {
                    return Err(serde::de::Error::custom("compact collection exceeds cap"));
                }
                let mut values = Vec::with_capacity(hint.min(4096));
                while let Some(value) = seq.next_element()? {
                    if values.len() == MAX_ITEMS {
                        return Err(serde::de::Error::custom("compact collection exceeds cap"));
                    }
                    values.push(value);
                }
                Ok(BoundedVec(values))
            }
        }
        deserializer.deserialize_seq(Visitor(std::marker::PhantomData))
    }
}
use crate::lowering_memo_wire::read_wire::ReadWire;
#[derive(Serialize, Deserialize)]
pub(crate) struct Payload<'a> {
    #[serde(borrow)]
    pub(crate) key: Cow<'a, [u8]>,
    pub(crate) identity: ProcedureIdentity,
    #[serde(borrow)]
    pub(crate) reads: BoundedVec<ReadWire<'a>>,
    pub(crate) versions: BoundedVec<(ReadDomain, u128)>,
    pub(crate) debug: BoundedVec<crate::debug_sources::RelativeDebugAnchor>,
    pub(crate) required_types: BoundedVec<SymbolId>,
    #[serde(borrow)]
    abi: Cow<'a, [u8]>,
    #[serde(borrow)]
    executable: crate::symbolic::procedure_artifact::disk::Encoded<'a>,
    #[serde(borrow)]
    helpers: BoundedVec<crate::symbolic::procedure_artifact::disk::HelperWire<'a>>,
    #[serde(borrow)]
    recipes: BoundedVec<crate::modified_initializers::RecipeWire<'a>>,
    instances: BoundedVec<(SymbolId, SymbolId)>,
}
pub(crate) fn encode<'a>(
    key: &[u8],
    reads: impl IntoIterator<Item = &'a ResolverRead>,
    versions: &[(ReadDomain, u128)],
    value: &crate::symbolic::PreparedContribution,
    debug: &[crate::debug_sources::RelativeDebugAnchor],
) -> Option<Vec<u8>> {
    let recipes = value.modified_recipes()?;
    let artifact = value.shared_artifact();
    let requests = artifact.disk_type_requests_with_modified(
        &recipes
            .iter()
            .map(|r| r.disk_evidence())
            .collect::<Vec<_>>(),
    );
    if requests != value.required_types() {
        return None;
    }
    let executable = artifact.disk_encoded()?;
    let identity = value.identity();
    let payload = Payload {
        key: Cow::Borrowed(key),
        identity: ProcedureIdentity {
            owner: identity.owner,
            name: identity.name,
            verb: identity.namespace == crate::lowering::Namespace::Verb,
            occurrence: identity.occurrence,
        },
        reads: BoundedVec(
            reads
                .into_iter()
                .map(|r| ReadWire {
                    query: r.query,
                    answer: Cow::Owned(r.answer.canonical_bytes()),
                })
                .collect(),
        ),
        versions: BoundedVec(
            versions
                .iter()
                .copied()
                .filter(|(d, _)| d.persistent_version())
                .collect(),
        ),
        debug: BoundedVec(debug.to_vec()),
        required_types: BoundedVec(value.required_types().to_vec()),
        abi: Cow::Owned(artifact.disk_abi()?),
        executable,
        helpers: BoundedVec(artifact.disk_helpers()?),
        recipes: BoundedVec(recipes.iter().map(|r| r.disk_evidence()).collect()),
        instances: BoundedVec(artifact.disk_instances().to_vec()),
    };
    dm_wire::encode_bounded(SCHEMA, &payload, MAX_RECORD).ok()
}
pub(crate) fn decode(bytes: &[u8]) -> Result<Payload<'_>, String> {
    let value: Payload<'_> = dm_wire::decode_borrowed(SCHEMA, bytes, MAX_RECORD)?;
    crate::lowering_memo_wire::validate_versions(&value.versions.0)?;
    if !valid_plain_instances(&value.instances.0, &value.reads.0)
        || value
            .helpers
            .0
            .iter()
            .any(|helper| !valid_plain_instances(helper.instances(), &value.reads.0))
    {
        return Err("malformed or unobserved plain instance tuple".into());
    }
    let mut references = std::collections::BTreeSet::new();
    if value
        .recipes
        .0
        .iter()
        .any(|recipe| !recipe.valid() || !references.insert(recipe.reference()))
    {
        return Err("malformed/duplicate compact modifier recipe".into());
    }
    if value
        .instances
        .0
        .iter()
        .chain(value.helpers.0.iter().flat_map(|helper| helper.instances()))
        .any(|(alias, _)| references.contains(&dm_ir::SymRef::Instance(*alias)))
    {
        return Err("plain and modified instance rosters overlap".into());
    }
    Ok(value)
}
fn valid_plain_instances(instances: &[(SymbolId, SymbolId)], reads: &[ReadWire<'_>]) -> bool {
    !instances.windows(2).any(|pair| pair[0].0 >= pair[1].0)
        && instances.iter().all(|(alias, runtime)| {
            alias != runtime
                && reads.iter().any(|read| {
                    read.query == ResolveQuery::RuntimeType(*alias)
                        && read.answer.as_ref()
                            == dm_ir::ResolvedMeaning::Symbol(*runtime).canonical_bytes()
                })
        })
}
impl Payload<'_> {
    pub(crate) fn verification_reads(&self) -> Vec<(ResolveQuery, Vec<u8>)> {
        self.reads
            .0
            .iter()
            .map(|r| (r.query, r.answer.to_vec()))
            .collect()
    }
    pub(crate) fn changed_read<R: Resolver>(&self, host: &R) -> Option<ResolveQuery> {
        let matching = crate::lowering_memo::matching_domains(&self.versions.0, host);
        self.reads.0.iter().find_map(|r| {
            (!matching.contains(&r.query.domain())
                && host.resolve(r.query).canonical_bytes() != r.answer.as_ref())
            .then_some(r.query)
        })
    }
    pub(crate) fn promotion(&self) -> crate::lowering_memo_wire::ResidentPromotion {
        crate::lowering_memo_wire::ResidentPromotion {
            queries: self.reads.0.iter().map(|r| r.query).collect(),
            versions: self.versions.0.clone(),
            relative_debug: self.debug.0.clone(),
        }
    }
    pub(crate) fn rebind(
        self,
        context: crate::lowering_memo_wire::ProcedureReplayContext<'_>,
        prepared: &crate::procedure_policy::PreparedUnit,
    ) -> Result<crate::symbolic::PreparedContribution, ReplayDecline> {
        let bindings = context.bindings.ok_or(ReplayDecline::ExecutableIssuer)?;
        prepared
            .require_production_abi()
            .map_err(|_| ReplayDecline::PreparedAbi)?;
        let abi = prepared.abi.as_ref().ok_or(ReplayDecline::PreparedAbi)?;
        if self.abi.as_ref() != abi.canonical_bytes() {
            return Err(ReplayDecline::PreparedAbi);
        }
        let debug =
            crate::lowering_memo::rebase_debug(context.frontend, context.body, &self.debug.0)
                .ok_or(ReplayDecline::DebugOrigins)?;
        let modified = if self.recipes.0.is_empty() {
            Vec::new()
        } else {
            context
                .modified
                .ok_or(ReplayDecline::ExecutableIssuer)?
                .reissue(&self.recipes.0, &debug, prepared)
                .ok_or(ReplayDecline::ExecutableIssuer)?
        };
        let instances = self.recipes.0.iter().map(|r| r.reference()).collect();
        let mut artifact = self
            .executable
            .restore(
                context.frontend,
                context.body,
                prepared,
                bindings,
                debug.entries.len(),
                &instances,
                &self.instances.0,
            )
            .ok_or(ReplayDecline::ExecutableIssuer)?;
        crate::symbolic::ReusableProcedureArtifact::disk_bind_helpers(
            &mut artifact,
            self.helpers.0,
            context.frontend,
            context.body,
            prepared,
            bindings,
        )
        .ok_or(ReplayDecline::ExecutableIssuer)?;
        let requests = artifact.disk_type_requests_with_modified(&self.recipes.0);
        if requests != self.required_types.0
            || requests
                .iter()
                .any(|id| context.frontend.snapshot.tree.symbols().text(*id).is_none())
        {
            return Err(ReplayDecline::ExecutableIssuer);
        }
        crate::symbolic::PreparedContribution::rebind_with_modified(
            &artifact,
            context.frontend,
            context.body,
            prepared,
            debug,
            self.required_types.0.into(),
            modified,
            self.recipes
                .0
                .iter()
                .map(|recipe| recipe.resident_recipe())
                .collect::<Option<Vec<_>>>()
                .map(Arc::from),
        )
        .ok_or(ReplayDecline::ExecutableIssuer)
    }
}

pub(crate) trait ModifiedIssuer {
    fn reissue(
        &self,
        recipes: &[crate::modified_initializers::RecipeWire<'_>],
        debug: &crate::debug_sources::DebugOrigins,
        prepared: &crate::procedure_policy::PreparedUnit,
    ) -> Option<Vec<crate::modified_initializers::PreparedSeed>>;
}
pub(crate) struct CurrentModifiedIssuer<'a, 'f, 'p, R: Resolver> {
    pub frontend: &'a dm_tree::frontend::ColdFrontend,
    pub body: &'a dm_tree::frontend::BodyOccurrence,
    pub bodies: &'a dm_tree::frontend::BodyArena<'f>,
    pub host: &'a R,
    pub parsed: Option<&'a dm_tree::frontend::ParsedBody<'p>>,
}
impl<R: Resolver> ModifiedIssuer for CurrentModifiedIssuer<'_, '_, '_, R> {
    fn reissue(
        &self,
        recipes: &[crate::modified_initializers::RecipeWire<'_>],
        debug: &crate::debug_sources::DebugOrigins,
        prepared: &crate::procedure_policy::PreparedUnit,
    ) -> Option<Vec<crate::modified_initializers::PreparedSeed>> {
        let owner = crate::lowering::source_unit_identity(self.frontend, self.body)
            .ok()?
            .identity
            .owner;
        let reissue = |parsed: &dm_tree::frontend::ParsedBody<'_>| {
            recipes
                .iter()
                .map(|recipe| {
                    recipe.reissue(
                        parsed,
                        self.frontend,
                        self.host,
                        self.frontend.snapshot.tree.symbols(),
                        debug,
                        prepared.inputs.resource_search_context,
                        owner,
                    )
                })
                .collect::<Option<Vec<_>>>()
        };
        if let Some(parsed) = self.parsed {
            reissue(parsed)
        } else {
            self.bodies.with_parsed(self.body, reissue).ok().flatten()
        }
    }
}
