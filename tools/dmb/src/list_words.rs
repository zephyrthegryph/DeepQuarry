//! Copy-on-write immutable list objects. Physical/shared ownership never
//! changes the semantic sequence exposed to validators and analysis tools.
use serde::{Serialize, Serializer, Deserialize, Deserializer};
use std::ops::{Deref,DerefMut};
use std::sync::Arc;
#[derive(Clone, Debug)]
pub enum ListWords { Owned(Vec<u32>), Shared(Arc<[u32]>) }
impl Default for ListWords { fn default()->Self {Self::Owned(Vec::new())} }
impl Deref for ListWords {
    type Target=[u32];
    fn deref(&self)->&[u32] {match self {Self::Owned(words)=>words,Self::Shared(words)=>words}}
}
impl DerefMut for ListWords { fn deref_mut(&mut self)->&mut [u32] {self.to_mut()} }
impl ListWords {
    pub fn to_mut(&mut self)->&mut Vec<u32> {
        if let Self::Shared(words)=self {*self=Self::Owned(words.to_vec());}
        match self {Self::Owned(words)=>words,Self::Shared(_)=>unreachable!()}
    }
    pub fn as_slice(&self)->&[u32] {self}
    pub fn capacity(&self)->usize {match self {Self::Owned(words)=>words.capacity(),Self::Shared(words)=>words.len()}}
    pub fn push(&mut self,word:u32) {self.to_mut().push(word);}
    pub fn insert(&mut self,index:usize,word:u32) {self.to_mut().insert(index,word);}
    pub fn remove(&mut self,index:usize)->u32 {self.to_mut().remove(index)}
    pub fn extend(&mut self,words:impl IntoIterator<Item=u32>) {self.to_mut().extend(words);}
    pub fn extend_from_slice(&mut self,words:&[u32]) {self.to_mut().extend_from_slice(words);}
    pub fn resize(&mut self,len:usize,word:u32) {self.to_mut().resize(len,word);}
    pub fn truncate(&mut self,len:usize) {self.to_mut().truncate(len);}
    pub fn clear(&mut self) {*self=Self::default();}
    pub fn retain(&mut self,f:impl FnMut(&u32)->bool) {self.to_mut().retain(f);}
    pub fn splice<R:std::ops::RangeBounds<usize>,I:IntoIterator<Item=u32>>(&mut self,range:R,words:I)->std::vec::Splice<'_,I::IntoIter> {self.to_mut().splice(range,words)}
}
impl From<Vec<u32>> for ListWords {fn from(words:Vec<u32>)->Self {Self::Owned(words)}}
impl From<Arc<[u32]>> for ListWords {fn from(words:Arc<[u32]>)->Self {Self::Shared(words)}}
impl AsRef<[u32]> for ListWords {fn as_ref(&self)->&[u32] {self}}
impl FromIterator<u32> for ListWords {fn from_iter<I:IntoIterator<Item=u32>>(words:I)->Self {Self::Owned(words.into_iter().collect())}}
impl PartialEq for ListWords {fn eq(&self,other:&Self)->bool {self.as_slice()==other.as_slice()}}
impl Eq for ListWords {}
impl std::hash::Hash for ListWords {fn hash<H:std::hash::Hasher>(&self,state:&mut H) {std::hash::Hash::hash(self.as_slice(),state);}}
impl PartialEq<Vec<u32>> for ListWords {fn eq(&self,other:&Vec<u32>)->bool {self.as_slice()==other.as_slice()}}
impl PartialEq<ListWords> for Vec<u32> {fn eq(&self,other:&ListWords)->bool {self.as_slice()==other.as_slice()}}
impl Serialize for ListWords {fn serialize<S:Serializer>(&self,s:S)->Result<S::Ok,S::Error> {self.as_slice().serialize(s)}}
impl<'de> Deserialize<'de> for ListWords {fn deserialize<D:Deserializer<'de>>(d:D)->Result<Self,D::Error> {Vec::<u32>::deserialize(d).map(Self::Owned)}}
impl<'a> IntoIterator for &'a ListWords {type Item=&'a u32;type IntoIter=std::slice::Iter<'a,u32>;fn into_iter(self)->Self::IntoIter {self.iter()}}
impl<'a> IntoIterator for &'a mut ListWords {type Item=&'a mut u32;type IntoIter=std::slice::IterMut<'a,u32>;fn into_iter(self)->Self::IntoIter {self.iter_mut()}}
impl IntoIterator for ListWords {type Item=u32;type IntoIter=std::vec::IntoIter<u32>;fn into_iter(self)->Self::IntoIter {match self {Self::Owned(words)=>words,Self::Shared(words)=>words.to_vec()}.into_iter()}}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ListTable(Vec<ListWords>);
impl Deref for ListTable {type Target=Vec<ListWords>;fn deref(&self)->&Self::Target {&self.0}}
impl DerefMut for ListTable {fn deref_mut(&mut self)->&mut Self::Target {&mut self.0}}
impl ListTable {
    pub fn push(&mut self,words:impl Into<ListWords>) {self.0.push(words.into());}
    pub fn resize(&mut self,len:usize,words:impl Into<ListWords>) {self.0.resize(len,words.into());}
    pub fn extend<T:Into<ListWords>>(&mut self,words:impl IntoIterator<Item=T>) {self.0.extend(words.into_iter().map(Into::into));}
}
impl<T:Into<ListWords>> From<Vec<T>> for ListTable {fn from(words:Vec<T>)->Self {Self(words.into_iter().map(Into::into).collect())}}
impl<T:Into<ListWords>> FromIterator<T> for ListTable {fn from_iter<I:IntoIterator<Item=T>>(words:I)->Self {Self(words.into_iter().map(Into::into).collect())}}
impl<'a> IntoIterator for &'a ListTable {type Item=&'a ListWords;type IntoIter=std::slice::Iter<'a,ListWords>;fn into_iter(self)->Self::IntoIter {self.0.iter()}}
impl<'a> IntoIterator for &'a mut ListTable {type Item=&'a mut ListWords;type IntoIter=std::slice::IterMut<'a,ListWords>;fn into_iter(self)->Self::IntoIter {self.0.iter_mut()}}
impl IntoIterator for ListTable {type Item=ListWords;type IntoIter=std::vec::IntoIter<ListWords>;fn into_iter(self)->Self::IntoIter {self.0.into_iter()}}
