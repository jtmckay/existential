---
machine: plugin
automation: calendar_extract
chart:
  description: Mirror Nextcloud Calendar events in a window around today into workspace/ai/calendar/ as one note per event.
  data:
    CALENDAR_EXTRACT_PAST_DAYS: {type: int, default: 7}
    CALENDAR_EXTRACT_FUTURE_DAYS: {type: int, default: 60}
    # Comma-separated calendar slugs; empty means every calendar the user has.
    CALENDAR_EXTRACT_CALENDARS: {type: string, default: ""}
    # IANA zone for the human-readable When: line.
    CALENDAR_EXTRACT_TZ: {type: string, default: UTC}
  initial: extract
  states:
    extract:
      invoke: calendar_extract
      transitions: {done: done}
    done: {final: true}
    failed: {final: true}
scripts:
  calendar_extract: |
    #!/usr/bin/env bash
    # calendar_extract — mirror upcoming (and recently past) Nextcloud Calendar
    # events into workspace/ai/calendar/ as plain notes, so OpenViking indexes
    # them and pi can answer "what's on my calendar" the same way it answers
    # anything else that lives in workspace/.
    #
    # Why notes instead of a live CalDAV lookup at query time: OpenViking's MCP
    # tool searches an index, not a live API — see note_connect.sh's header for
    # why a department can't just "ask" an external service ad hoc. Turning
    # each event into a note is what makes calendar content reachable the same
    # way everything else in workspace/ is: through search, not a bespoke tool.
    #
    # One markdown file per event under workspace/ai/calendar/<calendar-slug>/,
    # not workspace/<subdir>/: this content is machine-derived from Nextcloud, not
    # something you wrote, and workspace/ai/ is the established home for that —
    # see openviking_index_dir's cron (workspace/ai/ is deliberately NOT excluded
    # from indexing). Writing it fires no Nextcloud file event, and no file
    # handler should match ai/, so content pulled *from* Nextcloud never loops back in.
    #
    # Full-mirror semantics, not an append log: every run recomputes exactly which
    # events currently fall in [-CALENDAR_EXTRACT_PAST_DAYS, +CALENDAR_EXTRACT_FUTURE_DAYS]
    # and deletes any note left over from a previous run whose event no longer
    # does — cancelled, deleted, or simply aged out the back of the window. A
    # manifest of paths written last time (STATE_DIR/files.tsv) is what makes
    # that diff possible without re-querying "what did I write before".
    #
    # Recurring events: requested via CalDAV's expand (RFC 4791/6321), so a
    # weekly meeting comes back as one VEVENT per occurrence in-window, each
    # already carrying its own DTSTART — no RRULE math done here. The one
    # fallback case (an occurrence the server did NOT expand, still carrying an
    # RRULE) is written as a single note describing the series rather than
    # guessed at.
    #
    # Params (the cron file's), exported under these names for caldav.ts:
    #   CALENDAR_EXTRACT_PAST_DAYS     how far back to include, default 7
    #   CALENDAR_EXTRACT_FUTURE_DAYS   how far ahead to include, default 60
    #   CALENDAR_EXTRACT_CALENDARS     comma-separated calendar slugs to include
    #                                  (default: every calendar the user has,
    #                                  e.g. "personal,contact_birthdays")
    #   CALENDAR_EXTRACT_TZ            IANA zone for the human-readable "When:"
    #                                  line, default UTC (all-day dates are always
    #                                  shown in UTC regardless — see caldav.ts)
    #
    # Env vars (passed through the decree container's compose env):
    #   NEXTCLOUD_URL                              default http://nextcloud
    #   NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD
    set -euo pipefail

    export CALENDAR_EXTRACT_PAST_DAYS="$DECREE_DATA_CALENDAR_EXTRACT_PAST_DAYS"
    export CALENDAR_EXTRACT_FUTURE_DAYS="$DECREE_DATA_CALENDAR_EXTRACT_FUTURE_DAYS"
    export CALENDAR_EXTRACT_CALENDARS="$DECREE_DATA_CALENDAR_EXTRACT_CALENDARS"
    export CALENDAR_EXTRACT_TZ="$DECREE_DATA_CALENDAR_EXTRACT_TZ"

    : "${NEXTCLOUD_ADMIN_USER:?NEXTCLOUD_ADMIN_USER is empty — enable nextcloud}"
    : "${NEXTCLOUD_ADMIN_PASSWORD:?NEXTCLOUD_ADMIN_PASSWORD is empty — enable nextcloud}"

    WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
    STATE_DIR="${STATE_DIR:-/data/calendar-extract}"
    OUT_ROOT="${WORKSPACE_DIR}/ai/calendar"
    MANIFEST="${STATE_DIR}/files.tsv"
    mkdir -p "${STATE_DIR}" "${OUT_ROOT}"
    touch "${MANIFEST}"

    # ── Fetch ─────────────────────────────────────────────────────────────────────
    # caldav.ts reads CALENDAR_EXTRACT_* / NEXTCLOUD_* straight from the
    # environment already exported into this process — nothing to pass on argv.

    _events_file=$(mktemp)
    trap 'rm -f "${_events_file}"' EXIT
    if ! tsx "${DECREE_LIB}/caldav.ts" > "${_events_file}"; then
        echo "caldav.ts failed — see output above" >&2
        exit 1
    fi

    if [ ! -s "${_events_file}" ]; then
        echo "No calendars (or no events in the configured window)."
    fi

    # ── Markdown escaping for the YAML frontmatter values below ──────────────────

    yaml_str() { printf '%s' "${1:-}" | tr -d '\r' | tr '\n' ' ' | sed "s/'/''/g"; }

    # ── Write one note per event, tracking what THIS run wrote ────────────────────

    _new_manifest=$(mktemp)
    _written=0 _skipped=0

    while IFS= read -r event; do
        [ -n "$event" ] || continue

        status=$(printf '%s' "$event" | jq -r '.status')
        if [ "$status" = "CANCELLED" ]; then
            _skipped=$((_skipped + 1))
            continue
        fi

        cal_slug=$(printf '%s' "$event" | jq -r '.calendarSlug')
        cal_name=$(printf '%s' "$event" | jq -r '.calendarName')
        uid=$(printf '%s' "$event" | jq -r '.uid')
        summary=$(printf '%s' "$event" | jq -r '.summary')
        description=$(printf '%s' "$event" | jq -r '.description')
        location=$(printf '%s' "$event" | jq -r '.location')
        start=$(printf '%s' "$event" | jq -r '.start')
        end=$(printf '%s' "$event" | jq -r '.end')
        all_day=$(printf '%s' "$event" | jq -r '.allDay')
        recurring=$(printf '%s' "$event" | jq -r '.recurring')
        rrule=$(printf '%s' "$event" | jq -r '.rrule')
        when_text=$(printf '%s' "$event" | jq -r '.whenText')

        [ -n "$cal_slug" ] && [ -n "$uid" ] || { _skipped=$((_skipped + 1)); continue; }

        date_prefix="${start%%T*}"
        title_slug=$(printf '%s' "$summary" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-60)
        uid8=$(printf '%s' "$uid" | sha256sum | cut -c1-8)
        rel_dir="ai/calendar/${cal_slug}"
        rel_path="${rel_dir}/${date_prefix}-${title_slug:-event}-${uid8}.md"
        mkdir -p "${WORKSPACE_DIR}/${rel_dir}"

        {
            printf -- '---\n'
            printf "calendar: '%s'\n"  "$(yaml_str "$cal_name")"
            printf "uid: '%s'\n"       "$(yaml_str "$uid")"
            printf "start: '%s'\n"     "$(yaml_str "$start")"
            printf "end: '%s'\n"       "$(yaml_str "$end")"
            printf "all_day: %s\n"     "${all_day}"
            [ -n "$location" ] && printf "location: '%s'\n" "$(yaml_str "$location")"
            printf -- '---\n\n'
            printf '# %s\n\n' "$summary"
            printf '**When:** %s\n' "$when_text"
            printf '**Calendar:** %s\n' "$cal_name"
            [ -n "$location" ] && printf '**Location:** %s\n' "$location"
            if [ "$recurring" = "true" ] && [ -n "$rrule" ]; then
                printf '**Repeats:** %s (server did not expand this occurrence)\n' "$rrule"
            fi
            if [ -n "$description" ]; then
                printf '\n%s\n' "$description"
            fi
        } > "${WORKSPACE_DIR}/${rel_path}.tmp"
        mv "${WORKSPACE_DIR}/${rel_path}.tmp" "${WORKSPACE_DIR}/${rel_path}"

        printf '%s\n' "$rel_path" >> "${_new_manifest}"
        _written=$((_written + 1))
    done < "${_events_file}"

    # ── Remove notes for events no longer in the window (aged out, cancelled, deleted) ──

    _removed=0
    if [ -s "${MANIFEST}" ]; then
        while IFS= read -r old_rel; do
            [ -n "$old_rel" ] || continue
            grep -qxF "$old_rel" "${_new_manifest}" 2>/dev/null && continue
            rm -f "${WORKSPACE_DIR}/${old_rel}"
            _removed=$((_removed + 1))
        done < "${MANIFEST}"
    fi

    sort -o "${_new_manifest}" "${_new_manifest}"
    mv "${_new_manifest}" "${MANIFEST}"

    echo "calendar-extract: ${_written} note(s) written, ${_skipped} skipped (cancelled/malformed), ${_removed} removed (out of window)."
