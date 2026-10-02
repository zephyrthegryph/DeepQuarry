//! Exact restart proof for binding evaluation, independent of procedure bodies.
//! This conservative producer covers every current binding input. Owner query
//! roots can replace the image digest once their production migration finishes.
use super::{canonical::InvocationPlan, initializer_pipeline::InitializerRecipe};
use dm_output::wire_image::WireImageBuilder;
use dm_codegen_byond::SharedLowerBindings;
use serde::{Serialize, Serializer, ser::{SerializeSeq, SerializeStruct}};
use sha2::{Digest, Sha256};
use std::{collections::{BTreeMap, HashMap}, io, sync::{Arc,Mutex}};

struct OrderedShared<'a>(&'a SharedLowerBindings);
impl Serialize for OrderedShared<'_> {
    fn serialize<S:Serializer>(&self, serializer:S)->Result<S::Ok,S::Error> {
        let value=self.0;let mut fields=serializer.serialize_struct("BindingNamespace",19)?;
        macro_rules! direct {($field:ident)=>{fields.serialize_field(stringify!($field),&value.$field)?;}}
        macro_rules! sorted {($field:ident)=>{fields.serialize_field(stringify!($field),&value.$field.iter().collect::<BTreeMap<_,_>>())?;}}
        sorted!(modified_instances);sorted!(member_type_fingerprints);
        direct!(member_types);direct!(member_globals);direct!(known_member_fields);
        direct!(member_procs);direct!(known_member_procs);sorted!(global_proc_return_types);
        direct!(member_proc_return_types);direct!(parent_types);direct!(fields);direct!(globals);
        sorted!(field_types);sorted!(global_types);direct!(global_procs);
        sorted!(numeric_constants);sorted!(string_constants);direct!(fingerprint);
        // Explicit schema marker also prevents a future field addition being
        // confused with this complete current input model.
        fields.serialize_field("version",&1u32)?;fields.end()
    }
}
struct OrderedInvocations<'a>(&'a [InvocationPlan]);
impl Serialize for OrderedInvocations<'_> {
    fn serialize<S:Serializer>(&self,serializer:S)->Result<S::Ok,S::Error> {
        let mut rows=serializer.serialize_seq(Some(self.0.len()))?;
        for plan in self.0 {
            rows.serialize_element(&(&plan.template,plan.static_ids.iter().collect::<BTreeMap<_,_>>()))?;
        }rows.end()
    }
}
fn image_identity(image:&WireImageBuilder)->Option<[u8;32]> {
    let state=Arc::new(Mutex::new((Sha256::new(),0usize)));
    let sink=state.clone();
    image.encode_prefix_to_sink(Box::new(move |page| {
        let mut state=sink.lock().map_err(|_|io::Error::other("binding proof sink poisoned"))?;
        state.1=state.1.checked_add(page.len()).ok_or_else(||io::Error::other("binding proof size overflow"))?;
        if state.1>64*1024*1024 {return Err(io::Error::other("binding proof image exceeds 64 MiB"));}
        state.0.update(page);Ok(())
    })).ok()?;
    let digest=state.lock().ok()?.0.clone().finalize().into();Some(digest)
}
pub(crate) fn prepare(
    image:&WireImageBuilder,shared:&SharedLowerBindings,invocations:&[InvocationPlan],
    initializer_globals:&HashMap<String,u32>,global_proc_ids:&HashMap<String,u32>,
    class_paths:&HashMap<String,u32>,initializers:&[InitializerRecipe],modified:&[InitializerRecipe],
)->Option<crate::project_graph::BindingContextProof> {
    let image=image_identity(image)?;
    crate::project_graph::BindingContextProof::from_components(&(
        "complete-physical-binding-context-v1",env!("DM_EMISSION_FINGERPRINT"),image,
        OrderedShared(shared),OrderedInvocations(invocations),
        initializer_globals.iter().collect::<BTreeMap<_,_>>(),
        global_proc_ids.iter().collect::<BTreeMap<_,_>>(),class_paths.iter().collect::<BTreeMap<_,_>>(),
        initializers,modified,
    )).ok()
}
