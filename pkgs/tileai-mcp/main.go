// tileai-mcp serves a chosen subset of the tile.ai REST API as MCP tools, one
// tool per OpenAPI operation, generated from the API's own spec. It holds an
// API token the MCP client never sees, and never calls a DELETE.
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func main() {
	specPath := flag.String("spec", "", "tile.ai v1 OpenAPI spec (services/server/openapi/v1/build/spec/openapi.yaml)")
	baseURL := flag.String("base-url", "", "API base URL including /v1, e.g. https://api.example/v1")
	tokenFile := flag.String("token-file", "", "file holding the API token; must not be readable by group or others")
	listen := flag.String("listen", "127.0.0.1:8091", "address to serve MCP on")
	readOnly := flag.Bool("read-only", false, "expose GET operations only")
	maxBytes := flag.Int("max-bytes", 200_000, "largest response body returned to the client")
	flag.Parse()

	if *specPath == "" || *baseURL == "" || *tokenFile == "" {
		flag.Usage()
		os.Exit(2)
	}
	token, err := readToken(*tokenFile)
	if err != nil {
		log.Fatal(err)
	}
	spec, err := loadSpec(*specPath)
	if err != nil {
		log.Fatal(err)
	}
	tools, err := buildTools(spec, allowed, *readOnly)
	if err != nil {
		log.Fatal(err)
	}
	api := newAPI(*baseURL, token, *maxBytes)
	server := newServer(tools, api)

	handler := mcp.NewStreamableHTTPHandler(func(*http.Request) *mcp.Server { return server },
		&mcp.StreamableHTTPOptions{Stateless: true, JSONResponse: true})
	mux := http.NewServeMux()
	mux.Handle("/mcp", handler)
	log.Printf("tileai-mcp: %d tools against %s on http://%s/mcp", len(tools), *baseURL, *listen)
	srv := &http.Server{Addr: *listen, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	log.Fatal(srv.ListenAndServe())
}

func readToken(path string) (string, error) {
	fi, err := os.Stat(path)
	if err != nil {
		return "", err
	}
	if fi.Mode().Perm()&0o077 != 0 {
		return "", fmt.Errorf("%s is readable by group or others (%v); chmod 600 it", path, fi.Mode().Perm())
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	t := strings.TrimSpace(string(b))
	if t == "" {
		return "", fmt.Errorf("%s is empty", path)
	}
	return t, nil
}

func newServer(tools []tool, api *api) *mcp.Server {
	s := mcp.NewServer(&mcp.Implementation{Name: "tileai", Version: "0.1.0"}, nil)
	for _, t := range tools {
		s.AddTool(t.mcpTool(), api.handler(t))
	}
	return s
}
