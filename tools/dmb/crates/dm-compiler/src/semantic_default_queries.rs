//! Salsa validity queries fed by the exact portable observations persisted with
//! resolved defaults. Evaluation remains in the semantic resolver.
use super::*;
use salsa::Setter as _;
#[salsa::input]
struct ObservedInput { #[returns(ref)] value: String }
#[salsa::input]
struct DefaultInput {
    #[returns(ref)] expected: Vec<String>,
    #[returns(ref)] inputs: Vec<ObservedInput>,
}
#[salsa::db]
trait DefaultDb: salsa::Database {}
#[salsa::db]
#[derive(Clone,Default)]
struct Database { storage:salsa::Storage<Self> }
#[salsa::db]
impl salsa::Database for Database {}
#[salsa::db]
impl DefaultDb for Database {}
#[salsa::tracked]
fn valid(db:&dyn DefaultDb,input:DefaultInput)->bool {
    let expected=input.expected(db);
    let inputs=input.inputs(db);
    inputs.len()==expected.len() && crate::observed_dependencies::validate(
        inputs.iter().zip(expected.iter()), |input|input.value(db).clone())
}
struct Candidate { record:Arc<ResolvedValue>, input:DefaultInput }
#[derive(Default)]
struct Queries {
    db:Database, candidates:BTreeMap<(String,String),Candidate>,
    observed:BTreeMap<SemanticRead,(ObservedInput,u64)>, bytes:usize,
}
fn input_for(queries:&mut Queries,model:&SemanticDeclarations,key:&SemanticRead)->ObservedInput {
    if let Some((input,generation))=queries.observed.get(key).copied() {
        if generation!=model.generation {
            let current=model.read_identity(key);
            if input.value(&queries.db)!=&current {input.set_value(&mut queries.db).to(current);}
            queries.observed.get_mut(key).unwrap().1=model.generation;
        }
        return input;
    }
    let current=model.read_identity(key);
    let charge=128+current.len()+match key {
        SemanticRead::Field(owner,name)=>owner.len()+name.len(),
        SemanticRead::Parent(owner)|SemanticRead::Global(owner)|SemanticRead::Builtin(owner)=>owner.len(),
    };
    let input=ObservedInput::new(&queries.db,current);
    queries.bytes+=charge;
    queries.observed.insert(key.clone(),(input,model.generation));
    input
}
fn queries()->&'static Mutex<Queries> {
    static QUERIES:OnceLock<Mutex<Queries>>=OnceLock::new();
    QUERIES.get_or_init(||Mutex::new(Queries::default()))
}
pub(super) fn reset() { *queries().lock().unwrap_or_else(|e|e.into_inner())=Queries::default(); }
pub(super) fn resident_bytes()->usize { queries().lock().unwrap_or_else(|e|e.into_inner()).bytes }
pub(super) fn validate(model:&SemanticDeclarations,record:&Arc<ResolvedValue>)->bool {
    // Literal/closed expressions have no edges to invalidate. Their source is
    // already part of the portable candidate key; no Salsa arena is needed.
    if record.reads.is_empty() {return true;}
    let key=(record.owner.clone(),record.name.clone());
    let mut queries=queries().lock().unwrap_or_else(|e|e.into_inner());
    let same=queries.candidates.get(&key).is_some_and(|candidate|Arc::ptr_eq(&candidate.record,record));
    if !same {
        // Salsa arena inputs cannot be individually freed. Bound the arena and
        // rebuild only its optional memo layer when replacing many candidates.
        let charge=record.reads.iter().map(|(key,value)|128+value.len()+match key {
            SemanticRead::Field(owner,name)=>owner.len()+name.len(),
            SemanticRead::Parent(owner)|SemanticRead::Global(owner)|SemanticRead::Builtin(owner)=>owner.len(),
        }).sum::<usize>()+256;
        if queries.bytes.saturating_add(charge.saturating_mul(2))>16*1024*1024 { *queries=Queries::default(); }
        let inputs=record.reads.iter().map(|(key,_)|input_for(&mut queries,model,key)).collect();
        let expected=record.reads.iter().map(|(_,value)|value.clone()).collect();
        let input=DefaultInput::new(&queries.db,expected,inputs);
        queries.bytes+=charge;
        queries.candidates.insert(key.clone(),Candidate {record:Arc::clone(record),input});
    }
    let input=queries.candidates[&key].input;
    // Shared stage facts are refreshed once for each immutable model generation.
    // Monotonic generation IDs avoid allocator address reuse across cold starts.
    for (key,_) in &record.reads { input_for(&mut queries,model,key); }
    *valid(&queries.db,input)
}
