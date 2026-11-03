pub const NAME:&str="sys/sfx";
pub const CONFIG:&str="[lint.sys]\nexempt_prefixes=[\"code/modules/unit_tests/\"]\n";
pub const FILES:&[(&str,&str)]=&[
("code/__defines/sfx.dm","// Named sets\n#define SFX_BEEP \"beep\"\n// File sets.\n#define SFX_FILE 'sound/file.ogg'\n"),
("code/a.dm","/proc/feed_sound_names()\n    playsound(src, ambient_sound, 50)\n    playsound_local(src, pick(src.window_sound), 50)\n    play_sfx(src, other_sound)\n    get_sfx(sfx_name)\n    playsound(src, user, 50)\n"),
("code/z.dm","/obj/sound_fixture\n    ambient_sound = pick('sound/a.ogg', 'sound/b.wav')\n    var/list/other_sound = list('sound/c.mid')\n    sfx_name = \"beep\"\n    unused_sound = 'sound/unused.mp3'\n    user = 'sound/user.ogg'\nGLOBAL_LIST_INIT(window_sound, list('sound/window.ogg'))\n/proc/literal_sounds()\n    playsound(src, 'sound/direct.ogg', 50)\n    playsound_local(src, \"beep\", 50)\n    get_sfx(\"beep\")\n    var/datum/effect/effect/system/spark_spread/sparks\n    playsound(src,\n        'sound/multiline.wav',\n        50)\n    playsound(src, 'sound/allowed.ogg', 50) // ALLOW(sys_literal_playsound): this deliberate fixture checks the original annotation path\n    playsound(src, 'sound//path.ogg', 50)\n// spark_spread and playsound(src, 'sound/comment.ogg') are comments\n"),
("code/game/sound_sets.dm","/proc/registry_original_suppression()\n    playsound(src, 'sound/registry.ogg', 50)\n    var/datum/effect/effect/system/spark_spread/registry\n"),
("maps/sounds.dm","/proc/map_sound()\n    playsound(src, 'sound/map.mp3', 50)\n"),
("code/.hidden/sound.dm","/proc/hidden_sound()\n    playsound(src, 'sound/hidden.ogg', 50)\n"),
("code/modules/unit_tests/sound.dm","/proc/test_sound()\n    playsound(src, 'sound/exempt.ogg', 50)\n")];
pub fn configuration(case:usize)->String{match case{0|4=>CONFIG.into(),1=>"[lint.sys]\nexempt_prefixes=[\"code/modules/unit_tests/\",\"code/a.dm\"]\n".into(),2=>format!("{CONFIG}[lint.\"sys/sfx\"]\nexempt_prefixes=[\"code/z.dm\"]\n"),3=>format!("{CONFIG}[lint.\"sys/sfx\".ceilings]\nliteral_playsound=50\n"),_=>panic!("unknown real sfx case")}}
pub fn files(case:usize)->Vec<(&'static str,String)>{FILES.iter().map(|(path,text)|(*path,if case==4&&*path=="code/__defines/sfx.dm"{"#define SFX_UNMARKED \"beep\"\n".into()}else{(*text).into()})).collect()}
