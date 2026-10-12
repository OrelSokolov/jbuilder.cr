# jbuilder.cr

A Crystal port of [rails/jbuilder](https://github.com/rails/jbuilder)
**2.14.1** — the JSON builder DSL, plus the `JbuilderTemplate` view
layer and railtie-style handler registration for CRails
(action_view.cr / action_pack.cr). Suite: **142 examples, 0 failures**
(`make spec`).

> ⚠️ EXPERIMENTAL — DO NOT USE IN PRODUCTION YET.

## Installation

```yaml
dependencies:
  jbuilder_cr:
    github: OrelSokolov/jbuilder.cr
```

```sh
shards install
```

## Usage

```crystal
Jbuilder.encode do |json|
  json.name "Peter"
  json.age  25
  json.address do
    json.city "Berlin"
  end
  json.friends ["Jen", "Pat"] do |friend|
    json.name friend
  end
  json.extract! person, :name, :age
  json.set! :custom, value
  json.array! posts, :title, :created_at
end
```

`.json.jbuilder` templates work in CRails controllers (implicit render
on `?format=json` / `Accept: application/json`, or explicit
`render(template: "posts/show.json.jbuilder")`); the application needs
`require "jbuilder_cr"`.

## Feature comparison vs jbuilder 2.14.1

### Core DSL

| Feature | Original (jbuilder) | Port (jbuilder.cr) | Status |
|---|---|---|---|
| `Jbuilder.new { \|json\| }`, `Jbuilder.encode`, `json.foo bar`, `json.set!`, block form `json.foo { }`, collection form `json.foo coll { \|el\| }`, `json.foo obj, :attr, :attr2` | ✅ | Same | ✅ |
| `array!` (plain / block / attribute list / nil), `child!`, `extract!`, `call` | ✅ | `json.(obj, :attr)` → `json.call(obj, :attr)` (no `.()` call syntax in Crystal) | 🔶 |
| `merge!`, `nil!`/`null!`, `attributes!`, `target!` | ✅ | Same | ✅ |
| `key_format! :upcase \| camelize: :lower \| ->(k){}`, `ignore_nil!`, `deep_format_keys!` + class-level defaults | ✅ | Same | ✅ |
| Errors: `NullError`, `ArrayError`, `MergeError` | ✅ | Same messages | ✅ |
| `method_missing` (`json.name ...`) | ✅ (runtime) | Compile-time macro dispatching into `set!`; arbitrary names on implicit self | 🔶 |
| `extract!` on arbitrary objects | runtime `public_send` | Hash/NamedTuple/JSON::Any by key; other objects via instance variables with public readers (`forall T` + `T.instance_vars`) | 🔶 |

### JbuilderTemplate (view integration)

| Feature | Original | Port | Status |
|---|---|---|---|
| `partial! "name", locals` / `partial: ..., collection:, as:` | ✅ | `partial! "name", {"local" => value}`; `as:` → `as_local:` (`as` is Crystal's cast syntax); locals are a Hash | 🔶 |
| `json.array! coll, partial: ..., as: ...` and inline `json.posts coll, partial: ...` (nil collection → `[]`) | ✅ | Same | ✅ |
| `cached: true` (per-element collection cache), `cache!` / `cache_if!` / `cache_root!` (+ `expires_in`) | ✅ | Via `ActionView.perform_caching` / `cache_store`; fragments stored as JSON strings; `cache_root!` error is a RuntimeError | 🔶 |
| `:layout` / `:spacer_template` errors | ✅ NotImplementedError | Same | ✅ |
| Runtime partial lookup (lookup_context) | ✅ | Partials compiled at build time via `compile_partials({...})` (file body is valid Crystal DSL, inlined with `read_file`) | ❌ (equivalent: compile-time registration) |

### Railtie / handler registration

| Feature | Original | Port | Status |
|---|---|---|---|
| Template handler for `*.json.jbuilder` in controllers | ✅ | action_pack.cr codegen calls `JbuilderHandler.call`; controller ivars/helpers visible in the template, local `json` = a fresh JbuilderTemplate | ✅ |
| Implicit render (`format=json` → `#{action}.json.jbuilder`, no layout, `Content-Type: application/json; charset=utf-8`) | ✅ | Same | ✅ |
| Explicit `render "posts/show", formats: :json` | ✅ | Named-argument form only: `render(template: "posts/show.json.jbuilder")` — the positional string in action_pack.cr is the JSON body | 🔶 |
| Runtime handler registration | ✅ | None — templates must exist at build time; `require "jbuilder_cr"` required (as Rails needs the gem) | 🔶 |
| `format=json` without a `.json.jbuilder` template | raises UnknownFormat/MissingTemplate | Renders html (general implicit-render behavior of action_pack.cr) | ❌ |

## Deviations & Crystal-specific notes

- The tree node is a closed `Jbuilder::Node` union; values: Nil/Bool/
  Int/Float/String/Symbol/Array/Hash/NamedTuple/JSON::Any/Jbuilder.
- Several Crystal 1.21 compiler bugs (annotated splats, recursive-alias
  restrictions) are worked around — see PLAN.md for the list.

## Testing

```sh
make spec    # 142 examples (CRAILS_VIEWS=spec/fixtures/app/views)
crystal spec # 138 without the view fixtures
```

- `spec/oracle_spec.cr` — 42 cases recorded with the real gem, replayed
  1:1.
- `spec/integration_spec.cr` — 68 tests ported from the official
  `test/jbuilder_test.rb` (v2.14.1).
- `spec/oracle_template_spec.cr` — 28 JbuilderTemplate cases recorded on
  plain ActionView 8.1.4 + FixtureResolver.
- `spec/railtie_spec.cr` — controller-level oracle (Rails 8.1.4 +
  jbuilder 2.14.1 minimal inline app): implicit render by format/Accept,
  collections, explicit render.
