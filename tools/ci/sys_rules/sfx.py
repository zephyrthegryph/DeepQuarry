"""Sound and effect sets (doc/rewrite/systems.md section 16).

The old patterns, whole:
- literal_playsound: a literal sound file anywhere in a playsound()/playsound_local() call,
  including inside pick() lists and ternaries.
- literal_sound_var: a literal sound file (alone, in pick() or in list()) assigned to a var, list
  or proc argument whose name is fed to playsound()/playsound_local()/play_sfx()/get_sfx() as
  the sound (`playsound(src, hitsound, ...)`, `playsound(src, pick(apply_sounds), ...)`,
  `GLOBAL_LIST_INIT(emote_sound, list(...))` fed through `pick(GLOB.emote_sound)`). The
  assignment may span continuation lines.
- sfx_string_key: a bare string key ("sparks", "punch", ...) passed to playsound()/get_sfx() or
  assigned to a var fed to them,
  instead of its SFX_* id.
- spark_triple: any use of the deleted spark_spread system (new, set_up, start, attach, vars),
  wherever the lines of the triple sit.
"""
import re

RULES = {
    "literal_playsound": "play_sfx(atom, SFX_ID) with a SOUND_SET row (code/game/sound_sets.dm), not a literal file",
    "literal_sound_var": "hold a SOUND_SET id (SFX_*) in sound vars/lists fed to playsound, not a literal file",
    "sfx_string_key": "pass the SFX_* id, not the bare string key",
    "spark_triple": "fx_sparks(atom, amount, cardinals), not a spark_spread new/set_up/start",
}

SOUND_CALL = re.compile(r"(?<![\w./])(?:playsound(?:_local)?|play_sfx|get_sfx)\s*\(")
PLAY_CALL = re.compile(r"(?<![\w./])playsound(?:_local)?\s*\(")
LITERAL = re.compile(r"'[^'\n]+\.(?:ogg|wav|mid|mp3)'")
STRING_KEY = re.compile(r"(?<![\w./])(?:playsound(?:_local)?\s*\([^,()]+|get_sfx\s*\()\s*,?\s*\"[a-z_]+\"")
SPARK = re.compile(r"\bspark_spread\b")
# the sound argument of a sound call: a name, a member access, GLOB.x, or pick(<that>)
FED = re.compile(
    r"(?<![\w./])(?:playsound(?:_local)?|play_sfx)\s*\(\s*[^,()]+(?:\([^()]*\))?\s*,\s*(?:pick\s*\(\s*)?([A-Za-z_][\w.]*)\s*\)?\s*[,)]"
    r"|(?<![\w./])get_sfx\s*\(\s*(?:pick\s*\(\s*)?([A-Za-z_][\w.]*)\s*\)?\s*\)")
ASSIGN = re.compile(r"(?:^|[^\w.])(?:var/(?:\w+/)*)?(\w+)\s*(?<![!<>=])=(?!=)\s*(?:pick\s*\(|list\s*\()?")
GLOBAL_LIST = re.compile(r"GLOBAL_LIST_INIT\s*\(\s*(\w+)\s*,")
NOT_FED = {"src", "null", "TRUE", "FALSE", "usr", "user", "loc"}


def code_of(line):
    return line.split("//", 1)[0]


def statement(lines, index, start=0):
    """The text from lines[index][start:] up to its closing paren / end of statement, following
    open parens and backslash continuations onto later lines."""
    depth = 0
    out = []
    k = index
    col = start
    while k < len(lines) and k < index + 40:
        line = code_of(lines[k])[col:]
        col = 0
        for c in line:
            out.append(c)
            if c in "([":
                depth += 1
            elif c in ")]":
                depth -= 1
                if depth <= 0 and start:
                    return "".join(out)
        stripped = line.rstrip()
        if depth <= 0 and not stripped.endswith("\\") and not (start == 0 and stripped.endswith(",")):
            break
        out.append("\n")
        k += 1
    return "".join(out)


def scan(files):
    out = {rule: [] for rule in RULES}
    fed = set()
    for rel, lines in files:
        for line in lines:
            code = code_of(line)
            if "(" not in code:
                continue
            for m in FED.finditer(code):
                name = (m.group(1) or m.group(2)).split(".")[-1]
                fed.add(name)
    fed -= NOT_FED
    named = set()
    for rel, lines in files:
        if rel == "code/__defines/sfx.dm":
            text = "\n".join(lines)
            section = text[text.find("// Named sets"):text.find("// File sets.")]
            named = set(re.findall(r'#define SFX_\w+ "(\w+)"', section))
    key_assign = re.compile(r'(?:^|[^\w.])(\w+)\s*(?<![!<>=])=(?!=)\s*"(\w+)"') if named else None
    for rel, lines in files:
        if rel == "code/game/sound_sets.dm":
            continue
        for number, line in enumerate(lines, 1):
            code = code_of(line)
            if SPARK.search(code):
                out["spark_triple"].append((rel, number))
            for m in PLAY_CALL.finditer(code):
                if LITERAL.search(statement(lines, number - 1, m.start())):
                    out["literal_playsound"].append((rel, number))
            if STRING_KEY.search(code):
                out["sfx_string_key"].append((rel, number))
            elif key_assign:
                for m in key_assign.finditer(code):
                    if m.group(1) in fed and m.group(2) in named:
                        out["sfx_string_key"].append((rel, number))
                        break
            if code.lstrip().startswith("#define"):
                continue
            gm = GLOBAL_LIST.search(code)
            names = []
            if gm:
                names.append((gm.group(1), gm.end()))
            else:
                for m in ASSIGN.finditer(code):
                    names.append((m.group(1), m.end()))
            for name, end in names:
                if name not in fed:
                    continue
                if LITERAL.search(statement(lines, number - 1, 0)[end:]):
                    out["literal_sound_var"].append((rel, number))
                    break
    return out
