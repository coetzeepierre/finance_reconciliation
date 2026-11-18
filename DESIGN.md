# Technical Design Document for a Statement Reconciliation Service

## 1. Problem Statement, Scope & Deliberate Deferrals

Treasury teams aggregate bank statement feeds from multiple upstream connectors (SWIFT MT940/CAMT.053, direct bank APIs, ERP exports) across multiple legal entities (tenants), bank accounts, and currencies. Upstream feeds are non-deterministic: statements are re-fetched, overlapping feeds emit near-duplicates without shared identifiers, formatting is inconsistent, and reversals arrive out-of-band. Counting a movement twice corrupts liquidity positions and downstream cash forecasts.

**Core Question Answered:**  
*"For my organisation, what is my reconciled closing balance per account and currency over a given date range — counting each real movement exactly once?"*

### In Scope (Implemented)

<p align="center">
<img src="app/assets/images/slide-1.jpg" style="border:1px solid #fff;padding: 2px;max-width:50rem" title="In Scope (Implemented)"/>
</p>

- **Idempotent Ingestion Pipeline:** Two-stage storage separating immutable raw feed audit records (`raw_statement_lines`) from the canonical ledger (`reconciled_movements`).
- **Data Normalization:** Deterministic parsing of CSV/Excel inputs via `Roo::Spreadsheet.open` (handling `DD/MM/YYYY` vs ISO-8601, currency casing, embedded symbols, zero-decimal currencies like JPY via `money-rails`/`monetize`, and business unit formatting).
- **Concurrency-Safe Deduplication & Reversal Handling:**
  - Database-enforced structural idempotency for exact re-deliveries (`source_id`).
  - Pessimistic row-level locking (`SELECT ... FOR UPDATE` via `Account#with_lock`) around candidate windows to prevent race conditions during concurrent near-duplicate and reversal resolution.
  - Paired reversal linking (`reversal_of_id`) that nets balances cleanly while preserving a full audit trail.
- **Multi-Tenant Isolation & Authorization:** Shared-schema row-level isolation (`tenant_id` on every table, `Current.tenant` scoping, composite indexes) with native Rails 8 authentication.
- **Balance Query API & Treasury UI:** Reconciled closing balance endpoint and server-rendered treasury view.

---

## Deliberately Deferred (and Why)
<p align="center">
<img src="app/assets/images/slide-2.jpg" style="border:1px solid #fff;padding: 2px;max-width:20rem" title="Deliberately deferred"/>
</p>

- **FX Conversion / Consolidated Base-Currency Rollups:** The brief explicitly asks for balances per account and currency. Mixing FX rate-source selection and spot vs. historical valuation risks obscuring ledger accuracy in a v1 core engine.
- **Automated Fuzzy Matching on Out-of-Order Reversals:** If a reversal arrives before the original movement, we flag it (`unmatched_reversal`) rather than guessing, preventing premature negative balance distortion until the original line lands.
- **Human-in-the-Loop Quarantine Review UI:** Borderline near-duplicates are marked (`duplicate`) with `duplicate_of_id` metadata so treasury ops can inspect them later, rather than building a full exception-workflow UI in v1.
- **Asynchronous Connector Ingestion (SWIFT/API Webhooks):** Built around synchronous/batch file ingestion backed by transactional services so core reconciliation invariants are deterministic and easy to test; Solid Queue wiring is documented for production.

---

## 2. Architecture, Key Decisions & Alternatives Considered

<p align="center">
<img src="app/assets/images/slide-3.jpg" style="border:1px solid #fff;padding: 2px;max-width:30rem" title="Architecture, Key Decisions & Alternatives Considered"/>
</p>

### Step 1. Incoming CSV/Excel/Feed data
Bank feeds arrive as CSV or Excel files from multiple bank connectors. We route them through ```Ingestion::ParseStatementFileService```, normalizing mixed date formats (```DD/MM/YYYY``` vs ```ISO-8601```), currency casing, embedded symbols, and subunit amounts via ```Monetize```.

