package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

// ---------------------------------------------------------------------------
// Grocy API tool definitions
// ---------------------------------------------------------------------------

type Param struct {
	Name     string `json:"name"`
	Type     string `json:"type"`
	In       string `json:"in"`       // "path", "body", or "query"
	Required bool   `json:"required"`
	Desc     string `json:"description"`
}

type Tool struct {
	Name   string  `json:"name"`
	Desc   string  `json:"description"`
	Method string  `json:"method"`
	Path   string  `json:"path"` // may contain {param} placeholders
	Params []Param `json:"params,omitempty"`
}

var tools = []Tool{
	// ---- Stock ----
	{Name: "get_stock", Desc: "Get all products currently in stock with amounts, best-before dates, and locations", Method: "GET", Path: "/api/stock"},
	{Name: "get_stock_volatile", Desc: "Get products expiring soon, already expired, and below minimum stock", Method: "GET", Path: "/api/stock/volatile"},
	{Name: "get_product_stock", Desc: "Get detailed stock info for a specific product", Method: "GET", Path: "/api/stock/products/{product_id}",
		Params: []Param{{Name: "product_id", Type: "integer", In: "path", Required: true, Desc: "Product ID"}}},
	{Name: "get_product_stock_entries", Desc: "Get individual stock entries for a product", Method: "GET", Path: "/api/stock/products/{product_id}/entries",
		Params: []Param{{Name: "product_id", Type: "integer", In: "path", Required: true, Desc: "Product ID"}}},
	{Name: "get_product_locations", Desc: "Get locations for a product's stock", Method: "GET", Path: "/api/stock/products/{product_id}/locations",
		Params: []Param{{Name: "product_id", Type: "integer", In: "path", Required: true, Desc: "Product ID"}}},
	{Name: "get_product_price_history", Desc: "Get price history for a product", Method: "GET", Path: "/api/stock/products/{product_id}/price-history",
		Params: []Param{{Name: "product_id", Type: "integer", In: "path", Required: true, Desc: "Product ID"}}},
	{Name: "add_product_stock", Desc: "Add stock for a product", Method: "POST", Path: "/api/stock/products/{product_id}/add",
		Params: []Param{
			{Name: "product_id", Type: "integer", In: "path", Required: true, Desc: "Product ID"},
			{Name: "amount", Type: "number", In: "body", Required: true, Desc: "Amount to add"},
			{Name: "best_before_date", Type: "string", In: "body", Required: false, Desc: "Best before date (YYYY-MM-DD)"},
			{Name: "price", Type: "number", In: "body", Required: false, Desc: "Price per unit"},
			{Name: "location_id", Type: "integer", In: "body", Required: false, Desc: "Location ID"},
		}},
	{Name: "consume_product", Desc: "Consume/use a product from stock", Method: "POST", Path: "/api/stock/products/{product_id}/consume",
		Params: []Param{
			{Name: "product_id", Type: "integer", In: "path", Required: true, Desc: "Product ID"},
			{Name: "amount", Type: "number", In: "body", Required: true, Desc: "Amount to consume"},
			{Name: "spoiled", Type: "boolean", In: "body", Required: false, Desc: "Whether the product was spoiled"},
			{Name: "location_id", Type: "integer", In: "body", Required: false, Desc: "Consume from specific location"},
		}},
	{Name: "transfer_product", Desc: "Transfer product stock between locations", Method: "POST", Path: "/api/stock/products/{product_id}/transfer",
		Params: []Param{
			{Name: "product_id", Type: "integer", In: "path", Required: true, Desc: "Product ID"},
			{Name: "amount", Type: "number", In: "body", Required: true, Desc: "Amount to transfer"},
			{Name: "location_id_from", Type: "integer", In: "body", Required: true, Desc: "Source location ID"},
			{Name: "location_id_to", Type: "integer", In: "body", Required: true, Desc: "Destination location ID"},
		}},
	{Name: "inventory_product", Desc: "Set exact stock amount for a product (inventory correction)", Method: "POST", Path: "/api/stock/products/{product_id}/inventory",
		Params: []Param{
			{Name: "product_id", Type: "integer", In: "path", Required: true, Desc: "Product ID"},
			{Name: "new_amount", Type: "number", In: "body", Required: true, Desc: "New stock amount"},
			{Name: "best_before_date", Type: "string", In: "body", Required: false, Desc: "Best before date (YYYY-MM-DD)"},
			{Name: "location_id", Type: "integer", In: "body", Required: false, Desc: "Location ID"},
		}},
	{Name: "open_product", Desc: "Mark a product as opened", Method: "POST", Path: "/api/stock/products/{product_id}/open",
		Params: []Param{
			{Name: "product_id", Type: "integer", In: "path", Required: true, Desc: "Product ID"},
			{Name: "amount", Type: "number", In: "body", Required: true, Desc: "Amount to open"},
		}},
	{Name: "get_product_by_barcode", Desc: "Get product stock info by barcode", Method: "GET", Path: "/api/stock/products/by-barcode/{barcode}",
		Params: []Param{{Name: "barcode", Type: "string", In: "path", Required: true, Desc: "Product barcode"}}},
	{Name: "add_by_barcode", Desc: "Add stock by barcode", Method: "POST", Path: "/api/stock/products/by-barcode/{barcode}/add",
		Params: []Param{
			{Name: "barcode", Type: "string", In: "path", Required: true, Desc: "Product barcode"},
			{Name: "amount", Type: "number", In: "body", Required: true, Desc: "Amount to add"},
			{Name: "best_before_date", Type: "string", In: "body", Required: false, Desc: "Best before date (YYYY-MM-DD)"},
			{Name: "price", Type: "number", In: "body", Required: false, Desc: "Price per unit"},
		}},
	{Name: "consume_by_barcode", Desc: "Consume stock by barcode", Method: "POST", Path: "/api/stock/products/by-barcode/{barcode}/consume",
		Params: []Param{
			{Name: "barcode", Type: "string", In: "path", Required: true, Desc: "Product barcode"},
			{Name: "amount", Type: "number", In: "body", Required: true, Desc: "Amount to consume"},
			{Name: "spoiled", Type: "boolean", In: "body", Required: false, Desc: "Whether the product was spoiled"},
		}},
	{Name: "transfer_by_barcode", Desc: "Transfer stock by barcode", Method: "POST", Path: "/api/stock/products/by-barcode/{barcode}/transfer",
		Params: []Param{
			{Name: "barcode", Type: "string", In: "path", Required: true, Desc: "Product barcode"},
			{Name: "amount", Type: "number", In: "body", Required: true, Desc: "Amount to transfer"},
			{Name: "location_id_from", Type: "integer", In: "body", Required: true, Desc: "Source location ID"},
			{Name: "location_id_to", Type: "integer", In: "body", Required: true, Desc: "Destination location ID"},
		}},
	{Name: "inventory_by_barcode", Desc: "Inventory correction by barcode", Method: "POST", Path: "/api/stock/products/by-barcode/{barcode}/inventory",
		Params: []Param{
			{Name: "barcode", Type: "string", In: "path", Required: true, Desc: "Product barcode"},
			{Name: "new_amount", Type: "number", In: "body", Required: true, Desc: "New stock amount"},
		}},
	{Name: "open_by_barcode", Desc: "Open product by barcode", Method: "POST", Path: "/api/stock/products/by-barcode/{barcode}/open",
		Params: []Param{
			{Name: "barcode", Type: "string", In: "path", Required: true, Desc: "Product barcode"},
			{Name: "amount", Type: "number", In: "body", Required: true, Desc: "Amount to open"},
		}},
	{Name: "get_stock_entry", Desc: "Get a specific stock entry", Method: "GET", Path: "/api/stock/entry/{entry_id}",
		Params: []Param{{Name: "entry_id", Type: "string", In: "path", Required: true, Desc: "Stock entry ID"}}},
	{Name: "edit_stock_entry", Desc: "Edit a stock entry", Method: "PUT", Path: "/api/stock/entry/{entry_id}",
		Params: []Param{
			{Name: "entry_id", Type: "string", In: "path", Required: true, Desc: "Stock entry ID"},
			{Name: "amount", Type: "number", In: "body", Required: false, Desc: "New amount"},
			{Name: "best_before_date", Type: "string", In: "body", Required: false, Desc: "New best before date"},
			{Name: "price", Type: "number", In: "body", Required: false, Desc: "New price"},
			{Name: "location_id", Type: "integer", In: "body", Required: false, Desc: "New location ID"},
		}},
	{Name: "get_stock_by_location", Desc: "Get stock entries for a specific location", Method: "GET", Path: "/api/stock/locations/{location_id}/entries",
		Params: []Param{{Name: "location_id", Type: "integer", In: "path", Required: true, Desc: "Location ID"}}},
	{Name: "undo_booking", Desc: "Undo a stock booking", Method: "POST", Path: "/api/stock/bookings/{booking_id}/undo",
		Params: []Param{{Name: "booking_id", Type: "integer", In: "path", Required: true, Desc: "Booking ID"}}},
	{Name: "undo_transaction", Desc: "Undo a stock transaction", Method: "POST", Path: "/api/stock/transactions/{transaction_id}/undo",
		Params: []Param{{Name: "transaction_id", Type: "string", In: "path", Required: true, Desc: "Transaction ID"}}},
	{Name: "external_barcode_lookup", Desc: "Look up a barcode using external services", Method: "GET", Path: "/api/stock/barcodes/external-lookup/{barcode}",
		Params: []Param{{Name: "barcode", Type: "string", In: "path", Required: true, Desc: "Barcode to look up"}}},

	// ---- Shopping List ----
	{Name: "add_missing_products_to_shopping_list", Desc: "Add products below minimum stock to shopping list", Method: "POST", Path: "/api/stock/shoppinglist/add-missing-products",
		Params: []Param{{Name: "list_id", Type: "integer", In: "body", Required: false, Desc: "Shopping list ID (default: 1)"}}},
	{Name: "add_overdue_products_to_shopping_list", Desc: "Add overdue products to shopping list", Method: "POST", Path: "/api/stock/shoppinglist/add-overdue-products",
		Params: []Param{{Name: "list_id", Type: "integer", In: "body", Required: false, Desc: "Shopping list ID (default: 1)"}}},
	{Name: "add_expired_products_to_shopping_list", Desc: "Add expired products to shopping list", Method: "POST", Path: "/api/stock/shoppinglist/add-expired-products",
		Params: []Param{{Name: "list_id", Type: "integer", In: "body", Required: false, Desc: "Shopping list ID (default: 1)"}}},
	{Name: "clear_shopping_list", Desc: "Clear all items from a shopping list", Method: "POST", Path: "/api/stock/shoppinglist/clear",
		Params: []Param{{Name: "list_id", Type: "integer", In: "body", Required: false, Desc: "Shopping list ID (default: 1)"}}},
	{Name: "add_product_to_shopping_list", Desc: "Add a product to the shopping list", Method: "POST", Path: "/api/stock/shoppinglist/add-product",
		Params: []Param{
			{Name: "product_id", Type: "integer", In: "body", Required: true, Desc: "Product ID"},
			{Name: "list_id", Type: "integer", In: "body", Required: false, Desc: "Shopping list ID (default: 1)"},
			{Name: "product_amount", Type: "number", In: "body", Required: false, Desc: "Amount (default: 1)"},
		}},
	{Name: "remove_product_from_shopping_list", Desc: "Remove a product from the shopping list", Method: "POST", Path: "/api/stock/shoppinglist/remove-product",
		Params: []Param{
			{Name: "product_id", Type: "integer", In: "body", Required: true, Desc: "Product ID"},
			{Name: "list_id", Type: "integer", In: "body", Required: false, Desc: "Shopping list ID (default: 1)"},
			{Name: "product_amount", Type: "number", In: "body", Required: false, Desc: "Amount to remove (default: 1)"},
		}},

	// ---- Recipes ----
	{Name: "get_recipes_fulfillment", Desc: "Check fulfillment status of all recipes", Method: "GET", Path: "/api/recipes/fulfillment"},
	{Name: "get_recipe_fulfillment", Desc: "Check fulfillment status of a specific recipe", Method: "GET", Path: "/api/recipes/{recipe_id}/fulfillment",
		Params: []Param{{Name: "recipe_id", Type: "integer", In: "path", Required: true, Desc: "Recipe ID"}}},
	{Name: "add_recipe_missing_to_shopping_list", Desc: "Add missing recipe ingredients to shopping list", Method: "POST", Path: "/api/recipes/{recipe_id}/add-not-fulfilled-products-to-shoppinglist",
		Params: []Param{{Name: "recipe_id", Type: "integer", In: "path", Required: true, Desc: "Recipe ID"}}},
	{Name: "consume_recipe", Desc: "Consume all ingredients of a recipe from stock", Method: "POST", Path: "/api/recipes/{recipe_id}/consume",
		Params: []Param{{Name: "recipe_id", Type: "integer", In: "path", Required: true, Desc: "Recipe ID"}}},
	{Name: "copy_recipe", Desc: "Copy a recipe", Method: "POST", Path: "/api/recipes/{recipe_id}/copy",
		Params: []Param{{Name: "recipe_id", Type: "integer", In: "path", Required: true, Desc: "Recipe ID"}}},

	// ---- Chores ----
	{Name: "get_chores", Desc: "Get all chores with next execution dates and assignments", Method: "GET", Path: "/api/chores"},
	{Name: "get_chore", Desc: "Get details for a specific chore", Method: "GET", Path: "/api/chores/{chore_id}",
		Params: []Param{{Name: "chore_id", Type: "integer", In: "path", Required: true, Desc: "Chore ID"}}},
	{Name: "execute_chore", Desc: "Mark a chore as executed", Method: "POST", Path: "/api/chores/{chore_id}/execute",
		Params: []Param{
			{Name: "chore_id", Type: "integer", In: "path", Required: true, Desc: "Chore ID"},
			{Name: "tracked_time", Type: "string", In: "body", Required: false, Desc: "Execution time (YYYY-MM-DD HH:MM:SS)"},
			{Name: "done_by", Type: "integer", In: "body", Required: false, Desc: "User ID who did the chore"},
		}},
	{Name: "undo_chore_execution", Desc: "Undo the last chore execution", Method: "POST", Path: "/api/chores/executions/{execution_id}/undo",
		Params: []Param{{Name: "execution_id", Type: "integer", In: "path", Required: true, Desc: "Chore execution ID"}}},
	{Name: "calculate_chore_assignments", Desc: "Recalculate chore assignments", Method: "POST", Path: "/api/chores/executions/calculate-next-assignments"},

	// ---- Tasks ----
	{Name: "get_tasks", Desc: "Get all tasks", Method: "GET", Path: "/api/tasks"},
	{Name: "complete_task", Desc: "Mark a task as completed", Method: "POST", Path: "/api/tasks/{task_id}/complete",
		Params: []Param{{Name: "task_id", Type: "integer", In: "path", Required: true, Desc: "Task ID"}}},
	{Name: "undo_task", Desc: "Undo task completion", Method: "POST", Path: "/api/tasks/{task_id}/undo",
		Params: []Param{{Name: "task_id", Type: "integer", In: "path", Required: true, Desc: "Task ID"}}},

	// ---- Batteries ----
	{Name: "get_batteries", Desc: "Get all batteries with charge status", Method: "GET", Path: "/api/batteries"},
	{Name: "get_battery", Desc: "Get details for a specific battery", Method: "GET", Path: "/api/batteries/{battery_id}",
		Params: []Param{{Name: "battery_id", Type: "integer", In: "path", Required: true, Desc: "Battery ID"}}},
	{Name: "charge_battery", Desc: "Track a battery charge cycle", Method: "POST", Path: "/api/batteries/{battery_id}/charge",
		Params: []Param{
			{Name: "battery_id", Type: "integer", In: "path", Required: true, Desc: "Battery ID"},
			{Name: "tracked_time", Type: "string", In: "body", Required: false, Desc: "Charge time (YYYY-MM-DD HH:MM:SS)"},
		}},
	{Name: "undo_charge_cycle", Desc: "Undo a battery charge cycle", Method: "POST", Path: "/api/batteries/charge-cycles/{cycle_id}/undo",
		Params: []Param{{Name: "cycle_id", Type: "integer", In: "path", Required: true, Desc: "Charge cycle ID"}}},

	// ---- Generic CRUD ----
	{Name: "list_objects", Desc: "List all objects of a given entity type (products, locations, shopping_list, recipes, chores, tasks, batteries, quantity_units, product_groups, shopping_locations, task_categories, product_barcodes, meal_plan, etc.)", Method: "GET", Path: "/api/objects/{entity}",
		Params: []Param{
			{Name: "entity", Type: "string", In: "path", Required: true, Desc: "Entity name (e.g. products, locations, shopping_list, recipes, quantity_units, product_groups, meal_plan)"},
			{Name: "query[]", Type: "string", In: "query", Required: false, Desc: "Filter expression (e.g. name=Milk or min_stock_amount>0). Can be repeated."},
		}},
	{Name: "get_object", Desc: "Get a specific object by entity type and ID", Method: "GET", Path: "/api/objects/{entity}/{object_id}",
		Params: []Param{
			{Name: "entity", Type: "string", In: "path", Required: true, Desc: "Entity name"},
			{Name: "object_id", Type: "integer", In: "path", Required: true, Desc: "Object ID"},
		}},
	{Name: "create_object", Desc: "Create a new object of a given entity type", Method: "POST", Path: "/api/objects/{entity}",
		Params: []Param{
			{Name: "entity", Type: "string", In: "path", Required: true, Desc: "Entity name"},
			// remaining fields go in body as arbitrary JSON
		}},
	{Name: "update_object", Desc: "Update an existing object", Method: "PUT", Path: "/api/objects/{entity}/{object_id}",
		Params: []Param{
			{Name: "entity", Type: "string", In: "path", Required: true, Desc: "Entity name"},
			{Name: "object_id", Type: "integer", In: "path", Required: true, Desc: "Object ID"},
		}},
	{Name: "delete_object", Desc: "Delete an object", Method: "DELETE", Path: "/api/objects/{entity}/{object_id}",
		Params: []Param{
			{Name: "entity", Type: "string", In: "path", Required: true, Desc: "Entity name"},
			{Name: "object_id", Type: "integer", In: "path", Required: true, Desc: "Object ID"},
		}},

	// ---- System ----
	{Name: "get_system_info", Desc: "Get Grocy system info (version, etc.)", Method: "GET", Path: "/api/system/info"},
	{Name: "get_system_time", Desc: "Get the current server time", Method: "GET", Path: "/api/system/time"},
	{Name: "get_db_changed_time", Desc: "Get the last database change timestamp", Method: "GET", Path: "/api/system/db-changed-time"},
}

