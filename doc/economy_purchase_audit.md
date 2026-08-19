# Economy purchase-path audit

This audit covers player-facing Thaler purchases and revenue paths. The core
invariant is that account-to-account movement uses `transfer_account_funds()`,
while true external sources and sinks use `credit()` or `debit()` explicitly.

| Channel | Funding path | Recipient / sink | Invoice or record | Result |
|---|---|---|---|---|
| Service register/scanner, ID | Department service charge | Civilian budget, staff tip | Global Service invoice + PDA receipt | Centralized |
| Service register/scanner, cash | Physical cash deposit | Civilian budget | Global Service invoice (`Cash`) | Centralized |
| Service register/scanner, e-wallet | E-wallet conversion | Civilian budget | Global Service invoice (`E-Wallet`) | Centralized |
| Department register/scanner | Account transfer | Linked department | Terminal and account ledgers | Centralized |
| Vending machine, ID | Account transfer | Vendor account | Account ledgers | Centralized in this audit |
| Vending machine, cash/e-wallet | Physical-value conversion | Vendor account | Vendor account ledger | Intentional conversion |
| EFTPOS | Account transfer | Linked account | Account ledgers | Centralized |
| Arcade, ID | Account transfer | Vendor account | Account ledgers | Centralized in this audit |
| Personal cargo order | Immediate personal debit | External procurement sink | Supply order history | Centralized |
| Department cargo order | Immediate budget debit | External procurement sink | Supply order history | Centralized |
| Science/Cargo crew sale | Account transfer | Linked department | Terminal and account ledgers | Centralized |
| Science/Cargo export | External trade credit | Producer, department, Cargo | Export and account ledgers | Centralized |
| Medical treatment | Department-service billing | Medical budget | Account ledgers | Centralized; not a Service retail invoice |
| Manufactured laptop/tablet | Personal debit | External manufacturer sink | Account ledger | Intentional sink |
| Mining/exploration equipment | Personal debit | External equipment sink | Account ledger | Intentional sink |

Food and drink price tags are defined in `price_list.dm`, and Southern Cross has
Civilian scanners/registers at its Service venues. There is no essential-food
exemption: the same paid quote path applies to every scanned item. Loose items
remain physically stealable, like other merchandise; the economy does not use
an invisible consumption lock or delete unpaid food from a player's hands.

Refunds are authoritative global-invoice operations. They restore the subsidy,
personal payment, and both gratuity shares. Service must still hold its share
and the tipped employee must still hold the staff gratuity; otherwise the
refund is rejected without changing any balance. An invoice can transition
only from `Paid` to `Refunded`.
