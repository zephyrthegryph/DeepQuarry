//! Position-independent inheritance decisions. Wire IDs are always bound afresh.
use dm_session::{Observation, ObservationHost};
use std::{
    collections::BTreeSet,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
};
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct HeaderRecipe {
    pub owner: Vec<u8>,
    /// Ordered fields read from the current finalized parent, never dense wire IDs.
    pub inherited_fields: Vec<String>,
    pub local: BTreeSet<String>,
    pub native_overrides: BTreeSet<Vec<u8>>,
    pub effective_authored: BTreeSet<String>,
    pub effective_overrides: BTreeSet<String>,
    pub authored_name: bool,
    pub authored_text: bool,
}
struct Parent<'a>(&'a Arc<HeaderRecipe>);
impl ObservationHost<(), Arc<HeaderRecipe>, ()> for Parent<'_> {
    fn answer(&self, _: &()) -> Arc<HeaderRecipe> {
        Arc::clone(self.0)
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct DefaultSelector {
    pub from_parent: bool,
    pub ordinal: usize,
    pub name: Vec<u8>,
}
struct NoReads;
impl ObservationHost<(), (), ()> for NoReads {
    fn answer(&self, _: &()) {}
}
pub struct HeaderRecipes {
    values: dm_session::ObservedArtifactStore<HeaderRecipe, (), Arc<HeaderRecipe>, ()>,
    defaults: dm_session::ObservedArtifactStore<Vec<DefaultSelector>, (), (), ()>,
    pub hits: AtomicU64,
    pub recomputed: AtomicU64,
}
impl Default for HeaderRecipes {
    fn default() -> Self {
        Self {
            values: dm_session::ObservedArtifactStore::current_revision(),
            defaults: dm_session::ObservedArtifactStore::current_revision(),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
        }
    }
}
fn strings(key: &mut Vec<u8>, values: &BTreeSet<String>) {
    key.extend_from_slice(&(values.len() as u64).to_le_bytes());
    for value in values {
        key.extend_from_slice(&(value.len() as u64).to_le_bytes());
        key.extend_from_slice(value.as_bytes());
    }
}
fn produce(
    owner: &[u8],
    authored: &BTreeSet<String>,
    overrides: &BTreeSet<String>,
    mut local: BTreeSet<String>,
    mut native: BTreeSet<Vec<u8>>,
    parent: &HeaderRecipe,
) -> HeaderRecipe {
    local.retain(|name| authored.contains(name) || !parent.effective_authored.contains(name));
    native.retain(|name| {
        !std::str::from_utf8(name).is_ok_and(|name| parent.effective_overrides.contains(name))
    });
    let mut effective_authored = parent.effective_authored.clone();
    effective_authored.extend(authored.iter().cloned());
    let mut effective_overrides = parent.effective_overrides.clone();
    effective_overrides.extend(overrides.iter().cloned());
    let mut inherited_fields = Vec::new();
    if !parent.owner.is_empty() {
        for name in [
            "desc",
            "icon",
            "icon_state",
            "layer",
            "dir",
            "maptext",
            "suffix",
            "maptext_width",
            "maptext_height",
            "maptext_x",
            "maptext_y",
            "transform",
            "invisibility",
            "density",
            "opacity",
            "appearance_flags",
            "luminosity",
            "mouse_opacity",
            "animate_movement",
        ] {
            if !local.contains(name) {
                inherited_fields.push(name.to_owned());
            }
        }
        if parent.authored_name && !local.contains("name") {
            inherited_fields.push("name".to_owned());
        }
        if parent.authored_text && !local.contains("text") {
            inherited_fields.push("text".to_owned());
        }
    }
    HeaderRecipe {
        owner: owner.to_vec(),
        inherited_fields,
        local,
        native_overrides: native,
        effective_authored,
        effective_overrides,
        authored_name: authored.contains("name") || parent.authored_name,
        authored_text: authored.contains("text") || parent.authored_text,
    }
}
impl HeaderRecipes {
    pub fn clear(&self) {
        self.values.retain_current_keys(std::iter::empty::<&[u8]>());
        self.defaults
            .retain_current_keys(std::iter::empty::<&[u8]>());
    }
    pub(crate) fn obtain(
        &self,
        owner: &[u8],
        authored: &BTreeSet<String>,
        overrides: &BTreeSet<String>,
        local: BTreeSet<String>,
        native: BTreeSet<Vec<u8>>,
        parent: &Arc<HeaderRecipe>,
    ) -> (Vec<u8>, Arc<HeaderRecipe>) {
        let mut key = b"dmbc-header-decisions-v1\0".to_vec();
        key.extend_from_slice(&(owner.len() as u64).to_le_bytes());
        key.extend_from_slice(owner);
        strings(&mut key, authored);
        strings(&mut key, overrides);
        strings(&mut key, &local);
        key.extend_from_slice(&(native.len() as u64).to_le_bytes());
        for value in &native {
            key.extend_from_slice(&(value.len() as u64).to_le_bytes());
            key.extend_from_slice(value);
        }
        if let Some(value) = self.values.lookup(&key, &Parent(parent)) {
            self.hits.fetch_add(1, Ordering::Relaxed);
            return (key, value);
        }
        let value = produce(owner, authored, overrides, local, native, parent);
        self.recomputed.fetch_add(1, Ordering::Relaxed);
        // Current-revision retention is bounded by the issued owner roster, not an approximate byte budget.
        let stored = self
            .values
            .insert_with_owned(
                key.clone().into(),
                vec![Observation {
                    domain: (),
                    query: (),
                    answer: Arc::clone(parent),
                }],
                Vec::new(),
                0,
                || value,
            )
            .expect("current-revision header store admits the current owner");
        (key, stored)
    }
    /// The caller has decoded/validated both current row rosters in original error order.
    pub(crate) fn defaults(
        &self,
        owner: &[u8],
        parent: &[Vec<u8>],
        own: &[Vec<u8>],
    ) -> (Vec<u8>, Arc<Vec<DefaultSelector>>) {
        let mut key = b"dmbc-header-default-selectors-v1\0".to_vec();
        let owner_row = owner.to_vec();
        for rows in [std::slice::from_ref(&owner_row), parent, own] {
            key.extend_from_slice(&(rows.len() as u64).to_le_bytes());
            for row in rows {
                key.extend_from_slice(&(row.len() as u64).to_le_bytes());
                key.extend_from_slice(row);
            }
        }
        if let Some(value) = self.defaults.lookup(&key, &NoReads) {
            return (key, value);
        }
        let own_names = own.iter().collect::<BTreeSet<_>>();
        let value = parent
            .iter()
            .enumerate()
            .filter(|(_, name)| !own_names.contains(name))
            .map(|(ordinal, name)| DefaultSelector {
                from_parent: true,
                ordinal,
                name: name.clone(),
            })
            .chain(
                own.iter()
                    .enumerate()
                    .map(|(ordinal, name)| DefaultSelector {
                        from_parent: false,
                        ordinal,
                        name: name.clone(),
                    }),
            )
            .collect::<Vec<_>>();
        self.defaults
            .insert_with(key.clone().into(), Vec::new(), Vec::new(), 0, || {
                value.clone()
            });
        (key, Arc::new(value))
    }
    pub(crate) fn retain_default_keys(&self, keys: &[Vec<u8>]) {
        self.defaults
            .retain_current_keys(keys.iter().map(Vec::as_slice));
    }
    pub(crate) fn visit_default_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<'_, Vec<DefaultSelector>, (), (), ()>,
        ),
    ) {
        self.defaults.visit_storage(visitor);
    }
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(
            dm_session::ObservedArtifactStorageView<
                '_,
                HeaderRecipe,
                (),
                Arc<HeaderRecipe>,
                (),
            >,
        ),
    ) {
        self.values.visit_storage(visitor);
    }
    pub(crate) fn retain_current(&self, keys: &[Vec<u8>]) {
        self.values
            .retain_current_keys(keys.iter().map(Vec::as_slice));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn names(values: &[&str]) -> BTreeSet<String> {
        values.iter().map(|v| (*v).to_owned()).collect()
    }
    #[test]
    fn inherited_authorship_invalidates_only_exact_parent_decisions() {
        let store = HeaderRecipes::default();
        let authored = names(&["density"]);
        let overrides = names(&["density", "icon_state"]);
        let local = names(&["density", "desc"]);
        let native = BTreeSet::from([b"icon_state".to_vec()]);
        let parent = Arc::new(HeaderRecipe::default());
        let (key, first) = store.obtain(
            b"/obj/example",
            &authored,
            &overrides,
            local.clone(),
            native.clone(),
            &parent,
        );
        let (_, repeated) = store.obtain(
            b"/obj/example",
            &authored,
            &overrides,
            local.clone(),
            native.clone(),
            &parent,
        );
        assert!(Arc::ptr_eq(
            &repeated,
            &store.values.lookup(&key, &Parent(&parent)).unwrap()
        ));
        assert_eq!(*first, *repeated);
        assert!(Arc::ptr_eq(&first, &repeated));
        let changed_parent = Arc::new(HeaderRecipe {
            effective_authored: names(&["desc"]),
            effective_overrides: names(&["icon_state"]),
            authored_name: true,
            ..HeaderRecipe::default()
        });
        let (_, changed) = store.obtain(
            b"/obj/example",
            &authored,
            &overrides,
            local,
            native,
            &changed_parent,
        );
        assert!(!changed.local.contains("desc"));
        assert!(changed.local.contains("density"));
        assert!(changed.native_overrides.is_empty());
        assert!(changed.authored_name);
        assert_eq!(store.hits.load(Ordering::Relaxed), 1);
        assert_eq!(store.recomputed.load(Ordering::Relaxed), 2);
        assert!(store.values.lookup(&key, &Parent(&parent)).is_none());
    }
    #[test]
    fn current_roster_prunes_deleted_owners_without_invalidating_borrowers() {
        let store = HeaderRecipes::default();
        let parent = Arc::new(HeaderRecipe::default());
        let empty = BTreeSet::new();
        let (a, value) = store.obtain(
            b"/obj/a",
            &empty,
            &empty,
            empty.clone(),
            BTreeSet::new(),
            &parent,
        );
        let (b, _) = store.obtain(
            b"/obj/b",
            &empty,
            &empty,
            empty.clone(),
            BTreeSet::new(),
            &parent,
        );
        store.retain_current(&[b]);
        assert!(store.values.lookup(&a, &Parent(&parent)).is_none());
        assert!(value.local.is_empty());
    }
}