// ---------------------------------------------------------------------------
// JSON-RPC types
// ---------------------------------------------------------------------------

type jsonRPCRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type jsonRPCResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  any             `json:"result,omitempty"`
	Error   *jsonRPCError   `json:"error,omitempty"`
}

type jsonRPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// MCP content types
type textContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type callToolResult struct {
	Content []textContent `json:"content"`
	IsError bool          `json:"isError,omitempty"`
}

// ---------------------------------------------------------------------------
// MCP handler
// ---------------------------------------------------------------------------

var (
	grocyBaseURL string
	grocyAPIKey  string
	httpClient   = &http.Client{Timeout: 30 * time.Second}
)

func main() {
	grocyBaseURL = strings.TrimRight(os.Getenv("GROCY_BASE_URL"), "/")
	if grocyBaseURL == "" {
		grocyBaseURL = "http://127.0.0.1:2383"
	}
	grocyAPIKey = os.Getenv("GROCY_API_KEY")

	scanner := bufio.NewScanner(os.Stdin)
	// Allow large messages (16 MB)
	scanner.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)

	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}

		var req jsonRPCRequest
		if err := json.Unmarshal(line, &req); err != nil {
			writeError(nil, -32700, "Parse error")
			continue
		}

		resp := handle(req)
		if resp != nil {
			writeJSON(resp)
		}
	}
}

