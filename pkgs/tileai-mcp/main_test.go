package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// The spec the server is built from: TILEAI_SPEC, or tile-ai's at /workspace.
func specFile(t *testing.T) string {
	if p := os.Getenv("TILEAI_SPEC"); p != "" {
		return p
	}
	p := "/workspace/services/server/openapi/v1/build/spec/openapi.yaml"
	if _, err := os.Stat(p); err != nil {
		t.Skip("no spec; set TILEAI_SPEC")
	}
	return p
}

type seen struct {
	mu   sync.Mutex
	reqs []*http.Request
	body []string
}

func (s *seen) last() (*http.Request, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.reqs[len(s.reqs)-1], s.body[len(s.body)-1]
}

func connect(t *testing.T, readOnly bool, apiHandler http.HandlerFunc) (*mcp.ClientSession, *seen) {
	t.Helper()
	rec := &seen{}
	fake := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		rec.mu.Lock()
		rec.reqs = append(rec.reqs, r)
		rec.body = append(rec.body, string(b))
		rec.mu.Unlock()
		apiHandler(w, r)
	}))
	t.Cleanup(fake.Close)

	spec, err := loadSpec(specFile(t))
	if err != nil {
		t.Fatal(err)
	}
	tools, err := buildTools(spec, allowed, readOnly)
	if err != nil {
		t.Fatal(err)
	}
	server := newServer(tools, newAPI(fake.URL+"/v1", "secret-token", 1000))
	st, ct := mcp.NewInMemoryTransports()
	ctx := context.Background()
	if _, err := server.Connect(ctx, st, nil); err != nil {
		t.Fatal(err)
	}
	cs, err := mcp.NewClient(&mcp.Implementation{Name: "test"}, nil).Connect(ctx, ct, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { cs.Close() })
	return cs, rec
}

