"""Sound and effect sets (doc/rewrite/systems.md section 16)."""
import re

RULES = {
    "literal_playsound": "play_sfx(atom, SFX_ID) with a SOUND_SET row (code/game/sound_sets.dm), not a literal file",
    "spark_triple": "fx_sparks(atom, amount, cardinals), not a spark_spread new/set_up/start",
}

CALL = re.compile(r"(?<![\w./])playsound\s*\(")
LITERAL = re.compile(r"'[^'\n]+\.(?:ogg|wav|mid|mp3)'")
SPARK = re.compile(r"\bspark_spread\b")


def call_text(lines, index, start):
    """The playsound( call's text from `start`, following open parens onto later lines."""
    depth = 0
    out = []
    for k in range(index, min(index + 8, len(lines))):
        line = lines[k].split("//", 1)[0] if k > index else lines[k][start:].split("//", 1)[0]
        for c in line:
            out.append(c)
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return "".join(out)
    return "".join(out)


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            if SPARK.search(code):
                out["spark_triple"].append((rel, number))
            for m in CALL.finditer(code):
                if LITERAL.search(call_text(lines, number - 1, m.start())):
                    out["literal_playsound"].append((rel, number))
    return out
