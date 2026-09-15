# MoMo SMS ETL

This project reads MoMo mobile money SMS messages (in XML format), cleans up the data, sorts it into categories, and saves it in a database. Finally, a simple dashboard then shows charts based on that data.

## Team: Data squad
## Members
- Yera Victoire Promise
- Akuzwe Anny Benitha
- Audrey Hategekimana

## Project folders

```
momo-sms-analytics/
├── web/            # The dashboard (what you see in the browser)
├── data/           # Raw messages, cleaned data, and logs
├── etl/            # Code that reads, cleans, and saves the data
├── scripts/        # Shortcuts to run the project
├── tests/          # Code that checks everything works
├── docs/           #  Architecture diagram image
```
### ERD:https://lucid.app/lucidchart/e596d4dc-5529-40dc-b395-deef53890519/edit?invitationId=inv_7e82cc2f-9efa-4e12-8246-7cb707400d4e
### ERD Design Documentation

The Entity Relationship Diagram (ERD) was designed to provide a structured database for storing, processing, and analyzing MoMo SMS transaction data. The design separates transaction information from user, category, participant, and system logging information so that each type of data can be managed independently while still maintaining relationships between related records.

The **Users** entity stores information about customers or parties involved in mobile money transactions. The **Transactions** entity represents the main transaction records and contains information such as transaction identifiers, dates, amounts, and references to the relevant category and users. **Transaction_Categories** stores different types of transactions, allowing transactions to be classified consistently without repeatedly storing category descriptions. **System_Logs** records processing or system activities, which supports monitoring and troubleshooting of the data processing system.

Primary keys are used to uniquely identify records in each entity, while foreign keys connect related entities and help maintain referential integrity. The relationship between transactions and participants is handled through the **Transaction_Participants** junction table. This resolves the many-to-many relationship because a transaction can involve multiple participants, while a user or party can participate in multiple transactions.

The design also supports data accuracy through constraints such as primary keys, foreign keys, required fields, and appropriate data types. Separating the information into related tables reduces data duplication and makes the database easier to query and maintain. The structure can also be extended in the future as additional transaction categories, users, or transaction types are introduced.







Tasks tracking: https://trello.com/b/6a9dc1374f7c721003ac5fca/ATTI026324660959581bdfa932faec7f602003B77A8B/momo-transaction-processing
