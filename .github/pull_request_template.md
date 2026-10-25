## Why

<!-- The problem this solves, for whom, and what happened before it (an error, a crash, a notification to the wrong person). -->

Fixes #<!-- the issue; see CONTRIBUTING.md for when a pull request needs one -->

## What

<!-- The change, in a few lines. -->

## How it was tested

<!-- The tests added, on SQLite and PostgreSQL if it touches the database. -->

## Checklist

- [ ] One change: anything unrelated is in its own pull request.
- [ ] A bug fix has a test that fails on `main` and passes here.
- [ ] `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix docs`, `mix test` and `mix dialyzer` pass.
- [ ] The guides and the unreleased section of `CHANGELOG.md` are updated, for a change a user can see.
- [ ] Says so here if it changes the public API, the tables, the JSON of the API, or what Chime does today.
- [ ] No change to the version (the maintainers keep it).
