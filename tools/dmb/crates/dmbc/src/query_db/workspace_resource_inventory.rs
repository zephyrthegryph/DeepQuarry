//! One guarded operation's resource inventory, never a semantic cache.
//! Initial derived Outcomes are pinned only until this value drops. PageInput
//! retains a Weak inventory handle, so an evicted input/Params cannot extend it.
use super::aggregate::Aggregate;
use super::*;
use std::any::Any;
// Conservative private BTree node/allocator allowance, not an exact census.
// Includes split/internal-node overhead even for a small non-full tree.
const ENTRY_ENVELOPE: usize = 256;
const ROOT_ENVELOPE: usize = 4096;
type Erased = Arc<dyn Any + Send + Sync>;
pub(super) struct ResourceInventory {
    pub(super) owners: Arc<Mutex<Owners>>,
    pins: Mutex<Vec<Erased>>,
}
impl ResourceInventory {
    pub(super) fn bytes(&self) -> usize {
        self.owners.lock().unwrap_or_else(|e| e.into_inner()).bytes
    }
    pub(super) fn coordination_charge(&self, extra: usize) -> io::Result<usize> {
        let owners = self.owners.lock().unwrap_or_else(|e| e.into_inner());
        let pins = self.pins.lock().unwrap_or_else(|e| e.into_inner());
        owners
            .keys
            .len()
            .checked_add(extra)
            .and_then(|n| n.checked_mul(ENTRY_ENVELOPE))
            .and_then(|n| n.checked_add(pins.capacity() * std::mem::size_of::<Erased>()))
            .and_then(|n| {
                n.checked_add(
                    ROOT_ENVELOPE
                        + std::mem::size_of::<Self>()
                        + std::mem::size_of::<Mutex<Owners>>()
                        + 2 * std::mem::size_of::<usize>(),
                )
            })
            .ok_or_else(|| invalid("workspace inventory coordination overflow"))
    }
    fn pin<T: Any + Send + Sync>(&self, value: &Arc<T>) -> io::Result<()> {
        let mut pins = self.pins.lock().unwrap_or_else(|e| e.into_inner());
        // Capacity is admitted and reserved before any inventory is constructed.
        // The node-count bound below includes replaced/evicted Outcomes pinned
        // by this operation; eviction never claims their bytes were released.
        if pins.len() == pins.capacity() {
            return Err(invalid(
                "workspace operation retained-owner bound exhausted",
            ));
        }
        pins.push(value.clone());
        Ok(())
    }
    pub(super) fn require_pin_room(&self) -> io::Result<()> {
        let pins = self.pins.lock().unwrap_or_else(|e| e.into_inner());
        if pins.len() == pins.capacity() {
            Err(invalid(
                "workspace operation retained-owner bound exhausted",
            ))
        } else {
            Ok(())
        }
    }
    /// Borrowed owners were admitted by the existing configuration producer.
    /// The caller must preflight map growth before registering these weak census
    /// rows. This stores no source authority or additional strong payload owner.
    pub(super) fn add_scopes(&self,scopes:&[Arc<Scope>]) {
        let mut owners=self.owners.lock().unwrap_or_else(|e|e.into_inner());
        for scope in scopes {owners.scope(scope);}
    }
    pub(super) fn add_page_result(
        &self,
        result: &Arc<Result<Arc<PageResult>, String>>,
    ) -> io::Result<()> {
        self.pin(result)?;
        let mut owners = self.owners.lock().unwrap_or_else(|e| e.into_inner());
        owners.outcome(4, result);
        if let Ok(page) = result.as_ref() {
            owners.page(page);
        }
        Ok(())
    }
    pub(super) fn add_aggregate(
        &self,
        result: &Arc<Result<Arc<Aggregate>, String>>,
    ) -> io::Result<()> {
        self.pin(result)?;
        let mut owners = self.owners.lock().unwrap_or_else(|e| e.into_inner());
        owners.outcome(5, result);
        if let Ok(aggregate) = result.as_ref() {
            aggregate.visit(&mut owners);
        }
        Ok(())
    }
}
impl QueryDb {
    pub(super) fn workspace_resource_inventory_locked(&self) -> io::Result<ResourceInventory> {
        // Existing bounded census performs one original preflight and one walk.
        // No allocation/content address authorizes a source or a cache read.
        let owners = self.workspace_owners_with_fixed_locked(&[], 0)?;
        let extra = NODE_BOUND
            .checked_mul(std::mem::size_of::<Erased>())
            .and_then(|n| n.checked_add(owners.keys.len().checked_mul(ENTRY_ENVELOPE)?))
            .and_then(|n| {
                n.checked_add(
                    ROOT_ENVELOPE
                        + std::mem::size_of::<ResourceInventory>()
                        + std::mem::size_of::<Mutex<Owners>>()
                        + 2 * std::mem::size_of::<usize>(),
                )
            })
            .ok_or_else(|| invalid("workspace initial inventory overflow"))?;
        self.workspace_input_headroom_locked(extra)?;
        let mut pins = Vec::<Erased>::new();
        pins.try_reserve_exact(NODE_BOUND).map_err(invalid)?;
        let inventory = ResourceInventory {
            owners: Arc::new(Mutex::new(owners)),
            pins: Mutex::new(pins),
        };
        // Same raw-family gate prevents prune/replace between the census and pin.
        let pages = self
            .raw_policy
            .workspace
            .pages
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        for key in pages.keys() {
            if let Some(value) = self
                .db
                .retained_value::<Result<Arc<PageResult>, String>>(*key)
            {
                inventory.require_pin_room()?;
                inventory.pin(&value)?;
            }
        }
        let roots = self
            .raw_policy
            .workspace
            .roots
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        for key in roots.keys() {
            if let Some(value) = self
                .db
                .retained_value::<Result<Arc<Aggregate>, String>>(*key)
            {
                inventory.require_pin_room()?;
                inventory.pin(&value)?;
            }
        }
        drop(roots);
        drop(pages);
        self.workspace_input_headroom_locked(inventory.coordination_charge(0)?)?;
        Ok(inventory)
    }
}
