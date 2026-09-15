-- Full script
-- Sections
--   1  Database
--   2  Tables
--   3  Indexes
--   4  Seed: categories and users
--   5  Seed: transactions and participants
--   6  Triggers
--   7  Views and access control
--   8  CRUD operations and rule tests

-- SECTION 1: DATABASE

DROP DATABASE IF EXISTS momo_sms_db;
CREATE DATABASE momo_sms_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE momo_sms_db;

-- SECTION 2: TABLES
CREATE TABLE Users (
    user_id       INT AUTO_INCREMENT PRIMARY KEY
                  COMMENT 'Surrogate key',
    full_name     VARCHAR(100) NOT NULL
                  COMMENT 'Name as written in the SMS body',
    phone_number  VARCHAR(20) NULL
                  COMMENT 'MSISDN, or the masked form (*********013) when the SMS hides it. 20 chars so raw input like "+250 788 123 456" survives long enough to be normalised.',
    user_type     ENUM('SELF','CUSTOMER','AGENT','MERCHANT','BANK') NOT NULL DEFAULT 'CUSTOMER'
                  COMMENT 'SELF is the account owner; BANK is a deposit channel',
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                  COMMENT 'First time the ETL saw this party',

    CONSTRAINT uq_users_name_phone   UNIQUE (full_name, phone_number),
    CONSTRAINT chk_users_name_len    CHECK (CHAR_LENGTH(TRIM(full_name)) >= 2),
    CONSTRAINT chk_users_phone_shape CHECK (
        phone_number IS NULL
        OR phone_number REGEXP '^250[0-9]{9}$'
        OR phone_number REGEXP '^\\*+[0-9]{3}$'
    )
) ENGINE=InnoDB COMMENT='Parties involved in mobile money transactions';

CREATE TABLE Transaction_Categories (
    category_id    INT AUTO_INCREMENT PRIMARY KEY
                   COMMENT 'Surrogate key',
    category_name  VARCHAR(50) NOT NULL UNIQUE
                   COMMENT 'Deposit, Transfer Sent, Payment, Withdrawal and so on',
    category_type  ENUM('TRANSFER','PAYMENT','DEPOSIT','WITHDRAWAL','AIRTIME','REVERSAL','SYSTEM') NOT NULL
                   COMMENT 'Product grouping, used for roll-up charts',
    direction      ENUM('CREDIT','DEBIT','NEUTRAL') NOT NULL
                   COMMENT 'Which way the money moved. NEUTRAL covers non-financial messages like OTPs.',
    description    VARCHAR(255) NULL
                   COMMENT 'Which SMS pattern maps here',

    CONSTRAINT chk_category_name_len CHECK (CHAR_LENGTH(TRIM(category_name)) >= 3)
) ENGINE=InnoDB COMMENT='Lookup table for transaction classification';