lib:
  caldav.ts: |
    // Discover CalDAV calendars and fetch events from Nextcloud (or any CalDAV
    // server) as flat, parsed objects. Same house style as rss.ts: hand-rolled
    // regex parsing over the wire format rather than a new npm dependency — the
    // two shapes involved (WebDAV multistatus XML, iCalendar text) are small and
    // stable enough that a full XML/ICS library is more weight than value here.
    //
    // Works as a reusable library OR as a standalone entry point when called
    // directly by tsx (reads NEXTCLOUD_URL / NEXTCLOUD_ADMIN_USER /
    // NEXTCLOUD_ADMIN_PASSWORD / CALENDAR_EXTRACT_* from env, writes one JSON
    // object per line per event to stdout — same contract as rss.ts).

    export interface CalendarInfo {
      href: string;
      slug: string;
      displayName: string;
    }

    export interface CalendarEvent {
      calendarSlug: string;
      calendarName: string;
      uid: string;
      summary: string;
      description: string;
      location: string;
      status: string;
      allDay: boolean;
      start: string; // ISO 8601
      end: string; // ISO 8601
      recurring: boolean; // true when the server did not expand this instance (has an RRULE)
      rrule: string;
      whenText: string; // human-readable, in CALENDAR_EXTRACT_TZ (default UTC)
    }

    function basicAuthHeader(user: string, pass: string): string {
      return "Basic " + Buffer.from(`${user}:${pass}`).toString("base64");
    }

    // Prefix-agnostic tag matcher: SabreDAV is free to pick its own namespace
    // prefixes (observed live: d:, cal:, oc:, x1: ...) and WebDAV/CalDAV clients
    // are required to tolerate whatever the server sends, so matching on local
    // name only is the only response-shape-independent option.
    function extractAll(xml: string, localName: string): string[] {
      const re = new RegExp(`<(?:\\w+:)?${localName}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/(?:\\w+:)?${localName}>`, "gi");
      return [...xml.matchAll(re)].map((m) => m[1]);
    }

    function hasTag(xml: string, localName: string): boolean {
      return new RegExp(`<(?:\\w+:)?${localName}(?:[\\s\\/>])`, "i").test(xml);
    }

    function decodeXmlEntities(s: string): string {
      return s
        .replace(/&quot;/g, '"')
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        // Numeric entities before &amp; — SabreDAV escapes the ICS payload's own
        // CRLF line endings as literal "&#13;" text, so decimal/hex refs (most
        // commonly &#13; for the \r half of CRLF) must resolve to real characters
        // before unfoldIcs's \r\n-based line joining can see them.
        .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)))
        .replace(/&#(\d+);/g, (_, dec) => String.fromCharCode(parseInt(dec, 10)))
        .replace(/&amp;/g, "&");
    }

    export async function discoverCalendars(
      baseUrl: string,
      user: string,
      pass: string,
    ): Promise<CalendarInfo[]> {
      const url = `${baseUrl}/remote.php/dav/calendars/${encodeURIComponent(user)}/`;
      const res = await fetch(url, {
        method: "PROPFIND",
        headers: {
          Authorization: basicAuthHeader(user, pass),
          Depth: "1",
          "Content-Type": "application/xml; charset=utf-8",
        },
        body:
          '<?xml version="1.0" encoding="utf-8" ?>' +
          '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:displayname/></d:prop></d:propfind>',
      });
      if (!(res.status === 207 || res.ok)) {
        throw new Error(`Calendar discovery failed (${res.status}) for ${url}`);
      }
      const xml = await res.text();

      const calendars: CalendarInfo[] = [];
      for (const response of extractAll(xml, "response")) {
        const [href] = extractAll(response, "href");
        if (!href) continue;
        // Only real, writable calendars: excludes the principal itself, the
        // scheduling inbox/outbox (cal:schedule-inbox / cal:schedule-outbox), and
        // the trashbin (nc:trash-bin) — none of those carry a cal:calendar marker
        // in their resourcetype.
        if (!hasTag(response, "calendar")) continue;
        const [displayName] = extractAll(response, "displayname");
        const slug = decodeURIComponent(href.replace(/\/+$/, "").split("/").pop() || "");
        calendars.push({
          href,
          slug,
          displayName: displayName ? decodeXmlEntities(displayName) : slug,
        });
      }
      return calendars;
    }

    // ── iCalendar parsing ─────────────────────────────────────────────────────

    // RFC 5545 line folding: a continuation line starts with a single space or
    // tab and is joined to the previous line with the whitespace dropped.
    function unfoldIcs(text: string): string {
      return text.replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "");
    }

    // RFC 5545 TEXT escaping — the reverse of what a compliant server sends.
    function unescapeIcsText(s: string): string {
      return s
        .replace(/\\n/gi, "\n")
        .replace(/\\,/g, ",")
        .replace(/\\;/g, ";")
        .replace(/\\\\/g, "\\");
    }

    interface IcsProp {
      params: Record<string, string>;
      value: string;
    }

    // Parses one unfolded ICS line into its property name, params, and raw value.
    // Handles the two shapes this routine cares about: "NAME:value" and
    // "NAME;PARAM=x;PARAM2=y:value". Does not handle multi-valued params
    // (PARAM=a,b) — none of the fields extracted below need them.
    function parseLine(line: string): { name: string; prop: IcsProp } | null {
      const colon = line.indexOf(":");
      if (colon === -1) return null;
      const head = line.slice(0, colon);
      const value = line.slice(colon + 1);
      const [name, ...paramParts] = head.split(";");
      const params: Record<string, string> = {};
      for (const part of paramParts) {
        const eq = part.indexOf("=");
        if (eq === -1) continue;
        params[part.slice(0, eq).toUpperCase()] = part.slice(eq + 1);
      }
      return { name: name.toUpperCase(), prop: { params, value } };
    }

    // DTSTART/DTEND come in three shapes: a bare UTC stamp (...Z), a floating
    // local time, or an all-day date (VALUE=DATE, no time component at all).
    // Nextcloud's server timezone is not known here, so anything without a
    // trailing Z is treated as UTC too — close enough for "what day/roughly what
    // time is this", which is the only thing a note needs to convey.
    function parseIcsDateTime(prop: IcsProp): { iso: string; allDay: boolean } {
      const v = prop.value.trim();
      if (prop.params.VALUE === "DATE" || /^\d{8}$/.test(v)) {
        const y = v.slice(0, 4), mo = v.slice(4, 6), d = v.slice(6, 8);
        return { iso: `${y}-${mo}-${d}T00:00:00Z`, allDay: true };
      }
      const m = v.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?$/);
      if (!m) return { iso: new Date().toISOString(), allDay: false };
      const [, y, mo, d, h, mi, s] = m;
      return { iso: `${y}-${mo}-${d}T${h}:${mi}:${s}Z`, allDay: false };
    }

    function formatWhen(startIso: string, endIso: string, allDay: boolean, tz: string): string {
      const start = new Date(startIso);
      const end = new Date(endIso);
      if (allDay) {
        // An all-day value has no time component — it names a calendar day, not
        // an instant. Formatting it in any zone but UTC can shift midnight to
        // the previous day's evening and print the wrong weekday/date entirely.
        const fmt = new Intl.DateTimeFormat("en-US", {
          timeZone: "UTC", weekday: "long", year: "numeric", month: "long", day: "numeric",
        });
        return `${fmt.format(start)} (all day)`;
      }
      const dateFmt = new Intl.DateTimeFormat("en-US", {
        timeZone: tz, weekday: "long", year: "numeric", month: "long", day: "numeric",
      });
      const timeFmt = new Intl.DateTimeFormat("en-US", {
        timeZone: tz, hour: "numeric", minute: "2-digit", timeZoneName: "short",
      });
      const sameDay = dateFmt.format(start) === dateFmt.format(end);
      if (sameDay) {
        return `${dateFmt.format(start)}, ${timeFmt.format(start).replace(/ [A-Z]+$/, "")}–${timeFmt.format(end)}`;
      }
      return `${dateFmt.format(start)} ${timeFmt.format(start)} – ${dateFmt.format(end)} ${timeFmt.format(end)}`;
    }

    // One <cal:calendar-data> block is a full VCALENDAR that may hold more than
    // one VEVENT — a recurring series the server expanded comes back as several
    // VEVENTs sharing a UID, each with its own DTSTART/RECURRENCE-ID.
    export function parseCalendarData(
      raw: string,
      calendarSlug: string,
      calendarName: string,
      tz: string,
    ): CalendarEvent[] {
      const text = unfoldIcs(raw);
      const events: CalendarEvent[] = [];
      for (const block of [...text.matchAll(/BEGIN:VEVENT([\s\S]*?)END:VEVENT/g)].map((m) => m[1])) {
        const props: Record<string, IcsProp> = {};
        for (const rawLine of block.split("\n")) {
          const line = rawLine.trim();
          if (!line) continue;
          const parsed = parseLine(line);
          if (!parsed) continue;
          // First occurrence wins (a VALARM sub-block could carry its own
          // DESCRIPTION; the outer loop only sees VEVENT-level lines here anyway
          // since VALARM is not stripped, so guard against it overwriting).
          if (!(parsed.name in props)) props[parsed.name] = parsed.prop;
        }
        if (!props.DTSTART) continue; // not a real event (e.g. a stray VALARM-only fragment)

        const { iso: start, allDay } = parseIcsDateTime(props.DTSTART);
        const { iso: end } = props.DTEND ? parseIcsDateTime(props.DTEND) : { iso: start };

        events.push({
          calendarSlug,
          calendarName,
          uid: props.UID?.value ?? "",
          summary: props.SUMMARY ? unescapeIcsText(props.SUMMARY.value) : "(untitled event)",
          description: props.DESCRIPTION ? unescapeIcsText(props.DESCRIPTION.value) : "",
          location: props.LOCATION ? unescapeIcsText(props.LOCATION.value) : "",
          status: props.STATUS?.value ?? "",
          allDay,
          start,
          end,
          recurring: Boolean(props.RRULE),
          rrule: props.RRULE?.value ?? "",
          whenText: formatWhen(start, end, allDay, tz),
        });
      }
      return events;
    }

    export async function fetchEvents(
      baseUrl: string,
      user: string,
      pass: string,
      calendar: CalendarInfo,
      startIso: string,
      endIso: string,
      tz: string,
    ): Promise<CalendarEvent[]> {
      // start/end need the ICS UTC form (YYYYMMDDTHHMMSSZ), not a "-" separated
      // ISO string, per RFC 4791's time-range element.
      const toIcsUtc = (iso: string) => iso.replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
      const s = toIcsUtc(startIso);
      const e = toIcsUtc(endIso);

      const url = `${baseUrl}${calendar.href}`;
      const body =
        '<?xml version="1.0" encoding="utf-8" ?>' +
        '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">' +
        "<d:prop><d:getetag/>" +
        `<c:calendar-data><c:expand start="${s}" end="${e}"/></c:calendar-data>` +
        "</d:prop>" +
        "<c:filter><c:comp-filter name=\"VCALENDAR\"><c:comp-filter name=\"VEVENT\">" +
        `<c:time-range start="${s}" end="${e}"/>` +
        "</c:comp-filter></c:comp-filter></c:filter>" +
        "</c:calendar-query>";

      const res = await fetch(url, {
        method: "REPORT",
        headers: {
          Authorization: basicAuthHeader(user, pass),
          Depth: "1",
          "Content-Type": "application/xml; charset=utf-8",
        },
        body,
      });
      if (!(res.status === 207 || res.ok)) {
        throw new Error(`REPORT failed (${res.status}) for ${url}`);
      }
      const xml = await res.text();

      const events: CalendarEvent[] = [];
      for (const response of extractAll(xml, "response")) {
        const [dataBlock] = extractAll(response, "calendar-data");
        if (!dataBlock) continue;
        events.push(...parseCalendarData(decodeXmlEntities(dataBlock), calendar.slug, calendar.displayName, tz));
      }
      return events;
    }

    if (require.main === module) {
      const baseUrl = (process.env.NEXTCLOUD_URL ?? "http://nextcloud").replace(/\/$/, "");
      const user = process.env.NEXTCLOUD_ADMIN_USER ?? "";
      const pass = process.env.NEXTCLOUD_ADMIN_PASSWORD ?? "";
      const pastDays = Number(process.env.CALENDAR_EXTRACT_PAST_DAYS ?? "7");
      const futureDays = Number(process.env.CALENDAR_EXTRACT_FUTURE_DAYS ?? "60");
      const tz = process.env.CALENDAR_EXTRACT_TZ ?? "UTC";
      const include = (process.env.CALENDAR_EXTRACT_CALENDARS ?? "")
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);

      if (!user || !pass) {
        console.error("NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD are required");
        process.exit(1);
      }

      const now = Date.now();
      const startIso = new Date(now - pastDays * 86400000).toISOString();
      const endIso = new Date(now + futureDays * 86400000).toISOString();

      discoverCalendars(baseUrl, user, pass)
        .then(async (calendars) => {
          const wanted = include.length > 0 ? calendars.filter((c) => include.includes(c.slug)) : calendars;
          for (const cal of wanted) {
            const events = await fetchEvents(baseUrl, user, pass, cal, startIso, endIso, tz);
            for (const ev of events) {
              process.stdout.write(JSON.stringify(ev) + "\n");
            }
          }
        })
        .catch((err: Error) => {
          console.error(err.message);
          process.exit(1);
        });
    }
---
# calendar_extract

Mirror Nextcloud Calendar events in a window around today into workspace/ai/calendar/ as one note per event.
