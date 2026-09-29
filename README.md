# MoMo SMS Analytics

A team project that turns MoMo (mobile money) SMS data into something you can query and analyse: the raw XML export is parsed and cleaned, categorised by transaction type, stored, and made available through a dashboard and a REST API.

This README covers the whole repository. The **REST API assignment** (Basic Auth, CRUD endpoints, DSA comparison) lives in `api/`, `dsa/`, `docs/` and `screenshots/`, and its setup instructions are further down.

## Team

**Team name:** Data squad

**Members**

- Yera Victoire Promise
- Akuzwe Anny Benitha
- Audrey Hategekimana

## Repository structure

```
momo-sms-analytics/
├── web/                          # The dashboard (what you see in the browser)
├── data/                         # Raw messages, cleaned data, and logs
├── etl/                          # Code that reads, cleans, and saves the data
├── scripts/                      # Shortcuts to run the project
├── tests/                        # Code that checks everything works
├── docs/                         # Architecture diagram image and API documentation
│   └── api_docs.md               # Endpoint documentation (API assignment)
├── api/
│   └── api_server.py             # REST API server (port 8000)
├── dsa/
│   ├── parse.py                  # XML -> transactions.json
│   ├── search_compare.py         # Linear search vs dictionary lookup
│   └── modified_sms_v2-1.xml     # Raw SMS dataset (input)
├── screenshots/                  # API test evidence (curl / Postman)
├── MoMo_API_Report.pdf           # Report (security, endpoints, DSA, Basic Auth)
└── README.md
```

`web/`, `data/`, `etl/`, `scripts/` and `tests/` belong to the ETL and dashboard part of the project. `api/`, `dsa/`, `screenshots/` and the API docs and report belong to the REST API assignment.

## Requirements

- Python 3.10 or newer
- No third-party packages. Everything used is in the standard library: `http.server`, `xml.etree.ElementTree`, `json`, `base64`, `re`, `time`.

## Setup and running

Run the steps in this order. **Each script must be run from inside its own folder**, because the file paths are relative.

**1. Create `transactions.json` from the XML**

```bash
cd dsa
python3 parse.py
```

Expected output: `Total transactions: 1691`. This creates `dsa/transactions.json`.

**2. Start the API server**

```bash
cd ../api
python3 api_server.py
```

Expected output: `Server running at http://localhost:8000`. Leave this terminal open.

> The server reads `../dsa/transactions.json` once, when it starts. If you re-run the parser, restart the server. If the file is missing, the server starts with no data and every id returns 404.

**3. Run the DSA comparison** (does not need the server)

```bash
cd ../dsa
python3 search_compare.py
```

This looks up 20 random ids with both methods and prints the total time for each and how many times faster the dictionary was.

## Authentication

All endpoints use HTTP Basic Authentication. The username and password are set as `USERNAME` and `PASSWORD` at the top of `api/api_server.py`. Requests with missing or wrong credentials receive `401 Unauthorized`.

Below, `USER:PASS` stands for those values.

## Endpoints

| Method | Path | Purpose | Success code |
|---|---|---|---|
| GET | `/transactions` | List all transactions | 200 |
| GET | `/transactions/{id}` | Get one transaction | 200 |
| POST | `/transactions` | Create a transaction | 201 |
| PUT | `/transactions/{id}` | Update a transaction | 200 |
| DELETE | `/transactions/{id}` | Delete a transaction | 200 |

Error codes: `400` (id is not a number), `401` (bad credentials), `404` (not found).

Full request and response examples are in [`docs/api_docs.md`](docs/api_docs.md).

### Quick examples

```bash
# List all
curl -u USER:PASS http://localhost:8000/transactions

# Get one
curl -u USER:PASS http://localhost:8000/transactions/1

# Create
curl -u USER:PASS -X POST http://localhost:8000/transactions \
  -H "Content-Type: application/json" \
  -d '{"type":"payment","amount":5000,"counterparty":"Test Vendor"}'

# Update (use the id returned by the POST)
curl -u USER:PASS -X PUT http://localhost:8000/transactions/1692 \
  -H "Content-Type: application/json" \
  -d '{"amount":7500}'

# Delete
curl -u USER:PASS -X DELETE http://localhost:8000/transactions/1692

# Wrong credentials -> 401
curl -i -u wrong:creds http://localhost:8000/transactions
```

## Testing

The API was tested with curl. Screenshots in [`screenshots/`](screenshots/) show:

- a successful authenticated GET
- an unauthorized request with wrong credentials (401)
- a successful POST (201)
- a successful PUT (200)
- a successful DELETE (200)

## Data structures and algorithms

`dsa/search_compare.py` compares two ways of finding a transaction by id over 1,691 records, timing 20 random lookups:

| Method | Complexity | Idea |
|---|---|---|
| Linear search | O(n) | Scan the list until the id matches |
| Dictionary lookup | O(1) average | Hash the id and jump to the record |

In our runs the dictionary was roughly 90 to 130 times faster. Full results and discussion, including other structures that could help (binary search, database index), are in the report.

## Data notes

- The XML export has 1,691 SMS records. About 97.6% are classified into a transaction type (`payment`, `transfer`, `bank_deposit`, `received_money`, `merchant_payment`, `withdrawal`); the rest are labelled `unknown` (OTP codes, airtime, bundle confirmations, reversals) but keep their full raw text.
- Some messages contain characters that are illegal in XML attributes (a literal `<#>` prefix, or a bare `&`). `parse.py` escapes these before parsing.

## Security note

Basic Auth is used because the assignment requires it, but it is not suitable for production. The credentials are only Base64-encoded (not encrypted), are sent on every request, never expire, and here are hardcoded in the source. A real deployment should use HTTPS with JWT or OAuth 2.0. See the report for the full discussion.
