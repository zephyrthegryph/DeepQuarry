//! Ordered linker directory. Semantic identity alone never licenses output
//! reuse: allocation, lookup membership, relocation and debug witnesses must
//! also match. Records point to immutable typed/physical object pages.
use serde::{Deserialize, Serialize};
#[derive(Clone, Default, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AllocationCounts {
    pub strings: u32, pub variables: u32, pub lists: u32, pub procedures: u32,
    pub references: u32, pub instances: u32,
}
impl AllocationCounts {
    pub fn from_dmb(image:&byond_dmb::dmb::Dmb)->Option<Self> {
        Some(Self { strings:image.strings.len().try_into().ok()?,variables:image.variables.len().try_into().ok()?,
            lists:image.lists.len().try_into().ok()?,procedures:image.procs.len().try_into().ok()?,
            references:image.proc_references.len().try_into().ok()?,instances:image.instances.len().try_into().ok()? })
    }
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
/// Only allocation counts actually read by an operation constrain reuse.
/// Symbol IDs and typed/scalar reads record the remaining explicit edges.
#[derive(Clone, Copy, Default, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AllocationMask(pub u8);
impl AllocationMask {
    pub const NONE: Self=Self(0);
    pub const STRINGS: Self=Self(1);
    pub const VARIABLES: Self=Self(2);
    pub const LISTS: Self=Self(4);
    pub const PROCEDURES: Self=Self(8);
    pub const REFERENCES: Self=Self(16);
    pub const INSTANCES: Self=Self(32);
    pub const ALL: Self=Self(63);
    pub fn union(self,other:Self)->Self {Self(self.0|other.0)}
    pub fn matches(self,expected:&AllocationCounts,current:&AllocationCounts)->bool {
        self.0 & !Self::ALL.0 == 0
            && (self.0&1==0 || expected.strings==current.strings)
            && (self.0&2==0 || expected.variables==current.variables)
            && (self.0&4==0 || expected.lists==current.lists)
            && (self.0&8==0 || expected.procedures==current.procedures)
            && (self.0&16==0 || expected.references==current.references)
            && (self.0&32==0 || expected.instances==current.instances)
    }
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ObjectWitness {
    pub semantic_identity: String,
    /// Immutable operation recipe bytes/names must contribute to this identity.
    /// It excludes this certificate itself, so there is no circular hash.
    pub recipe_identity: String,
    pub start: AllocationCounts,
    pub allocation_mask: AllocationMask,
    /// IDs are ordered by the immutable recipe's observation slots. The recipe
    /// retains symbol names and string bytes, avoiding a duplicate payload here.
    pub symbol_ids: Vec<u32>,
    pub string_ids: Vec<u32>,
    pub debug_ids: Vec<(u32,u32)>,
    pub read_identities: Vec<String>,
    pub scalar_reads: Vec<u64>,
    pub unresolved_debug: Vec<usize>,
}
pub struct WitnessObservation<'a> {
    pub semantic_identity: &'a str,
    pub recipe_identity: &'a str,
    pub start: AllocationCounts,
    pub read_identities: &'a [String],
    pub scalar_reads: &'a [u64],
    pub unresolved_debug: &'a [usize],
}
impl ObjectWitness {
    /// All adapters use this comparison after deriving their ordered reads.
    /// Iterator equality checks both values and full lengths; zip truncation
    /// cannot silently omit a trailing dependency. No temporary Vec is needed.
    pub fn matches<S,T,D>(&self,current:&WitnessObservation<'_>,symbols:S,strings:T,debug:D)->bool
    where S:IntoIterator<Item=u32>,T:IntoIterator<Item=u32>,D:IntoIterator<Item=(u32,u32)> {
        self.matches_optional(current,symbols.into_iter().map(Some),strings,debug)
    }
    /// Fallible symbol resolution records None; it cannot match a stored ID.
    pub fn matches_optional<S,T,D>(&self,current:&WitnessObservation<'_>,symbols:S,strings:T,debug:D)->bool
    where S:IntoIterator<Item=Option<u32>>,T:IntoIterator<Item=u32>,D:IntoIterator<Item=(u32,u32)> {
        self.matches_observation(current)
            && self.symbol_ids.iter().copied().map(Some).eq(symbols)
            && self.string_ids.iter().copied().eq(strings)
            && self.debug_ids.iter().copied().eq(debug)
    }
    /// Semantic/recipe and non-relocatable dependencies authorize relinking.
    /// Changed physical operands must still pass typed-site preflight against
    /// the digest-bound old code object before producing a new generation.
    pub fn matches_observation(&self,current:&WitnessObservation<'_>)->bool {
        self.valid() && self.semantic_identity==current.semantic_identity
            && self.recipe_identity==current.recipe_identity
            && self.allocation_mask.matches(&self.start,&current.start)
            && self.read_identities.as_slice()==current.read_identities
            && self.scalar_reads.as_slice()==current.scalar_reads
            && self.unresolved_debug.as_slice()==current.unresolved_debug
    }
    pub fn valid(&self)->bool {
        let digest=|value:&str|value.len()==64 && value.bytes().all(|byte|byte.is_ascii_hexdigit());
        self.allocation_mask.0 & !AllocationMask::ALL.0 == 0
            && digest(&self.semantic_identity) && digest(&self.recipe_identity)
            && self.read_identities.iter().all(|identity|digest(identity))
    }
    pub fn matches_witness(&self,current:&Self)->bool {
        self.allocation_mask==current.allocation_mask && self.matches(&WitnessObservation {
            semantic_identity:&current.semantic_identity,recipe_identity:&current.recipe_identity,start:current.start.clone(),
            read_identities:&current.read_identities,scalar_reads:&current.scalar_reads,unresolved_debug:&current.unresolved_debug,
        },current.symbol_ids.iter().copied(),current.string_ids.iter().copied(),current.debug_ids.iter().copied())
    }
}
/// Typed references to rows allocated by this object. Allocation ordinals are
/// parameters to composition; moving an object's prefix is not a semantic edit.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum OwnedTable {Variable,List,Procedure,ProcedureReference,Instance}
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct OwnedReference {pub table:OwnedTable,pub ordinal:u32}
impl OwnedReference {
    pub fn resolve(self,base:&AllocationCounts)->Option<u32> {
        let start=match self.table {OwnedTable::Variable=>base.variables,OwnedTable::List=>base.lists,
            OwnedTable::Procedure=>base.procedures,OwnedTable::ProcedureReference=>base.references,OwnedTable::Instance=>base.instances};
        let id=start.checked_add(self.ordinal)?;
        if matches!(self.table,OwnedTable::List|OwnedTable::Procedure) && start<=0xffff && id>=0xffff {
            id.checked_add(1)
        } else {Some(id)}
    }
}
/// Every writable ID site is identified by its schema, not by scanning words.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SiteKind {LocalVariable(u32),ArgumentVariable(u32),ProcedureCode,ProcedureLocals,ProcedureArguments}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ProcedureRowLayout {pub version:u8,pub variable_count:u32,pub lists:[OwnedReference;3]}
impl ProcedureRowLayout {
    pub fn new(variable_count:u32)->Self {Self {version:1,variable_count,lists:[
        OwnedReference{table:OwnedTable::List,ordinal:0},OwnedReference{table:OwnedTable::List,ordinal:1},OwnedReference{table:OwnedTable::List,ordinal:2}]}}
    pub fn valid(&self)->bool {self.version==1 && self.lists.iter().enumerate().all(|(slot,reference)|
        reference.table==OwnedTable::List && reference.ordinal==slot as u32)}
    pub fn resolve(&self,site:SiteKind,relative:u32,base:&AllocationCounts)->Option<u32> {
        if !self.valid() {return None;}
        match site {
            SiteKind::LocalVariable(_)|SiteKind::ArgumentVariable(_) if relative<self.variable_count=>
                OwnedReference {table:OwnedTable::Variable,ordinal:relative}.resolve(base),
            SiteKind::ProcedureCode if relative==0=>self.lists[0].resolve(base),
            SiteKind::ProcedureLocals if relative==1=>self.lists[1].resolve(base),
            SiteKind::ProcedureArguments if relative==2=>self.lists[2].resolve(base),
            _=>None,
        }
    }
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
    pub fn reusable(&self, current: &ObjectWitness) -> bool { self.valid_ranges() && self.witness.matches_witness(current) }
    pub fn valid_ranges(&self) -> bool {
        self.witness.valid()
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
