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
