import type { ReactNode } from "react";
import type { Chime, ChimeOptions, Counts, Filter, Notification, Preferences, Setting } from "./index";
export * from "./index";
export declare function ChimeProvider(props: ChimeOptions & {
    client?: Chime;
    children: ReactNode;
}): import("react/jsx-runtime").JSX.Element;
/** The client of the nearest ChimeProvider. */
export declare function useChime(): Chime;
/** The person's counts, live. */
export declare function useCounts(): Counts;
/** The person's feed and counts, live, and what they do with it. */
export declare function useNotifications(opts?: {
    limit?: number;
    filter?: Filter;
}): {
    counts: Counts;
    items: Notification[];
    more: boolean;
    loading: boolean;
    filter: Filter;
    setFilter: import("react").Dispatch<import("react").SetStateAction<Filter>>;
    loadMore: () => Promise<void>;
    refresh: () => Promise<void>;
    markSeen: () => Promise<void>;
    markRead: (id: string) => Promise<void>;
    markUnread: (id: string) => Promise<void>;
    readAll: () => Promise<void>;
    archive: (id: string) => Promise<void>;
    act: (id: string, action: string) => Promise<Counts & {
        action: string;
        url: string | null;
    }>;
};
/** The person's preferences, and a change of one. */
export declare function usePreferences(): {
    preferences: Preferences | null;
    error: unknown;
    set: (category: string, channel: string, setting: Setting) => Promise<void>;
};
/** The bell: a dot while there is something not seen. */
export declare function Bell(props: {
    counts: Counts;
    open?: boolean;
    onClick?: () => void;
    label?: string;
    showCount?: boolean;
}): import("react/jsx-runtime").JSX.Element;
/** The bell and its feed: opening it marks the feed seen; a click on a
 *  notification reads it and goes to its url. */
export declare function NotificationBell(props: {
    limit?: number;
    onNavigate?: (url: string) => void;
    words?: Partial<Record<"title" | "empty" | "readAll" | "more" | "all" | "unread" | "archive", string>>;
}): import("react/jsx-runtime").JSX.Element;