CREATE TABLE Transactions (
    transaction_id           INT AUTO_INCREMENT PRIMARY KEY
                             COMMENT 'Surrogate key',
    financial_transaction_id VARCHAR(30) NULL
                             COMMENT 'MTN Financial Transaction Id / TxId. NULL on 52% of messages.',
    external_transaction_id  VARCHAR(30) NULL
                             COMMENT 'Third-party reference some merchants add on *164* messages',
    category_id              INT NOT NULL
                             COMMENT 'FK to Transaction_Categories',
    amount                   DECIMAL(12,2) NOT NULL
                             COMMENT 'Principal amount. DECIMAL not FLOAT — binary floating point cannot hold RWF exactly and the error compounds across SUM().',
    fee                      DECIMAL(10,2) NOT NULL DEFAULT 0.00
                             COMMENT 'MTN charge; 0 where the SMS says so',
    currency                 CHAR(3) NOT NULL DEFAULT 'RWF'
                             COMMENT 'ISO 4217. Only RWF in the corpus; column exists for later.',
    balance_after            DECIMAL(14,2) NULL
                             COMMENT 'Balance reported after the transaction; NULL where the SMS omits it',
    transaction_datetime     DATETIME NOT NULL
                             COMMENT 'Timestamp from the SMS body, not when the SMS arrived',
    status                   ENUM('COMPLETED','PENDING','FAILED','REVERSED') NOT NULL DEFAULT 'COMPLETED'
                             COMMENT 'Settlement outcome. We mark REVERSED rather than deleting.',
    raw_sms_body             TEXT NOT NULL
                             COMMENT 'Original SMS text, kept for audit. Made immutable by a trigger in section 6.',
    created_at               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                             COMMENT 'When the ETL inserted this row',

    CONSTRAINT fk_tx_category FOREIGN KEY (category_id)
        REFERENCES Transaction_Categories(category_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT uq_tx_financial_id  UNIQUE (financial_transaction_id),
    CONSTRAINT chk_tx_amount       CHECK (amount >= 0),
    CONSTRAINT chk_tx_fee          CHECK (fee >= 0),
    CONSTRAINT chk_tx_balance      CHECK (balance_after IS NULL OR balance_after >= 0),
    CONSTRAINT chk_tx_currency     CHECK (currency IN ('RWF','USD','EUR','KES','UGX')),
    CONSTRAINT chk_tx_date_window  CHECK (transaction_datetime >= '2020-01-01 00:00:00'),
    CONSTRAINT chk_tx_body_present CHECK (CHAR_LENGTH(raw_sms_body) > 0)
) ENGINE=InnoDB COMMENT='One row per financial SMS transaction';


CREATE TABLE Transaction_Participants (
    participant_id  INT AUTO_INCREMENT PRIMARY KEY
                    COMMENT 'Surrogate key',
    transaction_id  INT NOT NULL
                    COMMENT 'FK to Transactions',
    user_id         INT NOT NULL
                    COMMENT 'FK to Users',
    role            ENUM('SENDER','RECEIVER','AGENT','MERCHANT') NOT NULL
                    COMMENT 'What this party did in this transaction',

    CONSTRAINT fk_part_transaction FOREIGN KEY (transaction_id)
        REFERENCES Transactions(transaction_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_part_user FOREIGN KEY (user_id)
        REFERENCES Users(user_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_tx_role UNIQUE (transaction_id, user_id, role)
) ENGINE=InnoDB COMMENT='Junction table resolving Transactions <-> Users M:N';


CREATE TABLE System_Logs (
    log_id         INT AUTO_INCREMENT PRIMARY KEY
                   COMMENT 'Surrogate key',
    transaction_id INT NULL
                   COMMENT 'FK to the transaction concerned; NULL for pipeline-wide events',
    process_stage  ENUM('PARSE','CLEAN','CATEGORIZE','LOAD','EXPORT','API','AUDIT') NOT NULL DEFAULT 'PARSE'
                   COMMENT 'Which stage wrote this entry',
    log_level      ENUM('INFO','WARNING','ERROR') NOT NULL DEFAULT 'INFO'
                   COMMENT 'Severity',
    message        VARCHAR(255) NOT NULL
                   COMMENT 'What happened',
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                   COMMENT 'When the entry was written',

    CONSTRAINT fk_log_transaction FOREIGN KEY (transaction_id)
        REFERENCES Transactions(transaction_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT chk_log_message_len CHECK (CHAR_LENGTH(TRIM(message)) > 0)
) ENGINE=InnoDB COMMENT='ETL / parsing pipeline log entries';

-- SECTION 3: INDEXES

CREATE INDEX idx_tx_datetime      ON Transactions(transaction_datetime);
CREATE INDEX idx_tx_category_date ON Transactions(category_id, transaction_datetime);
CREATE INDEX idx_tx_status        ON Transactions(status);
CREATE INDEX idx_tx_amount        ON Transactions(amount);
CREATE INDEX idx_part_user        ON Transaction_Participants(user_id, role);
CREATE INDEX idx_log_level_time   ON System_Logs(log_level, created_at);
CREATE INDEX idx_log_stage        ON System_Logs(process_stage);

-- SECTION 4: SEED - CATEGORIES AND USERS

INSERT INTO Transaction_Categories (category_name, category_type, direction, description) VALUES
('Deposit',                 'DEPOSIT',    'CREDIT',  'Cash or bank deposit into the mobile money account (*113*R* pattern)'),
('Transfer Received',       'TRANSFER',   'CREDIT',  'Peer-to-peer money received ("You have received X RWF from ...")'),
('Reversal',                'REVERSAL',   'CREDIT',  'Funds returned after a reversed transaction'),
('Transfer Sent',           'TRANSFER',   'DEBIT',   'Peer-to-peer money sent (*165*S* pattern)'),
('Payment',                 'PAYMENT',    'DEBIT',   'Payment for goods/services to a named payee'),
('Withdrawal',              'WITHDRAWAL', 'DEBIT',   'Cash withdrawal via an agent'),
('Airtime Purchase',        'AIRTIME',    'DEBIT',   'Airtime top-up bought from the wallet (*162* pattern)'),
('Bundle Purchase',         'AIRTIME',    'DEBIT',   'Data or voice bundle purchase ("Umaze kugura ...")'),
('Bank Transfer Out',       'TRANSFER',   'DEBIT',   'Wallet-to-bank transfer'),
('Merchant Payment',        'PAYMENT',    'DEBIT',   'Payment to a registered business/paybill (*164* pattern)'),
('OTP Notification',        'SYSTEM',     'NEUTRAL', 'One-time password message; non-financial, kept for completeness');


INSERT INTO Users (full_name, phone_number, user_type) VALUES
('Account Owner',            '250795963036', 'SELF'),
('Jane Smith',               '*********013', 'CUSTOMER'),
('Samuel Carter',            '250791666666', 'CUSTOMER'),
('Robert Brown',             '250788999999', 'CUSTOMER'),
('Mediatrice UWAYISENGA',    '250788658286', 'CUSTOMER'),
('Agent Sophia',             '250790777777', 'AGENT'),
('DIRECT PAYMENT LTD',       NULL,           'MERCHANT'),
('MTN Airtime',              NULL,           'MERCHANT'),
('Bank Deposit Channel',     NULL,           'BANK');




-- SECTION 5: SEED - TRANSACTIONS, PARTICIPANTS, LOGS

INSERT INTO Transactions
    (financial_transaction_id, external_transaction_id, category_id, amount, fee,
     balance_after, transaction_datetime, status, raw_sms_body)
VALUES
-- 1. Incoming transfer. Sender's number was masked in the original message.
('76662021700', NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Transfer Received'),
 2000.00, 0.00, 2000.00, '2024-05-10 16:30:51', 'COMPLETED',
 'You have received 2000 RWF from Jane Smith (*********013) on your mobile money account at 2024-05-10 16:30:51. Message from sender: . Your new balance:2000 RWF. Financial Transaction Id: 76662021700.'),

-- 2. Payment to a personal code.
('73214484437', NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Payment'),
 1000.00, 0.00, 1000.00, '2024-05-10 16:31:39', 'COMPLETED',
 'TxId: 73214484437. Your payment of 1,000 RWF to Jane Smith 12845 has been completed at 2024-05-10 16:31:39. Your new balance: 1,000 RWF. Fee was 0 RWF.'),

-- 3. Bank deposit. The *113*R* pattern carries no transaction id at all,
--    which is exactly why financial_transaction_id is nullable.
(NULL, NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Deposit'),
 40000.00, 0.00, 40400.00, '2024-05-11 18:43:49', 'COMPLETED',
 '*113*R*A bank deposit of 40000 RWF has been added to your mobile money account at 2024-05-11 18:43:49. Your NEW BALANCE :40400 RWF. Cash Deposit::CASH::::0::250795963036.'),

-- 4. Outgoing transfer. Also has no id in the source.
(NULL, NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Transfer Sent'),
 10000.00, 100.00, 28300.00, '2024-05-11 20:34:47', 'COMPLETED',
 '*165*S*10000 RWF transferred to Samuel Carter (250791666666) from 36521838 at 2024-05-11 20:34:47 . Fee was: 100 RWF. New balance: 28300 RWF. Kugura ama inite cg interineti kanda *182*2*1#'),

-- 5. Airtime top-up.
('13913173274', NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Airtime Purchase'),
 2000.00, 0.00, 25280.00, '2024-05-12 11:41:28', 'COMPLETED',
 '*162*TxId:13913173274*S*Your payment of 2000 RWF to Airtime with token  has been completed at 2024-05-12 11:41:28. Fee was 0 RWF. Your new balance: 25280 RWF . Message: -'),

-- 6. Merchant debit initiated by a third party.
('13947831685', NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Merchant Payment'),
 25000.00, 0.00, 4060.00, '2024-05-14 21:01:00', 'COMPLETED',
 'A transaction of 25000 RWF by DIRECT PAYMENT LTD on your MOMO account was successfully completed at 2024-05-14 21:01:00. Financial Transaction Id: 13947831685.'),

-- 7. Agent cash withdrawal. 
('14098463509', NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Withdrawal'),
 20000.00, 350.00, 6400.00, '2024-05-26 02:10:27', 'COMPLETED',
 'You Account Owner (*********036) have via agent: Agent Sophia (250790777777), withdrawn 20000 RWF from your mobile money account: 36521838 at 2024-05-26 02:10:27 and you can now collect your money in cash. Your new balance: 6400 RWF. Fee paid: 350 RWF.'),

-- 8. Data bundle. No id, and the amount sits inside Kinyarwanda text.
(NULL, NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Bundle Purchase'),
 2000.00, 0.00, NULL, '2024-06-02 14:11:09', 'COMPLETED',
 'Yello!Umaze kugura 2000Rwf(1GB)/30days igura 2,000 RWF'),

-- 9. Reversal. Status REVERSED rather than deleting the original row.
(NULL, NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Reversal'),
 3000.00, 0.00, NULL, '2024-06-15 09:22:41', 'REVERSED',
 'A reversal has been initiated for your transaction to Mediatrice UWAYISENGA (250788658286) with 3000 RWF.'),

-- 10. OTP. Non-financial, amount 0, kept so the corpus is fully represented.
(NULL, NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='OTP Notification'),
 0.00, 0.00, NULL, '2024-06-18 07:55:12', 'COMPLETED',
 '<#> Dear Customer, your MTN MoMo application one-time password is :2476.MTN MoMo does not recommend that you share or expose your one-time password with anyone.');

-- ---------------------------------------------------------------------
-- Transaction_Participants — SENDER / RECEIVER / AGENT / MERCHANT
INSERT INTO Transaction_Participants (transaction_id, user_id, role) VALUES
-- 1. Incoming: Jane sends, owner receives
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='76662021700'),
 (SELECT user_id FROM Users WHERE full_name='Jane Smith'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='76662021700'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'RECEIVER'),

-- 2. Payment: owner sends, Jane receives
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='73214484437'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='73214484437'),
 (SELECT user_id FROM Users WHERE full_name='Jane Smith'), 'RECEIVER'),

