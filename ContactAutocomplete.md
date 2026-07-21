# Contact autocomplete and address book lookup

Status: implemented. Compose searches the local address book as you type,
commits recipients as removable pills, and offers a browsable directory.

## Behaviour

**Autocomplete** — typing in To/Cc/Bcc searches name and address together,
case- and diacritic-insensitively, on a 150ms debounce, and offers the five
closest matches. Ranking is explicit (`MatchRank`): name prefix, name word
prefix, address prefix, name substring, address substring; ties break by match
offset, then name, then address.

**Dropdown** — floats under the active row, one row per (contact, address) with
the matched characters bold. Capped at two rows per contact so one
many-addressed contact can't fill it. Up/Down move the highlight, Return or Tab
confirm, Escape closes. Empty results show "No contacts found". Nothing is
highlighted until you press Down, so Return commits what you actually typed.

**Tokens** — a committed recipient becomes a pill with an X button. Contact-
backed pills show an avatar and the person's name; hand-typed ones show the
bare address in mono.

**Address book** — the directory button by the To field opens a searchable
table (Name, Email, Department) with per-row TO/CC/BCC buttons. It stays open
for multi-select and ticks contacts already added. Multi-address contacts pick
an address from a menu.

**Edge cases** — duplicates are refused across all three fields (the same
person in To and Cc is always a mistake) with a toast; the other fields' buttons
show disabled rather than silently refusing. Addresses not in the book are
accepted if valid. Leaving a field commits what's in it, so nothing typed is
lost — including on send, where a typed-but-not-confirmed address still goes
out. Half-typed search terms survive a blur without an error.

## Implementation notes

| Concern | Where |
|---|---|
| Matching, ranking, highlighting | `Domain/UseCases/ContactSearch.swift` |
| Validation and header parsing | `Utilities/EmailAddress.swift` |
| Recipient model | `Domain/Models/RecipientToken.swift` |
| Field, dropdown, wrapping, toast | `Presentation/Components/` |
| Directory modal | `Presentation/Screens/AddressBookView.swift` |
| State, debounce, duplicates | `Presentation/Shared/ViewModels/ComposeViewModel.swift` |

Durable contracts and platform deviations: `KyPost/Presentation/AGENTS.md`.

## Where this differs from the original spec

The spec was written for a web client. Deviations, all deliberate:

- **Search is in memory, not a SQLite `LIKE`.** `Contact.emails` is an encoded
  Codable blob that `#Predicate` can't see inside, so matching on an address in
  the store would need a denormalized column, a schema migration, and upkeep on
  every write path. `ContactsViewModel.searchIndex` is that same SQLite book,
  materialized, and is already the list the UI renders. The 150ms debounce is
  kept regardless — it caps main-actor work and stops the dropdown flickering.
- **Validation is the HTML5 email grammar, not RFC 5322.** Real RFC 5322
  accepts quoted local parts, comments, and IP literals nobody wants in a To
  field. HTML5's production is what mail clients enforce; a dot in the domain
  is additionally required.
- **iOS has no arrow-key or Escape navigation** — `onKeyPress` needs a hardware
  keyboard. The dropdown is tap-driven there.
- **No backspace-deletes-last-token** — AppKit's field editor consumes
  backspace before SwiftUI sees it. The X button is the removal path.
- **The dropdown highlights nothing until you press Down.** Preselecting the
  first row would make Return on a fully-typed address silently insert a
  different contact.
- **A themed `List` of fixed-width rows, not `Table`** — `Table` collapses to
  one column on iOS and can't be themed. Costs column sorting, which the spec
  didn't ask for.
