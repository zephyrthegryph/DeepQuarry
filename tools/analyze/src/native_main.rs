//! Native-only executable client. It never loads the legacy Analyze engine.
fn main()->std::process::ExitCode{
 let args=std::env::args().skip(1).collect::<Vec<_>>();
 match args.first().map(String::as_str){
  Some("query"|"native-query")=>dq_analyze::native_cli_client::cli(&args[1..]),
  Some("native-check")=>dq_analyze::native_cli_client::policy_cli(&args[1..],false),
  Some("native-baseline")=>dq_analyze::native_cli_client::policy_cli(&args[1..],true),
  Some("gen"|"native-gen")=>dq_analyze::native_cli_client::generation_cli(&args[1..]),
  _=>{eprintln!("usage: analyze-native (query|gen) --dmbc ABSOLUTE_EXE REQUEST.json [--jsonl]");std::process::ExitCode::from(2)}
 }
}
