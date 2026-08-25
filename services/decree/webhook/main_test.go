// Test matrix for decree-webhook.
//
// Ported from difftest.sh, which proved this server byte-identical to the
// Express implementation it replaced. The golden frontmatter below was
// captured from that verified build, so these tests still pin the original
// behaviour — but they run under `go test` alone, with no node, no npm deps
// and no containers.
package main

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"gopkg.in/yaml.v3"
)

const (
	testSecret      = "0123456789abcdef0123456789abcdef"
	alternateSecret = "fedcba9876543210fedcba9876543210"
)

const bearerHeader = "Bearer " + testSecret

const testConfig = `
secret: ` + testSecret + `

endpoints:
  - path: /notify
    frontmatter:
      routine: notify
      ntfy_priority: low
      ntfy_tags: lobster
      ntfy_title: Untitled
      ntfy_topic: exist
  - path: /notify/{title}
    frontmatter:
      routine: notify
      ntfy_priority: high
      ntfy_title: "{{title}}"
  - path: /notify/alert/{title}
    frontmatter:
      routine: notify
      ntfy_title: "{{title}}"
  - path: /note/{id}
    params:
      id: '[0-9a-f]{8,16}'
    frontmatter:
      routine: notes
      note_id: '{{id}}'
      tags: [api, ingest]
  - path: /external
    secret: ` + alternateSecret + `
    frontmatter:
      routine: external
  - path: /styles
    frontmatter:
      routine: styles
      an_int: 5
      a_float: 1.5
      a_bool: true
      a_null: null
      colon_value: 'foo: bar'
      hash_value: 'trailing # hash'
      brace_value: '{not a map}'
      quoted_num: '42'
      empty_str: ''
      nested:
        a: 1
        b: [x, y]
`

func TestMain(m *testing.M) {
	// The server logs to stdout on every request; silence it so test output
	// stays readable.
	logger = slog.New(slog.NewJSONHandler(io.Discard, nil))
	errorLogger = logger
	os.Exit(m.Run())
}

// newTestServer builds a server over a throwaway inbox. Rate limits are set
// far out of the way unless a test overrides them.
func newTestServer(t *testing.T, requestLimit, failureLimit int) (*httptest.Server, string) {
	t.Helper()
	directory := t.TempDir()
	inbox := filepath.Join(directory, "inbox")
	if err := os.MkdirAll(inbox, 0o755); err != nil {
		t.Fatal(err)
	}
	configPath := filepath.Join(directory, "config.yml")
	if err := os.WriteFile(configPath, []byte(testConfig), 0o600); err != nil {
		t.Fatal(err)
	}
	routes, err := loadConfig(configPath)
	if err != nil {
		t.Fatalf("loadConfig: %v", err)
	}
	server := &webhookServer{
		inbox:          inbox,
		maxBodyBytes:   256 * 1024,
		requestLimiter: newFixedWindowLimiter(time.Minute, requestLimit),
		failureLimiter: newFixedWindowLimiter(time.Minute, failureLimit),
	}
	handler, err := newMux(server, routes)
	if err != nil {
		t.Fatalf("newMux: %v", err)
	}
	testServer := httptest.NewServer(handler)
	t.Cleanup(testServer.Close)
	return testServer, inbox
}

