# Team AI Usage Log

## 1. AI Tools Used

The team used AI as a supporting tool for:

* Explaining MySQL error messages encountered during implementation.
* Clarifying SQL syntax when an issue was encountered after the team had written the relevant code.
* Assisting with wording for documentation and commit messages.
* Consulting general MySQL best-practice references.

The team developed and reviewed the database implementation independently. AI responses were not treated as authoritative, and the implemented database code was tested in MySQL 8.0 before being committed.

---

## 2. Code and Syntax Verification

### `--CRUD` syntax error

An SQL script initially produced a MySQL syntax error near `--CRUD`. AI was used to clarify the syntax issue. The team corrected the comment formatting by adding the required space after `--` and then reran the script successfully.

**Lesson:** MySQL expects `--` comments to be followed by whitespace.

### `DELIMITER` and triggers

The team had already written the trigger definitions. AI was used to clarify the syntax of `DELIMITER` when an issue was encountered.

The triggers were then created and tested individually. The team verified the number of created triggers through `information_schema`, checking that the count increased as each trigger was successfully added: 1, 2, 4, and finally 6.

### Testing validation rules

The team tested the implemented validation rules using deliberately invalid statements. AI was used to clarify the meaning of the resulting MySQL error messages.

Examples included:

* Negative transaction amount → `ERROR 4025` from `chk_tx_amount`.
* Duplicate transaction ID → `ERROR 1062`.
* Future transaction date → custom `ERROR 1644`.
* Attempt to edit SMS text → custom `ERROR 1644`.

The team independently ran these tests and recorded the resulting database behavior.

### Evidence script

During evidence collection, the team identified that `capture_evidence.sh` was running `database_setup.sql` twice. Because the setup script begins by dropping the database, the second execution removed the results of the first execution.

The team removed the duplicate execution and reran the evidence process successfully.

---

## 3. Documentation and Data Verification

### Message category count

A discrepancy was identified between the design documentation and the database count of message categories. The team re-counted the XML message patterns and found 11 actual message patterns mapping to 11 categories. The additional “Uncategorized” entry was a leftover catch-all and was not counted as an actual category.

### System_Logs figures

The team also identified figures in the documentation that did not match the current parser results. The documentation referenced 42 records and 25 unparsed/no-rule records, while the current parser produced 9 and 4 respectively.

The discrepancy was flagged for confirmation rather than being presented as a confirmed figure.

---

## 4. MySQL Best-Practice References

The team consulted general MySQL documentation and best-practice material to support implementation decisions.

### DECIMAL vs. FLOAT

MySQL documentation was consulted for guidance on numeric data types, particularly the use of `DECIMAL` when exact-value calculations are required.

The team applied this guidance when reviewing the implemented database.

 **Reference:** [MySQL 8.0 Reference Manual, B.3.4.8 "Problems with Floating-Point Values"](https://dev.mysql.com/doc/refman/8.0/en/problems-with-float.html)

### SIGNAL

MySQL documentation was consulted to understand the `SIGNAL` statement and how custom errors can be raised from database triggers.

The implemented triggers use custom SQLSTATE values in the `45000` class to distinguish the validation errors.

**Reference:** [MySQL 8.0 Reference Manual, 15.6.7.5 "SIGNAL Statement"](https://dev.mysql.com/doc/refman/8.0/en/signal.html)

### Views

MySQL documentation was consulted for general guidance on `CREATE VIEW` and restricting access through views.

The team applied this when reviewing the implemented views, including the masked transaction view and dashboard access.

**Reference:** [MySQL 8.0 Reference Manual, 15.1.23 "CREATE VIEW Statement"](https://dev.mysql.com/doc/refman/8.0/en/create-view.html)

### Composite indexes

MySQL indexing guidance was consulted to understand composite-index behavior and the leftmost-prefix principle.

This was used when reviewing whether the additional `idx_part_tx` index was necessary, since the existing unique composite index already begins with `transaction_id`.

**Reference:** [MySQL 8.0 Reference Manual, 10.3.6 "Multiple-Column Indexes"](https://dev.mysql.com/doc/refman/8.0/en/multiple-column-indexes.html)

---

## 5. Verification of AI-Supplied Information

AI responses were treated as supporting information rather than authoritative project decisions.

Where AI provided information about syntax, errors, documentation, or MySQL behavior, the team checked the information against the actual project files, MySQL results, or official MySQL documentation before relying on it.

For example, an AI-supplied reference to specific file/line numbers did not match the actual project files. The team checked the files directly and corrected the references.

All implemented database code was run and tested in MySQL 8.0 before being committed.


## 6. Editing the ai_usage_log.md structure

AI was used to come up with the most presentable format for the information in ai_usage_log.md

---