func handle(req jsonRPCRequest) *jsonRPCResponse {
	switch req.Method {
	case "initialize":
		return &jsonRPCResponse{
			JSONRPC: "2.0",
			ID:      req.ID,
			Result: map[string]any{
				"protocolVersion": "2024-11-05",
				"capabilities": map[string]any{
					"tools": map[string]any{},
				},
				"serverInfo": map[string]any{
					"name":    "grocy-mcp",
					"version": "0.1.0",
				},
			},
		}

	case "notifications/initialized":
		// notification, no response
		return nil

	case "tools/list":
		return &jsonRPCResponse{
			JSONRPC: "2.0",
			ID:      req.ID,
			Result: map[string]any{
				"tools": mcpToolDefinitions(),
			},
		}

	case "tools/call":
		return handleToolCall(req)

	default:
		return &jsonRPCResponse{
			JSONRPC: "2.0",
			ID:      req.ID,
			Error:   &jsonRPCError{Code: -32601, Message: "Method not found: " + req.Method},
		}
	}
}

func mcpToolDefinitions() []map[string]any {
	return []map[string]any{
		{
			"name":        "grocy_list_tools",
			"description": "List all available Grocy API operations. Returns name and short description for each.",
			"inputSchema": map[string]any{
				"type":       "object",
				"properties": map[string]any{},
			},
		},
		{
			"name":        "grocy_describe_tool",
			"description": "Get full details for a Grocy API operation: HTTP method, URL path, and all parameters with types and descriptions.",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"name": map[string]any{
						"type":        "string",
						"description": "Tool name from grocy_list_tools",
					},
				},
				"required": []string{"name"},
			},
		},
		{
			"name":        "grocy_use_tool",
			"description": "Execute a Grocy API operation. Pass the tool name and any required parameters. For generic CRUD tools (create_object, update_object), extra fields beyond the defined params are sent as the JSON request body.",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"name": map[string]any{
						"type":        "string",
						"description": "Tool name from grocy_list_tools",
					},
					"params": map[string]any{
						"type":        "object",
						"description": "Parameters for the tool (path params, body fields, query params)",
					},
				},
				"required": []string{"name"},
			},
		},
	}
}

