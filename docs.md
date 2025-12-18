# MedEasy POS API Documentation

Base URL: `http://localhost:8080` (default)

## Authentication

### Register

**POST** `/auth/register`

Creates a new user account. If the role is `owner`, a pharmacy is also created.

**Request Body:**

```json
{
  "username": "john_doe",
  "email": "john@example.com",
  "password": "securepassword",
  "role": "owner", // or "employee"
  "pharmacy_name": "John's Pharmacy", // Required if role is "owner"
  "pharmacy_address": "123 Main St",
  "pharmacy_location": "New York"
}
```

**Response:**

```json
{
  "token": "jwt_token_here",
  "user": {
    "id": 1,
    "username": "john_doe",
    "email": "john@example.com",
    "role": "owner"
  },
  "pharmacy": {
    "id": 1,
    "name": "John's Pharmacy",
    "address": "123 Main St",
    "location": "New York",
    "owner_id": 1,
    "created_at": "2023-10-27T10:00:00Z"
  }
}
```

### Login

**POST** `/auth/login`

Authenticates a user and returns a JWT token.

**Request Body:**

```json
{
  "email": "john@example.com",
  "password": "securepassword"
}
```

**Response:**

```json
{
  "token": "jwt_token_here",
  "user": {
    "id": 1,
    "username": "john_doe",
    "email": "john@example.com",
    "role": "owner"
  }
}
```

### Reset Password

**POST** `/auth/reset-password`
_Requires Authentication_

Resets the authenticated user's password.

**Request Body:**

```json
{
  "new_password": "newsecurepassword"
}
```

**Response:**

```json
{
  "status": "password updated"
}
```

## Pharmacies

### Create Pharmacy

**POST** `/pharmacies`
_Requires Role: owner_

Creates a new pharmacy.

**Request Body:**

```json
{
  "name": "New Pharmacy",
  "address": "456 Elm St",
  "location": "Los Angeles"
}
```

**Response:**

```json
{
  "id": 2,
  "name": "New Pharmacy"
}
```

### List Pharmacies

**GET** `/pharmacies`
_Requires Authentication_

Lists all pharmacies.

**Response:**

```json
[
  {
    "id": 1,
    "name": "John's Pharmacy",
    "address": "123 Main St",
    "location": "New York",
    "owner_id": 1,
    "created_at": "2023-10-27T10:00:00Z"
  }
]
```

### Update Pharmacy

**PUT** `/pharmacies/{id}`
_Requires Role: owner_

Updates an existing pharmacy.

**Request Body:**

```json
{
  "name": "Updated Pharmacy Name",
  "address": "Updated Address",
  "location": "Updated Location"
}
```

**Response:**

```json
{
  "status": "updated"
}
```

## Medicines

### Search Medicines

**GET** `/medicines?query={search_term}`
_Requires Authentication_

Searches for medicines by brand name or generic name.

**Response:**

```json
[
  {
    "id": 1,
    "brand_id": 101,
    "brand_name": "Napa",
    "type": "Tablet",
    "generic_name": "Paracetamol",
    "manufacturer": "Beximco"
  }
]
```

## Inventory

### Add Inventory

**POST** `/inventory`
_Requires Role: owner, employee_

Adds a new item to the inventory.

**Request Body:**

```json
{
  "pharmacy_id": 1,
  "medicine_id": 1,
  "quantity": 100,
  "cost_price": 5.0,
  "sale_price": 10.0,
  "expiry_date": "2024-12-31"
}
```

**Response:**

```json
{
  "status": "inventory added"
}
```

### Update Inventory

**PUT** `/inventory/{id}`
_Requires Role: owner, employee_

Updates an existing inventory item.

**Request Body:**

```json
{
  "pharmacy_id": 1,
  "medicine_id": 1,
  "quantity": 150,
  "cost_price": 5.5,
  "sale_price": 11.0,
  "expiry_date": "2025-01-31"
}
```

**Response:**

```json
{
  "status": "updated"
}
```

### Update Stock

**POST** `/inventory/{id}/stock`
_Requires Role: owner, employee_

Updates the stock quantity of an inventory item.

**Request Body:**

```json
{
  "quantity": 200
}
```

**Response:**

```json
{
  "status": "stock updated"
}
```

### Expiry Alerts

**GET** `/inventory/expiry-alert?days={days}`
_Requires Authentication_

Lists inventory items expiring within the specified number of days (default 30).

**Response:**

```json
[
  {
    "id": 1,
    "pharmacy_id": 1,
    "medicine_id": 1,
    "quantity": 100,
    "expiry_date": "2023-11-15",
    ...
  }
]
```

## Sales

### Create Sale

**POST** `/sales`
_Requires Role: owner, employee_

Creates a new sale transaction.

**Request Body:**

```json
{
  "pharmacy_id": 1,
  "items": [
    {
      "medicine_id": 1,
      "quantity": 2
    }
  ],
  "discount": 5.0,
  "paid_amount": 15.0
}
```

**Response:**

```json
{
  "sale_id": 1,
  "total": 20.0,
  "discount": 5.0,
  "paid_amount": 15.0,
  "due_amount": 0.0,
  "final_amount": 15.0
}
```

## Reports

### Daily Sales

**GET** `/reports/sales/daily?pharmacy_id={id}`
_Requires Authentication_

Get total revenue and sales count for the current day.

**Response:**

```json
{
  "revenue": 1500.0,
  "sales_count": 10
}
```

### Monthly Sales

**GET** `/reports/sales/monthly?pharmacy_id={id}`
_Requires Authentication_

Get total revenue and sales count for the current month.

**Response:**

```json
{
  "revenue": 45000.0,
  "sales_count": 300
}
```

## Health Check

### Health

**GET** `/health`

Checks if the server is running.

**Response:**

```json
{
  "status": "ok"
}
```