-- 3. Deposit: bank channel in, owner receives
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-05-11 18:43:49'),
 (SELECT user_id FROM Users WHERE full_name='Bank Deposit Channel'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-05-11 18:43:49'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'RECEIVER'),

-- 4. Transfer out: owner sends, Samuel receives
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-05-11 20:34:47'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-05-11 20:34:47'),
 (SELECT user_id FROM Users WHERE full_name='Samuel Carter'), 'RECEIVER'),

-- 5. Airtime: owner sends, MTN is the merchant
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='13913173274'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='13913173274'),
 (SELECT user_id FROM Users WHERE full_name='MTN Airtime'), 'MERCHANT'),

-- 6. Merchant debit
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='13947831685'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='13947831685'),
 (SELECT user_id FROM Users WHERE full_name='DIRECT PAYMENT LTD'), 'MERCHANT'),

-- 7. Withdrawal: owner sends, agent handles it — two roles, one message
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='14098463509'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='14098463509'),
 (SELECT user_id FROM Users WHERE full_name='Agent Sophia'), 'AGENT'),

-- 8. Bundle
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-06-02 14:11:09'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-06-02 14:11:09'),
 (SELECT user_id FROM Users WHERE full_name='MTN Airtime'), 'MERCHANT'),

-- 9. Reversal: money comes back to the owner
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-06-15 09:22:41'),
 (SELECT user_id FROM Users WHERE full_name='Mediatrice UWAYISENGA'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-06-15 09:22:41'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'RECEIVER'),

-- 10. OTP: only the owner is involved
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-06-18 07:55:12'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'RECEIVER');


INSERT INTO System_Logs (transaction_id, process_stage, log_level, message, created_at) VALUES
(NULL, 'PARSE',      'INFO',    'Started parse of data/raw/modified_sms_v2.xml', '2025-01-16 08:00:01'),
(NULL, 'PARSE',      'INFO',    'Read 1691 <sms> elements from the backup file', '2025-01-16 08:00:04'),
(NULL, 'CLEAN',      'INFO',    'Normalised amounts, phone numbers and timestamps', '2025-01-16 08:00:07'),
(NULL, 'CLEAN',      'WARNING', 'Amount token not found on 42 messages; Kinyarwanda bundle format has no RWF delimiter', '2025-01-16 08:00:08'),
(NULL, 'CATEGORIZE', 'INFO',    'Applied 11 pattern rules across the corpus', '2025-01-16 08:00:10'),
(NULL, 'CATEGORIZE', 'WARNING', '25 messages matched no rule and were flagged for manual review', '2025-01-16 08:00:11'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='76662021700'),
 'LOAD', 'INFO', 'Parsed and inserted successfully', '2025-01-16 08:00:15'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='73214484437'),
 'LOAD', 'INFO', 'Parsed and inserted successfully', '2025-01-16 08:00:15'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='14098463509'),
 'LOAD', 'INFO', 'Agent withdrawal parsed successfully, 2 participants linked', '2025-01-16 08:00:16'),