func handleToolCall(req jsonRPCRequest) *jsonRPCResponse {
	var args struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal(req.Params, &args); err != nil {
		return &jsonRPCResponse{
			JSONRPC: "2.0",
			ID:      req.ID,
			Result:  errorResult("Invalid params: " + err.Error()),
		}
	}

	switch args.Name {
	case "grocy_list_tools":
		return &jsonRPCResponse{JSONRPC: "2.0", ID: req.ID, Result: doListTools()}
	case "grocy_describe_tool":
		return &jsonRPCResponse{JSONRPC: "2.0", ID: req.ID, Result: doDescribeTool(req.Params)}
	case "grocy_use_tool":
		return &jsonRPCResponse{JSONRPC: "2.0", ID: req.ID, Result: doUseTool(req.Params)}
	default:
		return &jsonRPCResponse{
			JSONRPC: "2.0",
			ID:      req.ID,
			Result:  errorResult("Unknown tool: " + args.Name),
		}
	}
}

// ---------------------------------------------------------------------------
// Tool implementations
// ---------------------------------------------------------------------------

func doListTools() callToolResult {
	type entry struct {
		Name string `json:"name"`
		Desc string `json:"description"`
	}
	entries := make([]entry, len(tools))
	for i, t := range tools {
		entries[i] = entry{Name: t.Name, Desc: t.Desc}
	}
	b, _ := json.Marshal(entries)
	return callToolResult{Content: []textContent{{Type: "text", Text: string(b)}}}
}

