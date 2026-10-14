//! Ordered symbolic map contents without wire IDs or inferred world defaults.
use crate::{SymbolId, SymbolicExpression};
use std::sync::Arc;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MapAssignment {
    pub name: SymbolId,
    pub value: SymbolicExpression,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MapAtom {
    pub type_path: SymbolId,
    /// An authored empty override block is distinct from omitted overrides.
    pub initializer_present: bool,
    pub assignments: Arc<[MapAssignment]>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MapTemplate {
    pub key: Arc<str>,
    pub atoms: Arc<[MapAtom]>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MapBlock {
    /// Authored positive coordinate tuple. Axis conventions belong to target ABI.
    pub origin: [u64; 3],
    /// Exact authored cell sequence including row separators. No per-cell
    /// default atoms or world extent values have been invented here.
    pub cells: Arc<str>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MapRecord {
    Template(usize),
    Block(usize),
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SymbolicMap {
    pub templates: Arc<[MapTemplate]>,
    pub blocks: Arc<[MapBlock]>,
    pub records: Arc<[MapRecord]>,
    /// Observed uniform template-key byte width; None means no uniform width
    /// can be established. This is not certification of target key/grid rules.
    pub key_width: Option<u64>,
}
fn framed(bytes: &mut Vec<u8>, value: &[u8]) {
    bytes.extend_from_slice(&(value.len() as u64).to_le_bytes());
    bytes.extend_from_slice(value);
}
impl SymbolicMap {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = b"dm-symbolic-map-v2\0".to_vec();
        bytes.push(u8::from(self.key_width.is_some()));
        if let Some(width) = self.key_width {
            bytes.extend_from_slice(&width.to_le_bytes());
        }
        bytes.extend_from_slice(&(self.templates.len() as u64).to_le_bytes());
        for template in self.templates.iter() {
            framed(&mut bytes, template.key.as_bytes());
            bytes.extend_from_slice(&(template.atoms.len() as u64).to_le_bytes());
            for atom in template.atoms.iter() {
                bytes.extend_from_slice(&atom.type_path.bits().to_le_bytes());
                bytes.push(u8::from(atom.initializer_present));
                bytes.extend_from_slice(&(atom.assignments.len() as u64).to_le_bytes());
                for assignment in atom.assignments.iter() {
                    bytes.extend_from_slice(&assignment.name.bits().to_le_bytes());
                    framed(&mut bytes, &assignment.value.canonical_bytes());
                }
            }
        }
        bytes.extend_from_slice(&(self.blocks.len() as u64).to_le_bytes());
        for block in self.blocks.iter() {
            for coordinate in block.origin {
                bytes.extend_from_slice(&coordinate.to_le_bytes());
            }
            framed(&mut bytes, block.cells.as_bytes());
        }
        bytes.extend_from_slice(&(self.records.len() as u64).to_le_bytes());
        for record in self.records.iter() {
            let (tag, index) = match *record {
                MapRecord::Template(index) => (0, index),
                MapRecord::Block(index) => (1, index),
            };
            bytes.push(tag);
            bytes.extend_from_slice(&(index as u64).to_le_bytes());
        }
        bytes
    }
}