(NULL, 'LOAD',   'WARNING', 'Skipped OTP SMS: not a financial transaction', '2025-01-16 08:00:16'),
(NULL, 'LOAD',   'ERROR',   'Rejected 1 row: category emitted by parser missing from lookup table', '2025-01-16 08:00:17'),
(NULL, 'EXPORT', 'INFO',    'Wrote dashboard aggregates to data/processed/dashboard.json', '2025-01-16 08:00:19');



-- SECTION 6: TRIGGERS
DELIMITER $$

-- RULE 1 — Clean up party data on the way in                  
DROP TRIGGER IF EXISTS trg_users_clean_bi $$
CREATE TRIGGER trg_users_clean_bi
BEFORE INSERT ON Users
FOR EACH ROW
BEGIN
    SET NEW.full_name = TRIM(REGEXP_REPLACE(NEW.full_name, '[[:space:]]+', ' '));

    IF NEW.phone_number IS NOT NULL AND NEW.phone_number NOT LIKE '*%' THEN
        SET NEW.phone_number = REGEXP_REPLACE(NEW.phone_number, '[^0-9]', '');

        IF CHAR_LENGTH(NEW.phone_number) = 10 AND LEFT(NEW.phone_number, 1) = '0' THEN
            SET NEW.phone_number = CONCAT('250', SUBSTRING(NEW.phone_number, 2));
        END IF;

        IF CHAR_LENGTH(NEW.phone_number) = 9 THEN
            SET NEW.phone_number = CONCAT('250', NEW.phone_number);
        END IF;
    END IF;
