//! The original name-based boot graph judgement; no parser/type model/cache.
use std::collections::HashSet;
#[path="global_compact.rs"]mod compact;
pub(crate) use compact::{Builder as CompactGlobalBuilder,Kind as CompactGlobalKind};
/// The lifecycle procs of a system and a controller: the kernel calls them once, while the world boots.
pub(crate) const BOOT_PROCS: &[&str] = &["New", "preinit", "initialize", "Initialize", "on_members_ready", "kernel_members_ready", "OnConfigLoad"];

/// Procs that run once before the first map load by the engine's own contract, though a late atom may call them as a fallback
/// (`static_entries_ensure`, `static_entries_setup_early`): both are guarded by `ready`.
pub(crate) const BOOT_ONCE: &[&str] = &["static_entries_build"];

/// Calls that change the list they are called on.
pub(crate) const LIST_MUTATORS: &[&str] = &["Add", "Cut", "Remove", "Insert", "Swap", "Splice"];

/// Calls that change their first argument in place.
pub(crate) const ARG_MUTATORS: &[&str] = &["sortTim", "shuffle", "reverse_range"];

/// The names a `PROC_REF` family macro takes.
pub(crate) const REF_MACROS: &[&str] = &["PROC_REF", "TYPE_PROC_REF", "GLOBAL_PROC_REF"];

pub(crate) type Node = (String, String);

#[derive(Default, serde::Serialize, serde::Deserialize)]
pub struct GlobalIndex {
    /// Global vars (`GLOB.x` as `x`, a real global as its name) written by a proc that is not boot-only.
    runtime_written: HashSet<String>,
    /// Every global var that is written anywhere.
    written: HashSet<String>,
    /// Var names (of any object) written by a proc that is not boot-only: the name-based test for a var of a global singleton (`SSjob.x`,
    /// `using_map.x`). Test code is compiled out of production and does not count.
    runtime_field_written: HashSet<String>,
    /// How many procs the boot set holds (for the report).
    pub boot_procs: usize,
}

impl GlobalIndex {
    /// A digest of the index (`walk_cache`).
    pub fn digest(&self) -> u128 {
        let mut h = blake3::Hasher::new();
        for set in [&self.runtime_written, &self.written, &self.runtime_field_written] {
            let mut v: Vec<&String> = set.iter().collect();
            v.sort();
            for x in v {
                h.update(x.as_bytes());
                h.update(b"\n");
            }
            h.update(b"|");
        }
        h.update(&self.boot_procs.to_le_bytes());
        u128::from_le_bytes(h.finalize().as_bytes()[..16].try_into().unwrap())
    }

    /// True when `var` (a `GLOB` field or a real global) is never changed after the world booted.
    pub fn constant_after_init(&self, var: &str) -> bool {
        !self.runtime_written.contains(var)
    }

    /// True when no proc outside the boot set writes a var of this name on any object: a var of a global singleton that only boot code fills reads
    /// like a constant. Name-based, so it over-approximates who writes (a same-named var elsewhere keeps it dynamic).
    pub fn field_constant_after_init(&self, var: &str) -> bool {
        !self.runtime_field_written.contains(var)
    }

    pub fn is_written(&self, var: &str) -> bool {
        self.written.contains(var)
    }


    pub(crate) fn into_rows<C:crate::key_policy_control::Control>(self,c:&mut C)->Result<GlobalRows,C::Error>{
        Ok(GlobalRows{runtime_written:names(self.runtime_written.into_iter(),c)?,written:names(self.written.into_iter(),c)?,runtime_field_written:names(self.runtime_field_written.into_iter(),c)?,boot_procs:self.boot_procs})
    }
    pub(crate) fn from_facts(nodes:&[(Node,Facts)],mut is_system:impl FnMut(&str)->bool)->GlobalIndex{
        let roots=nodes.iter().map(|(n,_)|is_root(n,||is_system(&n.0))).collect::<Vec<_>>();
        match Self::from_facts_controlled(nodes,&roots,&mut crate::key_policy_control::Compatibility){Ok(v)=>v,Err(never)=>match never{}}
    }
    pub(crate) fn from_facts_controlled<C:crate::key_policy_control::Control>(nodes:&[(Node,Facts)],roots:&[bool],c:&mut C)->Result<GlobalIndex,C::Error>{
        compact::Builder::from_facts(nodes,roots,c)?.classify(c)
    }

}
pub(crate) fn is_root(n:&Node,is_system:impl FnOnce()->bool)->bool{
    match is_root_controlled(n,||Ok::<_,std::convert::Infallible>(is_system())){Ok(v)=>v,Err(never)=>match never{}}
}
pub(crate) fn is_root_controlled<E>(n:&Node,is_system:impl FnOnce()->Result<bool,E>)->Result<bool,E>{
    if (n.0=="/datum/controller/global_vars"&&n.1.starts_with("InitGlobal")) ||
       (n.0=="/world"&&n.1=="New") ||
       (BOOT_ONCE.contains(&n.1.as_str())&&n.0=="/"){return Ok(true)}
    Ok(is_system()?&&BOOT_PROCS.contains(&n.1.as_str()))
}

