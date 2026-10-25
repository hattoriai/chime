// Chime's service worker: the app's Web Push notifications, shown, and
// opened on a click. Serve it from the app's root (/chime-sw.js) and
// register it with navigator.serviceWorker.register("/chime-sw.js"), or
// copy these two listeners into the app's own service worker.

self.addEventListener("push", (event) => {
  if (!event.data) return;
  const push = event.data.json();

  event.waitUntil(
    self.registration.showNotification(push.title, {
      body: push.body || undefined,
      icon: push.icon || undefined,
      badge: push.badge || undefined,
      image: push.image || undefined,
      // A newer push of the same group replaces this one.
      tag: push.tag || undefined,
      renotify: Boolean(push.tag),
      data: { url: push.url, id: push.id },
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  // The url is Chime's link: it reads the notification in the feed, then
  // goes to its page.
  const url = event.notification.data && event.notification.data.url;
  if (!url) return;

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((windows) => {
      for (const client of windows) {
        if ("navigate" in client && client.url.startsWith(self.location.origin)) {
          return client.focus().then(() => client.navigate(url));
        }
      }
      return self.clients.openWindow(url);
    })
  );
});