END $$


-- RULE 2 — Refuse transactions that cannot have happened     
DROP TRIGGER IF EXISTS trg_tx_validate_bi $$
CREATE TRIGGER trg_tx_validate_bi
BEFORE INSERT ON Transactions
FOR EACH ROW
BEGIN
    IF NEW.transaction_datetime > NOW() THEN
        SIGNAL SQLSTATE '45001'
            SET MESSAGE_TEXT = 'Rejected: transaction_datetime is in the future';
    END IF;

    IF NEW.fee > NEW.amount AND NEW.amount > 0 THEN
        SIGNAL SQLSTATE '45002'
            SET MESSAGE_TEXT = 'Rejected: fee cannot exceed the transaction amount';
    END IF;

    SET NEW.currency = UPPER(NEW.currency);
END $$


-- RULE 3 — Nobody sends money to themselves                  
DROP TRIGGER IF EXISTS trg_part_no_self_bi $$
CREATE TRIGGER trg_part_no_self_bi
BEFORE INSERT ON Transaction_Participants
FOR EACH ROW
BEGIN
    DECLARE v_clash INT DEFAULT 0;

    SELECT COUNT(*) INTO v_clash
    FROM Transaction_Participants
    WHERE transaction_id = NEW.transaction_id
      AND user_id        = NEW.user_id
      AND role          <> NEW.role
      AND role          IN ('SENDER','RECEIVER')
      AND NEW.role      IN ('SENDER','RECEIVER');

    IF v_clash > 0 THEN
        SIGNAL SQLSTATE '45003'
            SET MESSAGE_TEXT = 'Rejected: the same party cannot be both SENDER and RECEIVER';
    END IF;