// sendRequest issues one request and returns its status and body.
func sendRequest(t *testing.T, testServer *httptest.Server, method, path, authorization, body string) (int, string) {
	t.Helper()
	var bodyReader io.Reader
	if body != "" {
		bodyReader = strings.NewReader(body)
	}
	request, err := http.NewRequest(method, testServer.URL+path, bodyReader)
	if err != nil {
		t.Fatal(err)
	}
	if authorization != "" {
		request.Header.Set("Authorization", authorization)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	responseBody, _ := io.ReadAll(response.Body)
	return response.StatusCode, string(responseBody)
}

// onlyFile returns the content of the single .md in the inbox, failing if the
// count is not exactly one.
func onlyFile(t *testing.T, inbox string) string {
	t.Helper()
	matches, err := filepath.Glob(filepath.Join(inbox, "*.md"))
	if err != nil {
		t.Fatal(err)
	}
	if len(matches) != 1 {
		t.Fatalf("expected exactly 1 inbox file, got %d: %v", len(matches), matches)
	}
	contents, err := os.ReadFile(matches[0])
	if err != nil {
		t.Fatal(err)
	}
	return string(contents)
}

func inboxFiles(t *testing.T, inbox string) []string {
	t.Helper()
	matches, err := filepath.Glob(filepath.Join(inbox, "*.md"))
	if err != nil {
		t.Fatal(err)
	}
	return matches
}

func clearInbox(t *testing.T, inbox string) {
	t.Helper()
	for _, match := range inboxFiles(t, inbox) {
		os.Remove(match)
	}
}

// writeConfig drops a config file in a throwaway directory and returns its path.
func writeConfig(t *testing.T, contents string) string {
	t.Helper()
	configPath := filepath.Join(t.TempDir(), "config.yml")
	if err := os.WriteFile(configPath, []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
	return configPath
}

// ── golden frontmatter ───────────────────────────────────────────────────────

func TestWritesGoldenFrontmatter(t *testing.T) {
	testCases := []struct {
		name, path, authorization, body, want string
	}{
		{
			name: "static scalars",
			path: "/notify", authorization: bearerHeader, body: "hello world",
			want: "---\nroutine: notify\nntfy_priority: low\nntfy_tags: lobster\n" +
				"ntfy_title: Untitled\nntfy_topic: exist\n---\n\nhello world\n",
		},
		{
			name: "param substitution",
			path: "/notify/MyTitle", authorization: bearerHeader, body: "body here",
			want: "---\nroutine: notify\nntfy_priority: high\nntfy_title: MyTitle\n---\n\nbody here\n",
		},
		{
			name: "nested collections emit inline",
			path: "/note/deadbeef", authorization: bearerHeader, body: "note body",
			want: "---\nroutine: notes\nnote_id: deadbeef\ntags: [api, ingest]\n---\n\nnote body\n",
		},
		{
			// Key order follows config.yml, not alphabetical: this is why
			// frontmatter stays a yaml.Node tree rather than a map.
			name: "scalar quoting and key order",
			path: "/styles", authorization: bearerHeader, body: "b",
			want: "---\nroutine: styles\nan_int: 5\na_float: 1.5\na_bool: true\na_null: null\n" +
				"colon_value: 'foo: bar'\nhash_value: 'trailing # hash'\nbrace_value: '{not a map}'\n" +
				"quoted_num: '42'\nempty_str: ''\nnested: {a: 1, b: [x, 'y']}\n---\n\nb\n",
		},
		{
			name: "per-endpoint secret",
			path: "/external", authorization: "Bearer " + alternateSecret, body: "ext body",
			want: "---\nroutine: external\n---\n\next body\n",
		},
		{
			name: "body without trailing newline gets one",
			path: "/notify/X", authorization: bearerHeader, body: "no trailing newline",
			want: "---\nroutine: notify\nntfy_priority: high\nntfy_title: X\n---\n\nno trailing newline\n",
		},
		{
			name: "multiline body preserved",
			path: "/notify/X", authorization: bearerHeader, body: "line one\nline two\n",
			want: "---\nroutine: notify\nntfy_priority: high\nntfy_title: X\n---\n\nline one\nline two\n",
		},
	}

	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			testServer, inbox := newTestServer(t, 1000, 1000)
			status, _ := sendRequest(t, testServer, http.MethodPost, testCase.path, testCase.authorization, testCase.body)
			if status != http.StatusCreated {
				t.Fatalf("status = %d, want 201", status)
			}
			if got := onlyFile(t, inbox); got != testCase.want {
				t.Errorf("frontmatter mismatch\n got: %q\nwant: %q", got, testCase.want)
			}
		})
	}
}

