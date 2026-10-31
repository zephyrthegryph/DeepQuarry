//! Borrowed emitter view over original or moved ordered dependency RESULT rows.
//! No conversion back to trees and no copied analysis/AST/source data.
use crate::reactive_facts::{DepsAnalysis,Untracked,Leaf};
use std::collections::BTreeSet;
#[derive(Clone,Copy)]pub enum Analysis<'a>{Owned(&'a DepsAnalysis),#[cfg(feature="native-policy")]Frozen(&'a crate::reactive_dependency_result::FrozenDeps)}
#[derive(Clone,Copy)]pub enum Names<'a>{Tree(&'a BTreeSet<String>),Rows(&'a[String])}
pub enum NameIter<'a>{Tree(std::collections::btree_set::Iter<'a,String>),Rows(std::slice::Iter<'a,String>)}
impl<'a> Iterator for NameIter<'a>{type Item=&'a String;fn next(&mut self)->Option<Self::Item>{match self{Self::Tree(rows)=>rows.next(),Self::Rows(rows)=>rows.next()}}fn size_hint(&self)->(usize,Option<usize>){match self{Self::Tree(rows)=>rows.size_hint(),Self::Rows(rows)=>rows.size_hint()}}}
impl ExactSizeIterator for NameIter<'_>{}
impl<'a> Names<'a>{pub fn is_empty(self)->bool{self.len()==0}pub fn len(self)->usize{match self{Self::Tree(rows)=>rows.len(),Self::Rows(rows)=>rows.len()}}pub fn iter(self)->NameIter<'a>{match self{Self::Tree(rows)=>NameIter::Tree(rows.iter()),Self::Rows(rows)=>NameIter::Rows(rows.iter())}}}
pub enum ConsumerIter<'a>{Tree(std::collections::btree_map::Iter<'a,String,Vec<Untracked>>),Rows(std::slice::Iter<'a,(String,Vec<Untracked>)>)}
impl<'a> Iterator for ConsumerIter<'a>{type Item=(&'a String,&'a Vec<Untracked>);fn next(&mut self)->Option<Self::Item>{match self{Self::Tree(rows)=>rows.next(),Self::Rows(rows)=>rows.next().map(|(name,rows)|(name,rows))}}}
pub enum StringMapIter<'a>{Tree(std::collections::btree_map::Iter<'a,String,BTreeSet<String>>),Rows(std::slice::Iter<'a,(String,Vec<String>)>)}
impl<'a> Iterator for StringMapIter<'a>{type Item=(&'a String,Names<'a>);fn next(&mut self)->Option<Self::Item>{match self{Self::Tree(rows)=>rows.next().map(|(name,rows)|(name,Names::Tree(rows))),Self::Rows(rows)=>rows.next().map(|(name,rows)|(name,Names::Rows(rows)))}}}
impl<'a> Analysis<'a>{
 pub fn consumers(self)->ConsumerIter<'a>{match self{Self::Owned(data)=>ConsumerIter::Tree(data.consumers.iter()),#[cfg(feature="native-policy")]Self::Frozen(data)=>ConsumerIter::Rows(data.consumers.iter())}}
 pub fn leaves(self)->&'a[Leaf]{match self{Self::Owned(data)=>&data.leaves,#[cfg(feature="native-policy")]Self::Frozen(data)=>&data.leaves}}
 pub fn draw_keys(self)->StringMapIter<'a>{match self{Self::Owned(data)=>StringMapIter::Tree(data.draw_keys.iter()),#[cfg(feature="native-policy")]Self::Frozen(data)=>StringMapIter::Rows(data.draw_keys.iter())}}
}

impl<'a> IntoIterator for Names<'a>{type Item=&'a String;type IntoIter=NameIter<'a>;fn into_iter(self)->Self::IntoIter{self.iter()}}
pub enum PairIter<'a>{Tree(std::collections::btree_set::Iter<'a,(String,String)>),Rows(std::slice::Iter<'a,(String,String)>)}
impl<'a> Iterator for PairIter<'a>{type Item=&'a(String,String);fn next(&mut self)->Option<Self::Item>{match self{Self::Tree(rows)=>rows.next(),Self::Rows(rows)=>rows.next()}}}
pub enum VerbIter<'a>{Tree(std::collections::btree_map::Iter<'a,String,(BTreeSet<String>,bool)>),Rows(std::slice::Iter<'a,(String,(Vec<String>,bool))>)}
impl<'a> Iterator for VerbIter<'a>{type Item=(&'a String,(Names<'a>,bool));fn next(&mut self)->Option<Self::Item>{match self{Self::Tree(rows)=>rows.next().map(|(id,(names,flag))|(id,(Names::Tree(names),*flag))),Self::Rows(rows)=>rows.next().map(|(id,(names,flag))|(id,(Names::Rows(names),*flag)))}}}
impl<'a> Analysis<'a>{
 pub fn draw_reads(self)->StringMapIter<'a>{match self{Self::Owned(data)=>StringMapIter::Tree(data.draw_reads.iter()),#[cfg(feature="native-policy")]Self::Frozen(data)=>StringMapIter::Rows(data.draw_reads.iter())}}
 pub fn draw_hops(self)->StringMapIter<'a>{match self{Self::Owned(data)=>StringMapIter::Tree(data.draw_hops.iter()),#[cfg(feature="native-policy")]Self::Frozen(data)=>StringMapIter::Rows(data.draw_hops.iter())}}
 pub fn draw_links(self)->StringMapIter<'a>{match self{Self::Owned(data)=>StringMapIter::Tree(data.draw_links.iter()),#[cfg(feature="native-policy")]Self::Frozen(data)=>StringMapIter::Rows(data.draw_links.iter())}}
 pub fn verb_reads(self)->VerbIter<'a>{match self{Self::Owned(data)=>VerbIter::Tree(data.verb_reads.iter()),#[cfg(feature="native-policy")]Self::Frozen(data)=>VerbIter::Rows(data.verb_reads.iter())}}
 pub fn draws(self)->Names<'a>{match self{Self::Owned(data)=>Names::Tree(&data.draws),#[cfg(feature="native-policy")]Self::Frozen(data)=>Names::Rows(&data.draws)}}
 pub fn stat_reads(self)->Names<'a>{match self{Self::Owned(data)=>Names::Tree(&data.stat_reads),#[cfg(feature="native-policy")]Self::Frozen(data)=>Names::Rows(&data.stat_reads)}}
 pub fn reads(self)->PairIter<'a>{match self{Self::Owned(data)=>PairIter::Tree(data.reads.iter()),#[cfg(feature="native-policy")]Self::Frozen(data)=>PairIter::Rows(data.reads.iter())}}
 pub fn candidates(self)->PairIter<'a>{match self{Self::Owned(data)=>PairIter::Tree(data.candidates.iter()),#[cfg(feature="native-policy")]Self::Frozen(data)=>PairIter::Rows(data.candidates.iter())}}
 pub fn consumer(self,id:&str)->Option<&'a[Untracked]>{match self{Self::Owned(data)=>data.consumers.get(id).map(Vec::as_slice),#[cfg(feature="native-policy")]Self::Frozen(data)=>data.consumers.binary_search_by(|(key,_)|key.as_str().cmp(id)).ok().map(|at|data.consumers[at].1.as_slice())}}
}
