import xml.etree.ElementTree as ET
import json
import re


# Some SMS export files contain a raw "&" that was never escaped to
# "&amp;", which breaks strict XML parsing. This fixes only the bare
# "&" characters and leaves already-valid entities (&amp; &lt; etc.)
# untouched.
def load_xml_safely(filename):
    with open(filename, "r", encoding="utf-8") as f:
        content = f.read()
    # Fix stray "&" not already part of a valid entity
    content = re.sub(r"&(?!amp;|lt;|gt;|quot;|apos;|#\d+;|#x[0-9a-fA-F]+;)", "&amp;", content)
    # Fix stray "<" that isn't the start of a real tag (this file only uses
    # <sms ...>, </sms>, <smses ...>, </smses>, and <?xml ...?> as real tags -
    # anything else, like the "<#>" OTP message prefix, gets escaped)
    content = re.sub(r"<(?!/?sms|\?xml)", "&lt;", content)
    return content


# Turn an amount like "20,000" into 20000.0
def clean_amount(amount):
    if amount:
        return float(amount.replace(",", ""))
    return None


# Read one SMS and find the important transaction information
def get_transaction_info(message):

    transaction = {
        "type": "unknown",
        "amount": None,
        "counterparty": None,
        "transaction_id": None
    }

    # --------------------------------
    # 1. Money received
    # --------------------------------
    if "You have received" in message:

        transaction["type"] = "received_money"

        amount = re.search(r"received ([\d,]+) RWF", message)
        if amount:
            transaction["amount"] = clean_amount(amount.group(1))

        sender = re.search(r"from ([^(]+)", message)
        if sender:
            transaction["counterparty"] = sender.group(1).strip()

        txid = re.search(
            r"Financial Transaction Id:\s*(\d+)",
            message
        )
        if txid:
            transaction["transaction_id"] = txid.group(1)

    # --------------------------------
    # 2. Payment
    # --------------------------------
    elif "Your payment of" in message:

        transaction["type"] = "payment"

        amount = re.search(
            r"payment of ([\d,]+) RWF",
            message
        )
        if amount:
            transaction["amount"] = clean_amount(amount.group(1))

        # Example:
        # "to Alex Doe 42875 has been completed"
        receiver = re.search(
            r"to (.+?)\s+\d+\s+has been completed",
            message
        )

        if receiver:
            transaction["counterparty"] = receiver.group(1).strip()

        txid = re.search(
            r"TxId:\s*(\d+)",
            message
        )

        if txid:
            transaction["transaction_id"] = txid.group(1)

    # --------------------------------
    # 3. Money transfer
    # --------------------------------
    elif "RWF transferred to" in message:

        transaction["type"] = "transfer"

        amount = re.search(
            r"([\d,]+) RWF transferred",
            message
        )

        if amount:
            transaction["amount"] = clean_amount(amount.group(1))

        receiver = re.search(
            r"transferred to ([^(]+)\(",
            message
        )

        if receiver:
            transaction["counterparty"] = receiver.group(1).strip()

    # --------------------------------
    # 4. Bank deposit
    # --------------------------------
    elif "A bank deposit of" in message:

        transaction["type"] = "bank_deposit"

        amount = re.search(
            r"bank deposit of ([\d,]+) RWF",
            message
        )

        if amount:
            transaction["amount"] = clean_amount(amount.group(1))

    # --------------------------------
    # 5. Merchant payment
    # --------------------------------
    elif "A transaction of" in message:

        transaction["type"] = "merchant_payment"

        amount = re.search(
            r"transaction of ([\d,]+) RWF",
            message
        )

        if amount:
            transaction["amount"] = clean_amount(amount.group(1))

        # Example:
        # "by INFORMATION TECHNOLOGY ENGINEERING..."
        receiver = re.search(
            r"by (.+?) on your MOMO account",
            message
        )

        if receiver:
            transaction["counterparty"] = receiver.group(1).strip()

        txid = re.search(
            r"Financial Transaction Id:\s*(\d+)",
            message
        )

        if txid:
            transaction["transaction_id"] = txid.group(1)

    # --------------------------------
    # 6. Withdrawal
    # --------------------------------
    elif "withdrawn" in message:

        transaction["type"] = "withdrawal"

        amount = re.search(
            r"withdrawn ([\d,]+) RWF",
            message
        )

        if amount:
            transaction["amount"] = clean_amount(amount.group(1))

        agent = re.search(
            r"Agent ([^(]+)",
            message
        )

        if agent:
            transaction["counterparty"] = agent.group(1).strip()

    return transaction


# Read the XML file and create our transaction list
def parse_xml_file(filename):

    # Read and repair the XML text, then parse it
    content = load_xml_safely(filename)
    root = ET.fromstring(content)

    # This list will contain all transactions
    transactions = []

    # Go through every SMS in the XML file
    for number, sms in enumerate(root.findall("sms"), start=1):

        # Get the SMS text
        message = sms.get("body", "")

        # Extract useful information from the message
        information = get_transaction_info(message)

        # Create a dictionary for this transaction
        transaction = {
            "id": number,
            "date": sms.get("date"),
            "readable_date": sms.get("readable_date"),
            "type": information["type"],
            "amount": information["amount"],
            "counterparty": information["counterparty"],
            "transaction_id": information["transaction_id"],
            "raw_body": message
        }

        # Add the transaction to our list
        transactions.append(transaction)

    return transactions


# This part runs when we execute parser.py
if __name__ == "__main__":

    # Name of the XML file
    filename = "modified_sms_v2-1.xml"

    # Parse the XML file
    transactions = parse_xml_file(filename)

    # Save the transactions as JSON
    with open("transactions.json", "w") as file:
        json.dump(transactions, file, indent=4)

    # Show how many records we found
    print("Total transactions:", len(transactions))

    print("Transactions saved to transactions.json")

    # Display the first transaction so we can check the result
    if transactions:
        print("\nFirst transaction:")
        print(json.dumps(transactions[0], indent=4))
