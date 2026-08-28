// decree-webhook — receives authenticated POSTs and drops decree inbox messages.
//
// Ported from an Express server.js. The wire contract and the bytes written to
// the inbox are unchanged (see main_test.go, whose golden frontmatter comes
// from the parity-verified build); the Express-shaped scaffolding around them
// is not preserved. Behaviours kept deliberately rather than inherited are
// marked below — they are the ones a future change is most likely to regress.
//
// See README.md for the request contract and the ways this service departs
// from a conventional JSON endpoint.
package main

import (
	"bytes"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"gopkg.in/yaml.v3"
)

const maxParameterLength = 200

// minSecretLength is a floor, not a target. The templates mint 32-char hex
// (128 bits); anything shorter than that is almost certainly hand-typed, and a
// bearer token is the only thing standing between the internet and a routine
// the decree daemon will execute.
const minSecretLength = 32

// Inbox messages can carry secrets from callers, so they are not world-readable.
const inboxFileMode = 0o640

// Defaults for every DECREE_WEBHOOK_* setting; see README.md.
const (
	defaultPort                   = "8801"
	defaultInboxDirectory         = "/inbox"
	defaultConfigPath             = "/app/config.yml"
	defaultMaxBodyBytes           = 256 * 1024
	defaultRateWindowMilliseconds = 60000
	defaultRequestLimit           = 60
	defaultFailureLimit           = 10
)

const (
	configPollInterval = 2 * time.Second
	// Grace period before exiting on a config change, so a half-written file
	// is not what the restarted process reads.
	configReloadDelay = 300 * time.Millisecond
)

var (
	pathPattern             = regexp.MustCompile(`^/[A-Za-z0-9._\-/{}]+$`)
	parameterNamePattern    = regexp.MustCompile(`^\w+$`)
	defaultParameterPattern = regexp.MustCompile(`^[A-Za-z0-9_\-!]+$`)
	placeholderPattern      = regexp.MustCompile(`\{\{(\w+)\}\}`)
	pathParameterPattern    = regexp.MustCompile(`\{(\w+)\}`)
	slugUnsafePattern       = regexp.MustCompile(`[^A-Za-z0-9_-]`)
	bearerPattern           = regexp.MustCompile(`(?i)^Bearer\s+(.+)$`)
)

var (
	logger      = slog.New(slog.NewJSONHandler(os.Stdout, nil))
	errorLogger = slog.New(slog.NewJSONHandler(os.Stderr, nil))
)

func fatal(message string, arguments ...any) {
	errorLogger.Error(message, arguments...)
	os.Exit(1)
}

// ── config ───────────────────────────────────────────────────────────────────

// endpointConfig is one entry of the config file's endpoints[] array.
type endpointConfig struct {
	Path   string `yaml:"path"`
	Secret string `yaml:"secret"`
	// Value, not pointer: yaml.v3 leaves a *yaml.Node struct field zeroed.
	Frontmatter yaml.Node         `yaml:"frontmatter"`
	Parameters  map[string]string `yaml:"params"`
}

// webhookConfig is the whole config file.
type webhookConfig struct {
	Secret    string           `yaml:"secret"`
	Endpoints []endpointConfig `yaml:"endpoints"`
}

// route is one compiled, validated endpoint — the runtime form of an
// endpointConfig, with every pattern already compiled and every check passed.
type route struct {
	path        string
	secret      []byte
	frontmatter *yaml.Node // normalised: styles cleared, nested collections flow
	routineSlug string
	// parameterNames is ordered as the path declares them; parameterPatterns
	// holds only those with a stricter-than-default rule.
	parameterNames    []string
	parameterPatterns map[string]*regexp.Regexp
}

func loadConfig(path string) ([]*route, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var parsed webhookConfig
	if err := yaml.Unmarshal(contents, &parsed); err != nil {
		return nil, err
	}
	if len(parsed.Endpoints) == 0 {
		return nil, errors.New("config.yml must contain a non-empty endpoints[] array")
	}

	seenPaths := map[string]bool{}
	routes := make([]*route, 0, len(parsed.Endpoints))
	for _, entry := range parsed.Endpoints {
		compiled, err := compileRoute(entry, parsed.Secret)
		if err != nil {
			return nil, err
		}
		if seenPaths[compiled.path] {
			return nil, fmt.Errorf("duplicate endpoint path: %s", compiled.path)
		}
		seenPaths[compiled.path] = true
		routes = append(routes, compiled)
	}
	return routes, nil
}