func ok(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"ok":true}`))
}

func call(t *testing.T, cs *mcp.ClientSession, name string, args map[string]any) (string, bool) {
	t.Helper()
	res, err := cs.CallTool(context.Background(), &mcp.CallToolParams{Name: name, Arguments: args})
	if err != nil {
		t.Fatal(err)
	}
	return res.Content[0].(*mcp.TextContent).Text, res.IsError
}

func toolNames(t *testing.T, cs *mcp.ClientSession) []string {
	res, err := cs.ListTools(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, tl := range res.Tools {
		names = append(names, tl.Name)
	}
	return names
}

func TestEveryAllowedOperationIsAToolAndNoneDeletes(t *testing.T) {
	cs, _ := connect(t, false, ok)
	names := toolNames(t, cs)
	if len(names) != len(allowed) {
		t.Fatalf("got %d tools, want %d: %v", len(names), len(allowed), names)
	}
	for _, n := range names {
		if strings.Contains(n, "delete") || strings.Contains(n, "abandon") {
			t.Errorf("tool %s removes something", n)
		}
	}
}

func TestReadOnlyServesOnlyGets(t *testing.T) {
	cs, _ := connect(t, true, ok)
	for _, n := range toolNames(t, cs) {
		for _, w := range []string{"update_", "register_", "move_", "run_"} {
			if strings.HasPrefix(n, w) {
				t.Errorf("read-only serves %s", n)
			}
		}
	}
}

func TestTheTokenGoesInTheKeyHeaderAndNeverBackToTheClient(t *testing.T) {
	cs, rec := connect(t, false, ok)
	text, _ := call(t, cs, "get_self_user", nil)
	r, _ := rec.last()
	if r.Header.Get(keyHeader) != "secret-token" {
		t.Fatalf("key header = %q", r.Header.Get(keyHeader))
	}
	if strings.Contains(text, "secret-token") {
		t.Fatalf("result carries the token: %q", text)
	}
}

func TestAnEmptyTilePathListsTheTeamspaceRoot(t *testing.T) {
	cs, rec := connect(t, false, ok)
	call(t, cs, "list_tiles", map[string]any{"workspace": "ws", "teamspace": "ts"})
	r, _ := rec.last()
	if r.URL.EscapedPath() != "/v1/tiles/list/ws/ts" {
		t.Fatalf("path = %s", r.URL.EscapedPath())
	}
}

func TestATilePathKeepsItsSlashesAndEscapesEachSegment(t *testing.T) {
	cs, rec := connect(t, false, ok)
	call(t, cs, "list_tiles", map[string]any{"workspace": "ws", "teamspace": "my ts", "path": "/a b/100%/c?"})
	r, _ := rec.last()
	if got, want := r.URL.EscapedPath(), "/v1/tiles/list/ws/my%20ts/a%20b/100%25/c%3F"; got != want {
		t.Fatalf("path = %s, want %s", got, want)
	}
}

func TestAMissingPathParameterIsRefusedBeforeAnyCall(t *testing.T) {
	cs, rec := connect(t, false, ok)
	text, isErr := call(t, cs, "get_tile", map[string]any{"workspace": "ws", "teamspace": "ts"})
	if !isErr || !strings.Contains(text, "tile is required") {
		t.Fatalf("got %q, error=%v", text, isErr)
	}
	if len(rec.reqs) != 0 {
		t.Fatal("called the API anyway")
	}
}

func TestAnArrayQueryParameterRepeats(t *testing.T) {
	cs, rec := connect(t, false, ok)
	call(t, cs, "search_tiles", map[string]any{"workspace": "ws", "q": "vcf", "teamspace": []any{"a", "b"}})
	r, _ := rec.last()
	if got := r.URL.Query()["teamspace"]; len(got) != 2 || got[0] != "a" || got[1] != "b" {
		t.Fatalf("teamspace = %v", got)
	}
	if r.URL.Query().Get("q") != "vcf" {
		t.Fatalf("q = %q", r.URL.Query().Get("q"))
	}
}

func TestAWriteSendsItsBodyAsJSON(t *testing.T) {
	cs, rec := connect(t, false, ok)
	body := []any{map[string]any{"key": "k", "value": "v"}}
	call(t, cs, "update_tile_metadata", map[string]any{"workspace": "ws", "teamspace": "ts", "tile": "t1", "body": body})
	r, got := rec.last()
	if r.Method != http.MethodPatch || r.URL.Path != "/v1/tiles/item/ws/ts/t1/metadata" {
		t.Fatalf("%s %s", r.Method, r.URL.Path)
	}
	var back []map[string]any
	if err := json.Unmarshal([]byte(got), &back); err != nil || back[0]["key"] != "k" {
		t.Fatalf("body = %s", got)
	}
}

func TestAnOperationRunsWithItsParameters(t *testing.T) {
	cs, rec := connect(t, false, ok)
	call(t, cs, "run_tile_operation", map[string]any{"workspace": "ws", "teamspace": "ts", "tile": "t1", "op": "get_info", "body": map[string]any{}})
	r, _ := rec.last()
	if r.Method != http.MethodPost || r.URL.Path != "/v1/tiles/ops/ws/ts/t1/get_info" {
		t.Fatalf("%s %s", r.Method, r.URL.Path)
	}
}

func TestAnAPIErrorIsAToolErrorWithItsStatusAndBody(t *testing.T) {
	cs, _ := connect(t, false, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusForbidden)
		w.Write([]byte(`{"code":1003,"message":"no"}`))
	})
	text, isErr := call(t, cs, "get_tile", map[string]any{"workspace": "ws", "teamspace": "ts", "tile": "t"})
	if !isErr || !strings.Contains(text, "HTTP 403") || !strings.Contains(text, "1003") {
		t.Fatalf("got %q, error=%v", text, isErr)
	}
}

func TestBinaryContentIsSizedNotShown(t *testing.T) {
	cs, _ := connect(t, false, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Write(make([]byte, 5000))
	})
	text, _ := call(t, cs, "get_tile_content", map[string]any{"workspace": "ws", "teamspace": "ts", "tile": "t"})
	if !strings.Contains(text, "binary body of 5000 bytes") {
		t.Fatalf("got %q", text)
	}
}

func TestALongBodyIsTruncated(t *testing.T) {
	cs, _ := connect(t, false, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`"` + strings.Repeat("x", 3000) + `"`))
	})
	text, _ := call(t, cs, "get_tile", map[string]any{"workspace": "ws", "teamspace": "ts", "tile": "t"})
	if !strings.Contains(text, "truncated") || len(text) > 1200 {
		t.Fatalf("len %d: %.80q", len(text), text)
	}
}

func TestARedirectOffTheAPIHostDropsTheKey(t *testing.T) {
	var gotKey string
	store := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotKey = r.Header.Get(keyHeader)
		w.Header().Set("Content-Type", "text/plain")
		w.Write([]byte("bytes"))
	}))
	defer store.Close()
	cs, _ := connect(t, false, func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, store.URL+"/object", http.StatusFound)
	})
	text, _ := call(t, cs, "get_tile_content", map[string]any{"workspace": "ws", "teamspace": "ts", "tile": "t"})
	if !strings.Contains(text, "bytes") {
		t.Fatalf("got %q", text)
	}
	if gotKey != "" {
		t.Fatalf("the store received the key")
	}
}

func TestATokenFileOthersCanReadIsRefused(t *testing.T) {
	p := filepath.Join(t.TempDir(), "token")
	os.WriteFile(p, []byte("x\n"), 0o644)
	if _, err := readToken(p); err == nil {
		t.Fatal("accepted a 0644 token file")
	}
	os.Chmod(p, 0o600)
	if tok, err := readToken(p); err != nil || tok != "x" {
		t.Fatalf("got %q, %v", tok, err)
	}
}
