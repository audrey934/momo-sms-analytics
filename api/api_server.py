import json
import base64
from http.server import BaseHTTPRequestHandler, HTTPServer


DATA_FILE = "../dsa/transactions.json"


USERNAME = "audrey"
PASSWORD = "anniyera"


def load_data():
    """Read transactions from the JSON file."""
    try:
        with open(DATA_FILE, "r") as f:
            return json.load(f)
    except FileNotFoundError:
        return []  

def save_data(transactions):
    """Write transactions back to the JSON file."""
    with open(DATA_FILE, "w") as f:
        json.dump(transactions, f, indent=2)


transactions = load_data()


next_id = max((t["id"] for t in transactions), default=0) + 1


def check_auth(header):
    """Check if the request has the right username and password."""
    if not header:
        return False
    try:
        method, encoded = header.split(" ")
        if method != "Basic":
            return False
        decoded = base64.b64decode(encoded).decode("utf-8")
        user, pwd = decoded.split(":")
        return user == USERNAME and pwd == PASSWORD
    except Exception:
        return False


class SimpleAPI(BaseHTTPRequestHandler):
    def _unauthorized(self):
        """Send back a 401 error if login fails."""
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="MoMo API"')
        self.end_headers()
        self.wfile.write(b"Unauthorized")

    def _send_json(self, status, payload):
        """Send a JSON response with given status code."""
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        """Read JSON body from the request."""
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length))

   
    def do_GET(self):
        if not check_auth(self.headers.get("Authorization")):
            return self._unauthorized()

        if self.path == "/transactions":
            
            return self._send_json(200, transactions)

        if self.path.startswith("/transactions/"):
            try:
                tid = int(self.path.split("/")[-1])
                for tx in transactions:
                    if tx["id"] == tid:
                        return self._send_json(200, tx)
                return self._send_json(404, {"error": "Not found"})
            except ValueError:
                return self._send_json(400, {"error": "Bad request"})

        
        return self._send_json(404, {"error": "Not found"})

    def do_POST(self):
        global next_id
        if not check_auth(self.headers.get("Authorization")):
            return self._unauthorized()

        data = self._read_body()
        data["id"] = next_id  
        next_id += 1
        transactions.append(data)
        save_data(transactions)
        return self._send_json(201, data)

    
    def do_PUT(self):
        if not check_auth(self.headers.get("Authorization")):
            return self._unauthorized()

        try:
            tid = int(self.path.split("/")[-1])
            data = self._read_body()
            for tx in transactions:
                if tx["id"] == tid:
                    tx.update(data)  
                    save_data(transactions)
                    return self._send_json(200, tx)
            return self._send_json(404, {"error": "Not found"})
        except ValueError:
            return self._send_json(400, {"error": "Bad request"})

    
    def do_DELETE(self):
        if not check_auth(self.headers.get("Authorization")):
            return self._unauthorized()

        try:
            tid = int(self.path.split("/")[-1])
            for tx in transactions:
                if tx["id"] == tid:
                    transactions.remove(tx)
                    save_data(transactions)
                    return self._send_json(200, {"message": "Deleted"})
            return self._send_json(404, {"error": "Not found"})
        except ValueError:
            return self._send_json(400, {"error": "Bad request"})


if __name__ == "__main__":
    server = HTTPServer(("localhost", 8000), SimpleAPI)
    print("Server running at http://localhost:8000")
    server.serve_forever()