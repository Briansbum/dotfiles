---
name: grocy
description: "Use this skill when the user asks about groceries, shopping lists, stock/inventory, chores, meal planning, recipes, food expiry, or household management. Triggers include: 'what do we need', 'add to shopping list', 'what's expiring', 'grocery list', 'stock', 'inventory', 'chores', 'meal plan', 'recipe', 'what's in the fridge/pantry', 'household tasks', 'batteries', or any mention of Grocy."
---

# Grocy — Household Management API (via MCP)

Grocy is available through three MCP tools. Use them in this order:

1. **`grocy_list_tools()`** — Lists all available Grocy API operations with short descriptions. Call this first to find the right operation.
2. **`grocy_describe_tool(name)`** — Returns full details for an operation: HTTP method, URL path, and all parameters with types. Call this to learn what params to pass.
3. **`grocy_use_tool(name, params={})`** — Executes the operation. Pass path params, body fields, and query params in the `params` object.

## Quick Start

To check what's in stock: `grocy_use_tool(name="get_stock")`
To see expiring items: `grocy_use_tool(name="get_stock_volatile")`
To view shopping list: `grocy_use_tool(name="list_objects", params={"entity": "shopping_list"})`

## Tips

- Product/location/chore IDs are integers. Use `list_objects` with the right entity to find them.
- The default shopping list ID is `1`.
- Dates use `YYYY-MM-DD` format. Datetimes use `YYYY-MM-DD HH:MM:SS`.
- For generic CRUD (`create_object`, `update_object`), pass entity fields directly in `params`.
- Currency is GBP (configured in Grocy settings).