// compileRoute validates one endpoint and compiles it. Every failure here is
// fatal at startup: a half-valid route table is worse than not starting.
func compileRoute(entry endpointConfig, defaultSecret string) (*route, error) {
	if entry.Path == "" || !pathPattern.MatchString(entry.Path) || strings.Contains(entry.Path, "..") {
		return nil, fmt.Errorf("invalid endpoint path: %q", entry.Path)
	}
	if entry.Frontmatter.Kind != yaml.MappingNode {
		return nil, fmt.Errorf("endpoint %s missing frontmatter object", entry.Path)
	}

	secret := entry.Secret
	if secret == "" {
		secret = defaultSecret
	}
	// An unsubstituted placeholder is the dangerous case: templates.sh
	// rewrites EXIST_* tokens at render time, and a config that skipped
	// rendering would otherwise start with a *publicly known* secret.
	// EXIST_DECREE_MINIO_WEBHOOK_AUTH_TOKEN is 37 chars, so a length check
	// alone would wave it straight through.
	if strings.HasPrefix(secret, "EXIST_") {
		return nil, fmt.Errorf("%s: secret is an unrendered template placeholder (%s) — run ./existential.sh", entry.Path, secret)
	}
	if len(secret) < minSecretLength {
		// Actionable on purpose: config.yml is gitignored and is not
		// not re-rendered once written, so a deployment carrying a shorter
		// secret from the Express service (floor 16) hits this on upgrade and
		// crash-loops under `restart: unless-stopped`. Say how to fix it.
		return nil, fmt.Errorf(
			"%s: secret missing or too short (%d chars, min %d) — "+
				"generate a longer one and set it in services/decree/webhook/config.yml "+
				"(or re-render with ./existential.sh reset && ./existential.sh)",
			entry.Path, len(secret), minSecretLength)
	}

	var parameterNames []string
	for _, match := range pathParameterPattern.FindAllStringSubmatch(entry.Path, -1) {
		parameterNames = append(parameterNames, match[1])
	}

	patterns := map[string]*regexp.Regexp{}
	for name, expression := range entry.Parameters {
		if !parameterNamePattern.MatchString(name) {
			return nil, fmt.Errorf("endpoint %s: invalid param name %q", entry.Path, name)
		}
		if !slices.Contains(parameterNames, name) {
			return nil, fmt.Errorf("endpoint %s: params.%s not present in path", entry.Path, name)
		}
		// Go's regexp is RE2 — backreferences and lookaround compile in a
		// JS config but not here. Fail at startup, not at request time.
		compiled, err := regexp.Compile("^(?:" + expression + ")$")
		if err != nil {
			return nil, fmt.Errorf("endpoint %s: params.%s has invalid regex: %v", entry.Path, name, err)
		}
		patterns[name] = compiled
	}

	return &route{
		path:              entry.Path,
		secret:            []byte(secret),
		frontmatter:       normaliseNode(&entry.Frontmatter, 0),
		routineSlug:       routineSlug(&entry.Frontmatter),
		parameterNames:    parameterNames,
		parameterPatterns: patterns,
	}, nil
}

// routineSlug reads `routine` off the RAW (unsubstituted) frontmatter, so a
// {{param}} there yields the literal slug rather than attacker-chosen text in
// the filename.
func routineSlug(frontmatter *yaml.Node) string {
	slug := "message"
	// A mapping node's Content alternates key, value, key, value…
	for index := 0; index+1 < len(frontmatter.Content); index += 2 {
		if frontmatter.Content[index].Value != "routine" {
			continue
		}
		if value := frontmatter.Content[index+1].Value; value != "" {
			slug = value
		}
		break
	}
	return slugUnsafePattern.ReplaceAllString(slug, "-")
}

// normaliseNode fixes the emitted frontmatter so it does not echo config.yml's
// own formatting: styles are cleared so quoting is re-decided from the value,
// comments are dropped, and collections below the root are emitted inline.
// Key order follows config.yml — which is why frontmatter stays a yaml.Node
// tree rather than becoming a map (a map would emit alphabetically).
func normaliseNode(node *yaml.Node, depth int) *yaml.Node {
	clone := *node
	clone.Style = 0
	clone.HeadComment, clone.LineComment, clone.FootComment = "", "", ""

	isCollection := clone.Kind == yaml.MappingNode || clone.Kind == yaml.SequenceNode
	if isCollection && depth >= 1 {
		clone.Style = yaml.FlowStyle
	}

	childDepth := depth
	if isCollection {
		childDepth = depth + 1
	}
	clone.Content = make([]*yaml.Node, len(node.Content))
	for index, child := range node.Content {
		clone.Content[index] = normaliseNode(child, childDepth)
	}
	return &clone
}