### Step 2. Immutable Raw Audit Storage (```raw_statement_lines```)
- Record all incoming lines verbatim
- DB level re-delivery handling implements:
  ```INSERT ... ON CONFLICT (tenant_id, source_id) DO NOTHING```

### Step 3. Account Pessimistic lock
- For newly inserted lines, ```Reconciliation::ProcessLineService``` acquires a row-level pessimistic lock on the Account record (SELECT ... FOR UPDATE).

### Step 4.	Reversal Matching & Near-Duplicate
 #### Two main checks are executed:
  1) First, if the description indicates a reversal ```(REVERSAL OF <id>)```, it matches and nets against the original movement. If the target has not arrived yet, it is parked as ```unmatched_reversal``` .
  2) With no source_id present, evaluate candidate movements within a ```±24-hour``` posting window. If a candidate match exists, it is marked duplicate and suppressed to protect cash safety

### Step 5. Canonical Ledger Promotion
- Finally, validated, non-duplicate movements are promoted into ```reconciled_movements```.
- All balance reporting and API endpoints strictly query this canonical ledger layer.
  
---

```text
+-------------------------------------------------------------+
|          Raw Bank Statement Feed (CSV / Excel / API)        |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|            Ingestion::ParseStatementFileService             |
|     (Normalizes dates, currencies, and subunit amounts)     |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|            Stage 1: RawStatementLine (Audit Log)            |
|      Atomic INSERT ... ON CONFLICT (tenant_id, source_id)   |
+-------------------------------------------------------------+
                     |                     |
    [Newly Inserted] |                     | [Duplicate source_id]
                     v                     v
+---------------------------+   +-----------------------------+
| Reconciliation::          |   |  Ignored (ON CONFLICT)      |
| ProcessLineService        |   |  Returns existing record    |
+---------------------------+   +-----------------------------+
             |
             +-> 1. Account#with_lock (Pessimistic Row Lock)
             |
             +-> 2. Reversal Check ("REVERSAL OF <source_id>")
             |        |-- Found & Valid -> Status: reversal
             |        +-- Missing Target -> Status: unmatched_reversal
             |
             +-> 3. Near-Duplicate Window Check (+/- 24h)
             |        |-- Match Found    -> Status: duplicate
             |        +-- No Match       -> Status: reconciled
             |
             v
+-------------------------------------------------------------+
|             Stage 2: ReconciledMovement (Ledger)            |
|       Append-only canonical single source of truth          |
+-------------------------------------------------------------+
```

###  Alternatives Considered & Trade-Off Matrix
<p align="center">
<img src="app/assets/images/slide-4.jpg" style="border:1px solid #fff;padding: 2px;max-width:30rem" title="Alternatives" alt="Alternatives"/>
</p>

<!-- ORIGINAL ASCII DIAGRAM (Hidden)
| Decision Area           | Selected Approach                                                       | Rejected Alternative                          | Trade-Off & Rationale                                                                                                                                                                                                                                                                                                         |
| :---------------------- | :---------------------------------------------------------------------- | :-------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Storage Model**       | **Two-Table Split** (`raw_statement_lines` + `reconciled_movements`)    | **Single-Table Deduplication**                | *Single-table* drops duplicate submissions or overwrites raw data, destroying auditability. *Two-table* costs slightly more storage but guarantees an immutable historical audit record explaining *why* every line was accepted, excluded, or reversed.                                                                      |
| **Concurrency Control** | **Pessimistic Locking** (`Account#with_lock` / `SELECT ... FOR UPDATE`) | **Optimistic Locking / Redis Advisory Locks** | Near-duplicates lack a shared unique key (`source_id IS NULL`), making database constraints alone impossible for candidate window evaluation. *Advisory locks* introduce distributed state management risks. *Account-level locking* guarantees serial evaluation per account without blocking unrelated accounts or tenants. |
| **Reversal Strategy**   | **Append-Only Reversal Ledger Entries** (`reversal_of_id`)              | **Soft-Deleting Original Movements**          | Soft-deleting distorts point-in-time historical reporting (e.g., balance reports for a past month change retroactively). *Append-only paired entries* net out cash positions cleanly while maintaining historical statement fidelity.                                                                                         |
| **Monetary Units**      | **Integer Subunits** (`amount_cents` via `money-rails` / `monetize`)    | **Floating-Point / Decimal Columns**          | *Float/Decimal* columns risk IEEE 754 rounding drift and misrepresent zero-decimal currencies. *Integer subunits* eliminate rounding errors and enforce exact ISO-4217 exponents (e.g., JPY exponent 0 vs USD exponent 2).                                                                                                    |
-->

