//! Native-only executable client. It never loads the legacy Analyze engine.
fn main()->std::process::ExitCode{
 let args=std::env::args().skip(1).collect::<Vec<_>>();
 match args.first().map(String::as_str){
  Some("query"|"native-query")=>dq_analyze::native_cli_client::cli(&args[1..]),
  Some("gen")=>dq_analyze::native_cli_client::generation_unavailable(),
  _=>{eprintln!("usage: analyze-native query --dmbc ABSOLUTE_EXE REQUEST.json [--jsonl]");std::process::ExitCode::from(2)}
 }
}
