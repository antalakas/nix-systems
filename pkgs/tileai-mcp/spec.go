package main

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"
	"unicode"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"sigs.k8s.io/yaml"
)

// allowed lists the operations served, by operationId. Anything absent,
// including every DELETE, is never reachable.
var allowed = []string{
	"getSelfUser",
	"listWorkspaces", "getWorkspace",
	"listTeamspaces", "getTeamspace",
	"listTileTemplates", "getTileTemplate",
	"listTiles", "getTilesInPath", "searchTiles",
	"getTile", "getTileMetadata", "getTileProperties", "listTileIndexes", "getTileContent",
	"runTileOperation",
	"updateTile", "updateTileMetadata", "updateTileProperties",
	"registerTile", "moveTiles",
}

type param struct {
	Name        string
	In          string // path or query
	Required    bool
	Description string
	Schema      map[string]any
}

type tool struct {
	Name        string
	OperationID string
	Method      string
	Path        string
	Summary     string
	Description string
	Params      []param
	Body        map[string]any // nil when the operation takes none
	BodyNeeded  bool
}

func loadSpec(path string) (map[string]any, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var spec map[string]any
	if err := yaml.Unmarshal(b, &spec); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return spec, nil
}

func buildTools(spec map[string]any, ids []string, readOnly bool) ([]tool, error) {
	want := map[string]bool{}
	for _, id := range ids {
		want[id] = true
	}
	paths, _ := spec["paths"].(map[string]any)
	var tools []tool
	for p, v := range paths {
		item, _ := v.(map[string]any)
		shared := asSlice(item["parameters"])
		for _, method := range []string{"get", "post", "patch", "put"} {
			op, ok := item[method].(map[string]any)
			if !ok {
				continue
			}
			id, _ := op["operationId"].(string)
			if !want[id] || (readOnly && method != "get") {
				continue
			}
			t := tool{
				Name:        snake(id),
				OperationID: id,
				Method:      strings.ToUpper(method),
				Path:        p,
				Summary:     str(op["summary"]),
				Description: str(op["description"]),
			}
			for _, raw := range append(append([]any{}, shared...), asSlice(op["parameters"])...) {
				prm := resolve(spec, raw, nil)
				in := str(prm["in"])
				if in != "path" && in != "query" {
					continue
				}
				schema := resolve(spec, prm["schema"], nil)
				if schema == nil {
					schema = map[string]any{"type": "string"}
				}
				name := str(prm["name"])
				// A tile path may be empty, meaning the teamspace root.
				required := prm["required"] == true
				if in == "path" {
					required = name != "path"
				}
				t.Params = append(t.Params, param{
					Name: name, In: in, Required: required,
					Description: str(prm["description"]), Schema: schema,
				})
			}
			if rb, ok := op["requestBody"].(map[string]any); ok {
				rb = resolve(spec, rb, nil)
				content, _ := rb["content"].(map[string]any)
				if js, ok := content["application/json"].(map[string]any); ok {
					t.Body = resolve(spec, js["schema"], nil)
					if t.Body == nil {
						t.Body = map[string]any{}
					}
					if d := str(rb["description"]); d != "" {
						t.Body["description"] = d
					}
					t.BodyNeeded = rb["required"] == true
				}
			}
			tools = append(tools, t)
			delete(want, id)
		}
	}
	if len(want) > 0 {
		var missing []string
		for id := range want {
			missing = append(missing, id)
		}
		sort.Strings(missing)
		if !readOnly {
			return nil, fmt.Errorf("operations not in the spec: %s", strings.Join(missing, ", "))
		}
	}
	sort.Slice(tools, func(i, j int) bool { return tools[i].Name < tools[j].Name })
	return tools, nil
}

