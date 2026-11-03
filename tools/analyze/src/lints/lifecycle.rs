//! Original lifecycle policy delegates to the unique source-neutral algorithm.
use crate::{lint::{Cx,Lint,Meta,Registry,Sink},dm::schema::Schema,parity::{ParseKind,Parity},key_policy_control::Compatibility,lifecycle_policy::{self as policy,FileFacts,Patterns}};
struct Lifecycle{patterns:Patterns}
impl Lint for Lifecycle{fn meta(&self)->&Meta{&policy::META}
 fn scan_tree(&self,cx:&Cx,out:&mut Sink){let all=cx.all_files();let schema=Schema::get(cx.tree,&all);let mut compatibility=Compatibility;let mut files=Vec::new();for file in cx.files(){let bodies=policy::scan_using(file.code(),&self.patterns,&mut compatibility,&mut Compatibility).unwrap_or_else(|never|match never{});files.push(FileFacts{relative:file.rel.clone(),bodies});}let output=std::cell::RefCell::new(out);policy::judge_using(&schema,&files,&self.patterns,&mut compatibility,&mut|rule,relative,line,message,_|{output.borrow_mut().site_in_msg(rule,relative,line as usize,message);Ok(())},&mut|message,_|{output.borrow_mut().note(message);Ok(())}).unwrap_or_else(|never|match never{});}
    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/lifecycle_lint.py"],
            old_raw: &[],
            blank: &[],
            parse: ParseKind::FileLine,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}
pub fn register(reg:&mut Registry){reg.add(Lifecycle{patterns:Patterns::new()});}
