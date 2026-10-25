import { test } from "node:test";
import assert from "node:assert/strict";

import { ChimeError, createChime } from "../src/index.ts";

type Call = { url: string; init: RequestInit };

function fakeFetch(responses: Record<string, unknown>, status = 200) {
  const calls: Call[] = [];
  const fetch = async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    const key = `${init.method} ${url}`;
    const body = key in responses ? responses[key] : { unseen: 0, unread: 0 };
    return new Response(JSON.stringify(body), { status });
  };
  return { calls, fetch: fetch as unknown as typeof globalThis.fetch };
}

class FakeEventSource {
  static last: FakeEventSource | null = null;
  listeners: Record<string, (e: { data: string }) => void> = {};
  closed = false;
  url: string;
  init: EventSourceInit;
  constructor(url: string, init: EventSourceInit) {
    this.url = url;
    this.init = init;
    FakeEventSource.last = this;
  }
  addEventListener(event: string, listener: (e: { data: string }) => void) {
    this.listeners[event] = listener;
  }
  close() {
    this.closed = true;
  }
}

const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

test("the feed's query, with the workspace", async () => {
  const { calls, fetch } = fakeFetch({
    "GET /api/n/?limit=5&filter=unread&workspace=acme": { notifications: [], more: false, unseen: 1, unread: 2 },
  });
  const chime = createChime({ api: "/api/n/", workspace: "acme", fetch, csrfToken: null });

  const page = await chime.feed({ limit: 5, filter: "unread" });

  assert.deepEqual(page, { notifications: [], more: false, unseen: 1, unread: 2 });
  assert.equal(calls[0].init.credentials, "same-origin");
});

test("a POST carries the CSRF token, and a bearer leaves the cookie out", async () => {
  const { calls, fetch } = fakeFetch({});
  await createChime({ api: "/n", fetch, csrfToken: "csrf" }).markRead("abc");
  await createChime({ api: "/n", fetch, token: () => "tok" }).archive("abc");

  const [read, archive] = calls;
  assert.equal(read.url, "/n/abc/read");
  assert.equal((read.init.headers as Record<string, string>)["x-csrf-token"], "csrf");
  assert.equal(archive.init.credentials, "omit");
  assert.equal((archive.init.headers as Record<string, string>).authorization, "Bearer tok");
});

test("an action's key is in its path", async () => {
  const { calls, fetch } = fakeFetch({ "POST /n/abc/actions/say%20yes": { unseen: 0, unread: 0, action: "say yes", url: "/x" } });
  const result = await createChime({ api: "/n", fetch, csrfToken: null }).act("abc", "say yes");
  assert.equal(result.url, "/x");
  assert.equal(calls[0].url, "/n/abc/actions/say%20yes");
});

test("a failed request throws a ChimeError with the API's code", async () => {
  const { fetch } = fakeFetch({ "GET /n/counts": { error: "unauthorized" } }, 401);
  await assert.rejects(createChime({ api: "/n", fetch }).counts(), (error: unknown) => {
    assert.ok(error instanceof ChimeError);
    assert.equal(error.status, 401);
    assert.equal(error.code, "unauthorized");
    return true;
  });
});

test("the stream with the cookie, and its events", async () => {
  const { fetch } = fakeFetch({});
  const chime = createChime({ api: "/n", fetch, EventSource: FakeEventSource as unknown as typeof EventSource });
  const events: [string, unknown][] = [];

  const stop = chime.subscribe((event, counts) => events.push([event, counts]));
  await tick();
  const source = FakeEventSource.last!;
  source.listeners.notified({ data: '{"unseen":1,"unread":1}' });
  stop();

  assert.equal(source.url, "/n/stream");
  assert.deepEqual(source.init, { withCredentials: true });
  assert.deepEqual(events, [["notified", { unseen: 1, unread: 1 }]]);
  assert.ok(source.closed);
});

test("the stream with a bearer takes a token of Chime's for its address", async () => {
  const { calls, fetch } = fakeFetch({ "POST /n/token": { token: "chime-token" } });
  const chime = createChime({ api: "/n", fetch, token: "app-token", EventSource: FakeEventSource as unknown as typeof EventSource });

  chime.subscribe(() => {});
  await tick();
  await tick();

  assert.equal(calls[0].url, "/n/token");
  assert.equal(FakeEventSource.last!.url, "/n/stream?token=chime-token");
  assert.deepEqual(FakeEventSource.last!.init, { withCredentials: false });
});