-----

## 3. Subunit Monetary Precision & ISO Currency Handling

Floating-point data types (`FLOAT`, `DOUBLE`) introduce rounding errors due to IEEE 754 binary representation limitations. In corporate treasury systems, fractional penny or cent drift destroys ledger integrity and invalidates closing balances.

- **Zero-Drift Integrity:** Storing values as integer subunits (bigint) guarantees CPU-native, zero-rounding-drift arithmetic across all application layers and database queries.
- **ISO-4217 Exponent Binding:** Binding currency codes at the model layer via Monetize ensures zero-decimal currencies (e.g., Japanese Yen) are stored with an exponent of 0 (¥3,385,780 = 3385780 units) rather than incorrectly scaled by 100x.
- **Database Guardrails:** Backing model validations with database-level CHECK constraints on supported currency codes ensures out-of-band writes or background scripts cannot insert unvalidated currency structures.

#### Subunit Representation with `money-rails` / `monetize`

Monetary amounts are strictly stored as integer subunits in a signed `bigint` column (`amount_cents`). The model layer binds ISO-4217 currency codes to exact subunit conversions using `money-rails` and `monetize`.

- Database integer arithmetic is CPU-native, zero-drift, fast, and eliminates floating-point representation bugs across different languages and platforms.

| Currency Code | ISO Name      | Subunit Exponent       | Example Raw Value | Stored `amount_cents` |
| :------------ | :------------ | :--------------------- | :---------------- | :-------------------- |
| **USD**       | US Dollar     | 2 ($1 = 100 cents)     | `$1,250.45`       | `125045`              |
| **EUR**       | Euro          | 2 (€1 = 100 cents)     | `-€764,644.00`    | `-76464400`           |
| **GBP**       | British Pound | 2 (£1 = 100 pence)     | `£31,585.50`      | `3158550`             |
| **CHF**       | Swiss Franc   | 2                      | `3,670,510.00`    | `367051000`           |
| **JPY**       | Japanese Yen  | **0** (1 JPY = 1 unit) | `¥3,385,780`      | `3385780`             |

#### Zero-Decimal Currency Handling (JPY)

Japanese Yen (JPY) does not utilize fractional subunits. `Monetize.parse!` detects the ISO currency code and automatically enforces a **0 subunit exponent**, preventing input scaling errors (e.g., ensuring `¥3,385,780` is stored as `3385780` integer units rather than incorrectly multiplied by 100).

#### Database-Level Currency Integrity & Constraints

PostgreSQL `CHECK` constraints reject unsupported or malformed currency codes directly at the database layer:

``` sql
ALTER TABLE raw_statement_lines
  ADD CONSTRAINT chk_raw_currency CHECK (currency IN ('USD', 'EUR', 'GBP', 'JPY', 'CHF'));

ALTER TABLE reconciled_movements
  ADD CONSTRAINT chk_rec_currency CHECK (currency IN ('USD', 'EUR', 'GBP', 'JPY', 'CHF'));

```


## 4. Data Model & Idempotency Guarantees

### Schema Diagram
<p align="center">
<img src="app/assets/images/slide-5.jpg" style="border:1px solid #fff;padding: 2px;max-width:30rem" title="Data Model & Idempotency Guarantees"  alt="Idempotency Guarantees"/>
</p>

