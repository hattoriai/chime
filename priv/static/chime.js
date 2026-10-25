// src/index.ts
var ChimeError = class extends Error {
  constructor(status, code, body) {
    super(`Chime: ${status} ${code}`);
    this.status = status;
    this.code = code;
    this.body = body;
  }
};
function createChime(options) {
  const api = options.api.replace(/\/$/, "");
  const doFetch = options.fetch ?? globalThis.fetch.bind(globalThis);
  const csrf = () => options.csrfToken !== void 0 ? options.csrfToken : globalThis.document?.querySelector("meta[name='csrf-token']")?.getAttribute("content") ?? null;
  const token = async () => typeof options.token === "function" ? await options.token() : options.token ?? null;
  const url = (path, query = {}) => {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries({ ...query, workspace: options.workspace })) {
      if (value !== void 0 && value !== null) params.set(key, String(value));
    }
    const search = params.toString();
    return api + path + (search ? `?${search}` : "");
  };
  async function request(method, path, body, query) {
    const headers = { accept: "application/json" };
    const bearer = await token();
    if (bearer) headers.authorization = `Bearer ${bearer}`;
    if (body !== void 0) headers["content-type"] = "application/json";
    const csrfToken = method === "GET" ? null : csrf();
    if (csrfToken) headers["x-csrf-token"] = csrfToken;
    const response = await doFetch(url(path, query), {
      method,
      headers,
      credentials: bearer ? "omit" : "same-origin",
      body: body === void 0 ? void 0 : JSON.stringify(body)
    });
    const json = await response.json().catch(() => ({}));
    if (!response.ok) throw new ChimeError(response.status, json.error ?? "error", json);
    return json;
  }
  const post = (path, body) => request("POST", path, body);
  return {
    feed: (opts = {}) => request("GET", "/", void 0, opts),
    counts: () => request("GET", "/counts"),
    markSeen: () => post("/seen"),
    readAll: () => post("/read"),
    markRead: (id) => post(`/${id}/read`),
    markUnread: (id) => post(`/${id}/unread`),
    archive: (id) => post(`/${id}/archive`),
    unarchive: (id) => post(`/${id}/unarchive`),
    act: (id, action) => post(`/${id}/actions/${encodeURIComponent(action)}`),
    preferences: () => request("GET", "/preferences"),
    setPreferences: (changes) => request("PUT", "/preferences", { preferences: changes }),
    devices: () => request("GET", "/devices").then((r) => r.devices),
    registerDevice: (device) => post("/devices", device).then((r) => r.device),
    updateDevice: (id, changes) => request("PATCH", `/devices/${id}`, changes).then((r) => r.device),
    removeDevice: (id) => request("DELETE", `/devices/${id}`),
    /** Asks the browser for push, subscribes it with the app's VAPID key,
     *  and registers it: the device, or null when the person said no. */
    async enableWebPush(opts = {}) {
      const { vapidPublicKey } = await request("GET", "/push");
      if (!vapidPublicKey) throw new Error("Chime: the app has no Web Push (:web of :push)");
      const registration = await navigator.serviceWorker.register(opts.serviceWorker ?? "/chime-sw.js");
      if (await Notification.requestPermission() !== "granted") return null;
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: vapidPublicKey
      });
      const { endpoint, keys } = subscription.toJSON();
      return post("/devices", {
        kind: "web",
        token: endpoint,
        keys,
        name: opts.name ?? navigator.userAgent
      }).then((r) => r.device);
    },
    /** The person's live news, as the stream of the API gives it: "counts"
     *  at once, "notified" when one comes, "updated" when they see or read
     *  in another tab. Returns the function that stops it. */
    subscribe(listener) {
      const Source = options.EventSource ?? globalThis.EventSource;
      let source = null;
      let stopped = false;
      (async () => {
        let bearer = await token();
        if (bearer) bearer = (await post("/token")).token;
        if (stopped) return;
        source = new Source(url("/stream", { token: bearer ?? void 0 }), { withCredentials: !bearer });
        for (const event of ["counts", "notified", "updated"]) {
          source.addEventListener(event, (e) => listener(event, JSON.parse(e.data)));
        }
      })();
      return () => {
        stopped = true;
        source?.close();
      };
    }
  };
}
export {
  ChimeError,
  createChime
};
