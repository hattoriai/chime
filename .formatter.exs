# The router macros of Chime, without parentheses, in Chime and in the
# apps that import its formatter (import_deps: [:chime]).
router = [
  chime_api: 1,
  chime_api: 2,
  chime_unsubscribe: 1,
  chime_unsubscribe: 2
]

# The notifier's declarations.
notifier = [deliver: 1, deliver: 2]

[
  import_deps: [:ecto, :ecto_sql, :phoenix, :phoenix_html, :phoenix_live_view, :phoenix_mountable],
  locals_without_parens: [attr: 2, attr: 3, slot: 1, slot: 2, slot: 3] ++ router ++ notifier,
  export: [locals_without_parens: router ++ notifier],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