// A YAML 1.1 reader turns bare `y`, `off` and friends into booleans. Param
// values reach frontmatter directly, so they must be emitted quoted.
func TestYAML11AmbiguousParamsAreQuoted(t *testing.T) {
	values := []string{"y", "Y", "n", "no", "NO", "on", "off", "yes", "true", "false", "null", "42"}
	for _, value := range values {
		t.Run(value, func(t *testing.T) {
			testServer, inbox := newTestServer(t, 1000, 1000)
			status, _ := sendRequest(t, testServer, http.MethodPost, "/notify/"+value, bearerHeader, "b")
			if status != http.StatusCreated {
				t.Fatalf("status = %d, want 201", status)
			}
			want := "ntfy_title: '" + value + "'\n"
			if got := onlyFile(t, inbox); !strings.Contains(got, want) {
				t.Errorf("value %q not quoted\n got: %q\nwant substring: %q", value, got, want)
			}
		})
	}
}

// The param allowlist blocks YAML metacharacters outright, before the encoder
// is ever reached.
func TestParamsWithMetacharactersAreRejected(t *testing.T) {
	injections := map[string]string{
		"colon":     "/notify/a%3Ab",
		"newline":   "/notify/a%0Ab",
		"quote":     "/notify/a%22b",
		"brace":     "/notify/a%7Bb",
		"space":     "/notify/bad%20title",
		"slash":     "/notify/a%2Fb",
		"hash":      "/notify/a%23b",
		"backslash": "/notify/a%5Cb",
		"ampersand": "/notify/a%26b",
		"asterisk":  "/notify/a%2Ab",
	}
	for name, path := range injections {
		t.Run(name, func(t *testing.T) {
			testServer, inbox := newTestServer(t, 1000, 1000)
			status, _ := sendRequest(t, testServer, http.MethodPost, path, bearerHeader, "b")
			if status == http.StatusCreated {
				t.Fatalf("metacharacter accepted (201): %s\nwrote: %s", path, onlyFile(t, inbox))
			}
			if matches := inboxFiles(t, inbox); len(matches) != 0 {
				t.Errorf("rejected request still wrote a file: %v", matches)
			}
		})
	}
}

// parseFrontmatter re-reads the YAML block of a written message.
func parseFrontmatter(t *testing.T, content string) map[string]any {
	t.Helper()
	rest, found := strings.CutPrefix(content, "---\n")
	if !found {
		t.Fatalf("message has no frontmatter: %q", content)
	}
	end := strings.Index(rest, "---\n")
	if end < 0 {
		t.Fatalf("frontmatter not terminated: %q", content)
	}
	var parsed map[string]any
	if err := yaml.Unmarshal([]byte(rest[:end]), &parsed); err != nil {
		t.Fatalf("emitted frontmatter does not parse: %v\n%q", err, rest[:end])
	}
	return parsed
}

// Characters the allowlist permits still have YAML meaning: `---` is a document
// separator, `!!str` a tag, `y` a 1.1 boolean, `42` an int. Rather than trust
// the encoder by inspection, round-trip every one and require the value back
// out as the exact string that went in. Anything that escapes quoting shows up
// here as a type change or a parse error.
func TestAcceptedParamsRoundTripAsStrings(t *testing.T) {
	values := []string{
		"---", "-", "----", "a---b",
		"!", "!!str", "!!int", "!!null", "!binary",
		"y", "n", "no", "yes", "on", "off", "true", "false", "null",
		"42", "0", "-1", "1_000", "0x10", "0b1",
		"___", "a_b", "A-B_c!", "NULL", "Y",
	}
	for _, value := range values {
		t.Run(value, func(t *testing.T) {
			testServer, inbox := newTestServer(t, 1000, 1000)
			status, _ := sendRequest(t, testServer, http.MethodPost, "/notify/"+value, bearerHeader, "b")
			if status != http.StatusCreated {
				t.Skipf("value rejected by the allowlist (%d) — not an encoder concern", status)
			}
			frontmatter := parseFrontmatter(t, onlyFile(t, inbox))
			title, present := frontmatter["ntfy_title"]
			if !present {
				t.Fatalf("ntfy_title missing from %v", frontmatter)
			}
			text, isString := title.(string)
			if !isString {
				t.Fatalf("ntfy_title round-tripped as %T (%v), want string %q", title, title, value)
			}
			if text != value {
				t.Errorf("ntfy_title = %q, want %q", text, value)
			}
			// The routine must not be steerable by a param either.
			if frontmatter["routine"] != "notify" {
				t.Errorf("routine = %v, want notify", frontmatter["routine"])
			}
		})
	}
}