<!-- ORIGINAL SCHEMA MARKDOWN - HIDDEN
```
+------------------+         +--------------------+
|     tenants      |         |      accounts      |
+------------------+         +--------------------+
| id (UUID, PK)    |<-------1| id (UUID, PK)      |
| name (string)    |         | tenant_id (UUID)   |---+
| slug (string, UN)|<-------+| account_number (str|   |
| shard (string)   |        || business_unit (str)|   |
+------------------+        ||+-------------------+   |
        ^                   ||                        |
        |                   ||                        |
        +-------------------+|                        |
        |                    |                        |
+----------------------------+----+                   |
|    raw_statement_lines          |                   |
+---------------------------------+                   |
| id (UUID, PK)                   |                   |
| tenant_id (UUID, FK)            |                   |
| account_id (UUID, FK) <---------+                   |
| source_id (string, NULL)        |                   |
| currency (string, limit: 3)     |                   |
| amount_cents (bigint)           |                   |
| value_date (date)               |                   |
| posting_ts (datetime)           |                   |
| status (string, default: pending)|                  |
| duplicate_of_id (UUID, FK) -----+----+              |
+---------------------------------+    |              |
        ^                              |              |
        |                              v              v
+-------+-----------------------------------------------+
|                   reconciled_movements                |
+-------------------------------------------------------+
| id (UUID, PK)                                         |
| tenant_id (UUID, FK)                                  |
| account_id (UUID, FK)                                 |
| raw_statement_line_id (UUID, FK, Unique)              |
| reversal_of_id (UUID, FK, Unique, NULL)               |
| currency (string, limit: 3)                           |
| amount_cents (bigint)                                 |
| value_date (date)                                     |
| posting_ts (datetime)                                 |
+-------------------------------------------------------+

```
-->
### Schema Overview (PostgreSQL 16+ + UUID Primary Keys)

#### `tenants`

  - `id` (uuid, PK)
  - `name` (varchar, NOT NULL)
  - `slug` (varchar, NOT NULL, UNIQUE)
  - `shard` (varchar, NOT NULL, DEFAULT 'default')
  - `created_at`, `updated_at` (timestamps)

#### `accounts`

  - `id` (uuid, PK)
  - `tenant_id` (uuid, NOT NULL, FK -\> tenants.id)
  - `account_number` (varchar, NOT NULL)
  - `business_unit` (varchar, NULL)
  - `created_at`, `updated_at` (timestamps)
  - *Indexes:* Unique index on `(tenant_id, account_number)`

#### `raw_statement_lines`

  - `id` (uuid, PK)
  - `tenant_id` (uuid, NOT NULL, FK -\> tenants.id)
  - `account_id` (uuid, NOT NULL, FK -\> accounts.id)
  - `source_id` (varchar, NULL)
  - `currency` (varchar(3), NOT NULL, CHECK IN ('USD','EUR','GBP','JPY','CHF'))
  - `amount_cents` (bigint, NOT NULL)
  - `value_date` (date, NOT NULL)
  - `posting_ts` (timestamptz, NOT NULL)
  - `category` (varchar, NULL)
  - `description` (text, NULL)
  - `status` (varchar, NOT NULL, DEFAULT 'pending')
  - `duplicate_of_id` (uuid, NULL, FK -\> raw\_statement\_lines.id)
  - `created_at`, `updated_at` (timestamps)
  - *Indexes:* Partial unique index `idx_unique_raw_source_per_tenant` ON `(tenant_id, source_id)` WHERE `source_id IS NOT NULL`

#### `reconciled_movements`

  - `id` (uuid, PK)
  - `tenant_id` (uuid, NOT NULL, FK -\> tenants.id)
  - `account_id` (uuid, NOT NULL, FK -\> accounts.id)
  - `raw_statement_line_id` (uuid, NOT NULL, UNIQUE, FK -\> raw\_statement\_lines.id)
  - `currency` (varchar(3), NOT NULL, CHECK IN ('USD','EUR','GBP','JPY','CHF'))
  - `amount_cents` (bigint, NOT NULL)
  - `value_date` (date, NOT NULL)
  - `posting_ts` (timestamptz, NOT NULL)
  - `category` (varchar, NULL)
  - `description` (text, NULL)
  - `reversal_of_id` (uuid, NULL, UNIQUE, FK -\> reconciled\_movements.id)
  - `created_at`, `updated_at` (timestamps)
  - *Indexes:* Composite index `idx_reconciled_movements_balance_query` ON `(tenant_id, account_id, currency, value_date)`