END $$


-- RULE 4 — Completed transactions are never deleted   

DROP TRIGGER IF EXISTS trg_tx_block_delete_bd $$
CREATE TRIGGER trg_tx_block_delete_bd
BEFORE DELETE ON Transactions
FOR EACH ROW
BEGIN
    IF OLD.status = 'COMPLETED' THEN
        SIGNAL SQLSTATE '45004'
            SET MESSAGE_TEXT = 'Rejected: completed transactions are append-only; set status = REVERSED instead';
    END IF;
END $$


-- RULE 5 — Every change to money writes its own audit row     
DROP TRIGGER IF EXISTS trg_tx_audit_au $$
CREATE TRIGGER trg_tx_audit_au
AFTER UPDATE ON Transactions
FOR EACH ROW
BEGIN
    IF OLD.amount <> NEW.amount
       OR OLD.fee <> NEW.fee
       OR OLD.status <> NEW.status THEN

        INSERT INTO System_Logs (transaction_id, process_stage, log_level, message)
        VALUES (
            NEW.transaction_id,
            'AUDIT',
            'WARNING',
            CONCAT('Modified by ', CURRENT_USER(),
                   ' | amount ', OLD.amount,  ' -> ', NEW.amount,
                   ' | fee ',    OLD.fee,     ' -> ', NEW.fee,
                   ' | status ', OLD.status,  ' -> ', NEW.status)
        );
    END IF;
END $$


-- RULE 6 — The raw SMS text cannot be edited          
DROP TRIGGER IF EXISTS trg_tx_body_immutable_bu $$
CREATE TRIGGER trg_tx_body_immutable_bu
BEFORE UPDATE ON Transactions
FOR EACH ROW
BEGIN
    IF OLD.raw_sms_body <> NEW.raw_sms_body THEN
        SIGNAL SQLSTATE '45005'
            SET MESSAGE_TEXT = 'Rejected: raw_sms_body is immutable; it is the audit source for every parsed value';
    END IF;
END $$

DELIMITER ;


-- SECTION 7: VIEWS AND ACCESS CONTROL

-- RULE 7(The dashboard never sees a full phone number)     

CREATE OR REPLACE VIEW v_transactions_masked AS
SELECT
    t.transaction_id,
    t.financial_transaction_id,
    c.category_name,
    c.category_type,
    c.direction,
    t.amount,
    t.fee,
    t.currency,
    t.transaction_datetime,
    t.status,
    s.full_name                                          AS sender_name,
    CONCAT('*****', RIGHT(COALESCE(s.phone_number,'000'), 3)) AS sender_phone_masked,
    r.full_name                                          AS receiver_name,
    CONCAT('*****', RIGHT(COALESCE(r.phone_number,'000'), 3)) AS receiver_phone_masked
