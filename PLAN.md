# jbuilder.cr — порт jbuilder

> ⚠️ EXPERIMENTAL, DO NOT USE IN PRODUCTION YET.

Порт [rails/jbuilder](https://github.com/rails/jbuilder) **2.14.1** на Crystal.
Оригинал: `~/.rvm/gems/ruby-3.4.5/gems/jbuilder-2.14.1`.

## Статус

**Готово, зелёное**: 142 примера (`make spec` = `CRAILS_VIEWS=spec/fixtures/app/views crystal spec`;
без CRAILS_VIEWS — 138):
- `spec/oracle_spec.cr` — 42 кейса, снятых с настоящего гема
  (`oracle/cases.rb > oracle/expected.yml`), воспроизводятся 1:1;
- `spec/integration_spec.cr` — 68 тестов из официального `test/jbuilder_test.rb`
  (v2.14.1), портированных с адаптацией под статическую типизацию;
- `spec/oracle_template_spec.cr` — 28 кейсов JbuilderTemplate (партиалы,
  коллекции, cached:, cache!/cache_if!/cache_root!), снятых с настоящего
  гема на чистом ActionView 8.1.4 + FixtureResolver
  (`oracle/cases_template.rb > oracle/expected_template.yml`).

## API 1:1

- `Jbuilder.new { |json| ... }`, `Jbuilder.encode { |json| ... }`
- `json.foo bar`, `json.set! :foo, bar`, `json.foo { ... }`,
  `json.foo collection { |el| ... }`, `json.foo obj, :attr, :attr2`
- `array! coll`, `array! coll { |el| ... }`, `array! coll, :attr`,
  `array!(nil)`, `child!`, `extract! obj, :attr`, `call` (= `json.(...)`)
- `merge!(hash | builder)`, `nil!`/`null!`, `attributes!`, `target!`
- `key_format! :upcase | camelize: :lower | ->(k){ ... }`,
  `ignore_nil!`, `deep_format_keys!` (+ класс-уровневые дефолты
  `Jbuilder.key_format/ignore_nil/deep_format_keys`)
- Ошибки: `Jbuilder::NullError`, `ArrayError`, `MergeError` (те же сообщения)

## Отличия от Ruby (статическая типизация)

- Узел дерева — `Jbuilder::Node` (замкнутый union), сериализация в `target!`;
  values: Nil/Bool/Int/Float/String/Symbol/Array/Hash/NamedTuple/JSON::Any/Jbuilder.
- `extract!`/`json.author obj, :attr` — извлечение на этапе выполнения:
  Hash/NamedTuple/JSON::Any по ключу, прочие объекты — по инстанс-переменным
  с публичными ридерами (`forall T` + `T.instance_vars`). runtime-`public_send`
  в Crystal нет.
- `json.(obj, :attr)` → `json.call(obj, :attr)` (нет call-синтаксиса `.()`).
- `method_missing` (json.name ...) — макрос: Crystal переименовывает аргументы
  (`_arg0`) и переписывает блоки с аргументами в yield-форму, поэтому
  `set!`/`array!`/`extract!` — обычные def-методы, а произвольные имена
  диспетчеризуются в `set!` на implicit self.

## Обход багов Crystal 1.21 (здесь и в PLAN других шардов)

1. `*args : UnionType` (annotated splat) — сегфолт компилятора; сплаты без аннотаций.
2. Union-alias в restriction (`Array(Func)`) матчит `Array(Symbol)` инвариантно —
   коэрсинг значений в цикле вместо аннотации.
3. Recursive alias (`Node`) в restriction перегрузки матчит посторонние типы
   (`Array(Int32)`) — identity-перегрузки убраны.
4. `set!(key, nil, &block)` через method_missing — сегфолт; закрыт явной
   Nil-перегрузкой.
5. Recursive alias в restriction аргумента НЕ матчится при вызове из тела
   метода, унаследованного подклассом: `json.array! [...]` в JbuilderTemplate
   уводил внутренний `_set_array(...)` в method_missing с ключом "_set_array" —
   рестрикшен `Array(Node)` у `_set_array` убран.

## Интеграция с rails.cr

### JbuilderTemplate ✅ (`src/jbuilder/jbuilder_template.cr`)

Порт `jbuilder/jbuilder_template.rb` поверх action_view.cr:

- `partial! "name", {"local" => value}` / `partial! "name", collection:,
  as_local: "name"` (в т.ч. форма `partial: "name", collection: ...`);
- `json.array! coll, partial: "post", as_local: "post"` и
  `json.posts coll, partial: "post", as_local: "post"` (inline под ключом,
  nil-коллекция → `[]`; одиночный объект — тоже);
- `cached: true` — поэлементный кэш коллекции (cache_key элемента);
- `cache!` / `cache_if!` / `cache_root!` (+ `expires_in`) — фрагментный кэш
  через `ActionView.perform_caching` / `ActionView.cache_store`;
- ошибки `:layout`/`:spacer_template` — те же NotImplementedError;
- `compile_partials({...})` — компиляция `.json.jbuilder`-партиалов в методы
  на этапе сборки (тело файла — валидный Crystal DSL, вставка через
  `read_file`; вызывать внутри `class JbuilderTemplate ... end`).

Отклонения от Ruby (см. шапку файла):
- `as:` → `as_local:` (`as` — синтаксис приведения типов Crystal);
- locals — Hash (именованно-произвольные ключи Ruby в Crystal невыразимы);
- партиалы регистрируются compile-time, файловой рантайм-подстановки
  (lookup_context) нет;
- фрагмент кэша хранится JSON-строкой ("null" — сентинел пустого фрагмента);
- cache_root!-ошибка — RuntimeError (обёртки ActionView::Template::Error нет).

### Railtie-регистрация ✅ (`src/jbuilder/handler.cr`)

Аналог JbuilderHandler + railtie для action_pack.cr (`~/rails.cr`):

- кодоген action_pack.cr (src/base.cr) для каждого найденного
  `#{action}.json.jbuilder` вызывает `JbuilderHandler.call` — шаблон
  компилируется в метод (тело файла — валидный Crystal DSL, локальная
  `json` = свежий JbuilderTemplate, ивары/хелперы контроллера видны,
  как в Rails);
- implicit render: `?format=json` / `Accept: application/json` →
  `#{action}.json.jbuilder` без layout, `Content-Type:
  application/json; charset=utf-8`;
- явный рендер: `render(template: "posts/show.json.jbuilder")`
  (также "posts/show" / "show" / "show.json.jbuilder");
- оракул — Rails 8.1.4 + jbuilder 2.14.1, минимальное инлайн-приложение
  без `rails new` (`oracle/cases_controller.rb > oracle/expected_controller.yml`,
  4 кейса: implicit по format/Accept, коллекция, явный рендер), шаблоны
  `oracle/views` и `spec/fixtures/app/views` байт-в-байт одинаковы;
  зеркало — `spec/railtie_spec.cr`, запуск `make spec` (CRAILS_VIEWS
  читается кодогеном на этапе компиляции; без него файл компилируется
  в пустоту — bare `crystal spec` остальных 138 тестов не трогает).

Отклонения от Ruby:
- явный рендер — только именованный аргумент `render(template:)`:
  позиционная строка render("...") в action_pack.cr занята телом
  JSON-ответа, а позиционная перегрузка с той же формой ломает
  именованную диспетчеризацию `render(json:)` (квирк Crystal 1.21);
  в Rails позиционная форма `render "posts/show", formats: :json`
  (полное имя файла в позиционной строке Rails 8.1 и сам не принимает);
- рантайм-регистрации хендлеров нет: шаблон обязан существовать на
  этапе сборки, приложение с .json.jbuilder-вьюхами обязано
  `require "jbuilder_cr"` (без него константа JbuilderHandler не
  разрешится — как в Rails без гема хендлер не зарегистрирован);
- format=json при отсутствии .json.jbuilder у экшена рендерит html
  (Rails поднимает ActionController::UnknownFormat / MissingTemplate) —
  общее поведение implicit render в action_pack.cr, не jbuilder-специфика.