// ── auth ─────────────────────────────────────────────────────────────────────

func TestAuth(t *testing.T) {
	testCases := []struct {
		name, path, authorization string
		want                      int
	}{
		{"no header", "/notify", "", http.StatusUnauthorized},
		{"wrong scheme", "/notify", "Basic " + testSecret, http.StatusUnauthorized},
		{"bearer without token", "/notify", "Bearer", http.StatusUnauthorized},
		{"short token", "/notify", "Bearer short", http.StatusUnauthorized},
		{"same length, wrong token", "/notify", "Bearer " + testSecret[:31] + "0", http.StatusUnauthorized},
		{"other endpoint's secret", "/notify", "Bearer " + alternateSecret, http.StatusUnauthorized},
		{"global secret on scoped endpoint", "/external", bearerHeader, http.StatusUnauthorized},
		{"lowercase scheme accepted", "/notify", "bearer " + testSecret, http.StatusCreated},
		{"correct token", "/notify", bearerHeader, http.StatusCreated},
	}
	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			testServer, inbox := newTestServer(t, 1000, 1000)
			status, _ := sendRequest(t, testServer, http.MethodPost, testCase.path, testCase.authorization, "body")
			if status != testCase.want {
				t.Errorf("status = %d, want %d", status, testCase.want)
			}
			matches := inboxFiles(t, inbox)
			if testCase.want != http.StatusCreated && len(matches) != 0 {
				t.Errorf("unauthorised request wrote a file: %v", matches)
			}
		})
	}
}

// ── body and params ──────────────────────────────────────────────────────────

func TestBodyValidation(t *testing.T) {
	testCases := []struct {
		name, body string
		want       int
	}{
		{"empty", "", http.StatusBadRequest},
		{"whitespace only", "   \n\t  \n", http.StatusBadRequest},
		{"single char", "x", http.StatusCreated},
		{"oversized", strings.Repeat("a", 300*1024), http.StatusRequestEntityTooLarge},
	}
	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			testServer, _ := newTestServer(t, 1000, 1000)
			status, _ := sendRequest(t, testServer, http.MethodPost, "/notify", bearerHeader, testCase.body)
			if status != testCase.want {
				t.Errorf("status = %d, want %d", status, testCase.want)
			}
		})
	}
}

func TestParamValidation(t *testing.T) {
	testCases := []struct {
		name, path string
		want       int
	}{
		{"allowed punctuation", "/notify/a-b_c!", http.StatusCreated},
		{"over max length", "/notify/" + strings.Repeat("a", maxParameterLength+1), http.StatusBadRequest},
		{"at max length", "/notify/" + strings.Repeat("a", maxParameterLength), http.StatusCreated},
		{"pattern satisfied", "/note/deadbeef", http.StatusCreated},
		{"pattern violated, not hex", "/note/nothexx0", http.StatusBadRequest},
		{"pattern violated, too short", "/note/dead", http.StatusBadRequest},
	}
	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			testServer, _ := newTestServer(t, 1000, 1000)
			status, _ := sendRequest(t, testServer, http.MethodPost, testCase.path, bearerHeader, "b")
			if status != testCase.want {
				t.Errorf("status = %d, want %d", status, testCase.want)
			}
		})
	}
}

// ── routing ──────────────────────────────────────────────────────────────────

func TestRouting(t *testing.T) {
	testCases := []struct {
		name, method, path string
		want               int
	}{
		{"unknown path", http.MethodPost, "/nope", http.StatusNotFound},
		{"GET on a POST route 404s not 405", http.MethodGet, "/notify", http.StatusNotFound},
		{"POST on healthz", http.MethodPost, "/healthz", http.StatusNotFound},
		{"GET healthz", http.MethodGet, "/healthz", http.StatusOK},
		// Express's non-strict routing matched /notify to /notify/; callers
		// may still send the slash.
		{"trailing slash resolves", http.MethodPost, "/notify/", http.StatusCreated},
		{"double trailing slash does not", http.MethodPost, "/notify//", http.StatusNotFound},
		{"trailing slash on param route", http.MethodPost, "/notify/Foo/", http.StatusCreated},
		{"param route absorbs bare segment", http.MethodPost, "/notify/alert/", http.StatusCreated},
	}
	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			testServer, _ := newTestServer(t, 1000, 1000)
			status, _ := sendRequest(t, testServer, testCase.method, testCase.path, bearerHeader, "b")
			if status != testCase.want {
				t.Errorf("status = %d, want %d", status, testCase.want)
			}
		})
	}
}

