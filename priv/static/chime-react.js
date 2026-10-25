// src/react.tsx
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { createChime } from "./chime.js";
export * from "./chime.js";
import { jsx, jsxs } from "react/jsx-runtime";
var ChimeContext = createContext(null);
function ChimeProvider(props) {
  const { client, children, ...options } = props;
  const chime = useMemo(() => client ?? createChime(options), [client, options.api, options.workspace]);
  return /* @__PURE__ */ jsx(ChimeContext.Provider, { value: chime, children });
}
function useChime() {
  const chime = useContext(ChimeContext);
  if (!chime) throw new Error("Chime: useChime needs a <ChimeProvider>");
  return chime;
}
function useCounts() {
  const chime = useChime();
  const [counts, setCounts] = useState({ unseen: 0, unread: 0 });
  useEffect(() => chime.subscribe((_event, counts2) => setCounts(counts2)), [chime]);
  return counts;
}
function useNotifications(opts = {}) {
  const chime = useChime();
  const limit = opts.limit ?? 20;
  const [filter, setFilter] = useState(opts.filter ?? "inbox");
  const [counts, setCounts] = useState({ unseen: 0, unread: 0 });
  const [items, setItems] = useState([]);
  const [more, setMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const shown = useRef(limit);
  const load = useCallback(
    async (count = shown.current) => {
      const page = await chime.feed({ limit: count, filter });
      shown.current = count;
      setItems(page.notifications);
      setMore(page.more);
      setCounts({ unseen: page.unseen, unread: page.unread });
      setLoading(false);
    },
    [chime, filter]
  );
  useEffect(() => {
    load(limit);
    return chime.subscribe((event, counts2) => {
      setCounts(counts2);
      if (event !== "counts") load();
    });
  }, [chime, load, limit]);
  const then = (promise) => promise.then((counts2) => {
    setCounts({ unseen: counts2.unseen, unread: counts2.unread });
    return load();
  });
  return {
    counts,
    items,
    more,
    loading,
    filter,
    setFilter,
    loadMore: () => load(shown.current + limit),
    refresh: () => load(),
    markSeen: () => then(chime.markSeen()),
    markRead: (id) => then(chime.markRead(id)),
    markUnread: (id) => then(chime.markUnread(id)),
    readAll: () => then(chime.readAll()),
    archive: (id) => then(chime.archive(id)),
    act: async (id, action) => {
      const result = await chime.act(id, action);
      await then(Promise.resolve(result));
      return result;
    }
  };
}
function usePreferences() {
  const chime = useChime();
  const [preferences, setPreferences] = useState(null);
  const [error, setError] = useState(null);
  useEffect(() => {
    chime.preferences().then(setPreferences, setError);
  }, [chime]);
  const set = (category, channel, setting) => chime.setPreferences({ [category]: { [channel]: setting } }).then(setPreferences, (e) => {
    setError(e);
    throw e;
  });
  return { preferences, error, set };
}
function Bell(props) {
  const { counts, open, onClick, label = "Notifications", showCount = false } = props;
  return /* @__PURE__ */ jsxs("button", { type: "button", className: "chime-bell", "aria-label": label, "aria-haspopup": "dialog", "aria-expanded": open ?? false, onClick, children: [
    /* @__PURE__ */ jsxs("svg", { viewBox: "0 0 24 24", width: "20", height: "20", fill: "none", stroke: "currentColor", strokeWidth: "1.75", strokeLinecap: "round", strokeLinejoin: "round", "aria-hidden": "true", children: [
      /* @__PURE__ */ jsx("path", { d: "M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" }),
      /* @__PURE__ */ jsx("path", { d: "M10.3 21a1.94 1.94 0 0 0 3.4 0" })
    ] }),
    counts.unseen > 0 && !showCount && /* @__PURE__ */ jsx("span", { className: "chime-dot", "aria-hidden": "true" }),
    showCount && counts.unread > 0 && /* @__PURE__ */ jsx("span", { className: "chime-count", children: counts.unread })
  ] });
}
function NotificationBell(props) {
  const feed = useNotifications({ limit: props.limit ?? 10 });
  const [open, setOpen] = useState(false);
  const words = {
    title: "Notifications",
    empty: "Nothing yet.",
    readAll: "Mark all as read",
    more: "Show more",
    all: "All",
    unread: "Unread",
    archive: "Archive",
    ...props.words
  };
  const go = (url) => {
    if (!url) return;
    if (props.onNavigate) props.onNavigate(url);
    else globalThis.location.assign(url);
  };
  return /* @__PURE__ */ jsxs("div", { className: "chime", children: [
    /* @__PURE__ */ jsx(
      Bell,
      {
        counts: feed.counts,
        open,
        label: words.title,
        onClick: () => {
          if (!open) feed.markSeen();
          setOpen(!open);
        }
      }
    ),
    open && /* @__PURE__ */ jsxs("div", { className: "chime-feed", role: "dialog", "aria-label": words.title, children: [
      /* @__PURE__ */ jsxs("header", { className: "chime-feed-header", children: [
        /* @__PURE__ */ jsx("h2", { children: words.title }),
        feed.counts.unread > 0 && /* @__PURE__ */ jsx("button", { type: "button", className: "chime-read-all", onClick: feed.readAll, children: words.readAll })
      ] }),
      /* @__PURE__ */ jsxs("nav", { className: "chime-filters", children: [
        /* @__PURE__ */ jsx("button", { type: "button", "aria-pressed": feed.filter === "inbox", onClick: () => feed.setFilter("inbox"), children: words.all }),
        /* @__PURE__ */ jsx("button", { type: "button", "aria-pressed": feed.filter === "unread", onClick: () => feed.setFilter("unread"), children: words.unread })
      ] }),
      feed.items.length === 0 && !feed.loading && /* @__PURE__ */ jsx("p", { className: "chime-empty", children: words.empty }),
      /* @__PURE__ */ jsx("ul", { className: "chime-items", children: feed.items.map((n) => /* @__PURE__ */ jsxs("li", { className: n.read ? "chime-item" : "chime-item chime-unread", "data-kind": n.kind, children: [
        /* @__PURE__ */ jsxs("button", { type: "button", className: "chime-item-open", onClick: () => feed.markRead(n.id).then(() => go(n.url)), children: [
          /* @__PURE__ */ jsx("span", { className: "chime-item-title", children: n.title }),
          n.body && /* @__PURE__ */ jsx("span", { className: "chime-item-body", children: n.body }),
          /* @__PURE__ */ jsx("time", { className: "chime-item-time", dateTime: n.updatedAt, children: new Date(n.updatedAt).toLocaleString() })
        ] }),
        n.actions.length > 0 && !n.action && /* @__PURE__ */ jsx("div", { className: "chime-item-actions", children: n.actions.map((a) => /* @__PURE__ */ jsx("button", { type: "button", className: "chime-action", onClick: () => feed.act(n.id, a.key).then((r) => go(r.url)), children: a.label }, a.key)) }),
        /* @__PURE__ */ jsx("button", { type: "button", className: "chime-item-archive", "aria-label": words.archive, title: words.archive, onClick: () => feed.archive(n.id), children: "\xD7" })
      ] }, n.id)) }),
      feed.more && /* @__PURE__ */ jsx("button", { type: "button", className: "chime-more", onClick: feed.loadMore, children: words.more })
    ] })
  ] });
}
export {
  Bell,
  ChimeProvider,
  NotificationBell,
  useChime,
  useCounts,
  useNotifications,
  usePreferences
};
