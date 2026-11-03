//! Same API registry adapter; the unique lexical/index policy lives in api_policy.
use std::sync::OnceLock;
use crate::{api_policy,dm::{field_write::Fields,pylines::recorded_into},incr,lint::{Cx,Lint,Meta,Registry,Sink},parity::{ParseKind,Parity},tree::SourceFile};
struct Api{core:api_policy::Api}
struct Reporting<'file,'out>{file:&'file SourceFile,out:&'out mut Sink}
impl api_policy::Reporter for Reporting<'_,'_>{fn allowed(&mut self,line:usize)->bool{self.out.allowed(self.file,line,"api")}fn site(&mut self,rule:&str,line:usize){self.out.site(rule,line)}}
impl Lint for Api{fn meta(&self)->&Meta{&api_policy::META}
 fn scan_file(&self,_cx:&Cx,file:&SourceFile,out:&mut Sink){self.core.scan_file(file,&mut Reporting{file,out});}
    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        // field_write: every file, unit tests included. The global declared-field index is the merge
        // of per-file facts (cached by content); one file's judgement is cached by (content, index).
        let all = cx.all_files();
        let facts = incr::facts("api-fw-facts", &all, |f|api_policy::fw_facts(f));
        let files = cx.files();
        let index = api_policy::merge_index(&facts);
        let key = incr::ctx_key(&(&index.fields, api_policy::sorted_members(&index), api_policy::sorted_globals(&index)));
        let fields: OnceLock<Fields> = OnceLock::new();
        let found = recorded_into(out, || {
            incr::keyed("api-fw-judge", key, &files, |f| {
                let fields = fields.get_or_init(|| index.all_fields());
                let mut kept: Vec<u32> = Vec::new();
                for line in index.check(fields, &f.code().text) {
                    if !crate::dm::sys::kept_recorded(f, line, "api") {
                        kept.push(line as u32);
                    }
                }
                kept
            })
        });
        for (f, lines) in files.iter().zip(found) {
            for line in lines {
                out.site_in("field_write", &f.rel, line as usize);
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/api_lints.py"],
            old_raw: &[&["tools/ci/api_lints.py", "--report"]],
            blank: &[],
            parse: ParseKind::Report,
            update: Some(&["tools/ci/api_lints.py", "--update"]),
            seed: Some(&["tools/ci/api_lints.py", "--seed"]),
            files: &["tools/ci/api_lints_baseline.txt"],
            selftest: None,
        })
    }
}
pub fn register(reg:&mut Registry){reg.add(Api{core:api_policy::Api::new()});}