// ── rate limiting ────────────────────────────────────────────────────────────

func TestFailureLimiterTripsBeforeTotalLimiter(t *testing.T) {
	testServer, _ := newTestServer(t, 5, 3)
	var got []int
	for attempt := 0; attempt < 8; attempt++ {
		status, _ := sendRequest(t, testServer, http.MethodPost, "/notify", "", "b")
		got = append(got, status)
	}
	want := []int{401, 401, 401, 429, 429, 429, 429, 429}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("sequence = %v, want %v", got, want)
		}
	}
}

func TestSuccessDoesNotSpendFailureBudget(t *testing.T) {
	testServer, inbox := newTestServer(t, 1000, 3)
	for attempt := 0; attempt < 10; attempt++ {
		clearInbox(t, inbox)
		status, _ := sendRequest(t, testServer, http.MethodPost, "/notify", bearerHeader, "b")
		if status != http.StatusCreated {
			t.Fatalf("request %d: status = %d, want 201", attempt, status)
		}
	}
}

func TestHealthzIsNotRateLimited(t *testing.T) {
	testServer, _ := newTestServer(t, 2, 1)
	for attempt := 0; attempt < 10; attempt++ {
		status, _ := sendRequest(t, testServer, http.MethodGet, "/healthz", "", "")
		if status != http.StatusOK {
			t.Fatalf("healthz request %d: status = %d, want 200", attempt, status)
		}
	}
}

// ── inbox writes ─────────────────────────────────────────────────────────────

// Filenames carry a whole-second timestamp and are created O_EXCL, so a second
// message for the same routine inside one second is rejected rather than
// silently overwriting the first.
func TestSameSecondCollisionIsRejected(t *testing.T) {
	testServer, inbox := newTestServer(t, 1000, 1000)
	first, _ := sendRequest(t, testServer, http.MethodPost, "/notify", bearerHeader, "a")
	second, _ := sendRequest(t, testServer, http.MethodPost, "/notify", bearerHeader, "b")
	if first != http.StatusCreated {
		t.Fatalf("first = %d, want 201", first)
	}
	if second != http.StatusInternalServerError {
		t.Fatalf("second = %d, want 500", second)
	}
	if got := onlyFile(t, inbox); !strings.HasSuffix(got, "\na\n") {
		t.Errorf("first message was overwritten: %q", got)
	}
}

func TestInboxFileMode(t *testing.T) {
	testServer, inbox := newTestServer(t, 1000, 1000)
	status, _ := sendRequest(t, testServer, http.MethodPost, "/notify", bearerHeader, "b")
	if status != http.StatusCreated {
		t.Fatal("setup request failed")
	}
	info, err := os.Stat(inboxFiles(t, inbox)[0])
	if err != nil {
		t.Fatal(err)
	}
	// Not world-readable: inbox messages can carry secrets from callers.
	if permissions := info.Mode().Perm(); permissions != inboxFileMode {
		t.Errorf("mode = %o, want %o", permissions, inboxFileMode)
	}
}

func TestFilenameDerivesFromRawRoutine(t *testing.T) {
	testServer, inbox := newTestServer(t, 1000, 1000)
	status, _ := sendRequest(t, testServer, http.MethodPost, "/note/deadbeef", bearerHeader, "b")
	if status != http.StatusCreated {
		t.Fatal("request failed")
	}
	if base := filepath.Base(inboxFiles(t, inbox)[0]); !strings.HasPrefix(base, "notes-") {
		t.Errorf("filename = %q, want notes- prefix", base)
	}
}

// ── config validation ────────────────────────────────────────────────────────

