# Warehouse Management — specification

What the solution is for and what it has to do, written the way it should have been written
before any of it was built.

---

## The situation

A distribution company stores goods across more than one physical site — a main warehouse and an
overflow unit — and runs the whole operation on a shared spreadsheet.

Nobody trusts the numbers in it. Stock is counted when someone remembers to count it, and the
count is wrong again within a day because movements in and out are written down after the fact,
if at all. Two problems follow, and they are the ones worth fixing:

- **Goods are promised that are not there.** An order goes out against a quantity the spreadsheet
  claims exists. The shortfall is discovered on the floor, at the point of picking.
- **Nobody notices stock running out until it has.** There is no signal between "plenty" and
  "none", so restocking is reactive.

The system replaces the spreadsheet with a record where **the on-hand quantity is derived, never
typed** — it moves only because a movement was recorded — and where an attempt to take out more
than exists is refused at the moment it is attempted.

---

## Who it is for

Two personas, not more. Everyone who touches this system is either responsible for the catalogue
or responsible for moving goods, and those two jobs want different surfaces, different devices
and different authority. A third persona would be a variation of one of these.

### Warehouse manager

| | |
|---|---|
| **Context of use** | At a desk, full screen, in sessions of minutes rather than seconds. Works across the whole operation, not one site. |
| **Authority** | Organization-wide (**Global**) on everything, including delete. The only role that may retire a location or remove a record. |

Owns the catalogue of goods and the list of sites: what is stocked, where it belongs, what it
costs, and the level at which it should be reordered. Needs the state of the whole operation at a
glance, and the ability to correct anything in it.

### Warehouse floor worker

| | |
|---|---|
| **Context of use** | Standing, moving, on a shared device, often one-handed. Sessions are seconds long and repetitive. Needs a narrow, fast surface — not the same app the manager uses. |
| **Authority** | Reads everything organization-wide (**Global**), so any item at any site is findable. Creates and edits **only their own** movements (**Basic**). No delete on anything; no authority over sites. |

The job is narrow and repetitive: find an item, record that stock went out or came in, move on.

> The two personas differ in *context of use*, not only in privilege — and that difference is what
> justifies a second app surface rather than a second security role on the same app. Where they do
> differ only in depth, it is on movements: the manager holds Global create, write and delete; the
> worker Basic create and write, and no delete.

---

## Jobs to be done

| # | Persona | Job |
|---|---|---|
| J1 | Manager | Maintain the catalogue of items |
| J2 | Manager | Maintain the list of sites, retiring one without losing its history |
| J3 | Manager | Set the reorder point per item and see which items have reached it |
| J4 | Manager | Check one item's stock position against its reorder point on demand |
| J5 | Manager | See the shape of the whole operation in one view |
| J6 | Manager | Correct a movement recorded by anyone |
| J7 | Worker | Find an item quickly on a shared device |
| J8 | Worker | Record stock going out, and be refused if there is not enough |
| J9 | Worker | Record stock coming in |
| J10 | Worker | See how many of an item are on hand before promising any |

---

## The rules that matter

1. **A movement out may never exceed what is on hand.** It is rejected, and the rejection states
   what was available and what was asked for, because the person recording it needs to know how
   short they are, not just that they were wrong.
2. **On-hand quantity follows from movements automatically.** Goods in add, goods out subtract.
   This holds no matter which surface recorded the movement.
3. **An item at or below its reorder point is visibly low on stock** wherever items are listed —
   not buried in a report someone has to go and run.

Rules 1 and 2 are enforcement and belong in the backend, where every surface and the Web API hit
them alike. Rule 3 is presentation. **Nothing that matters is enforced only in the frontend.**

---

## What the system holds

Publisher prefix `almlab`. Three tables.

### `almlab_warehouseitem`

| Column | Type | Serves |
|---|---|---|
| `almlab_name` *(required)* | Text | J1, J7 |
| `almlab_sku` *(required)* | Text | J1, J7 — the code people actually search by |
| `almlab_category` | Choice — Electronics, Clothing, Food, Hardware, Other | J1 |
| `almlab_availablequantity` *(required)* | Whole number | J8, J10 — **derived; only a movement changes it** |
| `almlab_reorderpoint` | Whole number | J3 — the threshold the low-stock signal compares against |
| `almlab_unitprice` | Currency | J1 |
| `almlab_barcode` | Text | J7 |
| `almlab_weight` | Decimal | J1 |
| `almlab_isperishable` | Yes/No | J1 |
| `almlab_expirationdate` | Date | J1 |
| `almlab_description` | Multiline text | J1 |
| `almlab_locationid` | Lookup → location | J1, J5 |

### `almlab_warehouselocation`

| Column | Type | Serves |
|---|---|---|
| `almlab_name` *(required)* | Text | J2 |
| `almlab_address` | Text | J2 |
| `almlab_capacity` | Whole number | J2 |
| `almlab_isactive` | Yes/No | J2 — retire a site without deleting its items' history |
| `almlab_notes` | Multiline text | J2 |

### `almlab_warehousetransaction`

| Column | Type | Serves |
|---|---|---|
| `almlab_name` *(required)* | Text | J6 |
| `almlab_itemid` *(required)* | Lookup → item | J8, J9 |
| `almlab_transactiontype` *(required)* | Choice — Inbound, Outbound | J8, J9 |
| `almlab_quantity` *(required)* | Whole number | J8, J9 |
| `almlab_transactiondate` *(required)* | Date | J8, J9 |
| `almlab_referencenumber` | Text | J6 |
| `almlab_totalvalue` | Currency | J6 |
| `almlab_notes` | Multiline text | J8 |
| `almlab_isprocessed` | Yes/No | — **no job claims this; see Open questions** |
| `almlab_processedby` | Text | — **likewise** |