### How Exact Re-Deliveries Are Made Safe Under Concurrent Ingestion

1.  **Atomic Database Upsert (`ON CONFLICT DO NOTHING`):** When `source_id` is present, `RawStatementLine.ingest_safely!` executes a PostgreSQL `INSERT ... ON CONFLICT (tenant_id, source_id) WHERE source_id IS NOT NULL DO NOTHING RETURNING id`.
2.  **Single-Winner Guarantee:** If two worker threads ingest the exact same CSV or payload simultaneously, PostgreSQL's unique B-tree index guarantees exactly one `INSERT` returns a newly created row ID. The losing thread receives `nil` / existing record and skips `ProcessLineService` completely.
3.  **One-to-One Ledger Guardrail:** `reconciled_movements.raw_statement_line_id` carries a `UNIQUE` index as defense-in-depth so a single raw line can never generate two ledger entries.

-----

## 5. Near-Duplicate & Reversal Rules

### 1. Near-Duplicate Detection Rule
<p align="center">
<img src="app/assets/images/slide-6.jpg" style="border:1px solid #fff;padding: 2px;max-width:30rem" title="Near-Duplicate Detection Rule"  alt="Near-Duplicate Detection Rule"/>
</p>

When a line arrives without a `source_id` (and is not a reversal), two lines represent the same real movement if and only if they match on all five dimensions:

  - **Same Tenant:** `tenant_id`
  - **Same Account:** `account_id`
  - **Same Currency:** `currency`
  - **Exact Signed Amount:** `amount_cents`
  - **Posting Window:** `posting_ts` falls within +/- 24 hours of an existing `ReconciledMovement`.

### Known Failure Modes & False-Positive vs. False-Negative Trade-Off

  - **False Positive (Primary Risk):** Two genuinely distinct payments of the exact same amount settle on the same account within 24 hours without `source_id`s (e.g., two identical $500 vendor payouts on the same day). Under this rule, the second payment is marked `duplicate` and excluded from the ledger.
  - **False Negative (Secondary Risk):** Two feeds report the exact same movement with timestamps \> 24 hours apart (e.g., Friday initiation vs. Monday clearing across a bank holiday), causing both to be promoted to the ledger.
  - **Trade-Off Rationale (Bias Toward Cash Safety):** In treasury management, **overstating cash (false negative)** is catastrophic—a treasurer may invest or sweep non-existent funds, leading to overdrafts or failed settlements. Suppressing candidate near-duplicates while preserving full audit records in `raw_statement_lines` protects cash integrity first while enabling manual ops override.

---

### 2. Reversal Resolution Rule
<p align="center">
<img src="app/assets/images/slide-7.jpg" style="border:1px solid #fff;padding: 2px;max-width:30rem" title="Near-Duplicate Detection Rule"  alt="Reversal rules"/>
</p>

1.  Lines whose normalized description matches `/\bREVERSAL OF\s+([A-Z0-9-]+)\b/i` are classified as reversals.
2.  Under the Account pessimistic lock, we locate the target `ReconciledMovement` via `(tenant_id, raw_statement_lines.source_id = <target_id>)`.
3.  **Validation Checks:** Target must exist in the same `tenant_id` and `account_id`, match currency, have opposite sign (`target.amount_cents == -raw_line.amount_cents`), and not already be reversed (`reversal_of_id` unique constraint).
4.  **Execution:** If valid, a paired negative `ReconciledMovement` is inserted with `reversal_of_id: target.id`. If the target has not arrived yet, the line is marked `unmatched_reversal` for deferred resolution.

-----

## 6. Test Strategy & Plan

