//! Ordered linker directory. Semantic identity alone never licenses output
//! reuse: allocation, lookup membership, relocation and debug witnesses must
//! also match. Records point to immutable typed/physical object pages.
use serde::{Deserialize, Serialize};
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AllocationCounts {
    pub strings: u32, pub variables: u32, pub lists: u32, pub procedures: u32,
    pub references: u32, pub instances: u32,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SymbolAssignment { pub table: u8, pub key: String, pub id: u32 }
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct StringMembership {
    pub bytes: Vec<u8>,
    /// None certifies absence before this object; Some certifies exact existing
    /// dense ID. Events are ordered, so repeated literals see earlier events.
    pub previous: Option<u32>,
    pub assigned: u32,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct DebugAssignment {
    pub relative: usize, pub file: String, pub line: u32, pub file_id: u32,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ObjectWitness {
    pub semantic_identity: String,
    pub start: AllocationCounts,
    pub symbols: Vec<SymbolAssignment>,
    pub strings: Vec<StringMembership>,
    pub debug: Vec<DebugAssignment>,
    pub unresolved_debug: Vec<usize>,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ObjectRange { pub section: u8, pub start: u32, pub count: u32 }
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ObjectPages {
    pub physical_manifest: String,
    /// Schema-named typed page manifests restore analysis/semantic rows lazily.
    pub typed_manifests: Vec<(String,String)>,
    pub ranges: Vec<ObjectRange>,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LinkedObject {
    pub key: String, pub witness: ObjectWitness,
    pub end: AllocationCounts, pub pages: ObjectPages,
}
impl LinkedObject {
    /// Caller derives the current witness through its single dependency path.
    /// Equality includes exact strings and symbol IDs; no hash-only shortcuts.
    pub fn reusable(&self, current: &ObjectWitness) -> bool { self.valid_ranges() && self.witness==*current }
    pub fn valid_ranges(&self) -> bool {
        let mut strings=self.witness.start.strings;
        for event in &self.witness.strings {
            match event.previous {
                Some(id) if id<strings && event.assigned==id=>{},
                None if event.assigned==strings=>{
                    let Some(next)=strings.checked_add(1) else {return false;};strings=next;
                }
                _=>return false,
            }
        }
        strings==self.end.strings
            && self.pages.ranges.iter().all(|range|range.start.checked_add(range.count).is_some())
            && self.end.strings>=self.witness.start.strings
            && self.end.variables>=self.witness.start.variables
            && self.end.lists>=self.witness.start.lists
            && self.end.procedures>=self.witness.start.procedures
            && self.end.references>=self.witness.start.references
            && self.end.instances>=self.witness.start.instances
    }
}
/// Source order is explicit; replacing one object never silently shifts the
/// identities of following objects. Prefix changes are separate query inputs.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct OrderedDirectory { pub version: u32, pub objects: Vec<LinkedObject> }
impl OrderedDirectory {
    pub fn validate(&self) -> bool {
        let mut keys=std::collections::BTreeSet::new();
        self.version==1 && self.objects.iter().all(|object|keys.insert(&object.key) && object.valid_ranges())
            && self.objects.windows(2).all(|pair|pair[0].end==pair[1].witness.start)
    }
    pub fn reuse(&self,ordinal:usize,current:&ObjectWitness)->Option<&LinkedObject> {
        self.objects.get(ordinal).filter(|object|self.version==1 && object.reusable(current))
    }
    pub fn affected_suffix(&self, ordinal: usize, new_end: &AllocationCounts) -> std::ops::Range<usize> {
        if self.objects.get(ordinal).is_some_and(|object|&object.end==new_end) {
            ordinal..ordinal.saturating_add(1).min(self.objects.len())
        } else {ordinal.min(self.objects.len())..self.objects.len()}
    }
}
