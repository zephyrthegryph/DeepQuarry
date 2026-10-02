//! Invocation-local indexes over a frozen shared declaration snapshot.
//! They are accelerators, never portable memo identity or semantic result data.
use crate::SharedLowerBindings;
use std::collections::HashMap;
use std::sync::Arc;

/// A prepared name oracle for the computed-receiver class-global shortcut.
///
/// The strong source guard keeps the allocation alive and prevents safe in-place
/// mutation. `Arc::make_mut` creates another allocation; replacing or removing
/// shared bindings also stops index use. Public binding maps remain mutable.
#[derive(Clone, Default)]
pub struct PreparedMemberGlobals {
    inner: Option<Arc<MemberGlobalIndex>>,
}

struct MemberGlobalIndex {
    source: Arc<SharedLowerBindings>,
    names: HashMap<String, MemberGlobalEntry>,
}

enum MemberGlobalEntry {
    Unique(String),
    Ambiguous,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum MemberGlobalResolution<'a> {
    Unique(&'a str),
    Ambiguous,
    Absent,
}

impl PreparedMemberGlobals {
    /// Prepare once after the shared declaration snapshot is frozen, then clone
    /// this cheap handle into procedure binding frames. Work is O(64F + G) for
    /// F declared field entries and G direct global entries, with O(N) retained
    /// names; each guarded lookup is expected O(1).
    pub fn new(source: Arc<SharedLowerBindings>) -> Self {
        let mut names = HashMap::new();
        for (owner, fields) in &source.known_member_fields {
            for name in fields {
                if names.contains_key(name) {
                    // A blocking instance declaration is final for this name.
                    continue;
                }
                // Match the original oracle: an instance field with no reachable
                // class-global slot blocks this name, including untyped fields.
                if member_global(&source, owner, name).is_none() {
                    names.insert(name.clone(), MemberGlobalEntry::Ambiguous);
                }
            }
        }
        for members in source.member_globals.values() {
            for (name, symbol) in members {
                let entry = names
                    .entry(name.clone())
                    .or_insert_with(|| MemberGlobalEntry::Unique(symbol.clone()));
                if matches!(&*entry, MemberGlobalEntry::Unique(previous) if previous != symbol) {
                    *entry = MemberGlobalEntry::Ambiguous;
                }
            }
        }
        Self {
            inner: Some(Arc::new(MemberGlobalIndex { source, names })),
        }
    }

    /// `None` means no valid accelerator: the caller must use its raw oracle.
    /// `Some(Absent)` is a valid negative lookup in this exact frozen snapshot.
    pub(crate) fn resolve<'a>(
        &'a self,
        source: &Arc<SharedLowerBindings>,
        name: &str,
    ) -> Option<MemberGlobalResolution<'a>> {
        let index = self.inner.as_ref()?;
        if !Arc::ptr_eq(&index.source, source) {
            return None;
        }
        Some(match index.names.get(name) {
            Some(MemberGlobalEntry::Unique(symbol)) => MemberGlobalResolution::Unique(symbol),
            Some(MemberGlobalEntry::Ambiguous) => MemberGlobalResolution::Ambiguous,
            None => MemberGlobalResolution::Absent,
        })
    }
}

impl std::fmt::Debug for PreparedMemberGlobals {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PreparedMemberGlobals")
            .field(
                "names",
                &self.inner.as_ref().map_or(0, |index| index.names.len()),
            )
            .finish()
    }
}

// Preparation is not a semantic binding field. Adding/removing an accelerator
// must not make equal LowerBindings inputs unequal or invalidate Salsa results.
impl PartialEq for PreparedMemberGlobals {
    fn eq(&self, _other: &Self) -> bool {
        true
    }
}
impl Eq for PreparedMemberGlobals {}

