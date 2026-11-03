//! Authored source inputs for original state-schema policy comparisons.
pub const CASES:&[&str]=&["references","codecs_and_ownership","inherited_metadata","ordered_duplicates"];
pub fn files(case:&str)->Option<Vec<(&'static str,&'static str)>>{if !CASES.contains(&case){return None}let mut files=vec![("code/decls.dm","/datum/a
    latent_safe = TRUE
    var/obj/reference
    var/tmp/obj/temporary
    var/static/obj/shared
    var/list/obj/objects
    var/datum/material/material
")];match case{
 "codecs_and_ownership"=>{files.push(("code/codecs.dm",r#"/datum/a/state_codecs()
    return alist("reference" = /datum/state_codec/reference)
CAPABILITIES(/datum/a)
    owns_many(nameof(objects))
"#));},
 "inherited_metadata"=>{files.push(("code/metadata.dm","/datum/type_metadata_registry/register_defaults()
    register(/datum/a/child, TYPE_META_LATENT_SAFE, FALSE)
    register(/datum/other, TYPE_META_LATENT_SAFE, TRUE)
/datum/other
    var/obj/registry/ref
"));files.push(("code/datums/ownership/registry_types.dm","REGISTRY_TYPE(/obj/registry, /datum/registry)
"));},
 "ordered_duplicates"=>{files.push(("code/z.dm","/datum/a/child
    var/obj/extra
/datum/a/other
    var/obj/extra
/datum/a
    var/obj/reference
"));},_=>()};Some(files)}
