//! Typed references into DMB tables. The wire representation remains a `u32`;
//! `0xffff` is the format's reserved absent-object value even in wide tables.

use std::marker::PhantomData;

use crate::dmb::{Class, DmString, Dmb, Proc};

pub const NONE: u32 = 0xffff;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct Id<T> {
    raw: u32,
    table: PhantomData<fn() -> T>,
}

impl<T> Id<T> {
    pub fn from_raw(raw: u32) -> Option<Self> {
        (raw != NONE).then_some(Self {
            raw,
            table: PhantomData,
        })
    }

    pub fn raw(&self) -> u32 {
        self.raw
    }

    pub fn index(&self) -> usize {
        self.raw as usize
    }
}

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum StringTable {}
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum ClassTable {}
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum ProcTable {}
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum ListTable {}
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum ResourceTable {}

pub type StringId = Id<StringTable>;
pub type ClassId = Id<ClassTable>;
pub type ProcId = Id<ProcTable>;
pub type ListId = Id<ListTable>;
pub type ResourceId = Id<ResourceTable>;

impl Dmb {
    pub fn string_by_id(&self, id: StringId) -> Option<&DmString> {
        self.strings.get(id.index())
    }

    pub fn class_by_id(&self, id: ClassId) -> Option<&Class> {
        self.classes.get(id.index())
    }

    pub fn proc_by_id(&self, id: ProcId) -> Option<&Proc> {
        if self.is_reserved_proc_slot(id.index()) {
            None
        } else {
            self.procs.get(id.index())
        }
    }

    pub fn list_by_id(&self, id: ListId) -> Option<&[u32]> {
        self.lists.get(id.index()).map(|words|words.as_slice())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sentinel_is_absent_for_every_table() {
        assert!(StringId::from_raw(NONE).is_none());
        assert!(ClassId::from_raw(NONE).is_none());
        assert!(ProcId::from_raw(NONE).is_none());
        assert!(ListId::from_raw(NONE).is_none());
        assert!(ResourceId::from_raw(NONE).is_none());
        assert_eq!(ListId::from_raw(0x1_0000).unwrap().raw(), 0x1_0000);
    }
}
