---
name: grocy
description: "Use this skill when the user asks about groceries, shopping lists, stock/inventory, chores, meal planning, recipes, food expiry, or household management. Triggers include: 'what do we need', 'add to shopping list', 'what's expiring', 'grocery list', 'stock', 'inventory', 'chores', 'meal plan', 'recipe', 'what's in the fridge/pantry', 'household tasks', 'batteries', or any mention of Grocy."
---

# Grocy — Household Management API

## Overview

Grocy is a self-hosted household management system running on this server. Use the `web_fetch` tool to interact with its REST API.

**Base URL:** `http://127.0.0.1:2383`
**Authentication:** Add header `GROCY-API-KEY: <key>` to every request. The API key is available in the environment variable `GROCY_API_KEY`.

## Quick Reference

| Task | Method | Endpoint |
|------|--------|----------|
| Current stock overview | GET | `/api/stock` |
| Expiring/expired items | GET | `/api/stock/volatile` |
| Shopping list | GET | `/api/objects/shopping_list` |
| All products | GET | `/api/objects/products` |
| All chores status | GET | `/api/chores` |
| All tasks | GET | `/api/tasks` |
| All recipes | GET | `/api/objects/recipes` |
| All locations | GET | `/api/objects/locations` |

## Stock Management

### View Stock

```
GET /api/stock
```
Returns all products currently in stock with amounts, best-before dates, and locations.

```
GET /api/stock/volatile
```
Returns products that are expiring soon, already expired, and below minimum stock.

```
GET /api/stock/products/{productId}
```
Returns detailed stock info for a specific product.

### Add Stock

```
POST /api/stock/products/{productId}/add
Content-Type: application/json

{
  "amount": 1,
  "best_before_date": "2026-04-15",
  "price": 2.50,
  "location_id": 1
}
```

### Consume Stock

```
POST /api/stock/products/{productId}/consume
Content-Type: application/json

{
  "amount": 1,
  "spoiled": false
}
```

### Transfer Between Locations

```
POST /api/stock/products/{productId}/transfer
Content-Type: application/json

{
  "amount": 1,
  "location_id_from": 1,
  "location_id_to": 2
}
```

### Inventory (Set Exact Amount)

```
POST /api/stock/products/{productId}/inventory
Content-Type: application/json

{
  "new_amount": 5
}
```

### Lookup by Barcode

```
GET /api/stock/products/by-barcode/{barcode}
```

## Shopping List

### View Shopping List

```
GET /api/objects/shopping_list
```

### Add Product to Shopping List

```
POST /api/stock/shoppinglist/add-product
Content-Type: application/json

{
  "product_id": 1,
  "list_id": 1,
  "product_amount": 2
}
```

### Remove Product from Shopping List

```
POST /api/stock/shoppinglist/remove-product
Content-Type: application/json

{
  "product_id": 1,
  "list_id": 1,
  "product_amount": 1
}
```

### Auto-add Missing Products

```
POST /api/stock/shoppinglist/add-missing-products
Content-Type: application/json

{
  "list_id": 1
}
```

### Clear Shopping List

```
POST /api/stock/shoppinglist/clear
Content-Type: application/json

{
  "list_id": 1
}
```

## Products

### List All Products

```
GET /api/objects/products
```

### Create Product

```
POST /api/objects/products
Content-Type: application/json

{
  "name": "Milk",
  "location_id": 1,
  "qu_id_purchase": 1,
  "qu_id_stock": 1,
  "min_stock_amount": 1
}
```

### Update Product

```
PUT /api/objects/products/{productId}
Content-Type: application/json

{
  "name": "Semi-Skimmed Milk"
}
```

### Delete Product

```
DELETE /api/objects/products/{productId}
```

## Chores

### View All Chores

```
GET /api/chores
```
Returns all chores with next execution dates and assignment info.

### Execute Chore

```
POST /api/chores/{choreId}/execute
Content-Type: application/json

{
  "tracked_time": "2026-03-17 14:00:00"
}
```

### Undo Chore Execution

```
POST /api/chores/executions/{executionId}/undo
```

## Tasks

### View All Tasks

```
GET /api/tasks
```

### Create Task

```
POST /api/objects/tasks
Content-Type: application/json

{
  "name": "Buy birthday present",
  "due_date": "2026-03-25",
  "category_id": 1
}
```

### Complete Task

```
POST /api/tasks/{taskId}/complete
```

## Recipes

### List Recipes

```
GET /api/objects/recipes
```

### Check Recipe Fulfillment

```
GET /api/recipes/{recipeId}/fulfillment
```
Shows which ingredients are available and which are missing.

### Check All Recipes Fulfillment

```
GET /api/recipes/fulfillment
```

### Add Missing Ingredients to Shopping List

```
POST /api/recipes/{recipeId}/add-not-fulfilled-products-to-shoppinglist
```

### Consume Recipe Ingredients

```
POST /api/recipes/{recipeId}/consume
```

## Generic Entity API

Any Grocy entity can be queried with:

```
GET /api/objects/{entity}
GET /api/objects/{entity}/{objectId}
POST /api/objects/{entity}
PUT /api/objects/{entity}/{objectId}
DELETE /api/objects/{entity}/{objectId}
```

Common entities: `products`, `locations`, `shopping_list`, `recipes`, `chores`, `tasks`, `batteries`, `quantity_units`, `product_groups`, `shopping_locations`, `task_categories`, `product_barcodes`, `meal_plan`.

### Filtering

Add query parameters to filter:
```
GET /api/objects/products?query[]=name=Milk
GET /api/objects/products?query[]=min_stock_amount>0
```

## Batteries

```
GET /api/batteries
GET /api/batteries/{batteryId}
POST /api/batteries/{batteryId}/charge
```

## Meal Plan

```
GET /api/objects/meal_plan
POST /api/objects/meal_plan
```

## Tips

- Product IDs are integers. Use `GET /api/objects/products` to find them.
- Location IDs can be found with `GET /api/objects/locations`.
- Quantity unit IDs: `GET /api/objects/quantity_units`.
- The shopping list ID is usually `1` (default list).
- Dates use `YYYY-MM-DD` format. Datetimes use `YYYY-MM-DD HH:MM:SS`.
- The API returns JSON. POST/PUT requests need `Content-Type: application/json`.
- Currency is GBP (configured in Grocy settings).
