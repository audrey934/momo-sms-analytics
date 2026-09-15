-- MoMo SMS Data Processing System - database_setup.sql
--  Data squad: Yera Victoire Promise, Akuzwe Anny Benitha, Audrey Hategekimana

DROP DATABASE IF EXISTS momo_sms_db;
CREATE DATABASE momo_sms_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE momo_sms_db;

-- Users: senders, receivers, agents, merchants. SELF = account owner.
CREATE TABLE Users (
    user_id       INT AUTO_INCREMENT PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    phone_number  VARCHAR(20) NULL COMMENT 'MSISDN, or masked form e.g. *********013',
    user_type     ENUM('SELF','CUSTOMER','AGENT','MERCHANT','BANK') NOT NULL DEFAULT 'CUSTOMER',
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_users_name_phone   UNIQUE (full_name, phone_number),
    CONSTRAINT chk_users_name_len    CHECK (CHAR_LENGTH(TRIM(full_name)) >= 2),
    CONSTRAINT chk_users_phone_shape CHECK (
        phone_number IS NULL
        OR phone_number REGEXP '^250[0-9]{9}$'
        OR phone_number REGEXP '^\\*+[0-9]{3}$'
    )
) ENGINE=InnoDB COMMENT='Parties in mobile money transactions';

-- Transaction_Categories: derived from SMS pattern
CREATE TABLE Transaction_Categories (
    category_id    INT AUTO_INCREMENT PRIMARY KEY,
    category_name  VARCHAR(50) NOT NULL UNIQUE,
    category_type  ENUM('TRANSFER','PAYMENT','DEPOSIT','WITHDRAWAL','AIRTIME','REVERSAL','SYSTEM') NOT NULL,
    direction      ENUM('CREDIT','DEBIT','NEUTRAL') NOT NULL COMMENT 'Balance impact; NEUTRAL = non-financial (OTP)',
    description    VARCHAR(255) NULL,

    CONSTRAINT chk_category_name_len CHECK (CHAR_LENGTH(TRIM(category_name)) >= 3)
) ENGINE=InnoDB COMMENT='Lookup table for transaction classification';