#[derive(Default, Clone, serde::Serialize, serde::Deserialize)]
pub(crate) struct Facts {
    // Ordered sets: `body_facts` digests them.
    /// Names this body can call (`f()`, `x.f()`, `..()` as the proc's own name is not known here, so parent calls are skipped).
    pub(crate) calls: std::collections::BTreeSet<String>,
    /// Names a PROC_REF-family macro or a CALLBACK takes.
    pub(crate) refs: std::collections::BTreeSet<String>,
    /// Global vars written.
    pub(crate) writes: std::collections::BTreeSet<String>,
    /// Names of vars written on any object (`x = ..`, `a.x = ..`, `a.x[i] = ..`, `a.x.Add(..)`, `a.x++`).
    pub(crate) field_writes: std::collections::BTreeSet<String>,
}


#[derive(serde::Serialize)]
pub(crate) struct GlobalRows{runtime_written:Vec<String>,written:Vec<String>,runtime_field_written:Vec<String>,boot_procs:usize}
impl GlobalRows{
 pub(crate) fn constant_after_init(&self,n:&str)->bool{self.runtime_written.binary_search_by(|s|s.as_str().cmp(n)).is_err()}
 pub(crate) fn field_constant_after_init(&self,n:&str)->bool{self.runtime_field_written.binary_search_by(|s|s.as_str().cmp(n)).is_err()}
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){for rows in [&self.runtime_written,&self.written,&self.runtime_field_written]{visit_names(rows,&mut visit);}}
}
pub(crate) fn names<C:crate::key_policy_control::Control>(values:impl ExactSizeIterator<Item=String>,c:&mut C)->Result<Vec<String>,C::Error>{
 let len=values.len();let bytes=len.checked_mul(std::mem::size_of::<String>()).and_then(|n|n.checked_mul(4)).ok_or_else(||c.overflow())?;
 crate::key_policy_control::reserve(c,||bytes.checked_add(128))?;let mut out=Vec::new();out.try_reserve_exact(len).map_err(|_|c.allocation_failed())?;
 if out.capacity().checked_mul(std::mem::size_of::<String>()).is_none_or(|n|n>bytes){return Err(c.allocation_failed())}
 for value in values{c.checkpoint()?;out.push(value);}out.sort();c.checkpoint()?;Ok(out)
}
pub(crate) fn visit_names(rows:&Vec<String>,visit:&mut impl FnMut(usize,usize)){
 visit(rows.as_ptr() as usize,rows.capacity()*std::mem::size_of::<String>());
 for name in rows{visit(name.as_ptr() as usize,name.capacity());}
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Checked { polls:usize, stop:usize, reserved:usize }
    impl crate::key_policy_control::Control for Checked {
        type Error=&'static str;
        const CHECKED:bool=true;
        fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.polls>=self.stop{Err("actual cancellation")}else{Ok(())}}
        fn reserve(&mut self,n:usize)->Result<(),Self::Error>{self.reserved=self.reserved.checked_add(n).ok_or("overflow")?;Ok(())}
        fn overflow(&mut self)->Self::Error{"overflow"}
        fn allocation_failed(&mut self)->Self::Error{"allocation"}
    }
    fn facts(calls:&[&str],refs:&[&str],writes:&[&str])->Facts {
        Facts{calls:calls.iter().map(|s|s.to_string()).collect(),refs:refs.iter().map(|s|s.to_string()).collect(),writes:writes.iter().map(|s|s.to_string()).collect(),field_writes:Default::default()}
    }
    #[test]
    fn checked_graph_retracts_runtime_escape_and_retries_after_actual_cancellation() {
        let nodes=vec![
            (("/".into(),"static_entries_build".into()),facts(&["boot_only","escaped"],&[],&[])),
            (("/".into(),"boot_only".into()),facts(&[],&[],&["constant"])),
            (("/".into(),"escaped".into()),facts(&[],&[],&["dynamic"])),
            (("/".into(),"runtime".into()),facts(&["escaped"],&[],&[])),
        ];
        let roots=[true,false,false,false];
        let mut cancelled=Checked{polls:0,stop:7,reserved:0};
        assert!(matches!(GlobalIndex::from_facts_controlled(&nodes,&roots,&mut cancelled),Err("actual cancellation")));
        let mut admitted=Checked{polls:0,stop:usize::MAX,reserved:0};
        let index=GlobalIndex::from_facts_controlled(&nodes,&roots,&mut admitted).unwrap();
        assert_eq!(index.boot_procs,2);
        assert!(index.constant_after_init("constant"));
        assert!(!index.constant_after_init("dynamic"));
        assert!(admitted.reserved>0);
        let rows=index.into_rows(&mut admitted).unwrap();
        assert!(rows.constant_after_init("constant"));
        assert!(!rows.constant_after_init("dynamic"));
        let mut bytes=0;rows.visit_storage(|_,n|bytes+=n);assert!(bytes>0);
    }
}
