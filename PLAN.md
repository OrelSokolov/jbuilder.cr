# jbuilder.cr — порт jbuilder

> ⚠️ EXPERIMENTAL, DO NOT USE IN PRODUCTION YET.

Порт [rails/jbuilder](https://github.com/rails/jbuilder) **2.14.1** на Crystal.
Оригинал: `~/.rvm/gems/ruby-3.4.5/gems/jbuilder-2.14.1`.

## Статус

**Готово, зелёное**: 110 примеров (`crystal spec`):
- `spec/oracle_spec.cr` — 42 кейса, снятых с настоящего гема
  (`oracle/cases.rb > oracle/expected.yml`), воспроизводятся 1:1;
- `spec/integration_spec.cr` — 68 тестов из официального `test/jbuilder_test.rb`
  (v2.14.1), портированных с адаптацией под статическую типизацию.

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

## Интеграция с rails.cr (TODO)

- `JbuilderTemplate` для action_view.cr: `render "show.json.jbuilder"`,
  partials (`json.array! @posts, partial: "posts/post", as: :post`), cache!.
- Railtie-регистрация `.json.jbuilder`-хендлера — после стабилизации
  action_view.cr.
