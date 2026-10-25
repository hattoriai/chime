export type Counts = {
    unseen: number;
    unread: number;
};
export type Action = {
    key: string;
    label: string;
};
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
    actors: {
        id: string;
        name: string;
    }[];
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
export type FeedPage = Counts & {
    notifications: Notification[];
    more: boolean;
};
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
    channels: {
        key: string;
        settings: Setting[];
    }[];
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
export declare class ChimeError extends Error {
    readonly status: number;
    readonly code: string;
    readonly body: unknown;
    constructor(status: number, code: string, body: unknown);
}
export type Chime = ReturnType<typeof createChime>;
export declare function createChime(options: ChimeOptions): {
    feed: (opts?: {
        before?: string;
        limit?: number;
        filter?: Filter;
    }) => Promise<FeedPage>;
    counts: () => Promise<Counts>;
    markSeen: () => Promise<Counts>;
    readAll: () => Promise<Counts>;
    markRead: (id: string) => Promise<Counts>;
    markUnread: (id: string) => Promise<Counts>;
    archive: (id: string) => Promise<Counts>;
    unarchive: (id: string) => Promise<Counts>;
    act: (id: string, action: string) => Promise<Counts & {
        action: string;
        url: string | null;
    }>;
    preferences: () => Promise<Preferences>;
    setPreferences: (changes: Record<string, Record<string, Setting>>) => Promise<Preferences>;
    devices: () => Promise<Device[]>;
    registerDevice: (device: {
        kind: Device["kind"];
        token: string;
        keys?: Record<string, string>;
        name?: string;
    }) => Promise<Device>;
    updateDevice: (id: string, changes: {
        enabled?: boolean;
        name?: string;
    }) => Promise<Device>;
    removeDevice: (id: string) => Promise<{
        removed: boolean;
    }>;
    /** Asks the browser for push, subscribes it with the app's VAPID key,
     *  and registers it: the device, or null when the person said no. */
    enableWebPush(opts?: {
        serviceWorker?: string;
        name?: string;
    }): Promise<Device | null>;
    /** The person's live news, as the stream of the API gives it: "counts"
     *  at once, "notified" when one comes, "updated" when they see or read
     *  in another tab. Returns the function that stops it. */
    subscribe(listener: (event: StreamEvent, counts: Counts) => void): () => void;
};