// YAML 1.1 resolves these bare words to non-strings. Emitting them unquoted
// would let a 1.1 reader turn a frontmatter value of `y` or `off` into a
// boolean. Param values land in frontmatter directly (POST /notify/y), so this
// is reachable input, not just a config concern.
var yaml11Special = map[string]bool{
	"": true, "~": true,
	"null": true, "Null": true, "NULL": true,
	"true": true, "True": true, "TRUE": true,
	"false": true, "False": true, "FALSE": true,
	"y": true, "Y": true, "yes": true, "Yes": true, "YES": true,
	"n": true, "N": true, "no": true, "No": true, "NO": true,
	"on": true, "On": true, "ON": true,
	"off": true, "Off": true, "OFF": true,
	".inf": true, ".Inf": true, ".INF": true,
	"-.inf": true, "-.Inf": true, "-.INF": true,
	".nan": true, ".NaN": true, ".NAN": true,
}

var numericPattern = regexp.MustCompile(`^[-+]?(0b[01_]+|0o[0-7_]+|0x[0-9a-fA-F_]+|[0-9][0-9_]*(\.[0-9_]*)?([eE][-+]?[0-9]+)?|\.[0-9_]+([eE][-+]?[0-9]+)?)$`)

func needsQuote(value string) bool {
	return yaml11Special[value] || numericPattern.MatchString(value)
}

// substituteNode applies {{param}} replacement to string scalars only, leaving
// numbers and booleans alone. An unknown placeholder is left verbatim.
func substituteNode(node *yaml.Node, parameters map[string]string) *yaml.Node {
	clone := *node
	if clone.Kind == yaml.ScalarNode && clone.Tag == "!!str" {
		clone.Value = placeholderPattern.ReplaceAllStringFunc(clone.Value, func(placeholder string) string {
			name := placeholderPattern.FindStringSubmatch(placeholder)[1]
			value, found := parameters[name]
			if !found {
				return placeholder
			}
			return value
		})
		if needsQuote(clone.Value) {
			clone.Style = yaml.SingleQuotedStyle
		}
	}
	clone.Content = make([]*yaml.Node, len(node.Content))
	for index, child := range node.Content {
		clone.Content[index] = substituteNode(child, parameters)
	}
	return &clone
}

// renderFrontmatter substitutes params into the endpoint's frontmatter and
// marshals the result.
//
// Substitution happens on the node tree and the result is then marshalled, so
// the YAML encoder decides quoting. Never build this by string interpolation —
// that is what stops a param injecting YAML.
func renderFrontmatter(matched *route, parameters map[string]string) (string, error) {
	var buffer bytes.Buffer
	encoder := yaml.NewEncoder(&buffer)
	encoder.SetIndent(2)
	if err := encoder.Encode(substituteNode(matched.frontmatter, parameters)); err != nil {
		return "", err
	}
	if err := encoder.Close(); err != nil {
		return "", err
	}
	return buffer.String(), nil
}

// ── responses ────────────────────────────────────────────────────────────────

// createdResponse is the 201 body: the inbox file that was written, and the
// endpoint that wrote it.
type createdResponse struct {
	File string `json:"file"`
	Path string `json:"path"`
}

// writeJSON returns the status it wrote so callers can account for failures
// without wrapping the ResponseWriter.
func writeJSON(writer http.ResponseWriter, status int, payload any) int {
	// Every payload here is a fixed struct or map[string]string, so marshalling
	// cannot fail; an error would mean a programming mistake, not bad input.
	encoded, _ := json.Marshal(payload)
	writer.Header().Set("Content-Type", "application/json; charset=utf-8")
	writer.WriteHeader(status)
	writer.Write(encoded)
	return status
}

func writeError(writer http.ResponseWriter, status int, message string) int {
	return writeJSON(writer, status, map[string]string{"error": message})
}

// ── rate limiting ────────────────────────────────────────────────────────────

