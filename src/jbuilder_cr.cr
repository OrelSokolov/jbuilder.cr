# jbuilder_cr — порт jbuilder 2.14.1 (github.com/rails/jbuilder) на Crystal.
#
# API 1:1: json.foo bar / json.foo { ... } / array! / extract! / child! /
# merge! / nil! / key_format! / ignore_nil! / deep_format_keys! / target!.
#
# Отличия от Ruby, продиктованные статической типизацией Crystal:
#   * set!/array!/extract! — макросы (runtime-`public_send` невозможен),
#     но извлечение атрибутов (`json.author post, :name`) работает на
#     этапе выполнения: из Hash/NamedTuple/JSON::Any по ключу, из прочих
#     объектов — по инстанс-переменным с одноимёнными методами.
#   * method_missing — публичный диспетчер: в Crystal макросы класса не
#     вызываются через явный получатель (json.array! ...), поэтому вызовы
#     диспетчеризуются сюда и перевызываются на implicit self (аргументы
#     при этом становятся runtime-значениями — ключи/атрибуты могут быть
#     String или Symbol).
#   * Узел дерева — `Jbuilder::Node` (в Ruby — произвольный объект,
#     сериализуемый в JSON в момент target!).

require "json"
require "./jbuilder/errors"
require "./jbuilder/key_formatter"
require "./jbuilder/jbuilder_template"
require "./jbuilder/handler"