Relationships, both 1:N: location → item via `almlab_locationid`, item → movement via
`almlab_itemid`.

---

## Where each behaviour runs

| Behaviour | Runs where | Why there |
|---|---|---|
| Item name, SKU and quantity are mandatory; a movement needs item, type, quantity and date | **Configuration** | Required-level flags. Nothing here needs code. |
| Category and movement type are fixed sets | **Configuration** | Local choices on the columns. |
| **An outbound movement may not exceed what is on hand** | **Backend** — plug-in, **pre-validation** (stage 10, sync) | The rule has to hold for the model-driven app, the code app, the Web API and any import alike. Pre-validation because the right outcome is *rejection before anything is written* — and the message carries both numbers: `Not enough product in stock. Available: {n}, requested: {m}.` |
| **On-hand follows the movement** — inbound adds, outbound subtracts | **Backend** — plug-in, **post-operation** (stage 40, sync) | Two writes that must not diverge. Post-operation so the movement exists before the item is adjusted; synchronous so the number is right the instant the worker looks at it. |
| Low stock is visible wherever items are listed | **Frontend** — grid customiser | Presentation, not a rule. Cells at or below the reorder point are painted; items with no reorder point fall back to 10. Never the enforcement of anything. |
| Movement date defaults to today | **Frontend** — form `onLoad` | Saves a keystroke where a person is typing. The column stays required, so the default is a convenience, not the guarantee. |
| Check an item's level against its reorder point on demand | **Frontend** — ribbon button on the item form | Answers a question; changes nothing. J4. |
| Quantity column reads "Qty on hand" | **Frontend** — column interceptor | Wording, in one place, rather than renamed per view. |

---

## The surfaces

| Surface | Persona | What it is for |
|---|---|---|
| Model-driven app `almlab_warehouseapp` | Manager | The catalogue, the sites, the movements, and a dashboard |
| Dashboard (generative page, first in the sitemap) | Manager | Three totals — items, sites, items low on stock — above the stock itself with low rows marked |
| Warehouse Picking code app | Worker | A fast, task-focused surface: list items, open one, record a movement, be told immediately if there is not enough |

---

## User flows

**J1 · Maintain the catalogue** *(manager, model-driven app)* — Warehouse Items → grid → open or
new → main form → save. Low-stock rows are already tinted in the grid, so the items needing
attention surface without a filter.

**J2 · Maintain sites** *(manager)* — Warehouse Locations → grid → open or new → main form.
Retiring a site clears `almlab_isactive` rather than deleting the record, so the items that
reference it keep their history.

**J3 · Reorder points** *(manager)* — Item form → reorder point → save. Thereafter any grid
listing that item paints its quantity when it is at or below the point. The dashboard counts them.

**J4 · Check one item's stock position** *(manager)* — Item form → **Check Stock Levels** on the
command bar → a dialog states the level and whether it is above or below the reorder point.

**J5 · See the whole operation** *(manager)* — Dashboard, first in the sitemap, its own group.

**J6 · Correct a movement** *(manager)* — Warehouse Transactions → open → amend → save. **The
correction does not re-run either rule** — see Open questions.

**J7 · Find an item** *(worker, code app)* — Open the app → item list → tap through to the item.

**J8 · Record stock going out** *(worker, code app)* — Item detail → New transaction → type
Outbound, quantity, date → submit. Enough stock: the movement is created and on-hand drops. Not
enough: the write is refused and the message names the available and requested quantities.

**J9 · Record stock coming in** *(worker, code app)* — The same dialog with type Inbound. No
validation applies; on-hand rises.

**J10 · See what is on hand** *(worker, code app)* — Item detail shows the current quantity, read
after each movement rather than cached.

---

## Out of scope

Purchase orders, suppliers and replenishment workflow. Picking routes and bin-level positions
within a site. Barcode scanning hardware — the barcode is stored, not read. Costing beyond a unit
price and a movement's total value. Shipping and customers. Stock-takes and adjustments that are
not a movement.

---

## Open questions

These are stated rather than left out, because a specification is exactly where a rule nobody
implemented should become visible.

1. **Both plug-in steps are registered on Create only.** `Create of almlab_warehousetransaction`,
   stages 10 and 40. Editing a saved movement therefore neither re-validates it nor adjusts
   on-hand. Combined with the worker's Basic write on movements, a worker can record an outbound
   of 1 against an item holding 1, then edit it to 1000: no rejection, and the item's quantity
   never moves. Either movements become immutable once saved, or both steps gain an Update
   registration with a pre-image to work out the delta. **This is the most significant gap.**
2. **`almlab_isprocessed` and `almlab_processedby` serve no job.** Nothing reads or writes them.
   They are either the residue of a workflow that was never built, or a requirement nobody wrote
   down. Columns with no job are how a data model rots.
3. **The worker's authority is broader than stated.** This document says workers should not
   reshape the catalogue; the `Warehouse worker` role holds **Global create and write on items**.
   Either loosen the statement or tighten the role — it matters, because the authority column
   above is what a security role is generated from.
4. **Does an expiry date block a movement of perishable goods, or only warn?** The columns exist;
   no rule references them.
5. **Should a worker see other workers' movements?** They currently read all movements
   organization-wide but may only write their own. Deliberate, or an oversight?
6. **Is a stock-take a third movement type, or something else?** Listed out of scope, but the
   moment a physical count disagrees with the system, someone needs an answer.
7. **"Shared device" is an inference** from the floor worker's task shape, not a stated
   requirement. It is the reason their surface is separate and narrow, so it is worth confirming.