// These run at startup in production, so a bad config fails the container
// rather than surfacing per-request.
func TestConfigValidation(t *testing.T) {
	testCases := []struct {
		name, config, wantError string
	}{
		{
			name:      "no endpoints",
			config:    "secret: " + testSecret + "\nendpoints: []\n",
			wantError: "non-empty endpoints",
		},
		{
			name:      "short secret",
			config:    "secret: tooshort\nendpoints:\n  - path: /a\n    frontmatter:\n      routine: x\n",
			wantError: "too short",
		},
		{
			// 31 chars — one under the floor.
			name:      "secret one char under the floor",
			config:    "secret: " + strings.Repeat("a", minSecretLength-1) + "\nendpoints:\n  - path: /a\n    frontmatter: {routine: x}\n",
			wantError: "too short",
		},
		{
			// The dangerous case: long enough to pass a length check, but a
			// publicly known string. An unrendered config must never serve.
			name:      "unrendered placeholder that is long enough to pass length check",
			config:    "secret: EXIST_DECREE_MINIO_WEBHOOK_AUTH_TOKEN\nendpoints:\n  - path: /a\n    frontmatter: {routine: x}\n",
			wantError: "unrendered template placeholder",
		},
		{
			name:      "unrendered placeholder on a per-endpoint secret",
			config:    "secret: " + testSecret + "\nendpoints:\n  - path: /a\n    secret: EXIST_32_CHAR_HEX_KEY\n    frontmatter: {routine: x}\n",
			wantError: "unrendered template placeholder",
		},
		{
			name:      "missing frontmatter",
			config:    "secret: " + testSecret + "\nendpoints:\n  - path: /a\n",
			wantError: "missing frontmatter",
		},
		{
			name:      "duplicate path",
			config:    "secret: " + testSecret + "\nendpoints:\n  - path: /a\n    frontmatter: {routine: x}\n  - path: /a\n    frontmatter: {routine: y}\n",
			wantError: "duplicate endpoint path",
		},
		{
			name:      "traversal in path",
			config:    "secret: " + testSecret + "\nendpoints:\n  - path: /a/../b\n    frontmatter: {routine: x}\n",
			wantError: "invalid endpoint path",
		},
		{
			name:      "param not present in path",
			config:    "secret: " + testSecret + "\nendpoints:\n  - path: /a\n    params: {id: '[0-9]+'}\n    frontmatter: {routine: x}\n",
			wantError: "not present in path",
		},
		{
			// RE2 has no backreferences; this compiles in a JS config but not
			// here, and must fail at startup rather than at request time.
			name:      "regex unsupported by RE2",
			config:    "secret: " + testSecret + "\nendpoints:\n  - path: /a/{id}\n    params: {id: '(a)\\1'}\n    frontmatter: {routine: x}\n",
			wantError: "invalid regex",
		},
	}
	for _, testCase := range testCases {
		t.Run(testCase.name, func(t *testing.T) {
			_, err := loadConfig(writeConfig(t, testCase.config))
			if err == nil {
				t.Fatalf("expected error containing %q, got nil", testCase.wantError)
			}
			if !strings.Contains(err.Error(), testCase.wantError) {
				t.Errorf("error = %q, want substring %q", err, testCase.wantError)
			}
		})
	}
}

func TestValidConfigLoads(t *testing.T) {
	routes, err := loadConfig(writeConfig(t, testConfig))
	if err != nil {
		t.Fatalf("loadConfig: %v", err)
	}
	if len(routes) != 6 {
		t.Fatalf("routes = %d, want 6", len(routes))
	}
}

// Conflicting ServeMux patterns panic; that must surface as a config error.
func TestConflictingRoutesReportedAsError(t *testing.T) {
	config := "secret: " + testSecret + "\nendpoints:\n" +
		"  - path: /a/{x}\n    frontmatter: {routine: x}\n" +
		"  - path: /a/{y}\n    frontmatter: {routine: y}\n"
	routes, err := loadConfig(writeConfig(t, config))
	if err != nil {
		t.Fatalf("loadConfig: %v", err)
	}
	server := &webhookServer{
		inbox:          t.TempDir(),
		maxBodyBytes:   1024,
		requestLimiter: newFixedWindowLimiter(time.Minute, 10),
		failureLimiter: newFixedWindowLimiter(time.Minute, 10),
	}
	if _, err := newMux(server, routes); err == nil {
		t.Fatal("expected an error from conflicting patterns, got nil")
	}
}
