//! Coordinator admission adopts exact shared authored metadata into current leaves.
use super::*;
use crate::declaration_contributions::KeyedDeclarations;
pub(super) struct AdmittedAuthored {
    index: KeyedDeclarations,
    pub(super) leaves: Vec<Arc<Vec<crate::Skeleton>>>,
}

#[cfg(test)]
mod tests {
    use super::*;
    fn leaf(text: &str) -> Arc<Vec<crate::Skeleton>> {
        let parsed = dm_syntax::parse_declaration_skeleton(text);
        let ast = AstFile {
            items: parsed.items,
            diagnostics: parsed.diagnostics,
            tokens: Vec::new(),
        };
        Arc::new(
            crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0)
                .unwrap()
                .skeletons,
        )
    }
    fn admit(state: &RetainedDeclarations, text: &str) {
        let parsed = dm_syntax::parse_declaration_skeleton(text);
        let ast = AstFile {
            items: parsed.items,
            diagnostics: parsed.diagnostics,
            tokens: Vec::new(),
        };
        let mut facts = crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0).unwrap();
        let ledger =
            crate::allocation_ledger::capture(&ast.items, "/", &mut facts.symbols).unwrap();
        let mut current = state
            .capture(
                &RetainedDeclarations::key(text),
                text,
                0,
                ast.items,
                facts,
                ledger,
            )
            .unwrap();
        state.adopt_authored(std::iter::once(&mut current)).unwrap();
    }
    #[test]
    fn admitted_body_edit_keeps_index_roster_and_default_edit_refreshes_owner() {
        let state = RetainedDeclarations::with_shared_authored(Arc::new(
            crate::SharedNormalizedDeclarations::default(),
        ));
        admit(
            &state,
            "/obj/base\n    var/count=1\n/proc/probe()\n    return 1\n",
        );
        let previous = state
            .authored_current()
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .index
            .clone();
        admit(
            &state,
            "/obj/base\n    var/count=1\n/proc/probe()\n    return 2\n",
        );
        let current = state
            .authored_current()
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .index
            .clone();
        assert!(Arc::ptr_eq(
            previous.shared_roster(),
            current.shared_roster()
        ));
        for (owner, value) in previous.owners() {
            assert!(Arc::ptr_eq(value, current.owner(*owner).unwrap()));
        }
        admit(
            &state,
            "/obj/base\n    var/count=2\n/proc/probe()\n    return 2\n",
        );
        let changed = state
            .authored_current()
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .index
            .clone();
        assert!(!previous.skeletons().eq(changed.skeletons()));
        let expected = state
            .authored_current()
            .lock()
            .unwrap()
            .as_ref()
            .unwrap()
            .leaves
            .as_ptr();
        let mut visits = 0;
        state.visit_storage(|view| {
            if let DeclarationStorageView::AuthoredLeafRoster { leaves } = view {
                assert_eq!(leaves.as_ptr(), expected);
                assert_eq!(leaves.len(), 1);
                visits += 1;
            }
        });
        assert_eq!(visits, 1);
    }
    #[test]
    fn leaf_receipt_accepts_exact_body_changes_but_declines_defaults_and_structure() {
        let original = leaf("/obj/base\n    var/count=1\n/proc/probe()\n    return 1\n");
        let body = leaf("/obj/base\n    var/count=1\n/proc/probe()\n    return 2\n");
        assert!(same_leaves(
            &[Arc::clone(&original)],
            &[Arc::clone(&original)]
        ));
        assert!(same_leaves(&[Arc::clone(&original)], &[body]));
        let default = leaf("/obj/base\n    var/count=2\n/proc/probe()\n    return 1\n");
        assert!(!same_leaves(&[Arc::clone(&original)], &[default]));
        let structural =
            leaf("/obj/base\n    var/count=1\n    var/extra=0\n/proc/probe()\n    return 1\n");
        assert!(!same_leaves(&[Arc::clone(&original)], &[structural]));
        let other = leaf("/obj/other\n");
        assert!(!same_leaves(
            &[Arc::clone(&original), Arc::clone(&other)],
            &[other, original]
        ));
    }
}
fn same_leaves(
    previous: &[Arc<Vec<crate::Skeleton>>],
    current: &[Arc<Vec<crate::Skeleton>>],
) -> bool {
    previous.len() == current.len()
        && previous
            .iter()
            .zip(current)
            .all(|(a, b)| Arc::ptr_eq(a, b) || a == b)
}
impl DeclarationClaims {
    pub(crate) fn with_shared_authored(owner: Arc<crate::SharedNormalizedDeclarations>) -> Self {
        Self {
            values: DeclarationValues::shared(&owner),
            authored: Some(owner.authored.lease()),
            ..Self::default()
        }
    }
    pub(crate) fn visit_authored_storage(
        &self,
        visit: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                crate::declaration_contributions::TypeContribution,
                dm_ir::SymbolId,
                Option<Arc<[crate::declaration_contributions::DeclarationRow]>>,
                (),
            >,
        ),
    ) {
        if let Some(authored) = &self.authored {
            authored.visit_storage(visit);
        }
    }
    pub(crate) fn take_authored_index(
        &self,
        skeletons: crate::skeleton_roster::SkeletonView<'_>,
    ) -> Option<KeyedDeclarations> {
        let index = self
            .authored_current
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()?
            .index
            .clone();
        // Public compatibility overlays cannot reuse a receipt for different rows.
        index.skeletons().eq(skeletons.iter()).then_some(index)
    }
    pub(crate) fn adopt_authored<'a>(
        &self,
        currents: impl IntoIterator<Item = &'a mut CurrentContribution>,
    ) -> Option<()> {
        let Some(authored) = &self.authored else {
            return Some(());
        };
        let mut currents: Vec<_> = currents.into_iter().collect();
        let leaves: Vec<_> = currents.iter().map(|current| current.skeletons()).collect();
        let reused = {
            let previous = self
                .authored_current
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            previous
                .as_ref()
                .filter(|previous| same_leaves(&previous.leaves, &leaves))
                .map(|previous| (previous.index.clone(), previous.leaves.clone()))
        };
        if let Some((index, admitted_leaves)) = reused {
            for (current, skeletons) in currents.iter_mut().zip(admitted_leaves) {
                if !Arc::ptr_eq(&current.value.skeletons, &skeletons) {
                    let mut replacement = current.value.as_ref().clone();
                    replacement.skeletons = skeletons;
                    current.value = Arc::new(replacement);
                }
            }
            // Sharing the previous leaf backing does not transfer its lease.
            // Replay and claim the exact rows for this pending request as well.
            let index = authored.adopt(index);
            return self.publish_authored(currents, index);
        }
        let mut roster = crate::skeleton_roster::SkeletonRoster::default();
        for current in &currents {
            roster.push_leaf(current.skeletons());
        }
        let (index, _) = {
            let previous = self
                .authored_current
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            KeyedDeclarations::capture_view(
                previous.as_ref().map(|value| &value.index),
                roster.view(),
            )
            .ok()?
        };
        let index = authored.adopt(index);
        let mut rows = index.skeletons();
        for current in &mut currents {
            let mut changed = false;
            let start = rows.clone();
            for original in current.value.skeletons.iter() {
                let shared = rows.next()?;
                if original != shared {
                    return None;
                }
                if let (
                    crate::Skeleton::Member { metadata: a, .. },
                    crate::Skeleton::Member { metadata: b, .. },
                ) = (original, shared)
                {
                    changed |= !Arc::ptr_eq(a, b);
                }
            }
            if !changed {
                continue;
            }
            let replacement = start.take(current.value.skeletons.len()).cloned().collect();
            let old = &current.value;
            let replacement = Contribution {
                source: Arc::clone(&old.source),
                facts: Arc::clone(&old.facts),
                syntax: Arc::clone(&old.syntax),
                skeletons: Arc::new(replacement),
                ledger: old.ledger.clone(),
                event_leaf: old.event_leaf.clone(),
                origin_max: old.origin_max,
            };
            current.value = Arc::new(replacement);
        }
        if rows.next().is_some() {
            return None;
        }
        drop(rows);
        self.publish_authored(currents, index)
    }
    fn publish_authored(
        &self,
        currents: Vec<&mut CurrentContribution>,
        index: KeyedDeclarations,
    ) -> Option<()> {
        let mut leaves = Vec::with_capacity(currents.len());
        for current in currents {
            let key = RetainedDeclarations::key(&current.value.source);
            self.values.publish(&key, current)?;
            leaves.push(current.skeletons());
        }
        *self
            .authored_current
            .lock()
            .unwrap_or_else(|error| error.into_inner()) =
            Some(Arc::new(AdmittedAuthored { index, leaves }));
        Some(())
    }
}
