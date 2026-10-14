# Empty namespace allocation phases

Captured with pinned BYOND 516.1687, compile only. Each case retains exact
source/assets, compiler hash/arguments receipt, stdout, and decoded archive order.
No runtime was started. The duplicate controls replace only the empty namespace
with an empty declaration of that namespace kind.

| Control | Legal | Native aliases |
|---|---|---|
| `block` (empty var block) | yes | A.txt, B.txt |
| `declaration` (empty var declaration) | yes | A.txt, B.txt |
| `procblock` (empty proc block) | yes | B.txt, A.txt |
| `procdeclaration` (empty proc declaration) | yes | B.txt, A.txt |

The proc pair distinguishes ignoring an empty namespace: it creates the proc
allocation phase before the later var phase, even though it contains no literal.
This supports retaining Namespace events in the generic allocation ledger and
creating persistent Var/Proc/Verb group keys when visited. Verb grouping remains
supported by the existing namespace grammar; no new verb-only control is claimed.
