use crate::SymbolId;
use dm_syntax::{SettingAdmission, SettingRootLease};
use std::{alloc::{alloc, Layout}, io, ptr::NonNull, sync::Arc};

const SHARDS: usize = 256;
const PAGE_BYTES: usize = 16 * 1024;
const SOURCE: u64 = 1 << 63;

/// Retained immutable byte storage. Implementations must return the same
/// immutable view for the full lifetime of this handle. This interface
/// conveys storage only, never compiler/source-occurrence authority.
pub trait CompactSpellingSource: Send + Sync {
    fn text(&self) -> &str;

    /// Actual retained buffers, in the same address/size convention as the
    /// source producer's normal resident inventory.
    fn visit_storage(&self, visit: &mut dyn FnMut(usize, usize, usize));
}

struct SourceLoan {
    source: Box<dyn CompactSpellingSource>,
    credit: SettingRootLease,
}

#[derive(Clone, Copy, Debug)]
struct Slot {
    id: SymbolId,
    // One plus the slab ordinal occupies the high word, so zero is vacant.
    locator: u64,
}

#[derive(Default)]
struct Shard {
    slots: Vec<Slot>,
    len: usize,
    _credit: Option<SettingRootLease>,
}

fn allocate<T>(capacity: usize, a: &SettingAdmission<'_>) -> io::Result<Option<(Vec<T>, SettingRootLease)>> {
    let layout = Layout::array::<T>(capacity).map_err(|_| io::ErrorKind::OutOfMemory)?;
    let Some(credit) = a.try_reserve_optimization(layout.size()).map_err(|error| a.take_operational_error().unwrap_or(error))? else { return Ok(None) };
    debug_assert_ne!(layout.size(), 0);
    // The exact nonempty allocation moves into its matching empty Vec.
    let ptr = NonNull::new(unsafe { alloc(layout) }.cast::<T>()).ok_or(io::ErrorKind::OutOfMemory)?;
    Ok(Some((unsafe { Vec::from_raw_parts(ptr.as_ptr(), 0, capacity) }, credit)))
}

fn slot_index(slots: &[Slot], id: SymbolId) -> usize {
    let mask = slots.len() - 1;
    let mut i = ((id.bits() >> 8) as usize) & mask;
    while slots[i].locator != 0 && slots[i].id != id {
        i = (i + 1) & mask;
    }
    i
}

struct Page {
    bytes: String,
    _credit: SettingRootLease,
}

pub(super) struct CompactSpellings {
    shards: Vec<Shard>,
    pages: Vec<Page>,
    len: usize,
    _directory_credit: Option<SettingRootLease>,
    _shards_credit: Option<SettingRootLease>,
    source: Option<SourceLoan>,
    control: SettingRootLease,
}

pub(super) struct CompactOwner(Option<Arc<CompactSpellings>>);

impl std::fmt::Debug for CompactOwner {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CompactOwner").field("len", &self.get().len()).finish()
    }
}

impl Clone for CompactOwner {
    fn clone(&self) -> Self {
        Self(Some(Arc::clone(self.0.as_ref().expect("live compact spellings"))))
    }
}
impl Drop for CompactOwner {
    fn drop(&mut self) {
        // All strong references use this wrapper and there are no weak
        // references. Deallocate the Arc control before refunding its lease.
        if let Some(owner) = self.0.take() { drop(Arc::into_inner(owner)); }
    }
}
impl CompactOwner {
    pub(super) fn new(a: &SettingAdmission<'_>) -> io::Result<Option<Self>> {
        let bytes = Layout::new::<[usize; 2]>().extend(Layout::new::<CompactSpellings>())
            .map_err(|_| io::ErrorKind::OutOfMemory)?.0.pad_to_align().size();
        Ok(a.try_reserve_optimization(bytes).map_err(|error| a.take_operational_error().unwrap_or(error))?.map(|control| Self(Some(Arc::new(CompactSpellings {
            shards: Vec::new(), pages: Vec::new(), len: 0,
            _directory_credit: None, _shards_credit: None, source: None, control,
        })))))
    }

    pub(super) fn get(&self) -> &CompactSpellings {
        self.0.as_deref().expect("live compact spellings")
    }

