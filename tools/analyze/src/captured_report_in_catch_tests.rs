use super::*;
use crate::captured_raw_file::RawPolicyViews;
use std::cell::Cell;

const PROBE: &str = concat!(
    "/proc/probe()\n",
    "\tcatch (e)\n",
    "\t\t// CRASH(\"comment\")\n",
    "\t\tvar/message = \"stack_trace()\"\n",
    "\n",
    "\t\t#if 0\n",
    "\t\tCRASH(\"inactive but authored\") // ALLOW(report_in_catch): the original never consults ALLOW\n",
    "\t\t#endif\n",
    "\t\tcatch (nested)\n",
    "\t\t\tstack_trace(\"reported only once\")\n",
    "\t\tstack_trace (\"requires immediate paren\")\n",
    "\t\tstack_trace(\"first\") + CRASH(\"same line\")\n",
    "\treturn\n",
    "\t\tCRASH(\"after authored dedent\")\n",
    "\tcatching(e)\n",
    "\t\tCRASH(\"not a catch head\")\n",
    "\tcatch (e)\n",
    "        CRASH(\"spaces do not count as tabs\")\n",
    "\t\tCRASH(\"after space dedent\")\n",
    "\tcatch (e)\n",
    "\t\t/* CRASH(\"block comment\")\n",
    "\t\tstack_trace(\"still in comment\") */\n",
    "\t\tCALL_THROW()\n",
    "\t\tCRASH(\"same range after comment\")\n",
);

// Frozen old nested look-ahead algorithm, independent of the new shared scan.
fn old_lines(file: &SourceFile) -> Vec<usize> {
    let head=crate::pat::Pat::new(r"^\s*catch\b");
    let throwing=crate::pat::Pat::new(r"\b(?:stack_trace|CRASH)\(");
    let indent=|text: &str|text.len()-text.trim_start_matches('\t').len();
    let lines=file.code().numbered().collect::<Vec<_>>();
    let mut reported=Vec::new();
    for (i,&(_,line)) in lines.iter().enumerate() {
        if !head.is_match(line){continue}
        for &(number,text) in &lines[i+1..] {
            if text.trim().is_empty(){continue}
            if indent(text)<=indent(line){break}
            if throwing.is_match(text)&&!reported.contains(&number){reported.push(number)}
        }
    }
    reported
}

struct Pages {
    files: Vec<SourceFile>,
    calls: Cell<usize>,
    stop: bool,
}
impl RawPolicyPages for Pages {
    fn for_each(&self,visit:&mut dyn FnMut(&str,RawPolicyViews<'_>)->Result<bool,Failure>)->Result<bool,Failure>{
        self.calls.set(self.calls.get()+1);
        for file in &self.files {
            if !visit(&file.rel,RawPolicyViews::from_source(file))?||self.stop{return Ok(false)}
        }
        Ok(true)
    }
}

#[test]
fn report_in_catch_keeps_authored_code_ranges_frozen_sites_and_no_allow_usage() {
    let files=["code/dir/sub.dm","code/dir-a.dm","code/exempt.dm","code/tests/test.dm","code/_generated/parts.dm","code/.hidden/witness.dm"]
        .map(|path|SourceFile::from_text(path,PROBE));
    assert_eq!(old_lines(&files[0]),[7,10,12,24]);
    let pages=Pages{files:Vec::from(files),calls:Cell::new(0),stop:false};
    let config=Config::capture(crate::captured_raw_policy::Configuration::Captured(
        b"[lint.report_in_catch]\nexempt_files=['code/exempt.dm']\n",
    )).unwrap();
    let policy=Policy::ReportInCatch;
    assert!(policy.selected_source_phase(0));
    assert_eq!(policy.source_visits(),1);
    assert!(!policy.permits_used_allow("report_in_catch"));
    let data=collect(&pages,policy,&config,&Budget::new(16<<20).unwrap(),&||Ok(())).unwrap();
    assert_eq!(pages.calls.get(),1);
    assert!(data.message_only()&&data.source_text().is_empty()&&data.allow_used().is_empty());
    assert!(data.allow_source_digest("code/dir-a.dm").is_none());
    let expected=[&pages.files[1],&pages.files[0]].into_iter().flat_map(|file|{
        old_lines(file).into_iter().map(move |line|Site{
            rel:file.rel.clone(),line:line as u32,rule:"throwing_report".into(),
            msg:"stack_trace()/CRASH() inside a catch block".into(),key:String::new(),ident:String::new(),
        })
    }).collect::<Vec<_>>();
    assert_eq!(data.sites(),expected.as_slice());

    #[cfg(feature="legacy-sem")]
    {
        let registry=crate::run::registry();
        let legacy=registry.find("report_in_catch").unwrap();
        let tree=crate::tree::Tree::from_files(pages.files);
        let scope=config.borrowed_report_scope(legacy.meta().name,legacy.meta().group).unwrap();
        let mut old=crate::lint::Sink::new();
        legacy.scan_tree(&crate::lint::Cx{ fixture:None,tree:&tree,meta:legacy.meta(),scope},&mut old);
        assert_eq!(old.sites.as_slice(),data.sites());
        assert!(old.allow_used.is_empty());
    }
}

#[test]
fn report_in_catch_never_completes_a_short_actual_selected_source_phase() {
    let pages=Pages{files:vec![SourceFile::from_text("code/a.dm",PROBE)],calls:Cell::new(0),stop:true};
    let config=Config::capture(crate::captured_raw_policy::Configuration::ProvenMissing).unwrap();
    let result=collect(&pages,Policy::ReportInCatch,&config,&Budget::new(16<<20).unwrap(),&||Ok(()));
    assert!(matches!(result,Err(Failure::Unsupported(message)) if message.contains("stopped before EOF")));
}
