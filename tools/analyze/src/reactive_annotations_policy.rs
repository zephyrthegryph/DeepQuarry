//! Unique original reactive annotation policy, independent of the DM model.
//! Source callbacks must issue original marker/own-callable/header facts.
use std::collections::{HashMap,HashSet};
use crate::raw_marker_policy::split_args;
#[derive(Clone,Copy)]
pub struct Marker<'a>{pub name:&'a str,pub rel:&'a str,pub line:u32,pub args:&'a [String]}
pub trait Source{
 type Error;
 fn markers_named(&self,name:&'static str)->impl Iterator<Item=Marker<'_>>;
 fn owner_candidates(&self,rel:&str,line:u32)->Result<Vec<String>,Self::Error>;
 fn has_own_callable(&self,owner:&str,name:&str)->Result<bool,Self::Error>;
 fn relations(&self,emit:&mut dyn FnMut(&str,&str)->Result<(),Self::Error>)->Result<(),Self::Error>;
 fn def_at(&self,rel:&str,line:u32)->Result<Option<(String,String)>,Self::Error>;
 // Legacy sources do nothing. Captured callers admit real transient/output
 // widths BEFORE entering the unchanged owned String/map policy below.
 fn admit_marker(&self,marker:&Marker<'_>)->Result<(),Self::Error>;
 fn admit_relation(&self,owner:&str,name:&str)->Result<(),Self::Error>;
}
#[derive(Clone, Debug)]
pub struct LookupDeclaration {
    pub registry: String,
    pub identity_key: String,
    pub argument: usize,
    pub result: String,
}

/// `READS_AS` and `READS_FROM` annotations, resolved to procs.
#[derive(Default)]
pub struct Annotations {
    /// (owner type, proc) -> (key, via).
    pub reads_as: HashMap<(String, String), (String, Option<String>)>,
    /// global proc name -> the param names it reads from (empty = reads nothing).
    pub reads_from: HashMap<String, Vec<String>>,
    pub lookups: HashMap<String, LookupDeclaration>,
    /// Relations declared in `relations()` bodies (`rel_one(nameof(x), ...)` / `rel_many(...)`): type -> vars.
    pub relations: HashMap<String, HashSet<String>>,
    /// `SYSTEM_ACCESSOR(system, proc, nameof(var))`: proc -> (system, var).
    pub accessors: HashMap<String, (String, String)>,
    /// The accessor `cap_keys(CAP_X, KEY = ...)` generates for each state key (`cover_open`): proc -> the key's id name (`COVER_OPEN`).
    /// A call stands for a read of that key on its first argument; the global proc behind it is not followed.
    pub capkey_accessors: HashMap<String, String>,
    /// `PROC_SUMMARY(path, reads = list(...), writes = list(...))`: what a proc the walk cannot enter (a Verdigris FFI call, a `vars[]`
    /// dispatcher) reads and writes on its receiver, declared by hand. The walk takes the summary instead of the body.
    pub summaries: HashMap<(String, String), ProcSummary>,
}

/// A declared summary of a proc that is not walked (see [`Annotations::summaries`]): var names on the receiver.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ProcSummary {
    pub reads: Vec<String>,
    pub writes: Vec<String>,
}


pub fn build<S:Source>(source:&S)->Result<Annotations,S::Error>{
        let mut a = Annotations::default();
        for m in source.markers_named("READS_AS") {
            source.admit_marker(&m)?;
            let Some(first) = m.args.first() else { continue };
            let key = m.args.get(1).cloned().unwrap_or_default();
            let via = m.args.iter().skip(2).find_map(|x| {
                let x = x.replace(' ', "");
                x.strip_prefix("via=nameof(").and_then(|r| r.strip_suffix(')')).map(|s| s.to_string())
            });
            let mut owners: Vec<(String, String)> = Vec::new();
            if first.starts_with('/') {
                // /type/proc/name or /type/name
                let (ty, name) = first.rsplit_once('/').unwrap();
                let ty = ty.strip_suffix("/proc").unwrap_or(ty);
                owners.push((if ty.is_empty() { "/".to_string() } else { ty.to_string() }, name.to_string()));
            } else {
                for c in source.owner_candidates(m.rel,m.line)? {
                    owners.push((c, first.clone()));
                }
            }
            for (ty, name) in owners {
                if source.has_own_callable(&ty,&name)? {
                    a.reads_as.insert((ty, name), (key.clone(), via.clone()));
                    break;
                }
            }
        }
        for m in source.markers_named("PROC_SUMMARY") {
            source.admit_marker(&m)?;
            let Some(first) = m.args.first() else { continue };
            let Some((ty, name)) = first.rsplit_once('/') else { continue };
            let ty = ty.strip_suffix("/proc").unwrap_or(ty);
            let ty = if ty.is_empty() { "/".to_string() } else { ty.to_string() };
            let list = |key: &str| -> Vec<String> {
                m.args
                    .iter()
                    .skip(1)
                    .find_map(|a| a.split_once('=').filter(|(k, _)| k.trim() == key).map(|(_, v)| v.trim().to_string()))
                    .and_then(|v| v.strip_prefix("list(").and_then(|r| r.strip_suffix(')')).map(|r| r.to_string()))
                    .map(|inner| {
                        split_args(&inner).into_iter().map(|x| x.trim().trim_start_matches("nameof(").trim_end_matches(')').trim().to_string()).filter(|x| !x.is_empty()).collect()
                    })
                    .unwrap_or_default()
            };
            a.summaries.insert((ty, name.to_string()), ProcSummary { reads: list("reads"), writes: list("writes") });
        }
        for m in source.markers_named("READ_LOOKUP") {
            source.admit_marker(&m)?;
            let Some(path) = m.args.first() else { continue };
            let Some(name) = path.strip_prefix("/proc/") else { continue };
            let named = |name: &str| m.args.iter().skip(1).find_map(|a| a.split_once('=').filter(|(k, _)| k.trim() == name).map(|(_, v)| v.trim().to_string()));
            let proc_name = |value: Option<String>| value.and_then(|v| v.strip_prefix("GLOBAL_PROC_REF(").and_then(|x| x.strip_suffix(')')).map(|x| x.trim().to_string()));
            let (Some(registry), Some(identity_key), Some(result)) = (proc_name(named("registry")), proc_name(named("key")), named("result")) else { continue };
            let argument = named("argument").and_then(|s| s.parse::<usize>().ok()).unwrap_or(1);
            if argument == 0 || !result.starts_with('/') { continue; }
            a.lookups.insert(name.to_string(), LookupDeclaration { registry, identity_key, argument: argument - 1, result });
        }
        let mut cap_names: HashMap<String, String> = HashMap::new();
        for m in source.markers_named("CAPABILITY_TYPE").chain(source.markers_named("CAPABILITY_DEF")) {
            source.admit_marker(&m)?;
            if let (Some(name), Some(id)) = (m.args.first(), m.args.get(1)) {
                cap_names.insert(id.clone(), name.clone());
            }
        }
        for m in source.markers_named("cap_keys") {
            source.admit_marker(&m)?;
            let Some(cap_id) = m.args.first() else { continue };
            let Some(cap_name) = cap_names.get(cap_id) else { continue };
            for arg in m.args.iter().skip(1) {
                let key = arg.split('=').next().unwrap_or("").trim().to_string();
                if key.is_empty() {
                    continue;
                }
                a.capkey_accessors.insert(format!("{}_{}", cap_name, key.to_lowercase()), format!("{}_{}", cap_name.to_uppercase(), key));
            }
        }
        for m in source.markers_named("SYSTEM_ACCESSOR") {
            source.admit_marker(&m)?;
            if let (Some(sys), Some(name), Some(key)) = (m.args.first(), m.args.get(1), m.args.get(2)) {
                let var = key.trim().strip_prefix("nameof(").and_then(|s| s.strip_suffix(')')).unwrap_or(key).trim().to_string();
                a.accessors.insert(name.clone(), (sys.clone(), var));
            }
        }
        source.relations(&mut |owner,name|{
            source.admit_relation(owner,name)?;
            a.relations.entry(owner.to_owned()).or_default().insert(name.to_owned());Ok(())
        })?;
        for m in source.markers_named("READS_FROM") {
            source.admit_marker(&m)?;
            if let Some((owner, name)) = source.def_at(m.rel,m.line)? {
                let params = m.args.iter().filter(|x| !x.is_empty()).cloned().collect();
                if owner == "/" {
                    a.reads_from.insert(name, params);
                }
            }
        }
        Ok(a)
}
