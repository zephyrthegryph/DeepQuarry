//! Borrowed pinned builtin DATA for ordinary utility value projection only.
//! No runtime slot, parser/model, source occurrence or currentness is issued.
use super::*;
#[derive(Clone,Copy)]pub enum InitialValue{Absent,Number(f32),Text(&'static str),Prefab(&'static str)}
pub fn owner_encounters(profile:PackedU128)->Result<impl Iterator<Item=&'static str>,CheckerBuiltinError>{
 let catalog=pinned_catalog()?;if catalog.profile!=profile{return Err(CheckerBuiltinError::FactsHash)}
 Ok(data::ROWS.iter().map(|row|row.owner))
}
pub fn initial_value(row:&CheckerBuiltinDeclaration,profile:PackedU128)->Result<InitialValue,CheckerBuiltinError>{
 let catalog=pinned_catalog()?;if catalog.profile!=profile{return Err(CheckerBuiltinError::FactsHash)}
 let actual=catalog.members.get(&(row.owner,row.name,row.kind)).and_then(|index|catalog.declarations.get(*index)).ok_or(CheckerBuiltinError::Shape("utility builtin row absent"))?;
 if actual.ordinal!=row.ordinal||!Arc::ptr_eq(&actual.metadata,&row.metadata){return Err(CheckerBuiltinError::Shape("utility builtin row differs from actual catalog"))}
 let raw=data::ROWS.get(row.ordinal as usize).ok_or(CheckerBuiltinError::Shape("utility builtin ordinal"))?;
 Ok(match raw.default{None=>InitialValue::Absent,Some(RawDefault::Number(bits))=>InitialValue::Number(f32::from_bits(bits)),Some(RawDefault::Text(text))=>InitialValue::Text(text),Some(RawDefault::Type(path))=>InitialValue::Prefab(path)})
}

pub fn declared_hint(row:&CheckerBuiltinDeclaration,profile:PackedU128)->Result<Option<&'static str>,CheckerBuiltinError>{let catalog=pinned_catalog()?;if catalog.profile!=profile{return Err(CheckerBuiltinError::FactsHash)}let actual=catalog.members.get(&(row.owner,row.name,row.kind)).and_then(|index|catalog.declarations.get(*index)).ok_or(CheckerBuiltinError::Shape("utility builtin row absent"))?;if actual.ordinal!=row.ordinal||!Arc::ptr_eq(&actual.metadata,&row.metadata){return Err(CheckerBuiltinError::Shape("utility builtin row differs from actual catalog"))}Ok(data::ROWS.get(row.ordinal as usize).ok_or(CheckerBuiltinError::Shape("utility builtin ordinal"))?.type_path)}