The test suite validates data normalization, monetary calculations, reversal matching, near-duplicate edge cases, and real multi-threaded PostgreSQL concurrency.
<p align="center">
<img src="app/assets/images/slide-8.jpg" style="border:1px solid #fff;padding: 2px;max-width:30rem" title="Near-Duplicate Detection Rule"  alt="Near-Duplicate Detection Rule"/>
</p>

  - **Unit & Normalization Tests (`test/services/ingestion/`):** Verifies mixed date formats (`DD/MM/YYYY` vs ISO-8601), currency casing (`Usd`, `Eur`), embedded symbols (`$3,385,785`), and zero-decimal JPY subunit handling across `.csv` and `.xlsx` files.
  - **Domain & Reversal Tests (`test/services/reconciliation/process_line_service_test.rb`):** Tests +/- 23h 59m (duplicate) vs +/- 25h (reconciled) window boundaries, reversal netting (`reversal_of_id` link + net zero closing balance), duplicate reversal rejection, and unmatched reversal parking.
  - **Closing Balance Query Tests (`test/queries/reconciled_balance_query_test.rb`):** Verifies opening balance (`value_date < @from_date`), period net movement, closing balance per (account, currency), and exclusion of un-reconciled raw lines.
  - **Multi-Threaded Concurrency Testing (`test/services/reconciliation/concurrency_test.rb`):** Runs with transactional tests disabled (`self.use_transactional_tests = false`) using `Concurrent::CyclicBarrier` to execute real simultaneous threads against PostgreSQL, asserting single-movement creation under concurrent exact re-deliveries and near-duplicates.

-----

## 7. Risks & Mitigations

These are the 5 main risks and the mitigations implemented.
<p align="center">
<img src="app/assets/images/slide-9.jpg" style="border:1px solid #fff;padding: 2px;max-width:30rem" title="Risks & Mitigations"  alt="Risks & Mitigations"/>
</p>


| Identified Risk                                     | Severity | Mitigation Strategy                                                                                                                                        |
| :-------------------------------------------------- | :------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Concurrent Ingestion Race Conditions**            | High     | Partial unique index + `ON CONFLICT DO NOTHING` for `source_id`, plus `Account#with_lock` pessimistic row lock during reconciliation.                      |
| **Currency Subunit Misrepresentation (JPY vs USD)** | High     | `money-rails` / `monetize` integration with explicit ISO currency validation so zero-decimal JPY amounts store exact yen units without multiplying by 100. |
| **Messy Input Formatting**                          | Medium   | Normalization layer in `ParseStatementFileService` handling `DD/MM/YYYY` vs. ISO dates, embedded symbols/commas, and whitespace cleanup.                   |
| **Cross-Tenant Data Leakage**                       | High     | Mandatory `tenant_id` on all tables, leading `tenant_id` in composite indexes, `Current.tenant` scoping, and policy authorization.                         |
| **Out-of-Order Reversal Arrival**                   | Medium   | Detected via regex pattern and parked as `unmatched_reversal` rather than applying an unverified debit.                                                    |


---

## 8. Scaling, Multi-Tenancy & Production Readiness (ADR)
<p align="center">
<img src="app/assets/images/slide-10.jpg" style="border:1px solid #fff;padding: 2px;max-width:30rem" title="Data Model & Idempotency Guarantees"  alt="Phase 2 — Future Upgrade Paths"/>
</p>

### Phase 1 — Shared Database, Shared Schema (Current State)

  - **Tenant Context:** `Current.tenant` (`ActiveSupport::CurrentAttributes`) is resolved per request from the authenticated user's session.
  - **Database Scoping:** Every tenant-owned table includes `tenant_id NOT NULL` as the leading column in all composite indexes.
  - **Authorization:** Native Rails 8 authentication paired with `AccountPolicy` verifying tenant membership before querying balances or triggering ingestion.

### Phase 2A — PostgreSQL Declarative Partitioning (Intermediate Scale)

  - **PostgreSQL Table Partitioning:** Physical Table Partitioning: High-volume enterprise tenants can be isolated into dedicated physical PostgreSQL LIST partitions by tenant_id within the primary cluster (PARTITION BY LIST (tenant_id)).
  - **Zero Model Changes:** Active Record models remain unchanged while PostgreSQL manages partition pruning, bounding B-tree index depths and autovacuum overhead.