/// Shared raw member resolution used by both normal lookup and index creation.
/// Modified instances, inherited aliases and the depth bound retain their exact
/// existing meaning. This function does not observe dependencies itself.
pub(crate) fn member_global<'a>(
    source: &'a SharedLowerBindings,
    owner: &str,
    name: &str,
) -> Option<&'a str> {
    let mut path = source
        .modified_instances
        .get(owner)
        .map(String::as_str)
        .unwrap_or(owner);
    for _ in 0..64 {
        if let Some(symbol) = source
            .member_globals
            .get(path)
            .and_then(|members| members.get(name))
        {
            return Some(symbol);
        }
        path = source.parent_types.get(path)?;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{BindingFact, FactValue, LowerBindings};
    use std::collections::BTreeSet;

    fn snapshot() -> Arc<SharedLowerBindings> {
        Arc::new(SharedLowerBindings {
            member_globals: ([
                (
                    "/datum/base".into(),
                    ([
                        ("inherited".into(), "inherited_slot".into()),
                        ("same_alias".into(), "alias_slot".into()),
                        ("different_alias".into(), "first_slot".into()),
                        ("collision".into(), "collision_slot".into()),
                    ]).into_iter().collect(),
                ),
                (
                    "/datum/other".into(),
                    ([
                        ("same_alias".into(), "alias_slot".into()),
                        ("different_alias".into(), "second_slot".into()),
                    ]).into_iter().collect(),
                ),
            ]).into_iter().collect(),
            known_member_fields: ([
                ("/datum/child".into(), (["inherited".into()]).into_iter().collect()),
                (
                    "/datum/modified".into(),
                    (["inherited".into()]).into_iter().collect(),
                ),
                (
                    "/datum/instance".into(),
                    (["collision".into(), "instance_only".into()]).into_iter().collect(),
                ),
            ]).into_iter().collect(),
            parent_types: ([("/datum/child".into(), "/datum/base".into())]).into_iter().collect(),
            modified_instances: HashMap::from([("/datum/modified".into(), "/datum/child".into())]),
            ..Default::default()
        })
    }

    fn fact(bindings: &LowerBindings, name: &str) -> FactValue {
        bindings.binding_fact(&BindingFact::UniqueMemberGlobal(name.into()))
    }

    #[test]
    fn prepared_member_globals_match_inheritance_alias_and_ambiguity_oracle() {
        let shared = snapshot();
        let raw = LowerBindings {
            shared: Some(Arc::clone(&shared)),
            ..Default::default()
        };
        let prepared = LowerBindings {
            shared: Some(Arc::clone(&shared)),
            prepared_member_globals: PreparedMemberGlobals::new(Arc::clone(&shared)),
            ..Default::default()
        };
        for name in [
            "inherited",
            "same_alias",
            "different_alias",
            "collision",
            "instance_only",
            "missing",
        ] {
            assert_eq!(fact(&prepared, name), fact(&raw, name), "{name}");
        }
        assert_eq!(
            fact(&prepared, "inherited"),
            FactValue::Text("inherited_slot".into())
        );
        assert_eq!(
            fact(&prepared, "same_alias"),
            FactValue::Text("alias_slot".into())
        );
        for name in ["different_alias", "collision", "instance_only", "missing"] {
            assert_eq!(fact(&prepared, name), FactValue::Absent, "{name}");
        }
        assert_eq!(
            prepared
                .prepared_member_globals
                .resolve(&shared, "collision"),
            Some(MemberGlobalResolution::Ambiguous)
        );
        assert_eq!(
            prepared.prepared_member_globals.resolve(&shared, "missing"),
            Some(MemberGlobalResolution::Absent)
        );
    }

    #[test]
    fn prepared_member_globals_make_mut_and_parent_changes_cannot_reuse_stale_values() {
        let shared = snapshot();
        let mut bindings = LowerBindings {
            prepared_member_globals: PreparedMemberGlobals::new(Arc::clone(&shared)),
            shared: Some(shared),
            ..Default::default()
        };
        assert!(
            Arc::get_mut(bindings.shared.as_mut().unwrap()).is_none(),
            "strong guard must freeze its snapshot"
        );
        assert_eq!(
            fact(&bindings, "inherited"),
            FactValue::Text("inherited_slot".into())
        );
        Arc::make_mut(bindings.shared.as_mut().unwrap())
            .parent_types
            .remove("/datum/child");
        assert!(bindings
            .prepared_member_globals
            .resolve(bindings.shared.as_ref().unwrap(), "inherited")
            .is_none());
        assert_eq!(fact(&bindings, "inherited"), FactValue::Absent);
        Arc::make_mut(bindings.shared.as_mut().unwrap())
            .parent_types
            .insert("/datum/child".into(), "/datum/base".into());
        assert_eq!(
            fact(&bindings, "inherited"),
            FactValue::Text("inherited_slot".into())
        );
        Arc::make_mut(bindings.shared.as_mut().unwrap())
            .known_member_fields
            .insert(
                "/datum/new_instance".into(),
                (["inherited".into()]).into_iter().collect(),
            );
        assert_eq!(fact(&bindings, "inherited"), FactValue::Absent);
    }

    #[test]
    fn prepared_member_globals_replacement_and_removal_fall_back_to_current_snapshot() {
        let shared = snapshot();
        let mut bindings = LowerBindings {
            prepared_member_globals: PreparedMemberGlobals::new(Arc::clone(&shared)),
            shared: Some(shared),
            ..Default::default()
        };
        bindings.shared = Some(Arc::new(SharedLowerBindings {
            member_globals: ([(
                "/datum/replacement".into(),
                ([("inherited".into(), "replacement_slot".into())]).into_iter().collect(),
            )]).into_iter().collect(),
            ..Default::default()
        }));
        assert_eq!(
            fact(&bindings, "inherited"),
            FactValue::Text("replacement_slot".into())
        );
        bindings.shared = None;
        assert_eq!(fact(&bindings, "inherited"), FactValue::Absent);
    }

    #[test]
    fn prepared_member_globals_clone_equality_and_serde_keep_cache_out_of_identity() {
        let shared = snapshot();
        let raw = LowerBindings {
            shared: Some(Arc::clone(&shared)),
            ..Default::default()
        };
        let bindings = LowerBindings {
            prepared_member_globals: PreparedMemberGlobals::new(Arc::clone(&shared)),
            shared: Some(Arc::clone(&shared)),
            ..Default::default()
        };
        assert_eq!(
            bindings, raw,
            "preparation must not change semantic equality"
        );
        let cloned = bindings.clone();
        assert_eq!(fact(&cloned, "inherited"), fact(&bindings, "inherited"));
        assert_eq!(
            serde_json::to_vec(&bindings).unwrap(),
            serde_json::to_vec(&raw).unwrap()
        );
        let mut restored: LowerBindings =
            serde_json::from_slice(&serde_json::to_vec(&bindings).unwrap()).unwrap();
        assert!(restored.shared.is_none());
        assert!(restored.prepared_member_globals.inner.is_none());
        assert_eq!(fact(&restored, "inherited"), FactValue::Absent);
        restored.shared = Some(Arc::new(
            serde_json::from_slice(&serde_json::to_vec(shared.as_ref()).unwrap()).unwrap(),
        ));
        assert_eq!(fact(&restored, "inherited"), fact(&bindings, "inherited"));
    }

    #[test]
    fn prepared_member_globals_preserve_parent_cycle_and_depth_bound() {
        let mut shared = SharedLowerBindings::default();
        shared.member_globals.insert(
            "/datum/base".into(),
            ([("bounded".into(), "bounded_slot".into())]).into_iter().collect(),
        );
        shared
            .known_member_fields
            .insert("/datum/cycle".into(), (["bounded".into()]).into_iter().collect());
        shared
            .parent_types
            .insert("/datum/cycle".into(), "/datum/cycle".into());
        for index in 0..64 {
            shared.parent_types.insert(
                format!("/datum/level{index}"),
                if index == 63 {
                    "/datum/base".into()
                } else {
                    format!("/datum/level{}", index + 1)
                },
            );
        }
        shared
            .known_member_fields
            .insert("/datum/level0".into(), (["bounded".into()]).into_iter().collect());
        let shared = Arc::new(shared);
        let bindings = LowerBindings {
            shared: Some(Arc::clone(&shared)),
            prepared_member_globals: PreparedMemberGlobals::new(Arc::clone(&shared)),
            ..Default::default()
        };
        assert_eq!(fact(&bindings, "bounded"), FactValue::Absent);
        assert_eq!(member_global(&shared, "/datum/level0", "bounded"), None);
        assert_eq!(
            member_global(&shared, "/datum/level1", "bounded"),
            Some("bounded_slot")
        );
    }
}