func (t tool) mcpTool() *mcp.Tool {
	props := map[string]any{}
	required := []string{}
	for _, p := range t.Params {
		s := copyMap(p.Schema)
		if p.Description != "" {
			s["description"] = p.Description
		}
		if p.Name == "path" && p.In == "path" {
			s["description"] = strings.TrimSpace("Path inside the teamspace, slash-separated; empty for its root. " + p.Description)
		}
		props[p.Name] = s
		if p.Required {
			required = append(required, p.Name)
		}
	}
	if t.Body != nil {
		props["body"] = t.Body
		if t.BodyNeeded {
			required = append(required, "body")
		}
	}
	schema := map[string]any{"type": "object", "properties": props}
	if len(required) > 0 {
		schema["required"] = required
	}
	desc := t.Summary
	if t.Description != "" && t.Description != t.Summary {
		desc += "\n\n" + clip(t.Description, 1500)
	}
	desc += fmt.Sprintf("\n\n%s %s", t.Method, t.Path)
	if t.OperationID == "runTileOperation" {
		desc += "\n\nAn operation's parameters are declared by its tile's template: call get_tile_template for the template and read operations[].params (JSON Schema). Operations marked mutates need write access."
	}
	readOnly := t.Method == "GET"
	notDestructive := false
	return &mcp.Tool{
		Name:        t.Name,
		Description: desc,
		InputSchema: schema,
		Annotations: &mcp.ToolAnnotations{ReadOnlyHint: readOnly, DestructiveHint: &notDestructive},
	}
}

// resolve follows $ref through the spec's components, inlining them. A ref
// already being expanded on this branch becomes a bare object, which keeps a
// recursive schema finite.
func resolve(spec map[string]any, v any, seen map[string]bool) map[string]any {
	m, ok := v.(map[string]any)
	if !ok {
		return nil
	}
	if ref, ok := m["$ref"].(string); ok {
		if seen[ref] {
			return map[string]any{"type": "object"}
		}
		target := lookup(spec, ref)
		if target == nil {
			return map[string]any{"type": "object", "description": "unresolved " + ref}
		}
		next := map[string]bool{ref: true}
		for k := range seen {
			next[k] = true
		}
		return resolve(spec, target, next)
	}
	out := map[string]any{}
	for k, val := range m {
		switch x := val.(type) {
		case map[string]any:
			if r := resolve(spec, x, seen); r != nil {
				out[k] = r
			}
		case []any:
			arr := make([]any, len(x))
			for i, e := range x {
				if em, ok := e.(map[string]any); ok {
					arr[i] = resolve(spec, em, seen)
				} else {
					arr[i] = e
				}
			}
			out[k] = arr
		default:
			out[k] = val
		}
	}
	// OpenAPI 3.0's nullable is not JSON Schema; clients ignore it either way.
	delete(out, "nullable")
	delete(out, "example")
	return out
}

func lookup(spec map[string]any, ref string) map[string]any {
	if !strings.HasPrefix(ref, "#/") {
		return nil
	}
	var cur any = spec
	for _, part := range strings.Split(ref[2:], "/") {
		part = strings.ReplaceAll(strings.ReplaceAll(part, "~1", "/"), "~0", "~")
		m, ok := cur.(map[string]any)
		if !ok {
			return nil
		}
		cur = m[part]
	}
	m, _ := cur.(map[string]any)
	return m
}

var upper = regexp.MustCompile(`[A-Z]+`)

func snake(id string) string {
	s := upper.ReplaceAllStringFunc(id, func(u string) string { return "_" + strings.ToLower(u) })
	return strings.TrimLeftFunc(s, func(r rune) bool { return r == '_' || unicode.IsSpace(r) })
}

func asSlice(v any) []any { s, _ := v.([]any); return s }

func str(v any) string { s, _ := v.(string); return s }

func clip(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

func copyMap(m map[string]any) map[string]any {
	b, _ := json.Marshal(m)
	var out map[string]any
	_ = json.Unmarshal(b, &out)
	if out == nil {
		out = map[string]any{}
	}
	return out
}
