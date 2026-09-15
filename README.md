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
### ERD Design Documentation

The Entity Relationship Diagram (ERD) was designed to represent the main entities and relationships required for an Airbnb-style booking system. The database is divided into separate tables to reduce data duplication and make the system easier to maintain.

The *User*entity stores information about users of the system, while the **Property** entity stores information about properties available for booking. A user can own or manage multiple properties, so there is a one-to-many relationship between users and properties. The **Booking** entity connects users with properties and records important information such as check-in date, check-out date, total price, and booking status. This allows one user to make multiple bookings and one property to receive multiple bookings over time.

The *Review* entity is connected to both users and properties. This allows users to leave reviews for properties they have booked while keeping review information separate from the main user and property data. The **Payment** entity is linked to bookings so that payment information can be stored separately from booking details.

The *Amenity* entity stores reusable amenities such as Wi-Fi, parking, or a swimming pool. Because a property can have many amenities and an amenity can belong to many properties, the **Property_Amenity** junction table is used to implement this many-to-many relationship.

Primary keys uniquely identify each record, while foreign keys establish relationships between entities. This structure improves data integrity, reduces redundancy, and makes the database scalable and easier to query.

## How the system works (system architecture design)

https://lucid.app/lucidchart/e596d4dc-5529-40dc-b395-deef53890519/edit?invitationId=inv_7e82cc2f-9efa-4e12-8246-7cb707400d4e


Tasks tracking: https://trello.com/b/6a9dc1374f7c721003ac5fca/ATTI026324660959581bdfa932faec7f602003B77A8B/momo-transaction-processing
