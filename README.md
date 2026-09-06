# MoMo SMS ETL

This project reads MoMo mobile money SMS messages (in XML format), cleans up the data, sorts it into categories, and saves it in a database. Finally, a simple dashboard then shows charts based on that data.

## Team members:
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
└── docs/           # The architecture diagram
```
## How the system works (architecture)

![Architecture diagram](docs/architecture.png)

## Team task board
Tasks tracking: https://trello.com/invite/b/6a9dc1374f7c721003ac5fca/ATTI026324660959581bdfa932faec7f602003B77A8B/momo-transaction-processing
