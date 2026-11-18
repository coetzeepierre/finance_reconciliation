# Statement Reconciliation Service (Rails 8 + PostgreSQL)

[See Design document](https://github.com/coetzeepierre/finance_reconciliation/blob/main/DESIGN.md)

An idempotent, multi-tenant bank statement ingestion, deduplication, and reconciliation engine built with **Rails 8**, **PostgreSQL**, and **Hotwire**.

This application aggregates raw bank statement feeds across multiple legal entities (tenants), bank accounts, and currencies. It guarantees point-in-time financial auditability by separating raw feed ingestion from the canonical reconciled ledger, enforcing structural database-level idempotency, and providing real-time closing balance reports.

---

## Key Architectural Highlights

- **Two-Stage Ledger Architecture:** Separates raw immutable audit logs (`raw_statement_lines`) from canonical ledger records (`reconciled_movements`) to ensure full auditability of excluded duplicates and netted reversals.
- **Database-Enforced Idempotency:** Partial unique indexes on `(tenant_id, source_id)` combined with PostgreSQL `ON CONFLICT DO NOTHING` prevent duplicate ingestion of exact re-deliveries under high-concurrency feeds.
- **Pessimistic Locking for Race Conditions:** Uses `Account#with_lock` (`SELECT ... FOR UPDATE`) during reconciliation to serialize near-duplicate window checks and reversal resolution cleanly per account.
- **Monetary Integrity & Currency Safety:** Enforces integer subunit calculations (`amount_cents`) backed by PostgreSQL `CHECK` constraints and `money-rails` / `monetize`, ensuring safe handling of zero-decimal currencies like **JPY** alongside standard decimal currencies (**USD**, **EUR**, **GBP**, **CHF**).
- **Multi-Tenant Isolation:** Shared-schema row-level isolation via `tenant_id` scoping on every model, request-level context resolution (`Current.tenant`), and composite indexing.
- **Unified Multi-Format File Ingestion:** Supports `.csv`, `.xls`, and `.xlsx` statement uploads via `Ingestion::ParseStatementFileService` using streaming format detection and strict tenant matching.

---

## Tech Stack

- **Framework:** Ruby on Rails 8.0
- **Database:** PostgreSQL 16+ (with `pgcrypto` for UUID primary keys)
- **Frontend:** Hotwire (Turbo Frames / Turbo Streams) & Tailwind CSS
- **Money & Parsing:** `money-rails`, `monetize`, `roo` (Excel/CSV parsing)
- **Testing:** Minitest with real PostgreSQL transactional and multi-threaded concurrency suites

---

## Prerequisites & Setup

### System Requirements

- **Ruby:** 3.3+ (or 3.2+)
- **Rails:** 8.0+
- **Database:** PostgreSQL 16+

### 1. Installation

Clone the repository and install dependencies:

git clone [GitHub repo](https://github.com/coetzeepierre/finance_reconciliation.git)
```bash
cd rails-8-app
bundle install

````

### 2\. Database Setup

Initialize the database schema and seed initial tenant/account data:

``` bash
bin/rails db:prepare
bin/rails db:seed

```

-----

## Running the Application

Start the Rails development server:

``` bash
bin/rails server

```

Navigate to `http://localhost:3000` in your browser.

Authenticate with the seeded 
user name:
```
treasury.admin@acme.com
```
password:
```
securepassword123
```

-----

## Running the Test Suite

The test suite validates database-level constraints, money accuracy, near-duplicate window edge cases, and thread-level concurrency:

``` bash
# Run all unit, service, query, and integration tests
bin/rails test

# Run concurrency and idempotency tests specifically
bin/rails test test/services/reconciliation/concurrency_test.rb

```

-----

## Core Workflows & Usage

### 1\. Statement File Upload (UI)

1.  Navigate to an Account detail page (`/treasury/accounts/:id`).
2.  Click **Import Statement**.
3.  Select any bank statement file (`.csv`, `.xls`, or `.xlsx`).
4.  The file will be ingested via `Ingestion::ParseStatementFileService`, automatically matching rows to `Current.tenant` and promoting verified lines into `ReconciledMovement` ledger entries.

### 2\. Reconciled Balance API

Retrieve reconciled closing balances, period net movements, opening balances, and audit counts per account and currency over a specified date range.

#### Endpoint

``` http
curl -X GET "http://localhost:3000/api/v1/accounts/ACCOUNT-ID-HERE/reconciled_balance?from=2023-01-01&to=2026-06-30" \
     -H "Accept: application/json"
```

#### Sample JSON Response

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
    },
    {
      "currency": "USD",
      "opening_balance_cents": 5000000,
      "opening_balance_formatted": "$50,000.00",
      "period_net_movement_cents": -125000,
      "period_net_movement_formatted": "-$1,250.00",
      "closing_balance_cents": 4875000,
      "closing_balance_formatted": "$48,750.00",
      "reconciled_count": 89,
      "excluded_duplicates_count": 0,
      "reversals_count": 2
    }
  ]
}

```

-----