    pub(super) fn bind_source<T: CompactSpellingSource + 'static>(
        &mut self, source: T, a: &SettingAdmission<'_>,
    ) -> io::Result<()> {
        let owner = self.0.as_mut().and_then(Arc::get_mut).ok_or(io::ErrorKind::InvalidInput)?;
        if owner.len != 0 || owner.source.is_some() || !a.matches_lease_domain(&owner.control) {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        let Some(credit) = a.try_reserve_optimization(std::mem::size_of::<T>())
            .map_err(|error| a.take_operational_error().unwrap_or(error))?
        else { return Ok(()) };
        owner.source = Some(SourceLoan { source: Box::new(source), credit });
        Ok(())
    }

    pub(super) fn insert(&mut self, id: SymbolId, text: &str, source_start: Option<usize>, a: &SettingAdmission<'_>) -> io::Result<bool> {
        let Some(owner) = self.0.as_mut().and_then(Arc::get_mut) else { return Ok(false) };
        if !a.matches_lease_domain(&owner.control) {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        owner.insert(id, text, source_start, a)
    }
}

impl CompactSpellings {
    fn shard(id: SymbolId) -> usize { (id.bits() as usize) & (SHARDS - 1) }

    pub(super) fn len(&self) -> usize { self.len }

    pub(super) fn text(&self, id: SymbolId) -> Option<&str> {
        let slots = &self.shards.get(Self::shard(id))?.slots;
        if slots.is_empty() { return None }
        let slot = slots[slot_index(slots, id)];
        (slot.locator != 0).then(|| self.spelling(slot.locator))
    }

    fn spelling(&self, locator: u64) -> &str {
        if locator & SOURCE != 0 {
            let start = ((locator >> 16) as u32) as usize;
            let len = locator as u16 as usize;
            return &self.source.as_ref().expect("bound spelling source").source.text()[start..start + len];
        }
        let page = (locator >> 32) as usize - 1;
        let start = (locator >> 16) as u16 as usize;
        let len = locator as u16 as usize;
        &self.pages[page].bytes[start..start + len]
    }

    pub(super) fn rows(&self) -> impl Iterator<Item = (SymbolId, &str)> {
        self.shards.iter().flat_map(|shard| shard.slots.iter())
            .filter(|slot| slot.locator != 0)
            .map(|slot| (slot.id, self.spelling(slot.locator)))
    }

    pub(super) fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        visit(self as *const Self as usize, self.control.bytes(), self.control.bytes());
        if let Some(credit) = &self._shards_credit {
            visit(self.shards.as_ptr() as usize, credit.bytes(), credit.bytes());
        }
        for shard in &self.shards {
            if let Some(credit) = &shard._credit { visit(shard.slots.as_ptr() as usize, shard.len * std::mem::size_of::<Slot>(), credit.bytes()); }
        }
        if let Some(credit) = &self._directory_credit {
            visit(self.pages.as_ptr() as usize, self.pages.len() * std::mem::size_of::<Page>(), credit.bytes());
        }
        for page in &self.pages { visit(page.bytes.as_ptr() as usize, page.bytes.len(), page._credit.bytes()); }
        if let Some(loan) = &self.source {
            let bytes = loan.credit.bytes();
            if bytes != 0 {
                let address = std::ptr::from_ref(loan.source.as_ref()).cast::<()>() as usize;
                visit(address, bytes, bytes);
            }
            loan.source.visit_storage(&mut visit);
        }
    }

    fn insert(&mut self, id: SymbolId, text: &str, source_start: Option<usize>, a: &SettingAdmission<'_>) -> io::Result<bool> {
        let source_locator = source_start.and_then(|start| {
            let source = self.source.as_ref()?.source.text();
            let end = start.checked_add(text.len())?;
            let start32 = u32::try_from(start).ok()?;
            let len16 = u16::try_from(text.len()).ok()?;
            (source.get(start..end) == Some(text))
                .then_some(SOURCE | (u64::from(start32) << 16) | u64::from(len16))
        });
        if source_locator.is_none() && text.len() > PAGE_BYTES { return Ok(false) }
        let shard_id = Self::shard(id);
        let shard = self.shards.get(shard_id);
        let mut shard_directory = if self.shards.is_empty() {
            let Some((mut rows, credit)) = allocate(SHARDS, a)? else { return Ok(false) };
            rows.resize_with(SHARDS, Shard::default);
            Some((rows, credit))
        } else { None };

        let old_capacity = shard.map_or(0, |shard| shard.slots.len());
        let mut new_slots = if shard.map_or(0, |shard| shard.len) >= old_capacity - old_capacity / 4 {
            let capacity = old_capacity.max(2).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;
            let Some((mut slots, credit)) = allocate(capacity, a)? else { return Ok(false) };
            slots.resize(capacity, Slot { id: SymbolId::ZERO, locator: 0 });
            if let Some(shard) = shard {
                for &slot in shard.slots.iter().filter(|slot| slot.locator != 0) {
                    let index = slot_index(&slots, slot.id);
                    slots[index] = slot;
                }
            }
            Some((slots, credit))
        } else { None };

        let new_page = source_locator.is_none() && self.pages.last().is_none_or(|page| PAGE_BYTES - page.bytes.len() < text.len());
        let page = if new_page { self.pages.len() } else { self.pages.len().saturating_sub(1) };
        let Some(page_number) = u32::try_from(page).ok().and_then(|number| number.checked_add(1))
            .filter(|number| *number < 1 << 31) else { return Ok(false) };
        let page_directory = if new_page && self.pages.len() == self.pages.capacity() {
            let capacity = self.pages.capacity().max(2).checked_mul(2).ok_or(io::ErrorKind::OutOfMemory)?;
            let Some(rows) = allocate(capacity, a)? else { return Ok(false) };
            Some(rows)
        } else { None };
        let page_allocation = if new_page {
            let Some((bytes, credit)) = allocate(PAGE_BYTES, a)? else { return Ok(false) };
            Some(Page { bytes: String::from_utf8(bytes).expect("empty UTF-8 slab"), _credit: credit })
        } else { None };

        // No allocation or fallible operation follows the first mutation.
        if let Some((rows, credit)) = shard_directory.take() {
            self.shards = rows;
            self._shards_credit = Some(credit);
        }
        let shard = &mut self.shards[shard_id];
        if let Some((slots, credit)) = new_slots.take() {
            shard.slots = slots;
            shard._credit = Some(credit);
        }
        if let Some((mut pages, credit)) = page_directory {
            pages.append(&mut self.pages);
            self.pages = pages;
            self._directory_credit = Some(credit);
        }
        if let Some(page) = page_allocation { self.pages.push(page); }
        let locator = if let Some(locator) = source_locator {
            locator
        } else {
            let bytes = &mut self.pages[page].bytes;
            let locator = (u64::from(page_number) << 32) | ((bytes.len() as u64) << 16) | text.len() as u64;
            bytes.push_str(text);
            locator
        };
        let index = slot_index(&shard.slots, id);
        shard.slots[index] = Slot { id, locator };
        shard.len += 1;
        self.len += 1;
        Ok(true)
    }
}
