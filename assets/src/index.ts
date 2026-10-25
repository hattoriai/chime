// Chime's client: the JSON API of `chime_api`, for any frontend.
//
//   import { createChime } from "chime";
//
//   const chime = createChime({ api: "/api/v1/notifications" });
//   const { notifications, unseen } = await chime.feed();
//   const stop = chime.subscribe((event, counts) => console.log(event, counts));

export type Counts = { unseen: number; unread: number };

export type Action = { key: string; label: string };

export type Notification = {
  id: string;
  kind: string;
  category: string;
  title: string;
  body: string | null;
  url: string | null;
  icon: string | null;
  actions: Action[];
  action: string | null;
  extra: Record<string, unknown>;
  count: number;
  actors: { id: string; name: string }[];
  seen: boolean;
  read: boolean;
  archived: boolean;
  seenAt: string | null;
  readAt: string | null;
  archivedAt: string | null;
  actedAt: string | null;
  clickedAt: string | null;
  insertedAt: string;
  updatedAt: string;
};

export type FeedPage = Counts & { notifications: Notification[]; more: boolean };

export type Filter = "inbox" | "unread" | "archived" | "all";

export type Setting = "on" | "off" | "daily" | "weekly";

export type Preferences = {
  categories: {
    key: string;
    label: string;
    description: string | null;
    required: boolean;
    settings: Record<string, Setting>;
  }[];
  channels: { key: string; settings: Setting[] }[];
};

export type Device = {
  id: string;
  kind: "web" | "apns" | "fcm";
  name: string | null;
  enabled: boolean;
  lastUsedAt: string | null;
  insertedAt: string;
};

export type StreamEvent = "counts" | "notified" | "updated";

export type ChimeOptions = {
  /** Where `chime_api` is mounted: "/api/v1/notifications". */
  api: string;
  /** A token of `Chime.Token`, or a function that gives one, for a page on
   *  another origin or an API of bearer tokens. Without it, the session's
   *  cookie. */
  token?: string | (() => string | Promise<string>);
  /** The workspace of the requests (`?workspace=`), or the resolver's. */
  workspace?: string;
  /** The CSRF token of the session, for a POST behind `protect_from_forgery`:
   *  by default, the page's `<meta name="csrf-token">`. */
  csrfToken?: string | null;
  fetch?: typeof fetch;
  EventSource?: typeof EventSource;
};

export class ChimeError extends Error {
  readonly status: number;
  readonly code: string;
  readonly body: unknown;

  constructor(status: number, code: string, body: unknown) {
    super(`Chime: ${status} ${code}`);
    this.status = status;
    this.code = code;
    this.body = body;
  }
}

export type Chime = ReturnType<typeof createChime>;

export function createChime(options: ChimeOptions) {
  const api = options.api.replace(/\/$/, "");
  const doFetch = options.fetch ?? globalThis.fetch.bind(globalThis);

  const csrf = () =>
    options.csrfToken !== undefined
      ? options.csrfToken
      : (globalThis.document?.querySelector("meta[name='csrf-token']")?.getAttribute("content") ?? null);

  const token = async () =>
    typeof options.token === "function" ? await options.token() : (options.token ?? null);

  const url = (path: string, query: Record<string, string | number | undefined> = {}) => {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries({ ...query, workspace: options.workspace })) {
      if (value !== undefined && value !== null) params.set(key, String(value));
    }
    const search = params.toString();
    return api + path + (search ? `?${search}` : "");
  };

  async function request<T>(method: string, path: string, body?: unknown, query?: Record<string, string | number | undefined>): Promise<T> {
    const headers: Record<string, string> = { accept: "application/json" };
    const bearer = await token();
    if (bearer) headers.authorization = `Bearer ${bearer}`;
    if (body !== undefined) headers["content-type"] = "application/json";
    const csrfToken = method === "GET" ? null : csrf();
    if (csrfToken) headers["x-csrf-token"] = csrfToken;

    const response = await doFetch(url(path, query), {
      method,
      headers,
      credentials: bearer ? "omit" : "same-origin",
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    const json = await response.json().catch(() => ({}));
    if (!response.ok) throw new ChimeError(response.status, (json as { error?: string }).error ?? "error", json);
    return json as T;
  }

  const post = <T = Counts>(path: string, body?: unknown) => request<T>("POST", path, body);

  return {
    feed: (opts: { before?: string; limit?: number; filter?: Filter } = {}) =>
      request<FeedPage>("GET", "/", undefined, opts),
    counts: () => request<Counts>("GET", "/counts"),
    markSeen: () => post("/seen"),
    readAll: () => post("/read"),
    markRead: (id: string) => post(`/${id}/read`),
    markUnread: (id: string) => post(`/${id}/unread`),
    archive: (id: string) => post(`/${id}/archive`),
    unarchive: (id: string) => post(`/${id}/unarchive`),
    act: (id: string, action: string) =>
      post<Counts & { action: string; url: string | null }>(`/${id}/actions/${encodeURIComponent(action)}`),

    preferences: () => request<Preferences>("GET", "/preferences"),
    setPreferences: (changes: Record<string, Record<string, Setting>>) =>
      request<Preferences>("PUT", "/preferences", { preferences: changes }),

    devices: () => request<{ devices: Device[] }>("GET", "/devices").then((r) => r.devices),
    registerDevice: (device: { kind: Device["kind"]; token: string; keys?: Record<string, string>; name?: string }) =>
      post<{ device: Device }>("/devices", device).then((r) => r.device),
    updateDevice: (id: string, changes: { enabled?: boolean; name?: string }) =>
      request<{ device: Device }>("PATCH", `/devices/${id}`, changes).then((r) => r.device),
    removeDevice: (id: string) => request<{ removed: boolean }>("DELETE", `/devices/${id}`),

    /** Asks the browser for push, subscribes it with the app's VAPID key,
     *  and registers it: the device, or null when the person said no. */
    async enableWebPush(opts: { serviceWorker?: string; name?: string } = {}): Promise<Device | null> {
      const { vapidPublicKey } = await request<{ vapidPublicKey: string | null }>("GET", "/push");
      if (!vapidPublicKey) throw new Error("Chime: the app has no Web Push (:web of :push)");
      const registration = await navigator.serviceWorker.register(opts.serviceWorker ?? "/chime-sw.js");
      if ((await Notification.requestPermission()) !== "granted") return null;

      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: vapidPublicKey,
      });

      const { endpoint, keys } = subscription.toJSON();
      return post<{ device: Device }>("/devices", {
        kind: "web",
        token: endpoint,
        keys,
        name: opts.name ?? navigator.userAgent,
      }).then((r) => r.device);
    },

    /** The person's live news, as the stream of the API gives it: "counts"
     *  at once, "notified" when one comes, "updated" when they see or read
     *  in another tab. Returns the function that stops it. */
    subscribe(listener: (event: StreamEvent, counts: Counts) => void): () => void {
      const Source = options.EventSource ?? globalThis.EventSource;
      let source: EventSource | null = null;
      let stopped = false;

      // An EventSource sends no headers: with a bearer (the app's own, or
      // Chime's), the API gives a token of Chime's for the address.
      (async () => {
        let bearer = await token();
        if (bearer) bearer = (await post<{ token: string }>("/token")).token;
        if (stopped) return;
        source = new Source(url("/stream", { token: bearer ?? undefined }), { withCredentials: !bearer });
        for (const event of ["counts", "notified", "updated"] as const) {
          source.addEventListener(event, (e) => listener(event, JSON.parse((e as MessageEvent).data)));
        }
      })();

      return () => {
        stopped = true;
        source?.close();
      };
    },
  };
}
