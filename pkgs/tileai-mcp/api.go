package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const keyHeader = "X-TILEDB-REST-API-KEY"

type api struct {
	base     *url.URL
	token    string
	maxBytes int
	client   *http.Client
}

func newAPI(base, token string, maxBytes int) *api {
	u, err := url.Parse(strings.TrimRight(base, "/"))
	if err != nil {
		panic(err)
	}
	a := &api{base: u, token: token, maxBytes: maxBytes}
	a.client = &http.Client{
		Timeout: 3 * time.Minute,
		// Go forwards custom headers on redirect, so the key would follow a
		// redirect to a presigned store URL; strip it off-host.
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return errors.New("too many redirects")
			}
			if req.URL.Host != a.base.Host {
				req.Header.Del(keyHeader)
			}
			return nil
		},
	}
	return a
}

func (a *api) handler(t tool) mcp.ToolHandler {
	return func(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		var args map[string]any
		if len(req.Params.Arguments) > 0 {
			if err := json.Unmarshal(req.Params.Arguments, &args); err != nil {
				return failure("arguments are not a JSON object: %v", err), nil
			}
		}
		httpReq, err := a.request(ctx, t, args)
		if err != nil {
			return failure("%v", err), nil
		}
		resp, err := a.client.Do(httpReq)
		if err != nil {
			return failure("%s %s: %v", t.Method, httpReq.URL.Path, err), nil
		}
		defer resp.Body.Close()
		return a.result(resp), nil
	}
}

func (a *api) request(ctx context.Context, t tool, args map[string]any) (*http.Request, error) {
	if t.Method == http.MethodDelete {
		return nil, errors.New("DELETE is never served")
	}
	path := t.Path
	query := url.Values{}
	for _, p := range t.Params {
		v, present := args[p.Name]
		switch p.In {
		case "path":
			s := ""
			if present {
				s = fmt.Sprint(v)
			}
			if s == "" && p.Required {
				return nil, fmt.Errorf("%s is required", p.Name)
			}
			path = strings.Replace(path, "{"+p.Name+"}", escapePath(p.Name, s), 1)
		case "query":
			if !present || v == nil {
				if p.Required {
					return nil, fmt.Errorf("%s is required", p.Name)
				}
				continue
			}
			if list, ok := v.([]any); ok {
				for _, e := range list {
					query.Add(p.Name, fmt.Sprint(e))
				}
			} else {
				query.Set(p.Name, fmt.Sprint(v))
			}
		}
	}
	// An empty tile path leaves "…/{teamspace}/", which the router reads as a
	// different route than the teamspace root.
	path = strings.TrimSuffix(path, "/")

	u := *a.base
	u.RawPath = a.base.EscapedPath() + path
	u.Path, _ = url.PathUnescape(u.RawPath)
	u.RawQuery = query.Encode()

	var body io.Reader
	if t.Body != nil {
		if b, ok := args["body"]; ok {
			enc, err := json.Marshal(b)
			if err != nil {
				return nil, err
			}
			body = bytes.NewReader(enc)
		} else if t.BodyNeeded {
			return nil, errors.New("body is required")
		}
	}
	req, err := http.NewRequestWithContext(ctx, t.Method, u.String(), body)
	if err != nil {
		return nil, err
	}
	req.Header.Set(keyHeader, a.token)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "tileai-mcp/0.1")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	return req, nil
}

// escapePath escapes one path parameter; the tile path keeps its slashes.
func escapePath(name, v string) string {
	if name != "path" {
		return url.PathEscape(v)
	}
	parts := strings.Split(strings.Trim(v, "/"), "/")
	for i, s := range parts {
		parts[i] = url.PathEscape(s)
	}
	return strings.Join(parts, "/")
}

func (a *api) result(resp *http.Response) *mcp.CallToolResult {
	ctype := resp.Header.Get("Content-Type")
	media, _, _ := mime.ParseMediaType(ctype)
	textual := media == "" || strings.HasPrefix(media, "text/") || strings.Contains(media, "json") ||
		strings.Contains(media, "xml") || media == "application/x-ndjson"
	head := fmt.Sprintf("HTTP %d", resp.StatusCode)
	if ctype != "" {
		head += " (" + ctype + ")"
	}
	buf, err := io.ReadAll(io.LimitReader(resp.Body, int64(a.maxBytes)+1))
	if err != nil {
		return failure("%s: reading the body: %v", head, err)
	}
	var text string
	switch {
	case !textual:
		n, _ := io.Copy(io.Discard, resp.Body)
		text = fmt.Sprintf("%s: binary body of %d bytes, not shown", head, int64(len(buf))+n)
	case len(buf) > a.maxBytes:
		text = fmt.Sprintf("%s, first %d bytes:\n%s\n… truncated", head, a.maxBytes, buf[:a.maxBytes])
	default:
		text = head + "\n" + string(buf)
	}
	return &mcp.CallToolResult{
		Content: []mcp.Content{&mcp.TextContent{Text: text}},
		IsError: resp.StatusCode >= 400,
	}
}

func failure(format string, args ...any) *mcp.CallToolResult {
	return &mcp.CallToolResult{
		Content: []mcp.Content{&mcp.TextContent{Text: fmt.Sprintf(format, args...)}},
		IsError: true,
	}
}
