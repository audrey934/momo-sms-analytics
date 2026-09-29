import json
import time
import random

# Load transactions from the JSON file created by parse.py
with open("transactions.json", "r") as file:
    transactions = json.load(file)

# Build a dictionary for fast lookup (id → transaction)
transaction_dict = {t["id"]: t for t in transactions}


# Linear search function

def linear_search(transactions, target_id):
    """Go through the list one by one until we find the transaction."""
    for t in transactions:
        if t["id"] == target_id:
            return t
    return None


# Dictionary lookup function

def dict_lookup(transaction_dict, target_id):
    """Directly access the transaction using its id as a key."""
    return transaction_dict.get(target_id)


# Compare efficiency

def compare(target_ids):
    # Linear search timing, over every id in the sample
    start = time.perf_counter()
    for tid in target_ids:
        linear_search(transactions, tid)
    linear_time = time.perf_counter() - start


    start = time.perf_counter()
    for tid in target_ids:
        dict_lookup(transaction_dict, tid)
    dict_time = time.perf_counter() - start

    print(f"Searched {len(target_ids)} ids")
    print(f"Linear search total time:     {linear_time * 1000:.4f} ms")
    print(f"Dictionary lookup total time: {dict_time * 1000:.4f} ms")
    print(f"Dictionary lookup was ~{linear_time / dict_time:.0f}x faster")


# Run comparison

if __name__ == "__main__":
    # Test over 20 random ids, as the assignment asks for
    sample_ids = random.sample([t["id"] for t in transactions], 20)
    compare(sample_ids)