// fixedWindowLimiter is a counter reset once per interval. The stdlib has no
// rate limiter, and golang.org/x/time/rate is a module whose current release
// needs a newer Go than the builder image — not a trade worth making for ~30
// lines.
type fixedWindowLimiter struct {
	mutex    sync.Mutex
	interval time.Duration
	limit    int
	count    int
	resetAt  time.Time
}

func newFixedWindowLimiter(interval time.Duration, limit int) *fixedWindowLimiter {
	return &fixedWindowLimiter{interval: interval, limit: limit, resetAt: time.Now().Add(interval)}
}

// resetIfExpiredLocked rolls the window over. The caller must hold the mutex.
func (limiter *fixedWindowLimiter) resetIfExpiredLocked() {
	now := time.Now()
	if !now.After(limiter.resetAt) {
		return
	}
	limiter.count = 0
	limiter.resetAt = now.Add(limiter.interval)
}

// allow consumes one slot, reporting whether one was available.
func (limiter *fixedWindowLimiter) allow() bool {
	limiter.mutex.Lock()
	defer limiter.mutex.Unlock()
	limiter.resetIfExpiredLocked()
	if limiter.count >= limiter.limit {
		return false
	}
	limiter.count++
	return true
}

// exhausted reports whether the budget is spent, without consuming.
func (limiter *fixedWindowLimiter) exhausted() bool {
	limiter.mutex.Lock()
	defer limiter.mutex.Unlock()
	limiter.resetIfExpiredLocked()
	return limiter.count >= limiter.limit
}

// ── server ───────────────────────────────────────────────────────────────────

type webhookServer struct {
	inbox        string
	maxBodyBytes int64
	// Global, not per-IP: the service sits behind Caddy and sees one source
	// address, so per-IP buckets would all be the same bucket. failureLimiter
	// is the brute-force brake — it only spends a slot when a request is
	// rejected, so a busy legitimate caller never exhausts it.
	requestLimiter *fixedWindowLimiter
	failureLimiter *fixedWindowLimiter
}

func (server *webhookServer) handler(matched *route) http.HandlerFunc {
	return func(writer http.ResponseWriter, request *http.Request) {
		// Limiters run before the method check: in the Express service the
		// rate-limit middleware was registered ahead of the 404 handler, so a
		// flood of wrong-method requests still charged both budgets.
		if !server.requestLimiter.allow() || server.failureLimiter.exhausted() {
			writeError(writer, http.StatusTooManyRequests, "too many requests")
			return
		}
		// Routes are registered without a method, so a GET lands here rather
		// than letting ServeMux answer 405 — callers of the Express version
		// saw 404 for a wrong method and some may depend on it.
		if request.Method != http.MethodPost {
			server.failureLimiter.allow()
			writeError(writer, http.StatusNotFound, "not found")
			return
		}
		if server.serve(writer, request, matched) >= http.StatusBadRequest {
			server.failureLimiter.allow()
		}
	}
}

// authorized compares the request's bearer token against the endpoint's secret.
// Length is compared first so a wrong-length token cannot be told apart by
// timing; ConstantTimeCompare covers the rest.
func authorized(request *http.Request, matched *route) bool {
	match := bearerPattern.FindStringSubmatch(request.Header.Get("Authorization"))
	if match == nil {
		return false
	}
	token := []byte(match[1])
	return len(token) == len(matched.secret) && subtle.ConstantTimeCompare(token, matched.secret) == 1
}

// pathParameters validates every parameter the route declares. Its error text
// is returned to the caller verbatim, so it names the offending parameter but
// never echoes the rejected value.
func (matched *route) pathParameters(request *http.Request) (map[string]string, error) {
	parameters := make(map[string]string, len(matched.parameterNames))
	for _, name := range matched.parameterNames {
		value := request.PathValue(name)
		if value == "" {
			return nil, fmt.Errorf("missing param: %s", name)
		}
		if len(value) > maxParameterLength {
			return nil, fmt.Errorf("param too long: %s", name)
		}
		if !defaultParameterPattern.MatchString(value) {
			return nil, fmt.Errorf("invalid param: %s", name)
		}
		if pattern, restricted := matched.parameterPatterns[name]; restricted && !pattern.MatchString(value) {
			return nil, fmt.Errorf("invalid param: %s", name)
		}
		parameters[name] = value
	}
	return parameters, nil
}

