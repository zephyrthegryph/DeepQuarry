//! Shared read-back adapter.
use std::collections::BTreeSet;
use crate::lint::{Cx,Lint,Meta,Registry,Sink};
use crate::raw_tree_read_back_policy as policy;
struct ReadBack{p:policy::ReadBack}
impl Lint for ReadBack{fn meta(&self)->&Meta{&policy::META}fn scan_tree(&self,cx:&Cx,out:&mut Sink){let mut read_back=BTreeSet::new();for f in cx.all_files(){policy::schema(f,&self.p,|ty|{read_back.insert(ty.to_string());});}for f in cx.files(){policy::judge_file(f,&self.p,&read_back,out)}}}
pub fn register(reg:&mut Registry){reg.add(ReadBack{p:policy::ReadBack::new()})}
