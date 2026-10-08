//! Independent deterministic table assignment. No DMB writer or global ledger.
use dm_ir::{RelocationError, SymRef, SymbolId, SymbolicCode};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

/// String slots sharing the native variable-modifier/sentinel word space.
pub fn is_reserved_string_index(index: u32) -> bool {
    (0xffcd..=0xfff1).contains(&index) || index == 0xffff
}

/// Confirmed native holes only; other table policies remain independent.
pub fn is_reserved_table_index(table: Table, index: u32) -> bool {
    match table {
        Table::String => is_reserved_string_index(index),
        Table::Procedure | Table::List => index == 0xffff,
        _ => false,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Table {
    String,
    Type,
    Procedure,
    Variable,
    /// Actual DMB variable records; separate from the shared footer slot domain.
    VariableRecord,
    Instance,
    List,
    Resource,
}
/// Anonymous executable initialization domains. A map descriptor has its own
/// occurrence identity even when it initializes the same receiver class.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum InitializerIdentity {
    Global,
    Class(SymbolId),
    Map { source: u128, descriptor: u32 },
    Modified(SymbolId),
}
/// Proc and verb semantic namespaces remain distinct even when sharing a wire table.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Key {
    ProcedureStatic(dm_ir::ProcedureStaticIdentity),
    String(SymbolId),
    Type(SymbolId),
    Proc {
        owner: SymbolId,
        name: SymbolId,
        occurrence: u32,
    },
    Verb {
        owner: SymbolId,
        name: SymbolId,
        occurrence: u32,
    },
    Variable {
        owner: SymbolId,
        name: SymbolId,
    },
    ArgumentSource {
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
        occurrence: u32,
        argument: u32,
    },
    Initializer(InitializerIdentity),
    BuiltinGlobalVars,
    Instance(SymbolId),
    MapInstance {
        source: u128,
        descriptor: u32,
    },
    DefaultMapInstance {
        kind: u8,
        owner: SymbolId,
    },
    List(u128),
    Resource(u128),
}
impl Key {
    pub fn table(self) -> Table {
        match self {
            Self::String(_) => Table::String,
            Self::Type(_) => Table::Type,
            Self::Proc { .. }
            | Self::Verb { .. }
            | Self::ArgumentSource { .. }
            | Self::Initializer(_) => Table::Procedure,
            Self::Variable { .. } | Self::ProcedureStatic(_) => Table::Variable,
            Self::BuiltinGlobalVars => Table::VariableRecord,
            Self::Instance(_) | Self::MapInstance { .. } | Self::DefaultMapInstance { .. } => {
                Table::Instance
            }
            Self::List(_) => Table::List,
            Self::Resource(_) => Table::Resource,
        }
    }
}
#[derive(Clone, Debug)]
pub struct Entry {
    pub key: Key,
    pub content: Arc<[u8]>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SlotAlias {
    pub symbol: SymbolId,
    pub owner: SymbolId,
    pub name: SymbolId,
}
#[derive(Clone, Debug, Default)]
pub struct LinkInventory {
    pub entries: Vec<Entry>,
    /// Exact spellings validate hashed SymbolId identity across all inventories.
    pub spellings: Vec<(SymbolId, Arc<[u8]>)>,
    pub slots: Vec<SlotAlias>,
    /// Pinned engine indexes. Unfilled holes remain reserved, never silently reused.
    pub fixed: Vec<(Key, u32)>,
    /// Full observable order for a table, when supplied. Unordered tables use
    /// canonical structural key order; the linker never guesses BYOND order.
    pub orders: BTreeMap<Table, Vec<Key>>,
    /// Entire retained physical table lengths, including unnamed/duplicate rows.
    /// Their indexes are unavailable for new allocations without fake symbols.
    pub reserved_prefixes: BTreeMap<Table, u32>,
    /// Complete order of fresh keys only, following the retained physical prefix.
    pub append_orders: BTreeMap<Table, Vec<Key>>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LinkError {
    SymbolCollision(SymbolId),
    InvalidSymbol(SymbolId),
    MissingSpelling(SymbolId),
    ContentCollision(Key),
    SlotCollision(SymbolId),
    UnknownKey(Key),
    DuplicateFixed(Key),
    FixedIndexCollision(Table, u32),
    DuplicateOrder(Key),
    WrongTable(Key),
    IncompleteOrder(Table),
    OrderConflictsFixed(Key),
    ConflictingOrderModes(Table),
    ReservedIndex(Table, u32),
    IndexOverflow(Table),
    UnknownReference(SymRef),
    MissingSourceFile(u32),
    MissingSourceLine(u32),
    SourceLineOverflow(u32),
    Relocation(RelocationError),
}
#[derive(Clone, Debug)]
pub struct LinkTables {
    indexes: Arc<BTreeMap<Key, u32>>,
    slots: Arc<BTreeMap<SymbolId, (SymbolId, SymbolId)>>,
    content: Arc<BTreeMap<Key, Arc<[u8]>>>,
}
impl LinkTables {
    pub fn index(&self, key: Key) -> Option<u32> {
        self.indexes.get(&key).copied()
    }
    pub fn assignments(&self) -> &BTreeMap<Key, u32> {
        &self.indexes
    }
    pub fn content(&self, key: Key) -> Option<&[u8]> {
        self.content.get(&key).map(AsRef::as_ref)
    }
    pub fn build(inventory: LinkInventory) -> Result<Self, LinkError> {
        let mut spellings = BTreeMap::new();
        for (id, bytes) in inventory.spellings {
            if SymbolId::of_bytes(&bytes) != id {
                return Err(LinkError::InvalidSymbol(id));
            }
            if spellings
                .insert(id, Arc::clone(&bytes))
                .is_some_and(|previous| previous != bytes)
            {
                return Err(LinkError::SymbolCollision(id));
            }
        }
        let mut content = BTreeMap::new();
        for entry in inventory.entries {
            for symbol in symbols(entry.key) {
                if !spellings.contains_key(&symbol) {
                    return Err(LinkError::MissingSpelling(symbol));
                }
            }
            if content
                .insert(entry.key, Arc::clone(&entry.content))
                .is_some_and(|previous| previous != entry.content)
            {
                return Err(LinkError::ContentCollision(entry.key));
            }
        }
        let mut slots = BTreeMap::new();
        for slot in inventory.slots {
            let tuple = (slot.owner, slot.name);
            if slots
                .insert(slot.symbol, tuple)
                .is_some_and(|previous| previous != tuple)
            {
                return Err(LinkError::SlotCollision(slot.symbol));
            }
            if !content.contains_key(&Key::Variable {
                owner: slot.owner,
                name: slot.name,
            }) {
                return Err(LinkError::UnknownKey(Key::Variable {
                    owner: slot.owner,
                    name: slot.name,
                }));
            }
        }
        let mut indexes = BTreeMap::new();
        let mut occupied: BTreeMap<Table, BTreeSet<u32>> = BTreeMap::new();
        for (key, index) in inventory.fixed {
            if is_reserved_table_index(key.table(), index) {
                return Err(LinkError::ReservedIndex(key.table(), index));
            }
            if !content.contains_key(&key) {
                return Err(LinkError::UnknownKey(key));
            }
            if indexes.insert(key, index).is_some() {
                return Err(LinkError::DuplicateFixed(key));
            }
            if !occupied.entry(key.table()).or_default().insert(index) {
                return Err(LinkError::FixedIndexCollision(key.table(), index));
            }
        }
        // Partition once in canonical Key order. Each domain retains the exact
        // previous sorted fallback order without scanning all keys eight times.
        let mut domain_keys: BTreeMap<Table, Vec<Key>> = BTreeMap::new();
        for &key in content.keys() {
            domain_keys.entry(key.table()).or_default().push(key);
        }
        for table in [
            Table::String,
            Table::Type,
            Table::Procedure,
            Table::Variable,
            Table::VariableRecord,
            Table::Instance,
            Table::List,
            Table::Resource,
        ] {
            let keys = domain_keys.remove(&table).unwrap_or_default();
            let ordered = inventory.orders.get(&table);
            let append_order = inventory.append_orders.get(&table);
            let prefix = inventory
                .reserved_prefixes
                .get(&table)
                .copied()
                .unwrap_or(0);
            if ordered.is_some() && append_order.is_some() {
                return Err(LinkError::ConflictingOrderModes(table));
            }
            if let Some(order) = ordered {
                let mut seen = BTreeSet::new();
                for key in order {
                    if key.table() != table {
                        return Err(LinkError::WrongTable(*key));
                    }
                    if !content.contains_key(key) {
                        return Err(LinkError::UnknownKey(*key));
                    }
                    if !seen.insert(*key) {
                        return Err(LinkError::DuplicateOrder(*key));
                    }
                }
                if seen.len() != keys.len() {
                    return Err(LinkError::IncompleteOrder(table));
                }
                let mut next = 0u64;
                for key in order {
                    while u32::try_from(next)
                        .is_ok_and(|index| is_reserved_table_index(table, index))
                    {
                        next += 1;
                    }
                    let index = u32::try_from(next).map_err(|_| LinkError::IndexOverflow(table))?;
                    next += 1;
                    if indexes.get(key).is_some_and(|fixed| *fixed != index) {
                        return Err(LinkError::OrderConflictsFixed(*key));
                    }
                    if !indexes.contains_key(key)
                        && occupied.entry(table).or_default().contains(&index)
                    {
                        return Err(LinkError::FixedIndexCollision(table, index));
                    }
                    if !indexes.contains_key(key) && index < prefix {
                        return Err(LinkError::ReservedIndex(table, index));
                    }
                    indexes.insert(*key, index);
                    occupied.entry(table).or_default().insert(index);
                }
            } else {
                let mut next = occupied
                    .get(&table)
                    .and_then(|set| set.last())
                    .map(|i| u64::from(*i) + 1)
                    .unwrap_or(0)
                    .max(u64::from(prefix));
                let fresh: Vec<_> = keys
                    .into_iter()
                    .filter(|key| !indexes.contains_key(key))
                    .collect();
                let allocation = if let Some(order) = append_order {
                    let mut seen = BTreeSet::new();
                    for key in order {
                        if key.table() != table {
                            return Err(LinkError::WrongTable(*key));
                        }
                        if !content.contains_key(key) {
                            return Err(LinkError::UnknownKey(*key));
                        }
                        if indexes.contains_key(key) {
                            return Err(LinkError::OrderConflictsFixed(*key));
                        }
                        if !seen.insert(*key) {
                            return Err(LinkError::DuplicateOrder(*key));
                        }
                    }
                    if seen.len() != fresh.len() {
                        return Err(LinkError::IncompleteOrder(table));
                    }
                    order.as_slice()
                } else {
                    fresh.as_slice()
                };
                for &key in allocation {
                    while u32::try_from(next)
                        .is_ok_and(|index| is_reserved_table_index(table, index))
                    {
                        next += 1;
                    }
                    let index = u32::try_from(next).map_err(|_| LinkError::IndexOverflow(table))?;
                    indexes.insert(key, index);
                    next += 1;
                }
            }
        }
        Ok(Self {
            indexes: Arc::new(indexes),
            slots: Arc::new(slots),
            content: Arc::new(content),
        })
    }
    pub fn link(
        &self,
        code: &SymbolicCode,
        source: &SourceBindings,
    ) -> Result<ProcedureImage, LinkError> {
        let mut resolved = BTreeMap::new();
        for relocation in code.relocations() {
            let reference = relocation.reference;
            // Immutable tables/source bindings give repeated references the
            // same answer. Retain first-encounter resolution/error order.
            let std::collections::btree_map::Entry::Vacant(entry) = resolved.entry(reference)
            else {
                continue;
            };
            let index = match reference {
                SymRef::LineDelta(delta) => source
                    .first_line
                    .checked_add(delta)
                    .ok_or(LinkError::SourceLineOverflow(delta))?,
                SymRef::SourceLine(origin) => *source
                    .lines
                    .get(&origin)
                    .ok_or(LinkError::MissingSourceLine(origin))?,
                SymRef::SourceFile(origin) => {
                    let symbol = *source
                        .files
                        .get(&origin)
                        .ok_or(LinkError::MissingSourceFile(origin))?;
                    self.index(Key::String(symbol))
                        .ok_or(LinkError::UnknownKey(Key::String(symbol)))?
                }
                _ => {
                    let key = reference_key(reference, &self.slots)
                        .ok_or(LinkError::UnknownReference(reference))?;
                    self.index(key)
                        .ok_or(LinkError::UnknownReference(reference))?
                }
            };
            entry.insert(index);
        }
        let words = code
            .link(|reference| resolved.get(&reference).copied())
            .map_err(LinkError::Relocation)?;
        Ok(ProcedureImage {
            words: words.into(),
        })
    }
}
fn symbols(key: Key) -> impl Iterator<Item = SymbolId> {
    let values = match key {
        Key::ProcedureStatic(identity) => [
            Some(identity.procedure.owner),
            Some(identity.procedure.name),
            Some(identity.name),
        ],
        Key::Initializer(InitializerIdentity::Class(owner))
        | Key::DefaultMapInstance { owner, .. } => [Some(owner), None, None],
        Key::Initializer(InitializerIdentity::Modified(alias)) => [Some(alias), None, None],
        Key::String(id) | Key::Type(id) | Key::Instance(id) => [Some(id), None, None],
        Key::Proc { owner, name, .. }
        | Key::Verb { owner, name, .. }
        | Key::ArgumentSource { owner, name, .. }
        | Key::Variable { owner, name } => [Some(owner), Some(name), None],
        _ => [None; 3],
    };
    values.into_iter().flatten()
}
fn reference_key(
    reference: SymRef,
    slots: &BTreeMap<SymbolId, (SymbolId, SymbolId)>,
) -> Option<Key> {
    Some(match reference {
        SymRef::ProcedureStatic(identity) => Key::ProcedureStatic(identity),
        SymRef::String(id) => Key::String(id),
        SymRef::Type(id) => Key::Type(id),
        SymRef::Proc {
            owner,
            name,
            occurrence,
        } => Key::Proc {
            owner,
            name,
            occurrence,
        },
        SymRef::Verb {
            owner,
            name,
            occurrence,
        } => Key::Verb {
            owner,
            name,
            occurrence,
        },
        SymRef::ArgumentSource {
            owner,
            name,
            verb,
            occurrence,
            argument,
        } => Key::ArgumentSource {
            owner,
            name,
            verb,
            occurrence,
            argument,
        },
        SymRef::Var { owner, name } => Key::Variable { owner, name },
        SymRef::VariableSlot(symbol) => {
            let &(owner, name) = slots.get(&symbol)?;
            Key::Variable { owner, name }
        }
        SymRef::BuiltinGlobalVars => Key::BuiltinGlobalVars,
        SymRef::Instance(id) => Key::Instance(id),
        SymRef::ConstantList(id) => Key::List(id),
        SymRef::Resource(id) => Key::Resource(id),
        SymRef::SourceFile(_) | SymRef::SourceLine(_) | SymRef::LineDelta(_) => return None,
    })
}
#[derive(Clone, Debug, Default)]
pub struct SourceBindings {
    pub first_line: u32,
    pub files: BTreeMap<u32, SymbolId>,
    pub lines: BTreeMap<u32, u32>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProcedureImage {
    pub words: Arc<[u32]>,
}

/// Initializer dependencies/registration order are supplied by semantic lowering,
/// separately from code words. This linker validates identities; it does not
/// infer constructor order or lower initializer expressions.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct InitializerReferences {
    pub reads: Vec<Key>,
    pub writes: Vec<Key>,
    pub registrations: Vec<Key>,
}
impl LinkTables {
    pub fn validate_initializer(&self, sidecar: &InitializerReferences) -> Result<(), LinkError> {
        for key in sidecar
            .reads
            .iter()
            .chain(&sidecar.writes)
            .chain(&sidecar.registrations)
        {
            if self.index(*key).is_none() {
                return Err(LinkError::UnknownKey(*key));
            }
        }
        Ok(())
    }
}

/// Positions in DMB.proc_references are an 8-bit argument-source ABI domain,
/// distinct from the helper's canonical procedure table index.
#[derive(Clone, Debug)]
pub struct ArgumentSourceReferences {
    references: BTreeMap<Key, u8>,
}
impl ArgumentSourceReferences {
    pub fn assign(
        tables: &LinkTables,
        retained_count: usize,
        order: &[Key],
    ) -> Result<Self, LinkError> {
        let mut references = BTreeMap::new();
        for (ordinal, &key) in order.iter().enumerate() {
            if !matches!(key, Key::ArgumentSource { .. }) {
                return Err(LinkError::WrongTable(key));
            }
            if tables.index(key).is_none() {
                return Err(LinkError::UnknownKey(key));
            }
            let position = retained_count
                .checked_add(ordinal)
                .and_then(|value| u8::try_from(value).ok())
                .ok_or(LinkError::IndexOverflow(Table::Procedure))?;
            if references.insert(key, position).is_some() {
                return Err(LinkError::DuplicateOrder(key));
            }
        }
        let expected = tables
            .assignments()
            .keys()
            .filter(|key| matches!(key, Key::ArgumentSource { .. }))
            .count();
        if expected != references.len() {
            return Err(LinkError::IncompleteOrder(Table::Procedure));
        }
        Ok(Self { references })
    }
    pub fn index(&self, key: Key) -> Option<u8> {
        self.references.get(&key).copied()
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn list_allocation_skips_nullable_slot_without_changing_other_domains() {
        let mut inventory = LinkInventory::default();
        let keys = [Key::List(1), Key::List(2), Key::List(3)];
        for key in keys {
            inventory.entries.push(Entry {
                key,
                content: Arc::from([]),
            });
        }
        inventory.reserved_prefixes.insert(Table::List, 0xfffe);
        inventory.append_orders.insert(Table::List, keys.to_vec());
        let tables = LinkTables::build(inventory.clone()).unwrap();
        assert_eq!(
            keys.map(|key| tables.index(key).unwrap()),
            [0xfffe, 0x10000, 0x10001]
        );
        inventory.fixed.push((keys[0], 0xffff));
        assert_eq!(
            LinkTables::build(inventory).unwrap_err(),
            LinkError::ReservedIndex(Table::List, 0xffff)
        );
        assert!(!is_reserved_table_index(Table::Variable, 0xffff));
        assert!(!is_reserved_table_index(Table::Resource, 0xffff));
    }
    #[test]
    fn initialization_domains_do_not_alias_callable_or_map_occurrences() {
        use super::*;
        let owner = SymbolId::of("/obj/a");
        let keys = [
            Key::Initializer(InitializerIdentity::Global),
            Key::Initializer(InitializerIdentity::Class(owner)),
            Key::Initializer(InitializerIdentity::Map {
                source: 1,
                descriptor: 0,
            }),
            Key::Initializer(InitializerIdentity::Map {
                source: 1,
                descriptor: 1,
            }),
            Key::Initializer(InitializerIdentity::Map {
                source: 2,
                descriptor: 0,
            }),
            Key::Proc {
                owner,
                name: SymbolId::of("Initialize"),
                occurrence: 0,
            },
        ];
        assert_eq!(keys.into_iter().collect::<BTreeSet<_>>().len(), 6);
        assert!(keys.into_iter().all(|key| key.table() == Table::Procedure));
    }
    use super::*;
    use dm_ir::{Relocation, RelocationEncoding};
    fn sample_inventory() -> LinkInventory {
        let names = ["/datum/a", "read", "vars", "text", "/datum/a/modified"];
        let owner = SymbolId::of(names[0]);
        let name = SymbolId::of(names[1]);
        LinkInventory {
            spellings: names
                .iter()
                .map(|s| (SymbolId::of(s), Arc::from(s.as_bytes())))
                .collect(),
            entries: vec![
                Key::String(SymbolId::of("text")),
                Key::Type(owner),
                Key::Proc {
                    owner,
                    name,
                    occurrence: 0,
                },
                Key::Verb {
                    owner,
                    name,
                    occurrence: 0,
                },
                Key::Variable {
                    owner,
                    name: SymbolId::of("vars"),
                },
                Key::BuiltinGlobalVars,
                Key::Instance(SymbolId::of(names[4])),
            ]
            .into_iter()
            .map(|key| Entry {
                key,
                content: Arc::from([]),
            })
            .collect(),
            ..Default::default()
        }
    }
    #[test]
    fn independent_inventory_orders_produce_identical_tables() {
        let inventory = sample_inventory();
        let a = LinkTables::build(inventory.clone()).unwrap();
        let mut reversed = inventory;
        reversed.entries.reverse();
        reversed.spellings.reverse();
        let b = LinkTables::build(reversed).unwrap();
        assert_eq!(a.assignments(), b.assignments());
        let owner = SymbolId::of("/datum/a");
        let name = SymbolId::of("read");
        assert_ne!(
            a.index(Key::Proc {
                owner,
                name,
                occurrence: 0
            }),
            a.index(Key::Verb {
                owner,
                name,
                occurrence: 0
            })
        );
        assert_ne!(
            Key::BuiltinGlobalVars.table(),
            Key::Variable {
                owner,
                name: SymbolId::of("vars")
            }
            .table()
        );
    }

    #[test]
    fn string_allocation_skips_modifier_and_absent_slots_in_both_order_modes() {
        let count = 65540usize;
        let mut inventory = LinkInventory::default();
        let mut order = Vec::new();
        for ordinal in 0..count {
            let text = format!("field_{ordinal}");
            let id = SymbolId::of(&text);
            let bytes: Arc<[u8]> = Arc::from(text.as_bytes());
            inventory.spellings.push((id, Arc::clone(&bytes)));
            inventory.entries.push(Entry {
                key: Key::String(id),
                content: bytes,
            });
            order.push(Key::String(id));
        }
        for explicit in [false, true] {
            let mut input = inventory.clone();
            if explicit {
                input.orders.insert(Table::String, order.clone());
            } else {
                input.append_orders.insert(Table::String, order.clone());
            }
            let tables = LinkTables::build(input).unwrap();
            let mut next = 0u32;
            for key in &order {
                while is_reserved_string_index(next) {
                    next += 1;
                }
                assert_eq!(tables.index(*key), Some(next));
                assert!(!is_reserved_string_index(next));
                next += 1;
            }
            assert!(next > 0x10000);
        }
        let mut invalid = LinkInventory::default();
        let entry = inventory.entries[0].clone();
        invalid.spellings.push(inventory.spellings[0].clone());
        invalid.fixed.push((entry.key, 0xffe9));
        invalid.entries.push(entry);
        assert_eq!(
            LinkTables::build(invalid).unwrap_err(),
            LinkError::ReservedIndex(Table::String, 0xffe9)
        );
    }

    #[test]
    fn procedure_allocation_skips_native_absent_slot_in_both_order_modes() {
        let owner = SymbolId::of("/datum/owner");
        let name = SymbolId::of("repeated");
        let mut inventory = LinkInventory {
            spellings: vec![
                (owner, Arc::from(b"/datum/owner".as_slice())),
                (name, Arc::from(b"repeated".as_slice())),
            ],
            ..Default::default()
        };
        let mut order = Vec::new();
        for occurrence in 0..65536 {
            let key = Key::Proc {
                owner,
                name,
                occurrence,
            };
            inventory.entries.push(Entry {
                key,
                content: Arc::from([]),
            });
            order.push(key);
        }
        for explicit in [false, true] {
            let mut input = inventory.clone();
            if explicit {
                input.orders.insert(Table::Procedure, order.clone());
            } else {
                input.append_orders.insert(Table::Procedure, order.clone());
            }
            let tables = LinkTables::build(input).unwrap();
            for (ordinal, key) in order.iter().enumerate() {
                let expected = ordinal as u32 + u32::from(ordinal >= 0xffff);
                assert_eq!(tables.index(*key), Some(expected));
                assert!(!is_reserved_table_index(Table::Procedure, expected));
            }
            assert_eq!(tables.index(order[65535]), Some(0x10000));
        }
        let mut invalid = LinkInventory {
            spellings: inventory.spellings.clone(),
            ..Default::default()
        };
        invalid.entries.push(inventory.entries[0].clone());
        invalid.fixed.push((order[0], 0xffff));
        assert_eq!(
            LinkTables::build(invalid).unwrap_err(),
            LinkError::ReservedIndex(Table::Procedure, 0xffff)
        );
        assert!(!is_reserved_table_index(Table::Resource, 0xffff));
        assert!(!is_reserved_table_index(Table::Variable, 0xffff));
    }

    #[test]
    fn retained_prefixes_reserve_unnamed_rows_and_append_order_is_complete() {
        let mut inventory = sample_inventory();
        let fresh = Key::String(SymbolId::of("text"));
        inventory.reserved_prefixes.insert(Table::String, 7);
        inventory.append_orders.insert(Table::String, vec![fresh]);
        let linked = LinkTables::build(inventory.clone()).unwrap();
        assert_eq!(linked.index(fresh), Some(7));
        inventory.append_orders.insert(Table::String, vec![]);
        assert_eq!(
            LinkTables::build(inventory).unwrap_err(),
            LinkError::IncompleteOrder(Table::String)
        );
    }

    #[test]
    fn variable_records_do_not_shift_shared_footer_slots() {
        let mut inventory = sample_inventory();
        inventory.fixed.push((Key::BuiltinGlobalVars, 120));
        inventory
            .reserved_prefixes
            .insert(Table::VariableRecord, 121);
        let linked = LinkTables::build(inventory).unwrap();
        assert_eq!(linked.index(Key::BuiltinGlobalVars), Some(120));
        assert_eq!(
            linked.index(Key::Variable {
                owner: SymbolId::of("/datum/a"),
                name: SymbolId::of("vars")
            }),
            Some(0)
        );
    }
    #[test]
    fn explicit_orders_and_fixed_bindings_are_constraints() {
        let mut inventory = sample_inventory();
        let key = Key::Type(SymbolId::of("/datum/a"));
        inventory.fixed.push((key, 12));
        let a = LinkTables::build(inventory.clone()).unwrap();
        assert_eq!(a.index(key), Some(12));
        inventory.orders.insert(Table::Type, vec![key]);
        assert_eq!(
            LinkTables::build(inventory).unwrap_err(),
            LinkError::OrderConflictsFixed(key)
        );
        let mut inventory = sample_inventory();
        inventory.orders.insert(Table::Procedure, vec![]);
        assert_eq!(
            LinkTables::build(inventory).unwrap_err(),
            LinkError::IncompleteOrder(Table::Procedure)
        );
    }
    #[test]
    fn exact_slot_aliases_reject_hash_collision_and_unknown_refs() {
        let mut inventory = sample_inventory();
        let owner = SymbolId::of("/datum/a");
        let name = SymbolId::of("vars");
        let symbol = SymbolId::of("slot");
        inventory.slots = vec![
            SlotAlias {
                symbol,
                owner,
                name,
            },
            SlotAlias {
                symbol,
                owner,
                name: SymbolId::of("read"),
            },
        ];
        assert_eq!(
            LinkTables::build(inventory).unwrap_err(),
            LinkError::SlotCollision(symbol)
        );
        let tables = LinkTables::build(sample_inventory()).unwrap();
        let reference = SymRef::VariableSlot(symbol);
        let code = SymbolicCode::new(
            vec![0],
            vec![Relocation {
                offset: 0,
                reference,
                encoding: RelocationEncoding::Direct,
            }],
        )
        .unwrap();
        assert_eq!(
            tables.link(&code, &SourceBindings::default()).unwrap_err(),
            LinkError::UnknownReference(reference)
        );
    }
    #[test]
    fn packed_direct_and_source_operands_are_immutable() {
        let mut inventory = sample_inventory();
        let key = Key::Type(SymbolId::of("/datum/a"));
        inventory.fixed.push((key, 0x123456));
        let tables = LinkTables::build(inventory.clone()).unwrap();
        let code = SymbolicCode::new(
            vec![42, 0, 0, 0, 0],
            vec![
                Relocation {
                    offset: 1,
                    reference: SymRef::Type(SymbolId::of("/datum/a")),
                    encoding: RelocationEncoding::Direct,
                },
                Relocation {
                    offset: 2,
                    reference: SymRef::Type(SymbolId::of("/datum/a")),
                    encoding: RelocationEncoding::PackedValue24 { tag: 6 },
                },
                Relocation {
                    offset: 4,
                    reference: SymRef::LineDelta(4),
                    encoding: RelocationEncoding::Direct,
                },
            ],
        )
        .unwrap();
        let image = tables
            .link(
                &code,
                &SourceBindings {
                    first_line: 20,
                    ..Default::default()
                },
            )
            .unwrap();
        assert_eq!(&*image.words, &[42, 0x123456, 0x1206, 0x3456, 24]);
        assert_eq!(code.words(), &[42, 0, 0, 0, 0]);
        inventory.fixed = vec![(key, 0x1000000)];
        let oversized = LinkTables::build(inventory).unwrap();
        assert_eq!(
            oversized
                .link(&code, &SourceBindings::default())
                .unwrap_err(),
            LinkError::Relocation(RelocationError::PackedValueOverflow {
                offset: 2,
                value: 0x1000000
            })
        );
        assert_eq!(code.words(), &[42, 0, 0, 0, 0]);
    }
}