class Jbuilder
  BLANK = Blank.new

  # Сентинел "значение ещё не задано" — 1:1 к Jbuilder::Blank.
  class Blank
    def ==(other : Blank) : Bool
      true
    end

    def empty? : Bool
      true
    end
  end

  # Значение узла дерева JSON (в Ruby — Object; здесь — замкнутый union).
  alias Node = Nil | Bool | Int32 | Int64 | Float32 | Float64 | String | Blank |
               Array(Node) | Hash(String, Node)

  @@key_formatter : KeyFormatter? = nil
  @@ignore_nil : Bool = false
  @@deep_format_keys : Bool = false

  @attributes : Node
  @key_formatter : KeyFormatter?
  @ignore_nil : Bool
  @deep_format_keys : Bool

  def initialize(key_formatter : KeyFormatter? = nil,
                 ignore_nil : Bool = @@ignore_nil,
                 deep_format_keys : Bool = @@deep_format_keys,
                 &block : self -> _)
    @attributes = {} of String => Node
    @key_formatter = key_formatter || @@key_formatter
    @ignore_nil = ignore_nil
    @deep_format_keys = deep_format_keys
    yield self
  end

  def initialize(key_formatter : KeyFormatter? = nil,
                 ignore_nil : Bool = @@ignore_nil,
                 deep_format_keys : Bool = @@deep_format_keys)
    @attributes = {} of String => Node
    @key_formatter = key_formatter || @@key_formatter
    @ignore_nil = ignore_nil
    @deep_format_keys = deep_format_keys
  end

  # Jbuilder.encode { |json| ... } → JSON-строка.
  def self.encode(&block : self -> _) : String
    new(&block).target!
  end

  # --- DSL -------------------------------------------------------------------

  # set! — макрос: ветвится по наличию блока/атрибутов, как set! в Ruby.
  #   json.name "David"                    → {"name":"David"}
  #   json.author { json.name "David" }    → {"author":{...}}
  #   json.person other_builder            → {"person":{...}}
  #   json.people people { |p| ... }       → {"people":[...]}
  #   json.author david, :name, :age       → {"author":{...}}
  #   json.comments comments, :content     → {"comments":[...]}
  # set! — def-методы (yield-based), те же ветви, что в Ruby:
  #   json.name "David"                    → {"name":"David"}
  #   json.author { json.name "David" }    → {"author":{...}}
  #   json.person other_builder            → {"person":{...}}
  #   json.people people { |p| ... }       → {"people":[...]}
  #   json.author david, :name, :age       → {"author":{...}}
  #   json.comments comments, :content     → {"comments":[...]}
  # При блоке атрибуты игнорируются (семантика Ruby: block_given? первым).
  def set!(key : String | Symbol, value)
    _set_value(_ks(key), _format_keys(_to_node(value)))
  end

  def set!(key : String | Symbol, &block)
    _set_value(_ks(key), _merge_block(_ks(key)) { yield self })
  end

  def set!(key : String | Symbol, value : Enumerable(E), *attributes, &block) forall E
    array = [] of Node
    value.each do |element|
      scoped = _scope { yield element }
      array << scoped unless scoped.is_a?(Blank)
    end
    _set_value(_ks(key), array)
  end

  # nil-коллекция с блоком → [] (Ruby: array! nil → [])
  def set!(key : String | Symbol, value : Nil, *attributes, &block)
    _set_value(_ks(key), [] of Node)
  end

  def set!(key : String | Symbol, value, *attributes)
    keys = [] of String
    attributes.each { |attribute| keys << _ks(attribute) }
    result =
      if value.responds_to?(:each) && !value.is_a?(String) && !value.is_a?(Hash) && !value.is_a?(JSON::Any)
        _scope { _set_array(_array_with_attributes(value, keys)) }
      else
        _merge_block(_ks(key)) do
          keys.each do |k|
            _set_value(k, _format_keys(_extract_value(value, k)))
          end
        end
      end
    _set_value(_ks(key), result)
  end

  # key_format! :upcase / key_format! camelize: :lower / key_format! ->(k){ "_"+k }
  # (splat без аннотации: annotated-splat + named-args ломают диспетчеризацию
  # Crystal и приводят к method_missing)
  def key_format!(*formats, camelize : Symbol? = nil) : Nil
    @key_formatter = KeyFormatter.new(Jbuilder._coerce_formats(formats), camelize)
  end

  def self.key_format(*formats, camelize : Symbol? = nil) : Nil
    @@key_formatter = KeyFormatter.new(_coerce_formats(formats), camelize)
  end

  def self._coerce_formats(formats) : Array(KeyFormatter::Func)
    coerced = [] of KeyFormatter::Func
    formats.each do |format|
      if format.is_a?(KeyFormatter::Func)
        coerced << format
      else
        raise ArgumentError.new("key_format! accepts Symbol or Proc(String, String), got: #{format}")
      end
    end
    coerced
  end

  def ignore_nil!(value : Bool = true) : Nil
    @ignore_nil = value
  end

  def self.ignore_nil(value : Bool = true) : Nil
    @@ignore_nil = value
  end

  def deep_format_keys!(value : Bool = true) : Nil
    @deep_format_keys = value
  end

  def self.deep_format_keys(value : Bool = true) : Nil
    @@deep_format_keys = value
  end

  # child! — превращает текущий элемент в массив и добавляет хеш.
  def child!(&block : self -> _) : Nil
    @attributes = [] of Node unless @attributes.is_a?(Array(Node))
    value = _scope { yield self }
    @attributes.as(Array(Node)) << value
  end

  # array! — те же ветви, что в Ruby:
  #   array! [1,2,3] / array!(nil) / array! coll { |el| ... } / array! coll, :name
  def array!(collection : Nil = nil)
    _set_array([] of Node)
  end

  def array!(collection : Enumerable, *attributes, &block)
    array = [] of Node
    collection.each do |element|
      scoped = _scope { yield element }
      array << scoped unless scoped.is_a?(Blank)
    end
    _set_array(array)
  end

  def array!(collection : Enumerable, *attributes)
    if attributes.empty?
      _set_array(_format_keys(_to_node_array(collection)))
    else
      keys = [] of String
      attributes.each { |attribute| keys << _ks(attribute) }
      _set_array(_array_with_attributes(collection, keys))
    end
  end

  # extract! obj, :name, :age — Hash / NamedTuple / JSON::Any / ivar-методы объекта.
  def extract!(object, *attributes)
    attributes.each do |attribute|
      key = _ks(attribute)
      _set_value(key, _format_keys(_extract_value(object, key)))
    end
  end

  # json.(obj, :name) / json.(coll) { |el| ... } — call-синтаксис (здесь json.call).
  def call(object, *attributes)
    extract!(object, *attributes)
  end

  def call(collection : Enumerable, &block)
    array!(collection) { |element| yield element }
  end

  # nil! / null! — null JSON.
  def nil! : Nil
    @attributes = nil
  end

  def null! : Nil
    nil!
  end

  # Атрибуты текущего билдера (в Ruby — Object, здесь — Node).
  def attributes! : Node
    @attributes
  end

  # merge! — Hash / NamedTuple / JSON::Any / другой Jbuilder.
  def merge!(object : Jbuilder) : Nil
    _merge_attributes(object.@attributes)
  end

  def merge!(object) : Nil
    _merge_attributes(_to_node(object))
  end

  # target! — JSON-строка.
  def target! : String
    String.build do |io|
      builder = JSON::Builder.new(io)
      builder.document do
        _write_json(@attributes, builder)
      end
    end
  end

  # --- Внутреннее ------------------------------------------------------------

  # method_missing → set! (json.name "David" — 1:1 к Ruby, где
  # method_missing = set!). DSL-методы (set!/array!/extract!/call) —
  # обычные def-методы и находятся напрямую, сюда попадают только
  # произвольные имена ключей. Аргументы приходят переименованными
  # (_arg0) и обрабатываются на этапе выполнения.
  # Internal underscore methods must NEVER land here: a call like
  # `_ks(<Node union>)` (no matching overload) used to expand into
  # `set!("_ks", node)` → set! → `_ks(...)` → method_missing → … — an
  # infinite runtime recursion (stack overflow). The guard turns that
  # into a compile error naming the call.
  macro method_missing(call)
    {% name = call.name.id.stringify %}
    {% if name.starts_with?("_") %}
      {% raise "internal method '#{name}' dispatched to Jbuilder method_missing in #{@type} — missing overload (call: #{call})" %}
    {% end %}
    {% if call.block %}
      {% bargs = call.block.args %}
      {% if call.args.empty? %}
        set!({{ name }}) do{% unless bargs.empty? %} |{{ bargs.splat }}|{% end %}
          {{ call.block.body }}
        end
      {% else %}
        set!({{ name }}, {{ call.args.splat }}) do{% unless bargs.empty? %} |{{ bargs.splat }}|{% end %}
          {{ call.block.body }}
        end
      {% end %}
    {% else %}
      set!({{ name }}{% unless call.args.empty? %}, {{ call.args.splat }}{% end %}{% if call.named_args %}{% for na in call.named_args %}, {{ na.name.id }}: {{ na.value }}{% end %}{% end %})
    {% end %}
  end

  # Ключ: String или Symbol → String (runtime, т.к. через method_missing
  # аргументы приходят как значения). Catch-all: без него вызов _ks со
  # статическим типом вне String|Symbol уходит в method_missing (см.
  # комментарий там) — рекурсия; на практике не-строковых ключей не
  # бывает, поэтому raise.
  def _ks(key : String) : String
    key
  end

  def _ks(key : Symbol) : String
    key.to_s
  end

  def _ks(key) : String
    raise ArgumentError.new("_ks expects a String or Symbol key, got #{key.class}")
  end

  # Извлечение значения атрибута из объекта — runtime-замена public_send.

  def _extract_value(object : Hash, key : String) : Node
    object.each do |k, value|
      return _to_node(value) if k.to_s == key
    end
    raise KeyError.new("key not found: #{key}")
  end

  def _extract_value(object : NamedTuple, key : String) : Node
    object.each do |k, value|
      return _to_node(value) if k.to_s == key
    end
    raise KeyError.new("key not found: #{key}")
  end

  def _extract_value(object : JSON::Any, key : String) : Node
    if hash = object.as_h?
      if value = hash[key]?
        return _to_node(value)
      end
    end
    raise KeyError.new("key not found: #{key}")
  end

  def _extract_value(object : T, key : String) : Node forall T
    {% for ivar in T.instance_vars %}
      if object.responds_to?({{ ivar.name.symbolize }})
        if key == {{ ivar.name.stringify }}
          return _to_node(object.{{ ivar.name.id }})
        end
      end
    {% end %}
    raise ArgumentError.new("cannot extract #{key} from #{T}")
  end

  def _merge_attributes(node : Node) : Nil
    @attributes = _merge_values(@attributes, _format_keys(node))
  end

  def _set_value(key : String, value : Node) : Nil
    raise NullError.build(key) if @attributes.nil?
    raise ArrayError.build(key) if @attributes.is_a?(Array(Node))
    return if (@ignore_nil && value.nil?) || value.is_a?(Blank)
    @attributes = {} of String => Node if @attributes.is_a?(Blank)
    @attributes.as(Hash(String, Node))[_key(key)] = value
  end

  # Без рестрикшена Array(Node): рекурсивный alias в ограничении аргумента
  # не матчит фактический Array(Node) при вызове из тела метода, унаследо-
  # ванного подклассом (json.array! в JbuilderTemplate уводило вызов в
  # method_missing с ключом "_set_array") — см. баги Crystal 1.21 ниже.
  def _set_array(array) : Nil
    @attributes = _merge_values(@attributes, array)
  end

  def _merge_block(key : String, &block) : Node
    current_value = _blank? ? BLANK : _fetch_or_blank(_key(key))
    raise NullError.build(key) if current_value.nil?
    new_value = _scope { yield self }
    _merge_values(current_value, new_value)
  end

  def _merge_values(current_value : Node, updates : Node) : Node
    return current_value if updates.is_a?(Blank)
    if current_value.is_a?(Blank) || updates.nil? ||
       (current_value.is_a?(Hash(String, Node)) && current_value.empty? && updates.is_a?(Array(Node)))
      updates
    elsif current_value.is_a?(Array(Node)) && updates.is_a?(Array(Node))
      current_value + updates
    elsif current_value.is_a?(Hash(String, Node)) && updates.is_a?(Hash(String, Node))
      _deep_merge(current_value, updates)
    else
      raise MergeError.build(current_value, updates)
    end
  end

  def _deep_merge(base : Hash(String, Node), updates : Hash(String, Node)) : Hash(String, Node)
    result = base.dup
    updates.each do |key, value|
      existing = result[key]?
      if existing.is_a?(Hash(String, Node)) && value.is_a?(Hash(String, Node))
        result[key] = _deep_merge(existing, value)
      else
        result[key] = value
      end
    end
    result
  end

  def _key(key : String) : String
    if formatter = @key_formatter
      formatter.format(key)
    else
      key
    end
  end

  def _format_keys(node : Node) : Node
    return node unless @deep_format_keys
    _deep_format_keys(node)
  end

  def _deep_format_keys(node : Node) : Node
    case node
    when Array(Node)
      node.map { |value| _deep_format_keys(value).as(Node) }.as(Node)
    when Hash(String, Node)
      formatted = {} of String => Node
      node.each { |key, value| formatted[_key(key)] = _deep_format_keys(value) }
      formatted
    else
      node
    end
  end

  def _scope(&block) : Node
    parent_attributes = @attributes
    parent_formatter = @key_formatter
    parent_deep = @deep_format_keys
    @attributes = BLANK
    yield
    result = @attributes
    @attributes = parent_attributes
    @key_formatter = parent_formatter
    @deep_format_keys = parent_deep
    result
  end

  def _is_collection?(object) : Bool
    object.responds_to?(:each) && !object.is_a?(String) && !object.is_a?(Hash) && !object.is_a?(JSON::Any)
  end

  def _blank?(value : Node = @attributes) : Bool
    value.is_a?(Blank)
  end

  def _fetch_or_blank(key : String) : Node
    attributes = @attributes
    return BLANK unless attributes.is_a?(Hash(String, Node))
    # Важно: сохранённый nil возвращается как nil (триггер NullError),
    # поэтому []?/|| не годится.
    if attributes.has_key?(key)
      attributes[key]
    else
      BLANK
    end
  end

  # Коллекция с атрибутами: array! people, :name, :age / json.comments comments, :content.
  def _array_with_attributes(collection, keys : Array(String)) : Array(Node)
    array = [] of Node
    collection.each do |element|
      array << _scope do
        keys.each do |key|
          _set_value(key, _format_keys(_extract_value(element, key)))
        end
      end
    end
    array
  end

  # --- Конвертация значений в Node -------------------------------------------

  def _to_node(value : Nil | Bool | Blank) : Node
    value
  end

  def _to_node(value : Int32 | Int64 | Float64 | String) : Node
    value
  end

  def _to_node(value : Float32) : Node
    value.to_f64
  end

  def _to_node(value : Int8 | Int16 | UInt8 | UInt16 | UInt32) : Node
    value.to_i64
  end

  def _to_node(value : Symbol) : Node
    value.to_s
  end

  def _to_node(value : Array) : Node
    value.map { |element| _to_node(element).as(Node) }
  end

  def _to_node(value : Hash) : Node
    converted = {} of String => Node
    value.each { |key, element| converted[key.to_s] = _to_node(element) }
    converted
  end

  def _to_node(value : NamedTuple) : Node
    _to_node(value.to_h)
  end

  def _to_node(value : JSON::Any) : Node
    raw = value.raw
    case raw
    when Array(JSON::Any) then raw.map { |element| _to_node(element).as(Node) }
    when Hash(String, JSON::Any)
      converted = {} of String => Node
      raw.each { |key, element| converted[key] = _to_node(element) }
      converted
    else
      _to_node(raw)
    end
  end

  def _to_node(value : Jbuilder) : Node
    value.@attributes
  end

  def _to_node(value) : Node
    raise ArgumentError.new("Jbuilder cannot serialize #{value.class} — supported: Nil, Bool, Int, Float, String, Symbol, Array, Hash, NamedTuple, JSON::Any, Jbuilder")
  end

  def _to_node_array(value : Nil) : Array(Node)
    [] of Node
  end

  def _to_node_array(value : Array) : Array(Node)
    value.map { |element| _to_node(element).as(Node) }
  end

  def _to_node_array(value) : Array(Node)
    raise ArgumentError.new("array! expects an Array (or nil), got #{value.class}")
  end

  # --- Сериализация Node → JSON ----------------------------------------------

  def _write_json(node : Node, builder : JSON::Builder) : Nil
    case node
    when Array(Node)
      builder.array do
        node.each { |element| _write_json(element, builder) }
      end
    when Hash(String, Node)
      builder.object do
        node.each do |key, value|
          builder.field(key) { _write_json(value, builder) }
        end
      end
    when Blank
      builder.scalar(nil)
    else
      builder.scalar(node)
    end
  end
end
