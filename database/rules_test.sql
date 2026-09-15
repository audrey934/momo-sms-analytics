-- rule_tests.sql
-- Each statement below is deliberately wrong and must be rejected by the database.
-- Run one at a time. An error means the rule worked.

USE momo_sms_db;

-- Negative amount
INSERT INTO Transactions (category_id, amount, transaction_datetime, raw_sms_body)
VALUES (1, -500.00, '2024-06-01 10:00:00', 'test');

-- Same transaction ID twice
INSERT INTO Transactions (financial_transaction_id, category_id, amount, transaction_datetime, raw_sms_body)
VALUES ('76662021700', 1, 2000.00, '2024-06-01 10:00:00', 'test');

-- A category that does not exist
INSERT INTO Transactions (category_id, amount, transaction_datetime, raw_sms_body)
VALUES (9999, 1000.00, '2024-06-01 10:00:00', 'test');

-- A phone number in the wrong shape
INSERT INTO Users (full_name, phone_number) VALUES ('Bad Number', '12345');

-- A date in the future
INSERT INTO Transactions (category_id, amount, transaction_datetime, raw_sms_body)
VALUES (1, 1000.00, '2099-01-01 00:00:00', 'test');

-- A fee bigger than the amount
INSERT INTO Transactions (category_id, amount, fee, transaction_datetime, raw_sms_body)
VALUES (1, 100.00, 500.00, '2024-06-01 10:00:00', 'test');

-- Same person as sender and receiver
INSERT INTO Transaction_Participants (transaction_id, user_id, role) VALUES (1, 1, 'SENDER');

-- Deleting a completed transaction
DELETE FROM Transactions WHERE transaction_id = 1;

-- Editing the original message text
UPDATE Transactions SET raw_sms_body = 'tampered' WHERE transaction_id = 1;

-- Deleting a person who has history
DELETE FROM Users WHERE user_id = 1;

-- An empty message body
INSERT INTO Transactions (category_id, amount, transaction_datetime, raw_sms_body)
VALUES (1, 100.00, '2024-06-01 10:00:00', '');