FROM Transactions t
    JOIN Transaction_Categories c ON c.category_id = t.category_id
    LEFT JOIN Transaction_Participants ps
           ON ps.transaction_id = t.transaction_id AND ps.role = 'SENDER'
    LEFT JOIN Users s ON s.user_id = ps.user_id
    LEFT JOIN Transaction_Participants pr
           ON pr.transaction_id = t.transaction_id AND pr.role IN ('RECEIVER','AGENT','MERCHANT')
    LEFT JOIN Users r ON r.user_id = pr.user_id;

-- RULE 8 — Aggregation happens in MySQL, not in the browser

CREATE OR REPLACE VIEW v_monthly_summary AS
SELECT
    DATE_FORMAT(t.transaction_datetime, '%Y-%m') AS month,
    c.category_name,
    c.category_type,
    c.direction,
    COUNT(*)                AS transaction_count,
    SUM(t.amount)           AS total_amount,
    ROUND(AVG(t.amount), 2) AS average_amount,
    SUM(t.fee)              AS total_fees
FROM Transactions t
    JOIN Transaction_Categories c ON c.category_id = t.category_id
WHERE t.status = 'COMPLETED'
GROUP BY month, c.category_name, c.category_type, c.direction;

-- RULE 9 — Two accounts, each with the narrowest useful grant (SECURITY)

DROP USER IF EXISTS 'momo_etl'@'localhost';
CREATE USER 'momo_etl'@'localhost' IDENTIFIED BY 'CHANGE_ME_IN_ENV';
GRANT SELECT, INSERT, UPDATE ON momo_sms_db.* TO 'momo_etl'@'localhost';

DROP USER IF EXISTS 'momo_dashboard'@'localhost';
CREATE USER 'momo_dashboard'@'localhost' IDENTIFIED BY 'CHANGE_ME_IN_ENV';
GRANT SELECT ON momo_sms_db.v_transactions_masked TO 'momo_dashboard'@'localhost';
GRANT SELECT ON momo_sms_db.v_monthly_summary     TO 'momo_dashboard'@'localhost';

FLUSH PRIVILEGES;


-- SECTION 8: CRUD OPERATIONS AND RULE TESTS
--CRUD
SELECT '===== A1. CREATE — add a merchant and a transaction =====' AS test;

INSERT INTO Users (full_name, phone_number, user_type)
VALUES ('Kigali Heights Pharmacy', '250788400123', 'MERCHANT');
SET @new_user := LAST_INSERT_ID();

INSERT INTO Transactions
    (financial_transaction_id, category_id, amount, fee, balance_after,
     transaction_datetime, status, raw_sms_body)
VALUES
    ('99001122334',
     (SELECT category_id FROM Transaction_Categories WHERE category_name='Merchant Payment'),
     7500.00, 0.00, 12500.00, '2025-01-14 10:02:33', 'COMPLETED',
     'TxId: 99001122334. Your payment of 7,500 RWF to Kigali Heights Pharmacy 41234 has been completed at 2025-01-14 10:02:33. Your new balance: 12500 RWF. Fee was 0 RWF.');
SET @new_tx := LAST_INSERT_ID();

