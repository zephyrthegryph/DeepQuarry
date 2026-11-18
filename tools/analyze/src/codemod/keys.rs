//! The key-collision report.
//!
//! A codemod that gives an entry a key (an op's key, a timer's `key =`) records a [`KeyUse`] for it. The
//! report groups the uses by `(owner, key)` and lists every group where one key names more than one handler:
//! on the same owner the second `after(..., key = "x")` replaces the pending first, and an op key that two
//! declarations share merges them. A collision between keys the old form already carried is `preserved`:
//! the conversion keeps today's behaviour and the report only says where it is. A collision that involves a
//! key the codemod synthesized is `unresolved` until the codemod resolves it (an `extend()` when the old
//! semantics appended, a macro-kind prefix when the entries were independent), and the gate fails while any
//! is unresolved (phase 2.5: "0 unresolved collisions on today's tree").

use std::collections::BTreeMap;

use super::KeyUse;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Collision {
    pub owner: String,
    pub key: String,
    /// `(origin, handler, synthesized)` of every use.
    pub uses: Vec<(String, String, bool)>,
    pub resolved: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct KeyReport {
    pub synthesized: usize,
    pub preserved: usize,
    pub collisions: Vec<Collision>,
    pub unresolved: usize,
}

pub fn analyze(keys: &[KeyUse]) -> KeyReport {
    let mut rep = KeyReport::default();
    let mut groups: BTreeMap<(String, String), Vec<&KeyUse>> = BTreeMap::new();
    for k in keys {
        if k.synthesized {
            rep.synthesized += 1;
        } else {
            rep.preserved += 1;
        }
        groups.entry((k.owner.clone(), k.key.clone())).or_default().push(k);
    }
    for ((owner, key), uses) in groups {
        let mut handlers: Vec<&str> = uses.iter().map(|u| u.handler.as_str()).collect();
        handlers.sort();
        handlers.dedup();
        if handlers.len() < 2 {
            continue;
        }
        let resolved = uses.iter().all(|u| !u.synthesized);
        if !resolved {
            rep.unresolved += 1;
        }
        rep.collisions.push(Collision { owner, key, uses: uses.iter().map(|u| (u.origin.clone(), u.handler.clone(), u.synthesized)).collect(), resolved });
    }
    rep
}

#[cfg(test)]
mod tests {
    use super::*;

    fn k(owner: &str, key: &str, handler: &str, synth: bool) -> KeyUse {
        KeyUse { owner: owner.into(), key: key.into(), origin: "f.dm:1".into(), handler: handler.into(), synthesized: synth }
    }

    #[test]
    fn same_key_same_handler_is_no_collision() {
        let r = analyze(&[k("/a", "t", "PROC_REF(x)", false), k("/a", "t", "PROC_REF(x)", false)]);
        assert!(r.collisions.is_empty());
        assert_eq!(r.preserved, 2);
    }

    #[test]
    fn preserved_collisions_are_listed_and_resolved() {
        let r = analyze(&[k("/a", "t", "PROC_REF(x)", false), k("/a", "t", "PROC_REF(y)", false), k("/b", "t", "PROC_REF(y)", false)]);
        assert_eq!(r.collisions.len(), 1);
        assert!(r.collisions[0].resolved);
        assert_eq!(r.unresolved, 0);
    }

    #[test]
    fn a_synthesized_key_in_a_collision_is_unresolved() {
        let r = analyze(&[k("/a", "t", "PROC_REF(x)", false), k("/a", "t", "PROC_REF(y)", true)]);
        assert_eq!(r.unresolved, 1);
        assert_eq!(r.synthesized, 1);
    }
}

/// Same ordered groups and collision decisions as analyze(), with every owned
/// row/string admitted by the held codemod operation before it allocates.
pub fn analyze_using(keys:&[KeyUse],work:&dyn crate::policy_finish::admitted::Work)->std::io::Result<KeyReport>{
 use super::work as paid;
 let mut ordered=paid::vec_capacity(Some(work),keys.len())?;
 let mut rep=KeyReport::default();
 for key in keys{work.checkpoint()?;if key.synthesized{rep.synthesized+=1}else{rep.preserved+=1}ordered.push(key);}
 paid::stable_sort_by(Some(work),&mut ordered,|a,b|(&a.owner,&a.key).cmp(&(&b.owner,&b.key)))?;
 let mut first=0;
 while first<ordered.len(){
  work.checkpoint()?;let seed=ordered[first];let mut end=first+1;
  while end<ordered.len()&&ordered[end].owner==seed.owner&&ordered[end].key==seed.key{work.checkpoint()?;end+=1;}
  // The old sorted/dedup handler vector asks only whether two distinct
  // handlers exist. This borrowed comparison gives exactly the same answer.
  if ordered[first+1..end].iter().any(|value|value.handler!=seed.handler){
   let resolved=ordered[first..end].iter().all(|value|!value.synthesized);
   let owner=paid::own(Some(work),&seed.owner)?;let key=paid::own(Some(work),&seed.key)?;
   let mut uses=paid::vec_capacity(Some(work),end-first)?;
   for value in &ordered[first..end]{work.checkpoint()?;uses.push((paid::own(Some(work),&value.origin)?,paid::own(Some(work),&value.handler)?,value.synthesized));}
   paid::row(Some(work),&mut rep.collisions)?;rep.collisions.push(Collision{owner,key,uses,resolved});if !resolved{rep.unresolved+=1}
  }
  first=end;
 }
 work.checkpoint()?;Ok(rep)
}
#[cfg(test)]mod admitted_controls{use super::*;
 struct Denied;impl crate::policy_finish::admitted::Work for Denied{fn checkpoint(&self)->std::io::Result<()>{Ok(())}fn reserve(&self,_:usize)->std::io::Result<()>{Err(std::io::Error::from_raw_os_error(1450))}fn overflow(&self)->std::io::Error{std::io::ErrorKind::OutOfMemory.into()}}
 #[test]fn first_actual_allocation_error_survives_key_grouping(){let error=analyze_using(&[],&Denied).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));}
}
