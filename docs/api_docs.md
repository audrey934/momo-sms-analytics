MoMo Transactions API — Simple Guide
Base URL: http://localhost:8000  
All requests need a username and password (Basic Auth). If you don’t include them or they’re wrong, the server replies with 401 Unauthorized.

 GET /transactions
Get the full list of transactions.

Example request

bash
curl -u admin:momo_secret_2024 http://localhost:8000/transactions
Example response

json
[
  {
    "id": 2,
    "type": "payment",
    "amount": 1000.0,
    "counterparty": "Jane Smith"
  }
]
Possible errors

401 Unauthorized → you didn’t log in correctly

 GET /transactions/{id}
Get one transaction by its ID.

Example request

bash
curl -u admin:momo_secret_2024 http://localhost:8000/transactions/2
Example response

json
{
  "id": 2,
  "type": "payment",
  "amount": 1000.0,
  "counterparty": "Jane Smith"
}
Possible errors

401 Unauthorized → bad login

404 Not Found → no transaction with that ID

 POST /transactions
Add a new transaction. The server will give it an ID automatically.

Example request

bash
curl -u admin:momo_secret_2024 -X POST http://localhost:8000/transactions \
  -H "Content-Type: application/json" \
  -d '{"type":"payment","amount":5000,"counterparty":"Test Vendor"}'
Example response

json
{
  "id": 1692,
  "type": "payment",
  "amount": 5000,
  "counterparty": "Test Vendor"
}
Possible errors

401 Unauthorized → bad login

400 Bad Request → you didn’t send valid JSON

 PUT /transactions/{id}
Update an existing transaction.

Example request

bash
curl -u admin:momo_secret_2024 -X PUT http://localhost:8000/transactions/1692 \
  -H "Content-Type: application/json" \
  -d '{"type":"payment","amount":7500,"counterparty":"Updated Vendor"}'
Example response

json
{
  "id": 1692,
  "type": "payment",
  "amount": 7500,
  "counterparty": "Updated Vendor"
}
Possible errors

401 Unauthorized → bad login

400 Bad Request → invalid JSON

404 Not Found → no transaction with that ID

DELETE /transactions/{id}
Remove a transaction.

Example request

bash
curl -u admin:momo_secret_2024 -X DELETE http://localhost:8000/transactions/1692
Example response

json
{ "message": "Transaction 1692 deleted" }
Possible errors

401 Unauthorized → bad login

404 Not Found → no transaction with that ID

 Error Codes Quick Reference
Code	Meaning	When it happens
400	Bad Request	You sent broken JSON
401	Unauthorized	Wrong or missing login
404	Not Found	Route or ID doesn’t exist


 Security Note
Right now the API uses Basic Auth. That means your username and password are sent (just base64‑encoded, not encrypted) with every request. This is fine for practice, but in real systems it’s weak because:

Anyone who sees the traffic can decode your password if you’re not using HTTPS.

Even with HTTPS, the same password is reused every time, so if it leaks once, it’s compromised forever.

Better options in real projects:

JWT (JSON Web Tokens): You log in once, get a temporary token, and use that instead of sending your password every time.

OAuth2: Lets a trusted identity provider handle login and gives you short‑lived tokens with specific permissions.