// serve returns the status it wrote, so failure accounting needs no
// ResponseWriter wrapper.
func (server *webhookServer) serve(writer http.ResponseWriter, request *http.Request, matched *route) int {
	if !authorized(request, matched) {
		return writeError(writer, http.StatusUnauthorized, "unauthorized")
	}

	body, err := io.ReadAll(http.MaxBytesReader(writer, request.Body, server.maxBodyBytes))
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			return writeError(writer, http.StatusRequestEntityTooLarge, "body too large")
		}
		return writeError(writer, http.StatusInternalServerError, "internal error")
	}
	if strings.TrimSpace(string(body)) == "" {
		return writeError(writer, http.StatusBadRequest, "empty body")
	}

	parameters, err := matched.pathParameters(request)
	if err != nil {
		return writeError(writer, http.StatusBadRequest, err.Error())
	}

	frontmatter, err := renderFrontmatter(matched, parameters)
	if err != nil {
		logger.Error("yaml encode failed", "path", matched.path, "err", err)
		return writeError(writer, http.StatusInternalServerError, "internal error")
	}

	content := "---\n" + frontmatter + "---\n\n" + string(body)
	if !strings.HasSuffix(content, "\n") {
		content += "\n"
	}

	filename := fmt.Sprintf("%s-%s.md", matched.routineSlug, time.Now().Format("150405"))
	fullPath := filepath.Join(server.inbox, filename)
	if !strings.HasPrefix(fullPath, server.inbox+string(os.PathSeparator)) {
		return writeError(writer, http.StatusInternalServerError, "path resolution failed")
	}
	if err := writeNewFile(fullPath, content); err != nil {
		logger.Error("write failed", "path", matched.path, "err", err)
		return writeError(writer, http.StatusInternalServerError, "write failed")
	}

	logger.Info("enqueued", "path", matched.path, "file", filename, "bytes", len(content))
	return writeJSON(writer, http.StatusCreated, createdResponse{File: filename, Path: matched.path})
}

// writeNewFile creates a file that must not already exist.
//
// O_EXCL: two messages for the same routine within one second collide and the
// second is rejected. Preserved deliberately — the daemon derives a message
// identity from this filename, so silently overwriting would drop a message.
// Changing it is a separate decision.
func writeNewFile(path, content string) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, inboxFileMode)
	if err != nil {
		return err
	}
	_, writeFailure := file.WriteString(content)
	closeFailure := file.Close()
	return errors.Join(writeFailure, closeFailure)
}

// newMux wires the routes. Split out of main so tests can build a server
// without binding a port.
func newMux(server *webhookServer, routes []*route) (http.Handler, error) {
	mux := http.NewServeMux()

	// Registered outside the rate limiters so healthchecks never consume quota.
	mux.HandleFunc("/healthz", func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodGet {
			writeError(writer, http.StatusNotFound, "not found")
			return
		}
		writeJSON(writer, http.StatusOK, map[string]bool{"ok": true})
	})

	if err := registerRoutes(mux, server, routes); err != nil {
		return nil, err
	}

	// Unknown paths sat behind the rate-limit middleware in the Express
	// service. Leaving them outside it here would mean a flood of `/` never
	// trips the brute-force brake — the one thing the failure budget is for.
	mux.HandleFunc("/", func(writer http.ResponseWriter, _ *http.Request) {
		if !server.requestLimiter.allow() || server.failureLimiter.exhausted() {
			writeError(writer, http.StatusTooManyRequests, "too many requests")
			return
		}
		server.failureLimiter.allow()
		writeError(writer, http.StatusNotFound, "not found")
	})
	return stripTrailingSlash(mux), nil
}

// ServeMux panics on conflicting patterns. That is a better failure mode than
// silently taking the first match, but it should read as a config error.
func registerRoutes(mux *http.ServeMux, server *webhookServer, routes []*route) (err error) {
	defer func() {
		if recovered := recover(); recovered != nil {
			err = fmt.Errorf("%v", recovered)
		}
	}()
	for _, matched := range routes {
		// config.yml's {name} placeholders are already ServeMux pattern syntax.
		mux.HandleFunc(matched.path, server.handler(matched))
		logger.Info("route registered", "path", matched.path)
	}
	return nil
}

// stripTrailingSlash keeps /notify/ resolving to /notify, as it did before the
// port — dropping it would turn a 201 into a 404 for any caller that sends the
// slash. Exactly one is removed, so /notify// still 404s. A ServeMux pattern
// cannot express this: a trailing slash there means subtree match, which would
// swallow /notify/{title}.
func stripTrailingSlash(next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if path := request.URL.Path; len(path) > 1 && strings.HasSuffix(path, "/") {
			request.URL.Path = path[:len(path)-1]
		}
		next.ServeHTTP(writer, request)
	})
}

