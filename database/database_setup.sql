-- MoMo SMS Data Processing System — database_setup.sql
-- Full setup script. Run top to bottom:
--   mysql -u root -p < database/database_setup.sql
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
