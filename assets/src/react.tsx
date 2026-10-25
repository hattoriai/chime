// Chime in React: a provider, hooks over the client, and an unstyled bell
// and feed with the classes of chime.css.
//
//   import { ChimeProvider, NotificationBell } from "chime/react";
//
//   <ChimeProvider api="/api/v1/notifications">
//     <NotificationBell />
//   </ChimeProvider>

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";

import { createChime } from "./index";
import type { Chime, ChimeOptions, Counts, Filter, Notification, Preferences, Setting } from "./index";

export * from "./index";

const ChimeContext = createContext<Chime | null>(null);

export function ChimeProvider(props: ChimeOptions & { client?: Chime; children: ReactNode }) {
  const { client, children, ...options } = props;
  const chime = useMemo(() => client ?? createChime(options), [client, options.api, options.workspace]);
  return <ChimeContext.Provider value={chime}>{children}</ChimeContext.Provider>;
}

/** The client of the nearest ChimeProvider. */
export function useChime(): Chime {
  const chime = useContext(ChimeContext);
  if (!chime) throw new Error("Chime: useChime needs a <ChimeProvider>");
  return chime;
}

/** The person's counts, live. */
export function useCounts(): Counts {
  const chime = useChime();
  const [counts, setCounts] = useState<Counts>({ unseen: 0, unread: 0 });
  useEffect(() => chime.subscribe((_event, counts) => setCounts(counts)), [chime]);
  return counts;
}

/** The person's feed and counts, live, and what they do with it. */
export function useNotifications(opts: { limit?: number; filter?: Filter } = {}) {
  const chime = useChime();
  const limit = opts.limit ?? 20;
  const [filter, setFilter] = useState<Filter>(opts.filter ?? "inbox");
  const [counts, setCounts] = useState<Counts>({ unseen: 0, unread: 0 });
  const [items, setItems] = useState<Notification[]>([]);
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
    [chime, filter],
  );

  useEffect(() => {
    load(limit);
    return chime.subscribe((event, counts) => {
      setCounts(counts);
      if (event !== "counts") load();
    });
  }, [chime, load, limit]);

  const then = (promise: Promise<Counts>) =>
    promise.then((counts) => {
      setCounts({ unseen: counts.unseen, unread: counts.unread });
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
    markRead: (id: string) => then(chime.markRead(id)),
    markUnread: (id: string) => then(chime.markUnread(id)),
    readAll: () => then(chime.readAll()),
    archive: (id: string) => then(chime.archive(id)),
    act: async (id: string, action: string) => {
      const result = await chime.act(id, action);
      await then(Promise.resolve(result));
      return result;
    },
  };
}

/** The person's preferences, and a change of one. */
export function usePreferences() {
  const chime = useChime();
  const [preferences, setPreferences] = useState<Preferences | null>(null);
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    chime.preferences().then(setPreferences, setError);
  }, [chime]);

  const set = (category: string, channel: string, setting: Setting) =>
    chime.setPreferences({ [category]: { [channel]: setting } }).then(setPreferences, (e) => {
      setError(e);
      throw e;
    });

  return { preferences, error, set };
}

/** The bell: a dot while there is something not seen. */
export function Bell(props: { counts: Counts; open?: boolean; onClick?: () => void; label?: string; showCount?: boolean }) {
  const { counts, open, onClick, label = "Notifications", showCount = false } = props;
  return (
    <button type="button" className="chime-bell" aria-label={label} aria-haspopup="dialog" aria-expanded={open ?? false} onClick={onClick}>
      <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" />
        <path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
      </svg>
      {counts.unseen > 0 && !showCount && <span className="chime-dot" aria-hidden="true" />}
      {showCount && counts.unread > 0 && <span className="chime-count">{counts.unread}</span>}
    </button>
  );
}

/** The bell and its feed: opening it marks the feed seen; a click on a
 *  notification reads it and goes to its url. */
export function NotificationBell(props: {
  limit?: number;
  onNavigate?: (url: string) => void;
  words?: Partial<Record<"title" | "empty" | "readAll" | "more" | "all" | "unread" | "archive", string>>;
}) {
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
    ...props.words,
  };
  const go = (url: string | null) => {
    if (!url) return;
    if (props.onNavigate) props.onNavigate(url);
    else globalThis.location.assign(url);
  };

  return (
    <div className="chime">
      <Bell
        counts={feed.counts}
        open={open}
        label={words.title}
        onClick={() => {
          if (!open) feed.markSeen();
          setOpen(!open);
        }}
      />
      {open && (
        <div className="chime-feed" role="dialog" aria-label={words.title}>
          <header className="chime-feed-header">
            <h2>{words.title}</h2>
            {feed.counts.unread > 0 && (
              <button type="button" className="chime-read-all" onClick={feed.readAll}>
                {words.readAll}
              </button>
            )}
          </header>
          <nav className="chime-filters">
            <button type="button" aria-pressed={feed.filter === "inbox"} onClick={() => feed.setFilter("inbox")}>
              {words.all}
            </button>
            <button type="button" aria-pressed={feed.filter === "unread"} onClick={() => feed.setFilter("unread")}>
              {words.unread}
            </button>
          </nav>
          {feed.items.length === 0 && !feed.loading && <p className="chime-empty">{words.empty}</p>}
          <ul className="chime-items">
            {feed.items.map((n) => (
              <li key={n.id} className={n.read ? "chime-item" : "chime-item chime-unread"} data-kind={n.kind}>
                <button type="button" className="chime-item-open" onClick={() => feed.markRead(n.id).then(() => go(n.url))}>
                  <span className="chime-item-title">{n.title}</span>
                  {n.body && <span className="chime-item-body">{n.body}</span>}
                  <time className="chime-item-time" dateTime={n.updatedAt}>
                    {new Date(n.updatedAt).toLocaleString()}
                  </time>
                </button>
                {n.actions.length > 0 && !n.action && (
                  <div className="chime-item-actions">
                    {n.actions.map((a) => (
                      <button key={a.key} type="button" className="chime-action" onClick={() => feed.act(n.id, a.key).then((r) => go(r.url))}>
                        {a.label}
                      </button>
                    ))}
                  </div>
                )}
                <button type="button" className="chime-item-archive" aria-label={words.archive} title={words.archive} onClick={() => feed.archive(n.id)}>
                  ×
                </button>
              </li>
            ))}
          </ul>
          {feed.more && (
            <button type="button" className="chime-more" onClick={feed.loadMore}>
              {words.more}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
