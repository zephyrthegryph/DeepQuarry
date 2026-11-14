//! Pure request/terminal selection DATA, never source or completion authority.
use crate::selected_exclusions_wire::Hex128;
use serde::{Deserialize,Serialize};use std::io;
#[derive(Clone,Copy,Debug,Eq,PartialEq,Serialize,Deserialize)]#[serde(deny_unknown_fields)]
pub struct SelectionBinding{pub selectors:u64,pub hash:Hex128}
impl SelectionBinding{
 pub fn for_selectors(selectors:&[String])->io::Result<Self>{Self::for_selectors_using(selectors,&||Ok(()))}
 pub fn for_selectors_using(selectors:&[String],poll:&dyn Fn()->io::Result<()>)->io::Result<Self>{
  poll()?;
  let count=u64::try_from(selectors.len()).map_err(|_|io::Error::from(io::ErrorKind::InvalidInput))?;
  let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"native-registry-check-selector-data-v1\0");hash.update(&count.to_le_bytes());
  for selector in selectors{poll()?;let length=u64::try_from(selector.len()).map_err(|_|io::Error::from(io::ErrorKind::InvalidInput))?;hash.update(&length.to_le_bytes());for bytes in selector.as_bytes().chunks(16384){poll()?;hash.update(bytes)}}
  Ok(Self{selectors:count,hash:Hex128(hash.digest128())})
 }
}
#[cfg(test)]mod tests{use super::*;#[test]fn selector_binding_preserves_exact_order_duplicates_and_boundaries_as_data(){let make=|rows:&[&str]|SelectionBinding::for_selectors(&rows.iter().map(|row|row.to_string()).collect::<Vec<_>>()).unwrap();assert_ne!(make(&["a","bc"]),make(&["ab","c"]));assert_ne!(make(&["a","b"]),make(&["b","a"]));assert_ne!(make(&["a"]),make(&["a","a"]));assert_eq!(make(&[]).selectors,0);}}
