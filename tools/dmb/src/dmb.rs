//! BYOND 516 compiled-world container reader and writer.
//!
//! Table boundaries and field widths are validated on DeepQuarry's v516 DMB.
//! Unknown fields retain their exact numeric values. Procedure bytecode is
//! stored as list words; semantic opcode decoding is a separate layer.
use crate::hash::nqcrc;
use crate::ids::{ResourceId, NONE};
use std::collections::{HashMap, HashSet};
use std::io::{self, ErrorKind};

#[path = "dmb_codec.rs"]
mod codec;
use codec::*;
#[path = "dmb_records.rs"]
mod records;
use records::crypt_string;
#[path = "dmb_write.rs"]
mod writing;
pub use records::{
    mob_sight, Class, ClassInterface, DmString, GridRun, Header, Instance, MapObject, MobType,
    Proc, ProcSource, ResourceRef, Variable, World, WorldViewEncoding,
};
pub use writing::EncodedDmb;
#[path = "dmb_lists.rs"]
mod word_lists;
pub use word_lists::{EncodedListRows, WordLists};
#[path = "dmb_resources.rs"]
mod resource_attachment;
pub use resource_attachment::{attach_resource_refs, ResourceAttachment, ResourceLookup};

#[derive(Clone, Debug, PartialEq)]
pub struct Dmb {
    pub header: Header,
    pub dimensions: [u16; 3],
    pub grid: Vec<GridRun>,
    pub classes: Vec<Class>,
    pub mobs: Vec<MobType>,
    pub strings: Vec<DmString>,
    pub lists: WordLists,
    pub procs: Vec<Proc>,
    pub variables: Vec<Variable>,
    /// List ID of (variable ID, declaration flags) pairs for globals.
    pub variable_footer: u32,
    pub proc_references: Vec<u32>,
    pub instances: Vec<Instance>,
    pub map_objects: Vec<MapObject>,
    pub world: World,
    pub resources: Vec<ResourceRef>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ProcArgument {
    /// DM `as` type restriction bits.
    pub type_flags: u32,
    /// Low byte identifies a `in` value source; the next byte is its argument.
    pub value_source: u32,
    /// VarID of the declared parameter (whose variable record owns the name).
    pub variable_id: u32,
    /// Zero in all arguments observed in the two DeepQuarry builds.
    pub reserved: u32,
}

pub mod argument_type {
    pub const MOB: u32 = 0x0001;
    pub const OBJ: u32 = 0x0002;
    pub const TEXT: u32 = 0x0004;
    pub const NUM: u32 = 0x0008;
    pub const FILE: u32 = 0x0010;
    pub const TURF: u32 = 0x0020;
    pub const NULL: u32 = 0x0080;
    pub const AREA: u32 = 0x0100;
    pub const ICON: u32 = 0x0200;
    pub const SOUND: u32 = 0x0400;
    pub const MESSAGE: u32 = 0x0800;
    pub const ANYTHING: u32 = 0x1000;
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ClassInitialValue {
    pub variable_id: u32,
    pub value: crate::operands::Value,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ClassBuiltinOverride {
    pub name_string_id: u32,
    pub value: crate::operands::Value,
}

impl ProcArgument {
    pub fn value_source_kind(&self) -> u8 {
        self.value_source as u8
    }
    pub fn value_source_parameter(&self) -> u8 {
        (self.value_source >> 8) as u8
    }
    /// Index into DMB's generated argument-expression procedure table when
    /// the source code's low byte is 0x40 (`arg in expression`).
    pub fn source_expression_index(&self) -> Option<u8> {
        (self.value_source_kind() == 0x40).then(|| self.value_source_parameter())
    }
}

impl Dmb {
    /// Checks the typed cross-table references needed to construct a world.
    /// Generic list contents and bytecode words have context-specific meanings.
    /// Remove unreachable list records and intern identical immutable word arrays.
    /// Call only after all procedure bodies and metadata lists have been finalized.
    /// List words contain values, procedure/variable IDs, or bytecode, never list IDs.
    pub fn compact_lists(&mut self) -> io::Result<usize> {
        self.validate_references()?;
        let old_count = self.lists.len();
        let mut live = vec![false; old_count];
        let mut mark = |id: u32| {
            if id != NONE {
                live[id as usize] = true;
            }
        };
        for class in &self.classes {
            for id in [
                class.verb_list_id(),
                class.proc_list_id(),
                class.initialized_variable_list_id(),
                class.defining_variable_list_id(),
                class.overriding_variable_list_id(),
            ] {
                mark(id);
            }
        }
        for proc in &self.procs {
            for &id in &proc.code_locals_args {
                mark(id);
            }
        }
        for run in &self.grid {
            mark(run.contents);
        }
        mark(self.world.ids[3]);
        mark(self.variable_footer);
        let mut remap = vec![NONE; old_count];
        use std::hash::{Hash, Hasher};
        let mut intern = std::collections::HashMap::<u64, Vec<u32>>::new();
        let mut lists = WordLists::default();
        for (old, words) in self.lists.iter().enumerate() {
            if !live[old] {
                continue;
            }
            let mut hasher = std::collections::hash_map::DefaultHasher::new();
            words.hash(&mut hasher);
            let bucket = intern.entry(hasher.finish()).or_default();
            let id = if let Some(&id) = bucket.iter().find(|&&id| lists[id as usize] == *words) {
                id
            } else {
                // 0xffff is NONE even when the table uses 32-bit object IDs.
                if lists.len() == NONE as usize {
                    lists.push(Vec::new());
                }
                let id =
                    u32::try_from(lists.len()).map_err(|_| invalid("list table exceeds u32"))?;
                lists.push_shared(std::sync::Arc::clone(self.lists.shared(old).unwrap()));
                bucket.push(id);
                id
            };
            remap[old] = id;
        }
        let map = |id: &mut u32| {
            if *id != NONE {
                *id = remap[*id as usize];
            }
        };
        for class in &mut self.classes {
            for index in [0, 1, 3, 4] {
                map(&mut class.lists_and_procs[index]);
            }
            map(&mut class.overrides);
        }
        for proc in &mut self.procs {
            for id in &mut proc.code_locals_args {
                map(id);
            }
        }
        for run in &mut self.grid {
            map(&mut run.contents);
        }
        map(&mut self.world.ids[3]);
        map(&mut self.variable_footer);
        self.lists = lists;
        self.validate_references()?;
        Ok(old_count.saturating_sub(self.lists.len()))
    }

    /// Validate list mutations against an already validated image. The caller
    /// must prove all non-list tables and list count are unchanged. Arbitrary
    /// structural edits require `validate_references` instead.
    pub fn validate_changed_lists(&self, changed: &[u32]) -> io::Result<()> {
        if changed.is_empty() {
            return Ok(());
        }
        let changed: std::collections::HashSet<u32> = changed.iter().copied().collect();
        if changed.iter().any(|&id| id as usize >= self.lists.len()) {
            return Err(invalid("changed list ID out of range"));
        }
        // Class/global payloads have several distinct schemas. These edits are
        // uncommon and keep the complete validator as their correctness gate.
        if changed.contains(&self.variable_footer)
            || changed.contains(&self.world.ids[3])
            || self.classes.iter().any(|class| {
                [
                    class.lists_and_procs[0],
                    class.lists_and_procs[1],
                    class.lists_and_procs[3],
                    class.lists_and_procs[4],
                    class.overrides,
                ]
                .iter()
                .any(|id| changed.contains(id))
            })
        {
            return self.validate_references();
        }
        for (index, proc_) in self.procs.iter().enumerate() {
            if self.is_reserved_proc_slot(index) {
                continue;
            }
            if changed.contains(&proc_.code_locals_args[1]) {
                let locals = self
                    .lists
                    .get(proc_.code_locals_args[1] as usize)
                    .ok_or_else(|| invalid("proc locals list missing"))?;
                if locals
                    .iter()
                    .any(|&id| id != NONE && id as usize >= self.variables.len())
                {
                    return Err(invalid("proc locals list contains invalid VarID"));
                }
            }
            if changed.contains(&proc_.code_locals_args[2]) {
                let mut arguments = self
                    .proc_arguments_iter(index)
                    .ok_or_else(|| invalid("malformed proc argument list"))?;
                if arguments.clone().any(|arg| {
                    arg.variable_id != NONE && arg.variable_id as usize >= self.variables.len()
                }) {
                    return Err(invalid("proc argument contains invalid VarID"));
                }
                if arguments.any(|arg| {
                    arg.source_expression_index().is_some_and(|reference| {
                        usize::from(reference) >= self.proc_references.len()
                    })
                }) {
                    return Err(invalid("proc argument expression reference out of range"));
                }
            }
        }
        Ok(())
    }

    pub fn validate_references(&self) -> io::Result<()> {
        fn in_table(id: u32, len: usize) -> bool {
            id == NONE || (id as usize) < len
        }
        for (class_index, class) in self.classes.iter().enumerate() {
            if !in_table(class.path_string_id(), self.strings.len())
                || !in_table(class.parent_class_id(), self.classes.len())
                || !in_table(class.name_string_id(), self.strings.len())
                || !in_table(class.description_string_id(), self.strings.len())
                || !in_table(class.icon_resource_id(), self.resources.len())
                || !in_table(class.icon_state_string_id(), self.strings.len())
                || !in_table(class.text, self.strings.len())
                || !in_table(class.maptext, self.strings.len())
                || !in_table(class.suffix, self.strings.len())
                || !in_table(class.lists_and_procs[0], self.lists.len())
                || !in_table(class.lists_and_procs[1], self.lists.len())
                || !in_table(class.lists_and_procs[2], self.procs.len())
                || !in_table(class.lists_and_procs[3], self.lists.len())
                || !in_table(class.lists_and_procs[4], self.lists.len())
                || !in_table(class.overrides, self.lists.len())
            {
                return Err(invalid("class cross-table reference out of range"));
            }
            for list_id in [class.verb_list_id(), class.proc_list_id()] {
                if list_id != NONE
                    && self.lists[list_id as usize]
                        .iter()
                        .any(|&id| !in_table(id, self.procs.len()))
                {
                    return Err(invalid("class procedure list contains invalid ProcID"));
                }
            }
            if class.initialized_variable_list_id() != NONE {
                let values = self
                    .class_initial_values(class_index)
                    .ok_or_else(|| invalid("malformed class initial value list"))?;
                if values
                    .iter()
                    .any(|v| !in_table(v.variable_id, self.variables.len()))
                {
                    return Err(invalid("class initial value has invalid VarID"));
                }
            }
            if class.defining_variable_list_id() != NONE {
                let values = self
                    .class_variable_declarations(class_index)
                    .ok_or_else(|| invalid("malformed class declaration list"))?;
                if values.iter().any(|v| !in_table(v.0, self.variables.len())) {
                    return Err(invalid("class declaration has invalid VarID"));
                }
            }
            if class.overriding_variable_list_id() != NONE {
                let values = self
                    .class_builtin_overrides(class_index)
                    .ok_or_else(|| invalid("malformed class builtin override list"))?;
                if values
                    .iter()
                    .any(|v| !in_table(v.name_string_id, self.strings.len()))
                {
                    return Err(invalid("class builtin override has invalid StringID"));
                }
            }
        }
        for mob in &self.mobs {
            if !in_table(mob.class, self.classes.len()) || !in_table(mob.key, self.strings.len()) {
                return Err(invalid("mob cross-table reference out of range"));
            }
        }
        for (proc_index, proc) in self.procs.iter().enumerate() {
            // Native wide tables reserve the nullable ProcID at FFFF as an
            // empty record. Its list references are absent by construction.
            if self.is_reserved_proc_slot(proc_index) {
                continue;
            }
            if proc_index == NONE as usize
                || (proc.strings == [NONE; 4] && proc.code_locals_args == [NONE; 3])
            {
                return Err(invalid("invalid reserved procedure record"));
            }
            if proc
                .strings
                .iter()
                .any(|&id| !in_table(id, self.strings.len()))
                || proc
                    .code_locals_args
                    .iter()
                    .any(|&id| !in_table(id, self.lists.len()))
            {
                return Err(invalid("proc cross-table reference out of range"));
            }
            let locals = self
                .lists
                .get(proc.code_locals_args[1] as usize)
                .ok_or_else(|| invalid("proc locals list missing"))?;
            if locals.iter().any(|&id| !in_table(id, self.variables.len())) {
                return Err(invalid("proc locals list contains invalid VarID"));
            }
            let mut arguments = self
                .proc_arguments_iter(proc_index)
                .ok_or_else(|| invalid("malformed proc argument list"))?;
            if arguments
                .clone()
                .any(|arg| !in_table(arg.variable_id, self.variables.len()))
            {
                return Err(invalid("proc argument contains invalid VarID"));
            }
            if arguments.any(|arg| {
                arg.source_expression_index()
                    .is_some_and(|index| usize::from(index) >= self.proc_references.len())
            }) {
                return Err(invalid("proc argument expression reference out of range"));
            }
        }
        for variable in &self.variables {
            if !in_table(variable.name, self.strings.len()) {
                return Err(invalid("variable name out of range"));
            }
        }
        for instance in &self.instances {
            let descriptors = if instance.kind == 8 {
                self.mobs.len()
            } else {
                self.classes.len()
            };
            if !in_table(instance.class, descriptors)
                || !in_table(instance.initializer, self.procs.len())
            {
                return Err(invalid("instance cross-table reference out of range"));
            }
        }
        for run in &self.grid {
            if !in_table(run.turf, self.instances.len())
                || !in_table(run.area, self.instances.len())
                || !in_table(run.contents, self.lists.len())
            {
                return Err(invalid("grid cross-table reference out of range"));
            }
        }
        for object in &self.map_objects {
            if !in_table(object.instance, self.instances.len()) {
                return Err(invalid("map object instance out of range"));
            }
        }
        for &id in &self.proc_references {
            if !in_table(id, self.procs.len()) {
                return Err(invalid("procedure reference out of range"));
            }
        }
        if !in_table(self.variable_footer, self.lists.len()) {
            return Err(invalid("global declaration list out of range"));
        }
        let w = &self.world;
        if !in_table(w.ids[0], self.mobs.len())
            || !in_table(w.ids[1], self.classes.len())
            || !in_table(w.ids[2], self.classes.len())
            || !in_table(w.ids[3], self.lists.len())
            || !in_table(w.ids[4], self.procs.len())
            || !in_table(w.ids[5], self.strings.len())
            || !in_table(w.ids[6], self.strings.len())
            || !in_table(w.client, self.classes.len())
            || !in_table(w.image, self.classes.len())
            || !in_table(w.client_script, self.strings.len())
            || w.client_script_files
                .iter()
                .any(|&id| id as usize >= self.resources.len())
            || !in_table(w.hub_password, self.strings.len())
            || !in_table(w.server_name, self.strings.len())
            || w.command_ids
                .iter()
                .any(|&id| !in_table(id, self.strings.len()))
            || !in_table(w.hub_channel_skin[0], self.strings.len())
            || !in_table(w.hub_channel_skin[1], self.strings.len())
            || !in_table(w.hub_channel_skin[2], self.resources.len())
        {
            return Err(invalid("world cross-table reference out of range"));
        }
        Ok(())
    }
    /// Installs new code for one procedure in a fresh list-table slot.
    /// Existing lists may be shared, so they are never modified in place.
    pub fn replace_proc_code(
        &mut self,
        proc_index: usize,
        instructions: &[crate::bytecode::Instruction],
    ) -> io::Result<()> {
        if proc_index >= self.procs.len() {
            return Err(io::Error::new(
                ErrorKind::InvalidInput,
                "proc index out of range",
            ));
        }
        let words = crate::bytecode::encode(instructions);
        if words.len() > u16::MAX as usize {
            return Err(io::Error::new(
                ErrorKind::InvalidInput,
                "procedure code exceeds list limit",
            ));
        }
        crate::bytecode::decode(&words)
            .map_err(|error| io::Error::new(ErrorKind::InvalidInput, error.reason))?;
        if self.lists.len() == NONE as usize {
            self.lists.push(Vec::new());
        }
        let list_id =
            u32::try_from(self.lists.len()).map_err(|_| invalid("list ID exceeds u32"))?;
        self.lists.push(words);
        self.procs[proc_index].code_locals_args[0] = list_id;
        if self.lists.len() > u16::MAX as usize {
            self.header.flags |= 0x4000_0000;
        }
        Ok(())
    }

    pub fn string(&self, id: u32) -> Option<&[u8]> {
        self.strings
            .get(id as usize)
            .map(|entry| entry.data.as_slice())
    }

    /// Whether this is the exact nullable ProcID record reserved by native wide tables.
    pub fn is_reserved_proc_slot(&self, index: usize) -> bool {
        self.procs.get(index).is_some_and(|proc| {
            index == NONE as usize
                && proc.strings == [NONE; 4]
                && proc.source_parameter == 255
                && proc.source_kind == 0
                && proc.flags == 4
                && proc.extended_flags.is_none()
                && proc.code_locals_args == [NONE; 3]
        })
    }

    pub fn proc_code_words(&self, proc_index: usize) -> Option<&[u32]> {
        if self.is_reserved_proc_slot(proc_index) {
            return None;
        }
        let list_id = self.procs.get(proc_index)?.code_locals_args[0];
        self.lists.get(list_id as usize).map(Vec::as_slice)
    }

    pub fn proc_arguments(&self, proc_index: usize) -> Option<Vec<ProcArgument>> {
        self.proc_arguments_iter(proc_index).map(Iterator::collect)
    }

    /// Decode argument records directly from the retained list without allocating
    /// a second argument vector. Cloning the iterator preserves validation order.
    pub fn proc_arguments_iter(
        &self,
        proc_index: usize,
    ) -> Option<impl ExactSizeIterator<Item = ProcArgument> + Clone + '_> {
        if self.is_reserved_proc_slot(proc_index) {
            return None;
        }
        let list_id = self.procs.get(proc_index)?.code_locals_args[2];
        let words = self.lists.get(list_id as usize)?;
        if words.len() % 4 != 0 {
            return None;
        }
        Some(words.chunks_exact(4).map(|arg| ProcArgument {
            type_flags: arg[0],
            value_source: arg[1],
            variable_id: arg[2],
            reserved: arg[3],
        }))
    }

    pub fn argument_source_proc_id(&self, argument: &ProcArgument) -> Option<u32> {
        self.proc_references
            .get(usize::from(argument.source_expression_index()?))
            .copied()
    }

    /// Variable IDs and declaration flags defined on this class itself.
    /// Inherited declarations are stored on parent classes.
    pub fn class_variable_declarations(&self, class_index: usize) -> Option<Vec<(u32, u32)>> {
        let list_id = self.classes.get(class_index)?.defining_variable_list_id();
        if list_id == NONE {
            return None;
        }
        let words = self.lists.get(list_id as usize)?;
        if words.len() % 2 != 0 {
            return None;
        }
        Some(
            words
                .chunks_exact(2)
                .map(|pair| (pair[0], pair[1]))
                .collect(),
        )
    }

    /// Initial variable assignments attached to this class. Each entry is a
    /// variable ID followed by the same tagged value used in bytecode.
    pub fn class_initial_values(&self, class_index: usize) -> Option<Vec<ClassInitialValue>> {
        let list_id = self
            .classes
            .get(class_index)?
            .initialized_variable_list_id();
        if list_id == NONE {
            return None;
        }
        let words = self.lists.get(list_id as usize)?;
        let mut result = Vec::new();
        let mut at = 0usize;
        while at < words.len() {
            let variable_id = *words.get(at)?;
            let (value, len) = crate::operands::Value::decode(&words[at + 1..]).ok()?;
            result.push(ClassInitialValue { variable_id, value });
            at += len + 1;
        }
        Some(result)
    }

    /// Builtin properties without dedicated class fields. The key is a
    /// StringID, followed by the same tagged value representation as above.
    pub fn class_builtin_overrides(&self, class_index: usize) -> Option<Vec<ClassBuiltinOverride>> {
        let list_id = self.classes.get(class_index)?.overriding_variable_list_id();
        if list_id == NONE {
            return None;
        }
        let words = self.lists.get(list_id as usize)?;
        let mut result = Vec::new();
        let mut at = 0usize;
        while at < words.len() {
            let name_string_id = *words.get(at)?;
            let (value, len) = crate::operands::Value::decode(&words[at + 1..]).ok()?;
            result.push(ClassBuiltinOverride {
                name_string_id,
                value,
            });
            at += len + 1;
        }
        Some(result)
    }

    /// Global variable declaration flags: 1 = global, 2 = const.
    pub fn global_variable_flags(&self) -> Option<Vec<(u32, u32)>> {
        let words = self.lists.get(self.variable_footer as usize)?;
        if words.len() % 2 != 0 {
            return None;
        }
        Some(
            words
                .chunks_exact(2)
                .map(|pair| (pair[0], pair[1]))
                .collect(),
        )
    }

    /// Finds DMB cache-file references absent from the parsed RSC archive.
    pub fn missing_resources(&self, archive: &[crate::rsc::Entry]) -> Vec<ResourceRef> {
        let present: HashSet<(u32, u8)> = archive
            .iter()
            .filter_map(|entry| match entry {
                crate::rsc::Entry::Named(resource) => Some((resource.id, resource.kind)),
                crate::rsc::Entry::Opaque { .. } => None,
            })
            .collect();
        self.resources
            .iter()
            .filter(|resource| !present.contains(&(resource.id, resource.kind)))
            .cloned()
            .collect()
    }

    /// Reads a BYOND 516 DMB. Older or newer versions must be implemented
    /// deliberately; their version-gated field layouts differ.
    pub fn from_bytes(data: &[u8]) -> io::Result<Self> {
        Self::from_bytes_with_list_spans(data).map(|(dmb, _)| dmb)
    }

    /// Decode while recording exact serialized list records. List words use
    /// object-width encoding and have no position-dependent cipher or offsets.
    pub fn from_bytes_with_list_spans(
        data: &[u8],
    ) -> io::Result<(Self, Vec<std::ops::Range<usize>>)> {
        let mut r = Reader {
            data,
            at: 0,
            object_size: 4,
            compatibility_version: 516,
        };
        let first_line = r.line()?;
        let (executor_line, version_line) = if first_line.starts_with(b"#!") {
            let mut prefix = first_line;
            loop {
                let line = r.line()?;
                if line == b"world bin v516\n" && r.data[r.at..].starts_with(b"min compatibility v")
                {
                    break (Some(prefix), line);
                }
                prefix.extend_from_slice(&line);
            }
        } else {
            (None, first_line)
        };
        let compatibility_line = r.line()?;
        if version_line != b"world bin v516\n"
            || !compatibility_line.starts_with(b"min compatibility v")
        {
            return Err(invalid("only BYOND v516 is supported"));
        }
        let flags = r.u32()?;
        let extended_flags = (flags & 0x8000_0000 != 0).then(|| r.u32()).transpose()?;
        r.object_size = if flags & 0x4000_0000 != 0 { 4 } else { 2 };
        r.compatibility_version = compatibility_version(&compatibility_line)?;
        let header = Header {
            executor_line,
            version_line,
            compatibility_line,
            flags,
            extended_flags,
        };
        let dimensions = [r.u16()?, r.u16()?, r.u16()?];
        let cell_count = dimensions
            .iter()
            .try_fold(1usize, |a, &b| a.checked_mul(usize::from(b)))
            .ok_or_else(|| invalid("grid dimensions overflow"))?;
        let mut grid = Vec::new();
        let mut covered = 0usize;
        while covered < cell_count {
            let run = GridRun {
                turf: r.object()?,
                area: r.object()?,
                contents: r.object()?,
                copies: r.u8()?,
            };
            if run.copies == 0 {
                return Err(invalid("zero-length grid run"));
            }
            covered += usize::from(run.copies);
            if covered > cell_count {
                return Err(invalid("grid runs exceed map dimensions"));
            }
            grid.push(run);
        }
        let expected_string_bytes = r.u32()? as usize;
        let classes = r.table(Class::read)?;
        let mobs = r.table(MobType::read)?;
        let string_count = r.object()? as usize;
        let mut strings = Vec::new();
        let mut string_bytes = 0usize;
        let mut string_hash = u32::MAX;
        // Executor text is outside the position-based string cipher's origin.
        let string_origin = header.executor_line.as_ref().map_or(0, Vec::len);
        for _ in 0..string_count {
            let mut len = 0usize;
            let mut long_chunks = 0u16;
            loop {
                let offset = r.at - string_origin;
                let chunk = r.u16()? ^ offset as u16;
                len = len
                    .checked_add(usize::from(chunk))
                    .ok_or_else(|| invalid("string length overflow"))?;
                if chunk != u16::MAX {
                    break;
                }
                long_chunks = long_chunks
                    .checked_add(1)
                    .ok_or_else(|| invalid("too many string length chunks"))?;
                if len == expected_string_bytes {
                    break;
                }
            }
            let start = r.at - string_origin;
            let mut data = r.take(len)?.to_vec();
            crypt_string(&mut data, start);
            string_hash = nqcrc(string_hash, &data);
            string_hash = nqcrc(string_hash, &[0]);
            string_bytes = string_bytes
                .checked_add(len + 1)
                .ok_or_else(|| invalid("string byte count overflow"))?;
            strings.push(DmString { data, long_chunks });
        }
        if string_bytes != expected_string_bytes {
            return Err(invalid("string byte count mismatch"));
        }
        if r.u32()? != string_hash {
            return Err(invalid("string table checksum mismatch"));
        }
        let mut list_spans = Vec::new();
        let lists = r.table(|r| {
            let start = r.at;
            let count = r.u16()? as usize;
            let mut list = Vec::with_capacity(count);
            for _ in 0..count {
                list.push(r.object()?);
            }
            list_spans.push(start..r.at);
            Ok(list)
        })?;
        let procs = r.table(Proc::read)?;
        let variables = r.table(|r| {
            Ok(Variable {
                kind: r.u8()?,
                value: r.u32()?,
                name: r.object()?,
            })
        })?;
        let variable_footer = r.u32()?;
        let proc_references = r.table(|r| r.object())?;
        let instances = r.table(|r| {
            Ok(Instance {
                kind: r.u8()?,
                class: r.u32()?,
                initializer: r.object()?,
            })
        })?;
        let map_object_count = r.u32()? as usize;
        let mut map_objects = Vec::with_capacity(map_object_count);
        for _ in 0..map_object_count {
            map_objects.push(MapObject {
                offset: r.u16()?,
                instance: r.object()?,
            });
        }
        let world = World::read(&mut r)?;
        let resources = r.table(|r| {
            Ok(ResourceRef {
                id: r.u32()?,
                kind: r.u8()?,
            })
        })?;
        if r.at != data.len() {
            return Err(invalid("trailing DMB bytes"));
        }
        Ok((
            Self {
                header,
                dimensions,
                grid,
                classes,
                mobs,
                strings,
                lists: lists.into(),
                procs,
                variables,
                variable_footer,
                proc_references,
                instances,
                map_objects,
                world,
                resources,
            },
            list_spans,
        ))
    }

    /// Serializes decoded v516 records, recomputing string offsets and checksum.
    pub fn to_bytes(&self) -> io::Result<Vec<u8>> {
        self.to_bytes_with_list_spans().map(|(bytes, _)| bytes)
    }
    pub fn to_bytes_with_list_spans(&self) -> io::Result<(Vec<u8>, Vec<std::ops::Range<usize>>)> {
        writing::write(self, None).map(|(owner, spans)| (owner.into_bytes(), spans))
    }
    /// Canonical serialization with a digest bound to its immutable byte owner.
    pub fn encode(&self) -> io::Result<EncodedDmb> {
        writing::write(self, None).map(|(owner, _)| owner)
    }
    pub fn encode_on_executor(&self, executor: &dm_exec::BuildExecutor) -> io::Result<EncodedDmb> {
        writing::write(self, Some(executor)).map(|(owner, _)| owner)
    }
    /// Canonical encoder with optional row serialization from an admitted previous
    /// generation. All current model validation, ordering and final hashing remain.
    /// Retain the opaque row certificate only after independent output validation.
    pub fn encode_reusing_list_rows(
        &self,
        previous: Option<&WordLists>,
        executor: Option<&dm_exec::BuildExecutor>,
    ) -> io::Result<(EncodedDmb, EncodedListRows)> {
        let previous = previous.and_then(WordLists::encoding);
        let (image, ranges) = writing::write_reusing_lists(self, executor, previous.as_deref())?;
        let width = if self.header.flags & 0x4000_0000 != 0 {
            4
        } else {
            2
        };
        let certificate = self.lists.issue_encoding(&image, ranges, width)?;
        Ok((image, certificate))
    }
    /// Encodes canonical table chunks on the existing build executor. No global
    /// pool or additional OS workers are created.
    pub fn to_bytes_on_executor(&self, executor: &dm_exec::BuildExecutor) -> io::Result<Vec<u8>> {
        self.to_bytes_with_list_spans_on_executor(executor)
            .map(|(bytes, _)| bytes)
    }
    pub fn to_bytes_with_list_spans_on_executor(
        &self,
        executor: &dm_exec::BuildExecutor,
    ) -> io::Result<(Vec<u8>, Vec<std::ops::Range<usize>>)> {
        writing::write(self, Some(executor)).map(|(owner, spans)| (owner.into_bytes(), spans))
    }
}

#[cfg(test)]
#[path = "dmb_tests.rs"]
mod tests;