func doDescribeTool(raw json.RawMessage) callToolResult {
	var args struct {
		Arguments struct {
			Name string `json:"name"`
		} `json:"arguments"`
	}
	if err := json.Unmarshal(raw, &args); err != nil {
		return errorResult("Invalid params: " + err.Error())
	}
	for _, t := range tools {
		if t.Name == args.Arguments.Name {
			b, _ := json.Marshal(t)
			return callToolResult{Content: []textContent{{Type: "text", Text: string(b)}}}
		}
	}
	return errorResult("Unknown tool: " + args.Arguments.Name)
}

func doUseTool(raw json.RawMessage) callToolResult {
	var args struct {
		Arguments struct {
			Name   string                 `json:"name"`
			Params map[string]any `json:"params"`
		} `json:"arguments"`
	}
	if err := json.Unmarshal(raw, &args); err != nil {
		return errorResult("Invalid params: " + err.Error())
	}
	params := args.Arguments.Params
	if params == nil {
		params = map[string]any{}
	}

	var tool *Tool
	for i := range tools {
		if tools[i].Name == args.Arguments.Name {
			tool = &tools[i]
			break
		}
	}
	if tool == nil {
		return errorResult("Unknown tool: " + args.Arguments.Name)
	}

	// Build URL path, replacing {param} placeholders
	path := tool.Path
	queryParts := []string{}
	bodyFields := map[string]any{}

	// Track which params are defined as path/query so we know what's "extra" for body
	definedParams := map[string]string{}
	for _, p := range tool.Params {
		definedParams[p.Name] = p.In
	}

	for k, v := range params {
		where, defined := definedParams[k]
		if defined {
			switch where {
			case "path":
				path = strings.ReplaceAll(path, "{"+k+"}", fmt.Sprintf("%v", v))
			case "query":
				// Support repeated query params (value can be string or []string)
				switch val := v.(type) {
				case []any:
					for _, item := range val {
						queryParts = append(queryParts, fmt.Sprintf("%s=%v", k, item))
					}
				default:
					queryParts = append(queryParts, fmt.Sprintf("%s=%v", k, val))
				}
			case "body":
				bodyFields[k] = v
			}
		} else {
			// Extra/unknown params go to body (for generic CRUD)
			bodyFields[k] = v
		}
	}

	url := grocyBaseURL + path
	if len(queryParts) > 0 {
		url += "?" + strings.Join(queryParts, "&")
	}

	// Build HTTP request
	var bodyReader io.Reader
	if len(bodyFields) > 0 && tool.Method != "GET" && tool.Method != "DELETE" {
		b, _ := json.Marshal(bodyFields)
		bodyReader = strings.NewReader(string(b))
	}

	httpReq, err := http.NewRequest(tool.Method, url, bodyReader)
	if err != nil {
		return errorResult("Failed to create request: " + err.Error())
	}
	httpReq.Header.Set("GROCY-API-KEY", grocyAPIKey)
	if bodyReader != nil {
		httpReq.Header.Set("Content-Type", "application/json")
	}

	resp, err := httpClient.Do(httpReq)
	if err != nil {
		return errorResult("HTTP request failed: " + err.Error())
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return errorResult("Failed to read response: " + err.Error())
	}

	// Return both status and body
	result := fmt.Sprintf("HTTP %d\n%s", resp.StatusCode, string(body))
	isErr := resp.StatusCode >= 400
	return callToolResult{
		Content: []textContent{{Type: "text", Text: result}},
		IsError: isErr,
	}
}

func errorResult(msg string) callToolResult {
	return callToolResult{
		Content: []textContent{{Type: "text", Text: msg}},
		IsError: true,
	}
}

func writeJSON(v any) {
	b, _ := json.Marshal(v)
	fmt.Fprintf(os.Stdout, "%s\n", b)
}

func writeError(id json.RawMessage, code int, msg string) {
	writeJSON(&jsonRPCResponse{
		JSONRPC: "2.0",
		ID:      id,
		Error:   &jsonRPCError{Code: code, Message: msg},
	})
}