INSERT INTO Transaction_Participants (transaction_id, user_id, role) VALUES
    (@new_tx, (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
    (@new_tx, @new_user, 'MERCHANT');

SELECT @new_tx AS created_transaction_id, @new_user AS created_user_id;
SELECT transaction_id, financial_transaction_id, amount, status
FROM Transactions WHERE transaction_id = @new_tx;


SELECT '===== A2. READ — complete transaction with all participants =====' AS test;

SELECT t.financial_transaction_id, t.amount, t.fee, t.transaction_datetime,
       c.category_name, c.direction,
       GROUP_CONCAT(CONCAT(u.full_name,' (',p.role,')') ORDER BY p.role SEPARATOR ' | ') AS parties
FROM Transactions t
JOIN Transaction_Categories   c ON c.category_id = t.category_id
JOIN Transaction_Participants p ON p.transaction_id = t.transaction_id
JOIN Users                    u ON u.user_id = p.user_id
WHERE t.transaction_id = @new_tx
GROUP BY t.transaction_id;


SELECT '===== A3. UPDATE — correct the amount, audit row appears by itself =====' AS test;

UPDATE Transactions SET amount = 8000.00 WHERE transaction_id = @new_tx;

SELECT transaction_id, amount FROM Transactions WHERE transaction_id = @new_tx;

SELECT '-- written automatically by RULE 5, nothing in the UPDATE asked for it --' AS note;
SELECT log_id, transaction_id, process_stage, log_level, message
FROM System_Logs WHERE transaction_id = @new_tx AND process_stage = 'AUDIT';


SELECT '===== A4. DELETE — remove the test rows =====' AS test;

-- RULE 4 refuses to delete a COMPLETED transaction, so reverse it first.
UPDATE Transactions SET status = 'REVERSED' WHERE transaction_id = @new_tx;
DELETE FROM Transactions WHERE transaction_id = @new_tx;   -- participants cascade
DELETE FROM Users        WHERE user_id = @new_user;

SELECT COUNT(*) AS transactions_left FROM Transactions        WHERE transaction_id = @new_tx;
SELECT COUNT(*) AS participants_left FROM Transaction_Participants WHERE transaction_id = @new_tx;


-- Rule Tests(Each statement below is invalid and must be rejected)
-- by a constraint or trigger. Run one at a time to check the rule fires.

SELECT '===== B. Each statement below must be rejected =====' AS test;

-- B1  chk_tx_amount — negative amount
-- INSERT INTO Transactions (category_id, amount, transaction_datetime, raw_sms_body)
-- VALUES (1, -500.00, '2024-06-01 10:00:00', 'test');

-- B2  uq_tx_financial_id — same transaction posted twice
-- INSERT INTO Transactions (financial_transaction_id, category_id, amount, transaction_datetime, raw_sms_body)
-- VALUES ('76662021700', 1, 2000.00, '2024-06-01 10:00:00', 'test');

-- B3  fk_tx_category — category that does not exist
-- INSERT INTO Transactions (category_id, amount, transaction_datetime, raw_sms_body)
-- VALUES (9999, 1000.00, '2024-06-01 10:00:00', 'test');

-- B4  chk_users_phone_shape — malformed number
-- INSERT INTO Users (full_name, phone_number) VALUES ('Bad Number', '12345');

-- B5  RULE 2 — dated in the future
-- INSERT INTO Transactions (category_id, amount, transaction_datetime, raw_sms_body)
-- VALUES (1, 1000.00, '2099-01-01 00:00:00', 'test');

-- B6  RULE 2 — fee larger than the amount
-- INSERT INTO Transactions (category_id, amount, fee, transaction_datetime, raw_sms_body)
-- VALUES (1, 100.00, 500.00, '2024-06-01 10:00:00', 'test');

-- B7  RULE 3 — same party as sender and receiver
-- INSERT INTO Transaction_Participants (transaction_id, user_id, role) VALUES (1, 1, 'SENDER');

-- B8  RULE 4 — deleting a completed transaction
-- DELETE FROM Transactions WHERE transaction_id = 1;

-- B9  RULE 6 — editing the raw SMS text
-- UPDATE Transactions SET raw_sms_body = 'tampered' WHERE transaction_id = 1;

-- B10 fk_part_user ON DELETE RESTRICT — removing a user with history
-- DELETE FROM Users WHERE user_id = 1;

-- B11 chk_tx_body_present — empty SMS body
-- INSERT INTO Transactions (category_id, amount, transaction_datetime, raw_sms_body)
-- VALUES (1, 100.00, '2024-06-01 10:00:00', '');

