# Service helper review (release 1.4.1, round 3)

Evidence: pinned EG `e0f8585914c134d9cb5d76756bd065b1e3e92ece`,
service evidence.json, all trainer fact extracts and trainers.tsv. Scan all
emitted identities, every available name/title in those extracts, and their build
histories for beta, test/testing, debug, GM/game master and seasonal/event roles.

| ID | Name / role | Decision |
| --- | --- | --- |
| 278680 | Gabbi Goodwhistle; Specialty Beta Goods & Training | Exclude: every EG record is 1.60.1.70532, before launch 1.60.1.70755. The title explicitly identifies a testing role. `build_services.HELPER_EXCLUSIONS` records the reviewed exclusion; the generic pre-launch test-role rule also rejects a distinct synthetic identity. |
| 14828 | Gelvas Grimegate; Darkmoon Faire Ticket Redemption | Keep witnessed vendor, Alliance access. Post-launch 1.60.1.70862/70888 evidence. Seasonal event service; availability depends on the Faire, not a permanent town vendor. |
| 14844 | Sylannia; Darkmoon Faire Drink Vendor | Keep ordinary seasonal vendor, post-launch evidence. Available during the Faire. |
| 14845 | Stamp Thunderhorn; Darkmoon Faire Food Vendor | Keep ordinary seasonal vendor, post-launch evidence. Available during the Faire. |
| 2833 | DEBUG - Gossip Gryphon Master | Questie trainer fact extract only; absent from the generated trainer roster and service supplement. Keep excluded. |
| 7314 | Test BattleMaster | Questie trainer fact extract only; absent from the generated trainer roster and service supplement. Keep excluded. |

No other beta/test/GM/event-only helper was identified by the complete extract
and output scan. There are no flagged trainer roster names/titles. This is a
pinned evidence audit, not a live-spawn assertion. Ordinary NPCs with only early
observations remain: 64 service identities have exclusively pre-launch EG
records and are retained. Build age alone does not justify removing them.

Quickcoin (258878) and Winklespark (265574): all pinned reaction records,
including the post-launch wowf records, show Horde witnesses and no Alliance
witness. Keep H in the supplement. A factionless packaged WTL row supplies no
additional positive access evidence; explicit personal/imported access still
unions with the supplement. No reference-page neutrality claim is promoted to
pinned observed access.

Mailbox/meeting-stone review: no Classic source spawn removals are approved.
The gate independently resolves all 60 mailbox and 22 meeting-stone source
spawns using pinned client names/rectangles and Classic bounds, then checks the
production candidate points for both eligible factions. Any future removal
requires an explicit literal-spawn exception with evidence/reason in the gate.
