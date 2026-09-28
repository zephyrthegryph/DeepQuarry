"""Materializing-walk lint (doc/rewrite/systems.md section 18).

`materializing_walk` counts, inside a tgui_data() or examine() proc body, any walk or read
that goes through the ledger or materializes latent entries: FOR_CONTENTS(), contents_of(),
slot_contents(), get_all_contents(), latent_materialize()/latent_materialize_all(). Looking
at a thing must not create its contents. Use FOR_REAL_CONTENTS(decl, holder)
(code/__defines/containment.dm) for the materialized part and latent_names()/latent_count()
for the rest; materialize in the tgui_act()/verb that takes the thing.
"""
import re

RULES = {
    "materializing_walk": "FOR_REAL_CONTENTS() + latent_names()/latent_count() in tgui_data()/examine() "
                          "(doc/rewrite/systems.md section 18)",
}

HEAD = re.compile(r"^/[\w/]*/(?:tgui_data|examine)\s*\(")
BAD = re.compile(r"\b(?:FOR_CONTENTS|contents_of|slot_contents|get_all_contents(?:_type)?|"
                 r"latent_materialize(?:_all)?)\s*\(")


def scan(files):
    out = {"materializing_walk": []}
    for rel, lines in files:
        inside = False
        for number, line in enumerate(lines, 1):
            if line and not line[0].isspace():
                inside = bool(HEAD.match(line))
                continue
            if inside and BAD.search(line.split("//", 1)[0]):
                out["materializing_walk"].append((rel, number))
    return out