### Phase 2B - Native Rails 8 Horizontal Sharding (Enterprise Scale) 
  - **Shard Structure:** Dedicated PostgreSQL databases ("shards") sharing an identical schema are provisioned per enterprise tenant or region using Rails 8 native ```connects_to```.
  - **Enabling Architecture Built Today**  
    - **UUID Primary Keys:** Prevent primary key collisions across shards when migrating or merging data.
    - **Denormalized tenant_id:** Present directly on child tables (```raw_statement_lines```, ```reconciled_movements```), enabling single-table extraction queries (WHERE tenant_id = ?) without cross-shard multi-table joins.
    - **Explicit Worker Context:** Background jobs receive tenant_id as an explicit parameter rather than relying on thread-local global state, making worker execution shard-aware.
<!-- HIDE PHASE 2 MARKDOWN
```
+-----------------------------------------------------------------------------------+
|                        Rails 8 Active Record Layer                                |
|         (Current.tenant / Explicit Worker Tenant Scoping Context)                 |
+-----------------------------------------------------------------------------------+

                    +-------------------------+-------------------------+
                    |                                                   |
                    v                                                   v
+----------------------------------+               +----------------------------------+
|      Database Shard 1            |               |      Database Shard 2            |
|  (Tenant: acme-treasury)         |               |  (Tenant: northwind-fx)          |
+----------------------------------+               +----------------------------------+
|  - tenants (UUID PK)             |               |  - tenants (UUID PK)             |
|  - accounts (tenant_id)          |               |  - accounts (tenant_id)          |
|  - raw_statement_lines           |               |  - raw_statement_lines           |
|  - reconciled_movements          |               |  - reconciled_movements          |
+----------------------------------+               +----------------------------------+
```
-->

---

## 9. Production Readiness & Observability Additions
<p align="center">
<img src="app/assets/images/slide-11.jpg" style="border:1px solid #fff;padding: 2px;max-width:30rem" title="Data Model & Idempotency Guarantees"  alt="Production Readiness & Observability Additions"/>
</p>

  - **Observability & Telemetry:** Structured JSON logging tagged with `tenant_id`, `account_id`, `source_id`, and `correlation_id`; OpenTelemetry traces around file ingestion batches; Prometheus metrics for `ingestion.lines.reconciled`, `ingestion.lines.duplicate`, `ingestion.lines.unmatched_reversal`, and `reconciliation.account_lock.wait_ms`.
  - **Asynchronous Ingestion & DLQ:** Move file processing into `Solid Queue` jobs partitioned by `account_id` with exponential backoff and a dead-letter queue (DLQ) for unparseable payloads.

-----

## 10. Frontend & API Shape

### REST API Endpoint

``` http
curl -X GET "http://localhost:3000/api/v1/accounts/49581bf6-7448-4efc-bc7b-6a4ec732652e/reconciled_balance?from=2023-01-01&to=2026-06-30" \
     -H "Accept: application/json" \
     -H "Authorization: Bearer HqsS6FeEN7Ihn7v-9W2xRiyxLZ_ZVQR-F5zwdG-gBQjmYfOk_9q_VNstpBqNhFGkd8u8V0PQyOA4b4QGYyLQcQ"
```

JSON Response Schema

``` json
{
  "tenant_slug": "acme-treasury",
  "account": {
    "id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
    "account_number": "ACC-01",
    "business_unit": "Americas Treasury"
  },
  "period": {
    "from": "2024-01-01",
    "to": "2024-06-30"
  },
  "balances_by_currency": [
    {
      "currency": "EUR",
      "opening_balance_cents": 1000000,
      "opening_balance_formatted": "€10,000.00",
      "period_net_movement_cents": 450000,
      "period_net_movement_formatted": "€4,500.00",
      "closing_balance_cents": 1450000,
      "closing_balance_formatted": "€14,500.00",
      "reconciled_count": 142,
      "excluded_duplicates_count": 3,
      "reversals_count": 1
    }
  ]
}

```

## 11. Treasury Dashboard UI
  - **Period Filter Form:** Standard HTML GET form allowing users to select `from_date` and `to_date` ranges to recalculate closing balances dynamically.
  - **Balance Cards & Ledger View:** Server-rendered Rails ERB view displaying opening balance, period net movement, and closing balance per currency alongside the recent reconciled movements table.
