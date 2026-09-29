# MoMo Transactions API — Documentation

Base URL: `http://localhost:8000`

All endpoints require HTTP Basic Authentication (`audrey` / `anniyera`). Requests without valid credentials receive `401 Unauthorized`.

---

## GET /transactions

Returns all transactions.

**Request**
```
curl -u audrey:anniyera http://localhost:8000/transactions
```

**Response — 200 OK**
```json
[
  {
    "id": 1,
    "date": "1715351458724",
    "readable_date": "10 May 2024 4:30:58 PM",
    "type": "received_money",
    "amount": 2000.0,
    "counterparty": "Jane Smith",
    "transaction_id": "76662021700",
    "raw_body": "You have received 2000 RWF from Jane Smith ..."
  }
]
```

**Errors**: `401 Unauthorized`

---

## GET /transactions/{id}

Returns a single transaction by id.

**Request**
```
curl -u audrey:anniyera http://localhost:8000/transactions/10
```

**Response — 200 OK**
```json
{
  "id": 10,
  "date": "1715513672603",
  "readable_date": "12 May 2024 1:34:32 PM",
  "type": "payment",
  "amount": 3500.0,
  "counterparty": "Alex Doe",
  "transaction_id": "82113964658",
  "raw_body": "TxId: 82113964658. Your payment of 3,500 RWF to Alex Doe ..."
}
```

**Errors**
- `401 Unauthorized`
- `400 Bad Request` — id in the URL isn't a number
- `404 Not Found` — no transaction with that id

---

## POST /transactions

Creates a new transaction. The server assigns the `id`.

**Request**
```
curl -u audrey:anniyera -X POST http://localhost:8000/transactions \
  -H "Content-Type: application/json" \
  -d '{"type":"payment","amount":5000,"counterparty":"Test Vendor"}'
```

**Response — 201 Created**
```json
{
  "type": "payment",
  "amount": 5000,
  "counterparty": "Test Vendor",
  "id": 1692
}
```

**Errors**: `401 Unauthorized`

---

## PUT /transactions/{id}

Updates fields on an existing transaction (only the fields you send are changed).

**Request**
```
curl -u audrey:anniyera -X PUT http://localhost:8000/transactions/1692 \
  -H "Content-Type: application/json" \
  -d '{"amount":7500}'
```

**Response — 200 OK**
```json
{
  "type": "payment",
  "amount": 7500,
  "counterparty": "Test Vendor",
  "id": 1692
}
```

**Errors**
- `401 Unauthorized`
- `400 Bad Request` — id in the URL isn't a number
- `404 Not Found` — no transaction with that id

---

## DELETE /transactions/{id}

Deletes a transaction.

**Request**
```
curl -u audrey:anniyera -X DELETE http://localhost:8000/transactions/1692
```

**Response — 200 OK**
```json
{ "message": "Deleted" }
```

**Errors**
 `401 Unauthorized`
 `400 Bad Request` — id in the URL isn't a number
 `404 Not Found` — no transaction with that id



## Error code summary

| Code | Meaning | When it happens |
|---|---|---|
| 400 | Bad Request | The `{id}` in the URL isn't a valid integer |
| 401 | Unauthorized | Missing or incorrect Basic Auth credentials |
| 404 | Not Found | No transaction with the given id, or an unrecognized route |

## Security note

This API uses HTTP Basic Auth, which sends the username and password base64-encoded — not encrypted — on every single request. Base64 is trivially reversible, so anyone who can see the traffic can recover the real password directly. Even over HTTPS, the same static credential is reused on every call, so one leak compromises the account indefinitely. Stronger alternatives:

 **JWT (JSON Web Tokens)**: the client authenticates once and receives a signed, time-limited token to send on subsequent requests, so the password isn't transmitted repeatedly and a leaked token eventually expires.
 **OAuth2**: delegates authentication to a dedicated identity provider and issues scoped, revocable access tokens, so credentials are never shared directly with the API.