-- Transactions: one row per parsed SMS
CREATE TABLE Transactions (
    transaction_id           INT AUTO_INCREMENT PRIMARY KEY,
    financial_transaction_id VARCHAR(30) NULL COMMENT 'MTN TxId; not all messages carry one',
    external_transaction_id  VARCHAR(30) NULL COMMENT 'Third-party ref on some merchant messages',
    category_id              INT NOT NULL,
    amount                   DECIMAL(12,2) NOT NULL,
    fee                      DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    currency                 CHAR(3) NOT NULL DEFAULT 'RWF',
    balance_after            DECIMAL(14,2) NULL,
    transaction_datetime     DATETIME NOT NULL,
    status                   ENUM('COMPLETED','PENDING','FAILED','REVERSED') NOT NULL DEFAULT 'COMPLETED',
    raw_sms_body             TEXT NOT NULL COMMENT 'Original SMS text, kept for audit',
    created_at               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

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

CREATE INDEX idx_tx_datetime      ON Transactions(transaction_datetime);
CREATE INDEX idx_tx_category_date ON Transactions(category_id, transaction_datetime);
CREATE INDEX idx_tx_status        ON Transactions(status);
CREATE INDEX idx_tx_amount        ON Transactions(amount);

-- Transaction_Participants: junction table, resolves M:N (sender/receiver/agent per transaction)
CREATE TABLE Transaction_Participants (
    participant_id  INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id  INT NOT NULL,
    user_id         INT NOT NULL,
    role            ENUM('SENDER','RECEIVER','AGENT','MERCHANT') NOT NULL,

    CONSTRAINT fk_part_transaction FOREIGN KEY (transaction_id)
        REFERENCES Transactions(transaction_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_part_user FOREIGN KEY (user_id)
        REFERENCES Users(user_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_tx_role UNIQUE (transaction_id, user_id, role)
) ENGINE=InnoDB COMMENT='Junction table: Transactions <-> Users';

CREATE INDEX idx_part_tx   ON Transaction_Participants(transaction_id);
CREATE INDEX idx_part_user ON Transaction_Participants(user_id, role);

-- System_Logs: ETL pipeline log entries
CREATE TABLE System_Logs (
    log_id         INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id INT NULL COMMENT 'NULL for pipeline-wide events',
    process_stage  ENUM('PARSE','CLEAN','CATEGORIZE','LOAD','EXPORT','API','AUDIT') NOT NULL DEFAULT 'PARSE',
    log_level      ENUM('INFO','WARNING','ERROR') NOT NULL DEFAULT 'INFO',
    message        VARCHAR(255) NOT NULL,
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_log_transaction FOREIGN KEY (transaction_id)
        REFERENCES Transactions(transaction_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT chk_log_message_len CHECK (CHAR_LENGTH(TRIM(message)) > 0)
) ENGINE=InnoDB COMMENT='ETL pipeline log entries';

CREATE INDEX idx_log_level_time ON System_Logs(log_level, created_at);
CREATE INDEX idx_log_stage      ON System_Logs(process_stage);


-- Seed data

INSERT INTO Transaction_Categories (category_name, category_type, direction, description) VALUES
('Deposit',                 'DEPOSIT',    'CREDIT',  'Cash or bank deposit (*113*R* pattern)'),
('Transfer Received',       'TRANSFER',   'CREDIT',  'P2P money received'),
('Reversal',                'REVERSAL',   'CREDIT',  'Funds returned after a reversed transaction'),
('Transfer Sent',           'TRANSFER',   'DEBIT',   'P2P money sent (*165*S* pattern)'),
('Payment',                 'PAYMENT',    'DEBIT',   'Payment for goods/services to a named payee'),
('Withdrawal',              'WITHDRAWAL', 'DEBIT',   'Cash withdrawal via an agent'),
('Airtime Purchase',        'AIRTIME',    'DEBIT',   'Airtime top-up (*162* pattern)'),
('Bundle Purchase',         'AIRTIME',    'DEBIT',   'Data or voice bundle purchase'),
('Bank Transfer Out',       'TRANSFER',   'DEBIT',   'Wallet-to-bank transfer'),
('Merchant Payment',        'PAYMENT',    'DEBIT',   'Payment to a registered business (*164* pattern)'),
('OTP Notification',        'SYSTEM',     'NEUTRAL', 'One-time password message; non-financial');

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

INSERT INTO Transactions
    (financial_transaction_id, external_transaction_id, category_id, amount, fee,
     balance_after, transaction_datetime, status, raw_sms_body)
VALUES
('76662021700', NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Transfer Received'),
 2000.00, 0.00, 2000.00, '2024-05-10 16:30:51', 'COMPLETED',
 'You have received 2000 RWF from Jane Smith (*********013) on your mobile money account at 2024-05-10 16:30:51. Message from sender: . Your new balance:2000 RWF. Financial Transaction Id: 76662021700.'),

('73214484437', NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Payment'),
 1000.00, 0.00, 1000.00, '2024-05-10 16:31:39', 'COMPLETED',
 'TxId: 73214484437. Your payment of 1,000 RWF to Jane Smith 12845 has been completed at 2024-05-10 16:31:39. Your new balance: 1,000 RWF. Fee was 0 RWF.'),

(NULL, NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Deposit'),
 40000.00, 0.00, 40400.00, '2024-05-11 18:43:49', 'COMPLETED',
 '*113*R*A bank deposit of 40000 RWF has been added to your mobile money account at 2024-05-11 18:43:49. Your NEW BALANCE :40400 RWF. Cash Deposit::CASH::::0::250795963036.'),

(NULL, NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Transfer Sent'),
 10000.00, 100.00, 28300.00, '2024-05-11 20:34:47', 'COMPLETED',
 '*165*S*10000 RWF transferred to Samuel Carter (250791666666) from 36521838 at 2024-05-11 20:34:47 . Fee was: 100 RWF. New balance: 28300 RWF. Kugura ama inite cg interineti kanda *182*2*1#'),

('13913173274', NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Airtime Purchase'),
 2000.00, 0.00, 25280.00, '2024-05-12 11:41:28', 'COMPLETED',
 '*162*TxId:13913173274*S*Your payment of 2000 RWF to Airtime with token  has been completed at 2024-05-12 11:41:28. Fee was 0 RWF. Your new balance: 25280 RWF . Message: -'),

('13947831685', NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Merchant Payment'),
 25000.00, 0.00, 4060.00, '2024-05-14 21:01:00', 'COMPLETED',
 'A transaction of 25000 RWF by DIRECT PAYMENT LTD on your MOMO account was successfully completed at 2024-05-14 21:01:00. Financial Transaction Id: 13947831685.'),

('14098463509', NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Withdrawal'),
 20000.00, 350.00, 6400.00, '2024-05-26 02:10:27', 'COMPLETED',
 'You Account Owner (*********036) have via agent: Agent Sophia (250790777777), withdrawn 20000 RWF from your mobile money account: 36521838 at 2024-05-26 02:10:27 and you can now collect your money in cash. Your new balance: 6400 RWF. Fee paid: 350 RWF.'),

(NULL, NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Bundle Purchase'),
 2000.00, 0.00, NULL, '2024-06-02 14:11:09', 'COMPLETED',
 'Yello!Umaze kugura 2000Rwf(1GB)/30days igura 2,000 RWF'),

(NULL, NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='Reversal'),
 3000.00, 0.00, NULL, '2024-06-15 09:22:41', 'REVERSED',
 'A reversal has been initiated for your transaction to Mediatrice UWAYISENGA (250788658286) with 3000 RWF.'),

(NULL, NULL,
 (SELECT category_id FROM Transaction_Categories WHERE category_name='OTP Notification'),
 0.00, 0.00, NULL, '2024-06-18 07:55:12', 'COMPLETED',
 '<#> Dear Customer, your MTN MoMo application one-time password is :2476.MTN MoMo does not recommend that you share or expose your one-time password with anyone.');

INSERT INTO Transaction_Participants (transaction_id, user_id, role) VALUES
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='76662021700'),
 (SELECT user_id FROM Users WHERE full_name='Jane Smith'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='76662021700'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'RECEIVER'),

((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='73214484437'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='73214484437'),
 (SELECT user_id FROM Users WHERE full_name='Jane Smith'), 'RECEIVER'),

((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-05-11 18:43:49'),
 (SELECT user_id FROM Users WHERE full_name='Bank Deposit Channel'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-05-11 18:43:49'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'RECEIVER'),

((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-05-11 20:34:47'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-05-11 20:34:47'),
 (SELECT user_id FROM Users WHERE full_name='Samuel Carter'), 'RECEIVER'),

((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='13913173274'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='13913173274'),
 (SELECT user_id FROM Users WHERE full_name='MTN Airtime'), 'MERCHANT'),

((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='13947831685'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='13947831685'),
 (SELECT user_id FROM Users WHERE full_name='DIRECT PAYMENT LTD'), 'MERCHANT'),

((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='14098463509'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='14098463509'),
 (SELECT user_id FROM Users WHERE full_name='Agent Sophia'), 'AGENT'),

((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-06-02 14:11:09'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-06-02 14:11:09'),
 (SELECT user_id FROM Users WHERE full_name='MTN Airtime'), 'MERCHANT'),

((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-06-15 09:22:41'),
 (SELECT user_id FROM Users WHERE full_name='Mediatrice UWAYISENGA'), 'SENDER'),
((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-06-15 09:22:41'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'RECEIVER'),

((SELECT transaction_id FROM Transactions WHERE transaction_datetime='2024-06-18 07:55:12'),
 (SELECT user_id FROM Users WHERE user_type='SELF'), 'RECEIVER');

INSERT INTO System_Logs (transaction_id, process_stage, log_level, message, created_at) VALUES
(NULL, 'PARSE',      'INFO',    'Started parse of data/raw/modified_sms_v2.xml', '2025-01-16 08:00:01'),
(NULL, 'PARSE',      'INFO',    'Read 1691 sms elements from the backup file', '2025-01-16 08:00:04'),
(NULL, 'CLEAN',      'INFO',    'Normalised amounts, phone numbers and timestamps', '2025-01-16 08:00:07'),
(NULL, 'CLEAN',      'WARNING', 'Amount token not found on 9 messages', '2025-01-16 08:00:08'),
(NULL, 'CATEGORIZE', 'INFO',    'Applied 11 pattern rules across the corpus', '2025-01-16 08:00:10'),
(NULL, 'CATEGORIZE', 'WARNING', '4 messages matched no rule, flagged for review', '2025-01-16 08:00:11'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='76662021700'),
 'LOAD', 'INFO', 'Parsed and inserted successfully', '2025-01-16 08:00:15'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='73214484437'),
 'LOAD', 'INFO', 'Parsed and inserted successfully', '2025-01-16 08:00:15'),
((SELECT transaction_id FROM Transactions WHERE financial_transaction_id='14098463509'),
 'LOAD', 'INFO', 'Agent withdrawal parsed, 2 participants linked', '2025-01-16 08:00:16'),
(NULL, 'LOAD',   'WARNING', 'Skipped OTP SMS: not a financial transaction', '2025-01-16 08:00:16'),
(NULL, 'LOAD',   'ERROR',   'Rejected 1 row: category missing from lookup table', '2025-01-16 08:00:17'),
(NULL, 'EXPORT', 'INFO',    'Wrote dashboard aggregates to data/processed/dashboard.json', '2025-01-16 08:00:19');


-- Security & accuracy rules
DELIMITER $$

-- RULE 1: normalize name/phone on insert
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

-- RULE 2: reject impossible transactions (future date, fee > amount)
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

-- RULE 3: same user can't be sender and receiver on one transaction
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

-- RULE 4: completed transactions are append-only, no deletes
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

-- RULE 5: auto-log any change to amount/fee/status
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

-- RULE 6: raw_sms_body is immutable once inserted
DROP TRIGGER IF EXISTS trg_tx_body_immutable_bu $$
CREATE TRIGGER trg_tx_body_immutable_bu
BEFORE UPDATE ON Transactions
FOR EACH ROW
BEGIN
    IF OLD.raw_sms_body <> NEW.raw_sms_body THEN
        SIGNAL SQLSTATE '45005'
            SET MESSAGE_TEXT = 'Rejected: raw_sms_body is immutable';
    END IF;
END $$

DELIMITER ;
