//! Admission of classified defaults against their exact captured source ledger.
//! Runtime code coverage is checked before any default records are written.
use crate::{
    initializer_policy::{ClassifiedInitializers, DefaultValue},
    symbolic::FrozenBatch,
};
use dm_ir::InitializerTarget;
use dm_link::InitializerIdentity;
use dm_tree::{initializers::InitializerPlan, OccurrenceId};
use std::collections::{BTreeMap, BTreeSet, HashSet};

pub struct CapturedDefault {
    pub origin_kind: dm_tree::initializers::InitializerOriginKind,
    pub source_ordinal: usize,
    pub occurrence: OccurrenceId,
    pub value: DefaultValue,
    pub runtime: bool,
    pub initializer: InitializerIdentity,
}
pub struct DefaultLedger {
    pub tree_identity: u128,
    pub source_identity: u128,
    pub defaults: Vec<CapturedDefault>,
}
pub fn admit(
    plan: &InitializerPlan,
    classified: &ClassifiedInitializers,
    batch: &FrozenBatch,
) -> Result<DefaultLedger, String> {
    admit_coverage(
        plan,
        classified,
        batch
            .initializers
            .iter()
            .map(|unit| (unit.identity, unit.declaration_writes())),
    )
}
pub fn admit_lowered(
    plan: &InitializerPlan,
    classified: &ClassifiedInitializers,
    units: &[crate::initializer_lowering::LoweredInitializerUnit],
) -> Result<DefaultLedger, String> {
    admit_coverage(
        plan,
        classified,
        units.iter().map(|unit| {
            (
                match unit.scope {
                    dm_ir::InitializerScope::Global => InitializerIdentity::Global,
                    dm_ir::InitializerScope::Instance(owner) => InitializerIdentity::Class(owner),
                },
                unit.write_ordinals.as_slice(),
            )
        }),
    )
}
fn admit_coverage<'a>(
    plan: &InitializerPlan,
    classified: &ClassifiedInitializers,
    units: impl IntoIterator<Item = (InitializerIdentity, &'a [usize])>,
) -> Result<DefaultLedger, String> {
    if plan.writes.len() != plan.origins.len() || classified.writes.len() != plan.writes.len() {
        return Err("classified defaults do not cover captured source ledger".into());
    }
    let mut runtime = BTreeMap::new();
    for (identity, ordinals) in units {
        for &ordinal in ordinals {
            if runtime.insert(ordinal, identity).is_some() {
                return Err("runtime initializer write is covered more than once".into());
            }
        }
    }
    let mut seen = BTreeSet::new();
    let mut occurrences = HashSet::new();
    let mut statics = HashSet::new();
    let mut defaults = Vec::with_capacity(classified.writes.len());
    for fact in &classified.writes {
        let ordinal = fact.source_ordinal;
        if !seen.insert(ordinal) || plan.writes.get(ordinal) != Some(&fact.write) {
            return Err("classified default differs from captured authored write".into());
        }
        let origin = plan
            .origins
            .get(ordinal)
            .ok_or("default source origin absent")?;
        let current = plan
            .source
            .occurrences
            .get(origin.occurrence)
            .ok_or("default occurrence absent")?;
        if current.provenance != origin.provenance {
            return Err("default source occurrence is stale or duplicated".into());
        }
        match &origin.kind {
            dm_tree::initializers::InitializerOriginKind::Declaration(member) => {
                if current.target != dm_tree::Target::Member(*member)
                    || !occurrences.insert(origin.occurrence)
                {
                    return Err("default declaration occurrence is stale or duplicated".into());
                }
            }
            dm_tree::initializers::InitializerOriginKind::ProcedureStatic {
                identity,
                expanded_span,
            } => {
                let dm_tree::Target::Member(member) = current.target else {
                    return Err("procedure static is not anchored to a procedure occurrence".into());
                };
                let tree = &plan.source.tree;
                let node = tree.member(member).ok_or("static procedure missing")?;
                let owner = tree
                    .type_node(node.owner)
                    .ok_or("static procedure owner missing")?
                    .path;
                let verb = node.kind == dm_tree::MemberKind::Verb;
                let occurrence = tree
                    .override_chain(member)
                    .iter()
                    .filter(|entry| {
                        tree.member(**entry).is_some_and(|entry| {
                            entry.owner == node.owner
                                && entry.name == node.name
                                && entry.kind == node.kind
                        })
                    })
                    .count()
                    .checked_sub(1)
                    .ok_or("static procedure chain empty")?;
                if !matches!(
                    node.kind,
                    dm_tree::MemberKind::Proc | dm_tree::MemberKind::Verb
                ) || identity.procedure.owner != owner
                    || identity.procedure.name != node.name
                    || identity.procedure.verb != verb
                    || usize::try_from(identity.procedure.occurrence).ok() != Some(occurrence)
                    || expanded_span.end < expanded_span.start
                    || fact.write.target != InitializerTarget::ProcedureStatic(*identity)
                    || fact.write.lexical_procedure != Some(identity.procedure)
                    || !statics.insert(*identity)
                {
                    return Err("procedure static source identity is stale or duplicated".into());
                }
            }
        }
        let expected = match fact.write.target {
            InitializerTarget::Shared { .. } => InitializerIdentity::Global,
            InitializerTarget::ProcedureStatic(_) => InitializerIdentity::Global,
            InitializerTarget::Instance { receiver_owner, .. } => {
                InitializerIdentity::Class(receiver_owner)
            }
        };
        if fact.phase.is_some() {
            if runtime.remove(&ordinal) != Some(expected) || fact.runtime_value.is_none() {
                return Err(
                    "runtime default lacks matching executable initializer coverage".into(),
                );
            }
        } else if runtime.contains_key(&ordinal) || fact.runtime_value.is_some() {
            return Err("scalar default has unexpected runtime initializer coverage".into());
        }
        defaults.push(CapturedDefault {
            origin_kind: origin.kind.clone(),
            source_ordinal: ordinal,
            occurrence: origin.occurrence,
            value: fact.default.clone(),
            runtime: fact.phase.is_some(),
            initializer: expected,
        });
    }
    if !runtime.is_empty() {
        return Err("initializer artifact covers unknown source writes".into());
    }
    defaults.sort_by_key(|value| value.source_ordinal);
    Ok(DefaultLedger {
        tree_identity: plan.source.tree.identity(),
        source_identity: plan.identity,
        defaults,
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/var/x = 3\n".into())
        }
    }
    struct Evaluator(bool);
    impl crate::initializer_policy::CapturedInitializerEvaluator for Evaluator {
        fn evaluate(
            &self,
            _: dm_ir::SymbolId,
            _: &dm_ir::SymbolicExpression,
        ) -> Result<crate::initializer_policy::Evaluation, String> {
            Ok(if self.0 {
                crate::initializer_policy::Evaluation::Runtime
            } else {
                crate::initializer_policy::Evaluation::Scalar(dm_ir::SemanticValue::NumberBits(
                    3f32.to_bits(),
                ))
            })
        }
    }
    #[test]
    fn actual_source_defaults_require_exact_identity_and_runtime_coverage() {
        let frontend = dm_tree::frontend::build(
            std::path::Path::new("project.dme"),
            &Source,
            &Default::default(),
            1,
        )
        .unwrap();
        let order: Vec<_> = (0..frontend.snapshot.occurrences.source_order().len())
            .map(|index| dm_tree::OccurrenceId(u32::try_from(index).unwrap()))
            .collect();
        let plan = dm_tree::initializers::plan(&frontend.snapshot, &order).unwrap();
        let batch = FrozenBatch {
            units: vec![],
            helpers: vec![],
            initializers: vec![],
            tables: dm_link::LinkTables::build(Default::default()).unwrap(),
        };
        let mut facts = crate::initializer_policy::classify(
            &plan.writes,
            frontend.snapshot.tree.symbols(),
            &Evaluator(false),
        )
        .unwrap();
        let ledger = admit(&plan, &facts, &batch).unwrap();
        assert_eq!(ledger.defaults.len(), 1);
        assert_eq!(ledger.defaults[0].occurrence, plan.origins[0].occurrence);
        facts.writes[0].source_ordinal = usize::MAX;
        assert!(admit(&plan, &facts, &batch).is_err());
        let runtime = crate::initializer_policy::classify(
            &plan.writes,
            frontend.snapshot.tree.symbols(),
            &Evaluator(true),
        )
        .unwrap();
        assert!(admit(&plan, &runtime, &batch).is_err());
    }
}