// ── env ──────────────────────────────────────────────────────────────────────

func envString(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

// envInt ignores anything unparseable or non-positive rather than failing: a
// typo in an optional tuning knob should not stop the service from starting.
func envInt(key string, fallback int) int {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(raw)
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}

// ── main ─────────────────────────────────────────────────────────────────────

func main() {
	port := envString("DECREE_WEBHOOK_PORT", defaultPort)

	// distroless ships no curl, so the container healthcheck is the binary
	// probing itself.
	if hasHealthcheckFlag(os.Args[1:]) {
		os.Exit(healthcheckExitCode(port))
	}

	inbox, err := filepath.Abs(envString("DECREE_WEBHOOK_INBOX", defaultInboxDirectory))
	if err != nil {
		fatal("inbox path invalid", "err", err)
	}
	configPath := envString("DECREE_WEBHOOK_CONFIG", defaultConfigPath)

	routes, err := loadConfig(configPath)
	if err != nil {
		fatal("config load failed", "err", err)
	}
	if err := checkWritable(inbox); err != nil {
		fatal("inbox not writable", "inbox", inbox, "err", err)
	}

	window := time.Duration(envInt("DECREE_WEBHOOK_RATE_WINDOW_MS", defaultRateWindowMilliseconds)) * time.Millisecond
	server := &webhookServer{
		inbox:          inbox,
		maxBodyBytes:   int64(envInt("DECREE_WEBHOOK_MAX_BODY_BYTES", defaultMaxBodyBytes)),
		requestLimiter: newFixedWindowLimiter(window, envInt("DECREE_WEBHOOK_RATE_MAX", defaultRequestLimit)),
		failureLimiter: newFixedWindowLimiter(window, envInt("DECREE_WEBHOOK_RATE_FAIL_MAX", defaultFailureLimit)),
	}

	handler, err := newMux(server, routes)
	if err != nil {
		fatal("route registration failed", "err", err)
	}

	go watchConfig(configPath)

	logger.Info("listening", "port", port, "inbox", inbox, "endpoints", len(routes))
	httpServer := &http.Server{
		Addr:              ":" + port,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
	}
	if err := httpServer.ListenAndServe(); err != nil {
		fatal("listen failed", "err", err)
	}
}

func hasHealthcheckFlag(arguments []string) bool {
	return slices.ContainsFunc(arguments, func(argument string) bool {
		return argument == "-healthcheck" || argument == "--healthcheck"
	})
}

// healthcheckExitCode probes the already-running process over the loopback
// interface and maps the result to a process exit code.
func healthcheckExitCode(port string) int {
	response, err := http.Get("http://127.0.0.1:" + port + "/healthz")
	if err != nil {
		return 1
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

// checkWritable fails at startup rather than on the first request.
//
// A leftover probe from a crashed run proves the directory was writable once,
// not that it is writable now — treating that as success lets exactly the case
// this exists to catch (a mount gone read-only) start cleanly and then 500 on
// every POST. Clear any stale probe, then prove writability freshly. Nothing is
// left behind afterwards: the decree daemon polls this directory every 2s.
func checkWritable(directory string) error {
	probe := filepath.Join(directory, ".writable-probe")
	if err := os.Remove(probe); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	file, err := os.OpenFile(probe, os.O_WRONLY|os.O_CREATE|os.O_EXCL, inboxFileMode)
	if err != nil {
		return err
	}
	file.Close()
	return os.Remove(probe)
}

// watchConfig exits on change so the container restart policy reloads config.
// Polling rather than inotify: the config is a bind-mounted file, and an editor
// replacing the inode drops a file watch.
func watchConfig(path string) {
	info, err := os.Stat(path)
	if err != nil {
		logger.Warn("config watch failed", "err", err)
		return
	}

	lastModified := info.ModTime()
	for {
		time.Sleep(configPollInterval)
		info, err := os.Stat(path)
		if err != nil {
			logger.Warn("config watch failed", "err", err)
			continue
		}
		if info.ModTime().Equal(lastModified) {
			continue
		}
		logger.Info("config changed, restarting to reload", "path", path)
		time.Sleep(configReloadDelay)
		os.Exit(0)
	}
}
