//! Coordinator admission adopts exact shared authored metadata into current leaves.
use super::*;
use crate::declaration_contributions::KeyedDeclarations;
pub(super) struct AdmittedAuthored {
    index: KeyedDeclarations,
    pub(super) leaves: Vec<Arc<Vec<crate::Skeleton>>>,
    /// The lease (`AuthoredLease::id`) that admitted `index` and claims its variants.
    admitted_by: Option<u64>,
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
/// Which current leaves can hold a row whose admitted value differs from the leaf's own: a leaf not among the previous request's
/// (pointer identity), and every leaf holding a row of an owner whose admitted contribution is not the previous one.
fn leaves_to_check(
    previous: &KeyedDeclarations,
    previous_leaves: &[Arc<Vec<crate::Skeleton>>],
    index: &KeyedDeclarations,
    leaves: &[Arc<Vec<crate::Skeleton>>],
) -> Vec<bool> {
    let known: std::collections::HashSet<usize> =
        previous_leaves.iter().map(|leaf| Arc::as_ptr(leaf) as usize).collect();
    let mut check: Vec<bool> = leaves.iter().map(|leaf| !known.contains(&(Arc::as_ptr(leaf) as usize))).collect();
    let mut moved: Vec<dm_ir::SymbolId> = index
        .owners()
        .filter(|(owner, value)| !previous.owner(**owner).is_some_and(|before| Arc::ptr_eq(before, value)))
        .map(|(owner, _)| *owner)
        .collect();
    moved.sort_unstable();
    if moved.is_empty() {
        return check;
    }
    let mut leaf = 0;
    let mut end = leaves.first().map_or(0, |leaf| leaf.len());
    for (position, handle) in index.roster().iter().enumerate() {
        while position >= end && leaf + 1 < leaves.len() {
            leaf += 1;
            end += leaves[leaf].len();
        }
        if moved.binary_search(&handle.owner).is_ok() {
            check[leaf] = true;
        }
    }
    check
}
/// Two captures name the same rows, keys, fingerprints, digests and handles.
fn same_index(a: &KeyedDeclarations, b: &KeyedDeclarations) -> bool {
    a.roster() == b.roster()
        && a.owners().len() == b.owners().len()
        && a.owners().zip(b.owners()).all(|((ao, av), (bo, bv))| {
            ao == bo && av.digest() == bv.digest() && av.rows() == bv.rows() && av.shared_shape() == bv.shared_shape()
        })
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
        let current = self
            .authored_current
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()?;
        // Public compatibility overlays cannot reuse a receipt for different rows. The leaves the index was admitted from are
        // its rows: a view of exactly those leaves needs no row compared.
        (skeletons.is_leaves(&current.leaves) || current.index.skeletons().eq(skeletons.iter())).then(|| current.index.clone())
    }
    pub(crate) fn adopt_authored<'a>(
        &self,
        currents: impl IntoIterator<Item = &'a mut CurrentContribution>,
    ) -> Option<()> {
        let Some(authored) = &self.authored else {
            return Some(());
        };
        let started = std::time::Instant::now();
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
                .map(|previous| (previous.index.clone(), previous.leaves.clone(), previous.admitted_by))
        };
        if let Some((index, admitted_leaves, admitted_by)) = reused {
            for (current, skeletons) in currents.iter_mut().zip(admitted_leaves) {
                if !Arc::ptr_eq(&current.value.skeletons, &skeletons) {
                    let mut replacement = current.value.as_ref().clone();
                    replacement.skeletons = skeletons;
                    current.value = Arc::new(replacement);
                    current.stored = false;
                }
            }
            // Sharing the previous leaf backing does not transfer its lease.
            // Replay and claim the exact rows for this pending request as well.
            let compared = started.elapsed();
            // The previous request admitted exactly this index, and this request's lease took over its claims when it
            // was forked: the replay would claim the same variants again. Otherwise replay as before.
            let inherited = admitted_by.is_some() && admitted_by == self.authored_inherited;
            let index = if inherited { index } else { authored.adopt(index) };
            let adopted = started.elapsed();
            let published = self.publish_authored(currents, index);
            crate::change_set::record_outcome(format!(
                "frontend authored (same leaves, {}): compare={:.3}s adopt={:.3}s publish={:.3}s",
                if inherited { "claims inherited" } else { "replayed" },
                compared.as_secs_f64(),
                (adopted - compared).as_secs_f64(),
                (started.elapsed() - adopted).as_secs_f64()
            ));
            return published;
        }
        let previous = self
            .authored_current
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone();
        let full_capture = |previous: Option<&KeyedDeclarations>| {
            let mut roster = crate::skeleton_roster::SkeletonRoster::default();
            for current in &currents {
                roster.push_leaf(current.skeletons());
            }
            KeyedDeclarations::capture_view(previous, roster.view()).ok().map(|(index, _)| index)
        };
        // The leaves that differ from the previous request's, and the owners they touch, are all a capture reads.
        let incremental = previous
            .as_ref()
            .and_then(|previous| KeyedDeclarations::capture_leaves(&previous.index, &previous.leaves, &leaves));
        let used_incremental = incremental.is_some();
        let index = match incremental {
            Some(captured) => {
                let (index, _) = captured.ok()?;
                if crate::frontend_verify_enabled() {
                    let full = full_capture(previous.as_ref().map(|value| &value.index))?;
                    crate::change_set::record_outcome(if same_index(&index, &full) {
                        "frontend verify: incremental authored capture equals the full capture".to_string()
                    } else {
                        eprintln!("frontend verify: INCREMENTAL AUTHORED CAPTURE MISMATCH");
                        "frontend verify: INCREMENTAL AUTHORED CAPTURE MISMATCH".to_string()
                    });
                }
                index
            }
            None => full_capture(previous.as_ref().map(|value| &value.index))?,
        };
        let captured = started.elapsed();
        // Owners whose rows did not change keep the value the previous request admitted, when this lease took over its
        // claims; the rest are replayed.
        let inherited = previous
            .as_ref()
            .filter(|previous| previous.admitted_by.is_some() && previous.admitted_by == self.authored_inherited);
        let index = match inherited {
            Some(previous) => authored.adopt_changed(index, &previous.index),
            None => authored.adopt(index),
        };
        let adopted = started.elapsed();
        // Each leaf takes the admitted rows (the lease may answer an owner with an equal earlier value). A leaf the previous
        // request admitted holds the previous admitted rows already, so only a new leaf, or a leaf holding a row of an owner
        // whose admitted value changed, is compared; without a previous request every leaf is.
        let check = previous.as_ref().map(|previous| leaves_to_check(&previous.index, &previous.leaves, &index, &leaves));
        let mut checked = 0;
        let mut at = 0;
        for (position, current) in currents.iter_mut().enumerate() {
            let len = current.value.skeletons.len();
            let start = at;
            at += len;
            if check.as_ref().is_some_and(|check| !check[position]) {
                continue;
            }
            checked += 1;
            let shared_rows = || index.roster().get(start..start + len).into_iter().flatten().map(|handle| index.row(*handle));
            let mut changed = false;
            let mut rows = shared_rows();
            for original in current.value.skeletons.iter() {
                let shared = &rows.next()??.skeleton;
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
            let mut replacement = Vec::with_capacity(len);
            for row in shared_rows() {
                replacement.push(row?.skeleton.clone());
            }
            let old = &current.value;
            let replacement = Contribution {
                source: old.source.clone(),
                facts: Arc::clone(&old.facts),
                syntax: Arc::clone(&old.syntax),
                skeletons: Arc::new(replacement),
                ledger: old.ledger.clone(),
                event_leaf: old.event_leaf.clone(),
                origin_max: old.origin_max,
            };
            current.value = Arc::new(replacement);
            current.stored = false;
        }
        if at != index.len() {
            return None;
        }
        let walked = started.elapsed();
        let published = self.publish_authored(currents, index);
        crate::change_set::record_outcome(format!(
            "frontend authored (changed leaves, {}, {}): capture={:.3}s adopt={:.3}s leaves={:.3}s ({checked} compared) publish={:.3}s",
            if used_incremental { "incremental capture" } else { "full capture" },
            if inherited.is_some() { "changed owners replayed" } else { "replayed" },
            captured.as_secs_f64(),
            (adopted - captured).as_secs_f64(),
            (walked - adopted).as_secs_f64(),
            (started.elapsed() - walked).as_secs_f64()
        ));
        published
    }
    fn publish_authored(
        &self,
        currents: Vec<&mut CurrentContribution>,
        index: KeyedDeclarations,
    ) -> Option<()> {
        let mut leaves = Vec::with_capacity(currents.len());
        for current in currents {
            // A value the store already holds under its key needs no second publication.
            if !current.stored {
                let key = RetainedDeclarations::key(&current.value.source);
                self.values.publish(&key, current)?;
            }
            leaves.push(current.skeletons());
        }
        *self
            .authored_current
            .lock()
            .unwrap_or_else(|error| error.into_inner()) =
            Some(Arc::new(AdmittedAuthored { index, leaves, admitted_by: self.authored.as_ref().map(|lease| lease.id()) }));
        Some(())
    }
}
