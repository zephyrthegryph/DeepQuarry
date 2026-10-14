//! Immutable linker assignment owner, distinct from current symbolic contents.
//! Equality admission occurs only after the ordinary builder validates every
//! current collision, allocation order, fixed index and reservation policy.
use super::*;

#[derive(Clone, Debug)]
pub struct BindingTables {
    inner: Arc<BindingData>,
}
#[derive(Debug, PartialEq, Eq)]
struct BindingData {
    indexes: BTreeMap<Key, u32>,
    slots: BTreeMap<SymbolId, (SymbolId, SymbolId)>,
}
impl BindingTables {
    pub(super) fn validated(
        indexes: BTreeMap<Key, u32>,
        slots: BTreeMap<SymbolId, (SymbolId, SymbolId)>,
        previous: Option<&Self>,
    ) -> Self {
        if let Some(previous) = previous
            .filter(|previous| previous.inner.indexes == indexes && previous.inner.slots == slots)
        {
            return previous.clone();
        }
        Self {
            inner: Arc::new(BindingData { indexes, slots }),
        }
    }
    pub fn assignments(&self) -> &BTreeMap<Key, u32> {
        &self.inner.indexes
    }
    pub fn same_owner(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.inner, &other.inner)
    }
    /// Actual immutable owner descriptor and logical index counts for opt-in census.
    /// Private BTree nodes and Arc control blocks are deliberately not estimated.
    pub fn storage(&self) -> (usize, usize, usize, usize) {
        (
            Arc::as_ptr(&self.inner) as usize,
            std::mem::size_of::<BindingData>(),
            self.inner.indexes.len(),
            self.inner.slots.len(),
        )
    }
    pub(super) fn slots(&self) -> &BTreeMap<SymbolId, (SymbolId, SymbolId)> {
        &self.inner.slots
    }
}

/// Latest successful validated binding owner for a live compiler session. This
/// retains no contents, diagnostic locations, or historical variants.
struct Current {
    bindings: BindingTables,
    recipe: Arc<super::assignment_recipe::AssignmentRecipe>,
}
type Pending = Arc<std::sync::Mutex<Option<Arc<Current>>>>;
pub struct RetainedBindings {
    current: Pending,
    publication: Arc<dm_session::ArtifactPublication<Pending>>,
    attempt: dm_session::ArtifactAttempt<Pending>,
    assignment_reuses: std::sync::atomic::AtomicUsize,
}
impl Default for RetainedBindings {
    fn default() -> Self {
        let current = Arc::new(std::sync::Mutex::new(None));
        let publication = Arc::new(dm_session::ArtifactPublication::default());
        let attempt = publication.begin(Arc::clone(&current));
        Self {
            current,
            publication,
            attempt,
            assignment_reuses: Default::default(),
        }
    }
}
impl RetainedBindings {
    pub fn for_request(&self, publishable: bool) -> Arc<Self> {
        let previous = self
            .publication
            .with_published(|current| current.lock().unwrap_or_else(|e| e.into_inner()).clone())
            .unwrap_or_else(|| {
                self.current
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .clone()
            });
        let current = Arc::new(std::sync::Mutex::new(previous));
        let attempt = if publishable {
            self.publication.begin(Arc::clone(&current))
        } else {
            self.publication.begin_ephemeral(Arc::clone(&current))
        };
        Arc::new(Self {
            current,
            publication: Arc::clone(&self.publication),
            attempt,
            assignment_reuses: Default::default(),
        })
    }
    pub fn publish_successful(&self) -> bool {
        self.attempt.publish_successful()
    }
    fn visit_owners(&self, mut visit: impl FnMut(&Pending)) {
        visit(&self.current);
        self.publication.with_published(|current| {
            if !Arc::ptr_eq(current, &self.current) {
                visit(current);
            }
        });
    }

    /// Observe the current immutable owner without cloning or rebuilding tables.
    /// The callback must not call back into this retained owner.
    pub fn visit_current(&self, mut visitor: impl FnMut(Option<&BindingTables>)) {
        self.visit_owners(|owner| {
            let current = owner.lock().unwrap_or_else(|e| e.into_inner());
            visitor(current.as_ref().map(|current| &current.bindings));
        });
    }
    pub fn assignment_reuses(&self) -> usize {
        self.assignment_reuses
            .load(std::sync::atomic::Ordering::Relaxed)
    }
    /// Borrowed exact inline owners and recipe buffers; Arc control blocks and
    /// private BTree backing remain explicitly unknown.
    pub fn visit_recipe_storage(
        &self,
        mut buffer: impl FnMut(usize, usize, usize),
        mut maps: impl FnMut(usize),
    ) {
        self.visit_owners(|owner| {
            let current = owner.lock().unwrap_or_else(|e| e.into_inner());
            if let Some(current) = current.as_ref() {
                let size = std::mem::size_of::<Current>();
                buffer(Arc::as_ptr(current) as usize, size, size);
                let size = std::mem::size_of::<super::assignment_recipe::AssignmentRecipe>();
                buffer(Arc::as_ptr(&current.recipe) as usize, size, size);
                current.recipe.visit_storage(&mut buffer, &mut maps);
            }
        });
    }
    pub fn build(&self, inventory: LinkInventory) -> Result<LinkTables, LinkError> {
        let mut inventory = Some(inventory);
        self.attempt
            .with_pending(|_| self.build_pending(inventory.take().expect("one pending build")))
            .unwrap_or_else(|| {
                LinkTables::build(inventory.take().expect("sealed build retains input"))
            })
    }
    fn build_pending(&self, inventory: LinkInventory) -> Result<LinkTables, LinkError> {
        let previous = self
            .current
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        let (tables, captured) = LinkTables::build_with_assignment_recipe(
            inventory,
            previous.as_ref().map(|current| &current.bindings),
            previous.as_ref().map(|current| current.recipe.as_ref()),
            true,
        )?;
        let recipe = match captured {
            Some(recipe) => Arc::new(recipe),
            None => {
                self.assignment_reuses
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                previous
                    .as_ref()
                    .expect("exact assignment reuse has prior owner")
                    .recipe
                    .clone()
            }
        };
        *self.current.lock().unwrap_or_else(|e| e.into_inner()) = Some(Arc::new(Current {
            bindings: tables.binding_tables(),
            recipe,
        }));
        Ok(tables)
    }
}
#[cfg(test)]
#[path = "bindings_tests.rs"]
mod tests;
