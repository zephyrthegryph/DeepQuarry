//! Bounded real DMB composition: pinned engine records plus fresh global procs.
//! This intentionally rejects classes, arguments, shared-slot allocation, maps,
//! resources and helper procedures until their semantic writer contracts exist.
use crate::{lowering::Namespace, symbolic::FrozenBatch};
use byond_dmb::{
    dmb::{DmString, Dmb, Proc, Variable},
    ids::NONE,
};
use dm_codegen_byond::procedure_abi::Category;
use dm_ir::{SymbolId, SymbolTable};
use dm_link::Key;
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    io,
};

#[derive(Debug)]
pub enum CompositionError {
    Decode(io::Error),
    Unsupported(String),
    MissingSymbol(SymbolId),
    InvalidBinding(Key, u32),
    NonContiguous(String),
    Link(crate::symbolic::IntegrationError),
}
fn unsupported(message: impl Into<String>) -> CompositionError {
    CompositionError::Unsupported(message.into())
}
fn text(symbols: &SymbolTable, id: SymbolId) -> Result<&str, CompositionError> {
    symbols.text(id).ok_or(CompositionError::MissingSymbol(id))
}
fn proc_path(
    symbols: &SymbolTable,
    owner: SymbolId,
    name: SymbolId,
) -> Result<String, CompositionError> {
    let owner = text(symbols, owner)?;
    let name = text(symbols, name)?;
    Ok(if owner == "/" {
        format!("/proc/{name}")
    } else {
        format!("{owner}/proc/{name}")
    })
}
/// Every retained linker binding is checked against the pinned wire artifact.
/// VM Variable keys index the global footer, NOT `Dmb.variables`. This bounded
/// writer accepts global slots only; declaring-owner statics need a later proof.
fn validate_binding(
    dmb: &Dmb,
    key: Key,
    index: u32,
    symbols: &SymbolTable,
) -> Result<(), CompositionError> {
    let valid = match key {
        Key::String(symbol) => dmb.string(index) == Some(text(symbols, symbol)?.as_bytes()),
        Key::Type(symbol) => {
            dmb.classes
                .get(index as usize)
                .and_then(|class| dmb.string(class.path_string_id()))
                == Some(text(symbols, symbol)?.as_bytes())
        }
        Key::Proc {
            owner,
            name,
            occurrence: 0,
        } => {
            dmb.procs
                .get(index as usize)
                .and_then(|proc| dmb.string(proc.strings[0]))
                == Some(proc_path(symbols, owner, name)?.as_bytes())
        }
        Key::Variable { owner, name } if text(symbols, owner)? == "/" => {
            dmb.lists
                .get(dmb.variable_footer as usize)
                .and_then(|footer| footer.get(index as usize * 2))
                .and_then(|id| dmb.variables.get(*id as usize))
                .and_then(|record| dmb.string(record.name))
                == Some(text(symbols, name)?.as_bytes())
        }
        _ => return Err(unsupported(format!("unproven retained binding {key:?}"))),
    };
    if valid {
        Ok(())
    } else {
        Err(CompositionError::InvalidBinding(key, index))
    }
}
fn append_list(dmb: &mut Dmb, words: Vec<u32>) -> Result<u32, CompositionError> {
    let id = u32::try_from(dmb.lists.len()).map_err(|_| unsupported("list count overflow"))?;
    dmb.lists.push(words);
    Ok(id)
}
struct StringIndex {
    buckets: HashMap<u128, Vec<u32>>,
}
impl StringIndex {
    fn build(dmb: &Dmb) -> Result<Self, CompositionError> {
        let mut result = Self {
            buckets: HashMap::new(),
        };
        for (index, string) in dmb.strings.iter().enumerate() {
            let id = u32::try_from(index).map_err(|_| unsupported("string count overflow"))?;
            result
                .buckets
                .entry(xxhash_rust::xxh3::xxh3_128(&string.data))
                .or_default()
                .push(id);
        }
        Ok(result)
    }
    fn intern(&mut self, dmb: &mut Dmb, data: &[u8]) -> Result<u32, CompositionError> {
        let hash = xxhash_rust::xxh3::xxh3_128(data);
        if let Some(ids) = self.buckets.get(&hash) {
            for &id in ids {
                if dmb.string(id) == Some(data) {
                    return Ok(id);
                }
            }
        }
        let id =
            u32::try_from(dmb.strings.len()).map_err(|_| unsupported("string count overflow"))?;
        let chunks =
            u16::try_from(data.len() / 65535).map_err(|_| unsupported("string too large"))?;
        dmb.strings.push(DmString {
            data: data.to_vec(),
            long_chunks: chunks,
        });
        self.buckets.entry(hash).or_default().push(id);
        Ok(id)
    }
}
/// Validate the complete source declaration admission before composing a program.
/// The artifact-only entry below does not claim it consumed a source program.
pub fn compose_global_program(
    engine_bytes: &[u8],
    batch: &FrozenBatch,
    frontend: &dm_tree::frontend::ColdFrontend,
) -> Result<Vec<u8>, CompositionError> {
    if frontend
        .plan
        .items
        .iter()
        .any(|item| matches!(item, dm_preprocess::regions::OrderedItem::NonText { .. }))
    {
        return Err(unsupported("source maps and skins are not admitted"));
    }
    fn admit(items: &[dm_syntax::Item]) -> Result<(), CompositionError> {
        for item in items {
            match item.kind {
                dm_syntax::ItemKind::Proc => {}
                dm_syntax::ItemKind::Type
                    if matches!(item.header.trim(), "/" | "proc" | "/proc") =>
                {
                    admit(&item.children)?
                }
                _ => {
                    return Err(unsupported(format!(
                        "source declaration not admitted: {}",
                        item.header
                    )))
                }
            }
        }
        Ok(())
    }
    admit(&frontend.syntax.items)?;
    let covered: HashSet<_> = batch
        .units
        .iter()
        .map(|unit| unit.lowered.origin.declaration)
        .collect();
    if covered.len() != batch.units.len()
        || frontend.bodies.len() != batch.units.len()
        || frontend
            .bodies
            .iter()
            .any(|body| !covered.contains(&body.declaration))
    {
        return Err(unsupported(
            "source procedure coverage does not match lowered artifacts",
        ));
    }
    compose_global_fixture(engine_bytes, batch, frontend.snapshot.tree.symbols())
}
/// Compose new global procedures into a pinned immutable engine image. Symbolic
/// table assignments are never silently rebased. Unsupported source table keys,
/// metadata, overrides and occupied indexes are explicit errors.
///
/// Returned bytes are a real validated DMB, not a complete production compiler.
/// Resources/maps/world configuration remain exactly the pinned engine artifact.
pub fn compose_global_fixture(
    engine_bytes: &[u8],
    batch: &FrozenBatch,
    symbols: &SymbolTable,
) -> Result<Vec<u8>, CompositionError> {
    let mut dmb = Dmb::from_bytes(engine_bytes).map_err(CompositionError::Decode)?;
    dmb.validate_references()
        .map_err(CompositionError::Decode)?;
    let engine_strings = dmb.strings.len();
    let engine_procs = dmb.procs.len();
    let mut strings = BTreeMap::new();
    let mut procs = BTreeMap::new();
    for (&key, &index) in batch.tables.assignments() {
        match key {
            Key::String(_) if (index as usize) >= engine_strings => {
                let bytes = batch
                    .tables
                    .content(key)
                    .ok_or(CompositionError::InvalidBinding(key, index))?;
                strings.insert(index, bytes.to_vec());
            }
            Key::Proc {
                owner,
                name,
                occurrence,
            } if (index as usize) >= engine_procs => {
                if text(symbols, owner)? != "/" || occurrence != 0 {
                    return Err(unsupported("only fresh global procedures are supported"));
                }
                procs.insert(index, (owner, name));
            }
            _ => validate_binding(&dmb, key, index, symbols)?,
        }
    }
    for (index, data) in strings {
        if index as usize != dmb.strings.len() {
            return Err(CompositionError::NonContiguous(
                "string table indexes".into(),
            ));
        }
        let chunks =
            u16::try_from(data.len() / 65535).map_err(|_| unsupported("string too large"))?;
        dmb.strings.push(DmString {
            data,
            long_chunks: chunks,
        });
    }
    let mut string_index = StringIndex::build(&dmb)?;
    if procs.len() != batch.units.len() {
        return Err(unsupported("every unit must be one fresh global procedure"));
    }
    let mut units = BTreeMap::new();
    for (index, unit) in batch.units.iter().enumerate() {
        let identity = unit.lowered.identity;
        if identity.namespace != Namespace::Proc
            || identity.occurrence != 0
            || units
                .insert((identity.owner, identity.name), (index, unit))
                .is_some()
        {
            return Err(unsupported("duplicate or unsupported procedure artifact"));
        }
    }
    for (index, (owner, name)) in procs {
        if index as usize != dmb.procs.len() {
            return Err(CompositionError::NonContiguous(
                "procedure table indexes".into(),
            ));
        }
        let &(unit_index, unit) = units
            .get(&(owner, name))
            .ok_or_else(|| unsupported("missing global procedure artifact"))?;
        let abi = unit
            .lowered
            .abi
            .as_ref()
            .ok_or_else(|| unsupported("procedure ABI was not authoritative"))?;
        let proc = &unit.lowered.code.procedure;
        if !proc.argument_names.is_empty()
            || !abi.argument_sources.is_empty()
            || !abi.source_helpers.is_empty()
        {
            return Err(unsupported(
                "arguments and argument-source helpers are not supported",
            ));
        }
        if proc.local_count as usize != proc.local_names.len() {
            return Err(unsupported("local metadata count mismatch"));
        }
        let linked = batch
            .link_unit(unit_index, &Default::default())
            .map_err(CompositionError::Link)?;
        let code_id = append_list(&mut dmb, linked.words.to_vec())?;
        let mut locals = Vec::new();
        for name in &proc.local_names {
            let name_id = string_index.intern(&mut dmb, name.as_bytes())?;
            let variable_id = u32::try_from(dmb.variables.len())
                .map_err(|_| unsupported("variable record overflow"))?;
            dmb.variables.push(Variable {
                kind: 0,
                value: 0,
                name: name_id,
            });
            locals.push(variable_id);
        }
        let locals_id = append_list(&mut dmb, locals)?;
        let args_id = append_list(&mut dmb, Vec::new())?;
        let path = proc_path(symbols, owner, name)?;
        let path_id = string_index.intern(&mut dmb, path.as_bytes())?;
        let default_display = text(symbols, name)?.replace('_', " ");
        let display = abi
            .layout
            .display_name
            .as_deref()
            .unwrap_or(default_display.as_bytes());
        let display_id = string_index.intern(&mut dmb, display)?;
        let description_id = match &abi.layout.description {
            Some(value) => string_index.intern(&mut dmb, value)?,
            None => NONE,
        };
        let category_id = match &abi.layout.category {
            Category::Text(value) => string_index.intern(&mut dmb, value)?,
            Category::Default | Category::Null => NONE,
        };
        let (flags, extended_flags) = abi.layout.encoded_flags();
        dmb.procs.push(Proc {
            strings: [path_id, display_id, description_id, category_id],
            source_parameter: abi.layout.source_parameter,
            source_kind: abi.layout.source_kind,
            flags,
            extended_flags,
            code_locals_args: [code_id, locals_id, args_id],
        });
    }
    let mut external = false;
    let mut debug = false;
    for index in 0..dmb.procs.len() {
        if dmb.is_reserved_proc_slot(index) {
            continue;
        }
        let words = dmb
            .proc_code_words(index)
            .ok_or_else(|| unsupported("missing procedure code"))?;
        let instructions = byond_dmb::bytecode::decode(words)
            .map_err(|e| unsupported(format!("invalid composed bytecode {e:?}")))?;
        for instruction in instructions {
            external |= matches!(instruction.name, "LoadExt" | "CallExt");
            debug |= matches!(instruction.name, "DbgFile" | "DbgLine");
        }
    }
    if external {
        dmb.header.flags |= 0x2000_0000;
    }
    if debug {
        dmb.header.flags |= 0x0002_0000;
    }
    // Choose the wide table ABI explicitly for the composed model. No instruction
    // operand is guessed/rebased; shared symbolic linking already fixed those.
    dmb.header.flags |= 0x4000_0000;
    dmb.validate_references()
        .map_err(CompositionError::Decode)?;
    let bytes = dmb.to_bytes().map_err(CompositionError::Decode)?;
    Dmb::from_bytes(&bytes)
        .and_then(|decoded| decoded.validate_references())
        .map_err(CompositionError::Decode)?;
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn real_pinned_image_composes_and_retains_external_feature_bit() {
        let engine = include_bytes!(
            "../../../fixtures/translation/client_header_probe/feature_load_ext.native.bin"
        );
        let batch = FrozenBatch {
            units: vec![],
            tables: dm_link::LinkTables::build(Default::default()).unwrap(),
        };
        let bytes = compose_global_fixture(engine, &batch, &SymbolTable::default()).unwrap();
        let decoded = Dmb::from_bytes(&bytes).unwrap();
        decoded.validate_references().unwrap();
        assert_ne!(decoded.header.flags & 0x2000_0000, 0);
        assert_eq!(
            decoded.procs.len(),
            Dmb::from_bytes(engine).unwrap().procs.len()
        );
    }
    #[test]
    fn canonical_indexes_cannot_overwrite_pinned_strings() {
        let engine = include_bytes!(
            "../../../fixtures/translation/client_header_probe/feature_load_ext.native.bin"
        );
        let mut symbols = SymbolTable::default();
        let wrong = symbols.intern("not-the-engine-string").unwrap();
        let inventory = dm_link::LinkInventory {
            entries: vec![dm_link::Entry {
                key: Key::String(wrong),
                content: std::sync::Arc::from(b"not-the-engine-string".as_slice()),
            }],
            spellings: vec![(
                wrong,
                std::sync::Arc::from(b"not-the-engine-string".as_slice()),
            )],
            ..Default::default()
        };
        let batch = FrozenBatch {
            units: vec![],
            tables: dm_link::LinkTables::build(inventory).unwrap(),
        };
        assert!(matches!(
            compose_global_fixture(engine, &batch, &symbols),
            Err(CompositionError::InvalidBinding(Key::String(_), 0))
        ));
    }
}
