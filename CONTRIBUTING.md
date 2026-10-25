# Contributing to Chime

Thank you for helping. This page says what to open (an issue, a pull
request, or a security report), what a pull request needs, and what the
maintainers keep for themselves. How to run the tests is in the README,
under [Development](README.md#development).

## Questions, bugs and ideas

- **A bug.** Open an issue with the bug report form. The smallest setup
  that shows it (the notifier, the resolver, the options given to
  `Chime`, and the mount if it matters) is the most useful thing you can
  give.
- **An idea or a change of behaviour.** Open an issue with the feature
  request form, and say the problem before the solution.
- **A security problem.** Do not open an issue. See
  [SECURITY.md](SECURITY.md).

Search the open and closed issues first: the idea may already be planned,
or turned down for a reason given there. [BACKLOG.md](https://github.com/hattoriai/chime/blob/main/BACKLOG.md) has the
known gaps.

## When a pull request needs an issue first

Open an issue, and agree on the change there, before a pull request that:

- adds a feature, an option, a mount, a channel, or a callback of
  `Chime.Notifier`, `Chime.Resolver` or `Chime.Channel`;
- changes what a notification, a delivery, the feed, the preferences,
  the JSON API or the components do, or the public API;
- changes the tables (a new version of `Chime.Migrations`), or the JSON
  of the API or of its stream;
- adds a dependency;
- touches many files, or needs a design decision.

A pull request does not need an issue when it is small and its reason is
plain from the diff: a typo, a broken link, a wrong sentence in a guide,
or a bug fix with a test that fails without it. When in doubt, open the
issue: a short discussion costs less than a pull request that is not
merged.

A pull request with an issue says so: `Fixes #123` or `Closes #123`.

## A pull request

- **One change.** A fix, the guide for an unrelated case and a README
  edit are three pull requests. Each is reviewed, reverted and released
  on its own.
- **Why, not only what.** The description says the problem the change
  solves, for whom, and what happened before it: an error, a crash, a
  notification to the wrong person. Say why a number was chosen when the
  change adds one.
- **Tests.** A bug fix has a test that fails on `main` and passes with
  the fix. A feature has tests of what it does, and of its errors, on
  SQLite and PostgreSQL when it touches the database.
- **Docs.** A change a user can see updates the guide it belongs to and
  the unreleased section at the top of [CHANGELOG.md](CHANGELOG.md).
- **The checks pass.** CI runs them; run them first:

  ```sh
  mix format --check-formatted
  mix compile --warnings-as-errors
  mix credo --strict
  mix docs
  mix test
  mix dialyzer
  ```

  `mix test` runs on SQLite, and on PostgreSQL too when it is reachable;
  CI has PostgreSQL. `mix precommit` runs most of the checks at once. CI
  also runs the tests with the oldest Elixir, Phoenix and LiveView that
  Chime supports (`CHIME_OLDEST=1`, see `.github/workflows/ci.yml`).

The JavaScript of `priv/static/chime.js` and `chime-react.js` is built
from `assets/src`; a change to it commits the bundles that
`npm run build` gives, as CI checks:

```sh
cd assets
npm ci
npm run typecheck
npm test
npm run build
```

`mix dev` runs a small app at http://localhost:4100, with notifications,
the bell, the admin at `/admin/notifications` and its previews, to see a
change in a browser.

The pull request template has these as a checklist.

## What the maintainers keep

- **Releases.** The version in `mix.exs`, the release headings of the
  changelog and the tags are changed by the maintainers, at a release.

## Style

Match the code around your change: its naming, its comments and the way
its guides are written. `mix format` and `mix credo --strict` settle the
rest.

## License

By contributing, you agree that your contribution is released under the
MIT License of the project (see [LICENSE](https://github.com/hattoriai/chime/blob/main/LICENSE)).
