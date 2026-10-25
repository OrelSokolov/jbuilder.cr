# JbuilderTemplate — порт jbuilder/jbuilder_template.rb 2.14.1.
#
# Интеграционный слой jbuilder ↔ action_view.cr:
#   * partial! / json.<key> coll, partial: "...", as: :... / array! coll,
#     partial: "..." — рендер jbuilder-партиалов (аналог @context.render);
#   * cache! / cache_if! / cache_root! — фрагментный кэш JSON (аналог
#     CacheHelper#cache через ActionView.perform_caching / cache_store);
#   * compile_partials — компиляция .json.jbuilder-партиалов в методы на
#     этапе сборки (замена FixtureResolver/lookup_context: файловую рантайм-
#     подстановку шаблонов Crystal себе позволить не может).
#
# Отличия от Ruby (продиктованы action_view.cr):
#   * Хендлер `.json.jbuilder` для контроллеров (JbuilderHandler + railtie)
#     — отдельный слой action_pack/railties, здесь только партиалы и кэш.
#   * perform_caching/кэш берутся с модуля ActionView (как в CacheHelper
#     action_view.cr), а не с @context.controller.
#   * Фрагмент кэша хранится JSON-строкой (CacheStore порта — String-only);
#     "null" — сентинел пустого фрагмента (Ruby хранит BLANK-объект).
#   * cached: true кладёт элементы в тот же ActionView.cache_store (Ruby —
#     в Jbuilder::CollectionRenderer.collection_cache = Rails.cache).
#   * Опции коллекций — именованные аргументы: json.array! posts, partial:
#     "post", as: :post (runtime-Hash с произвольными ключами Crystal не
#     соберёт без Union-типа — как и в action_view.cr).

require "../jbuilder_cr"
require "action_view_cr"

class JbuilderTemplate < Jbuilder
  @cached_root : String?

  def initialize
    super()
    @cached_root = nil
  end

  def initialize(&block : self -> _)
    initialize
    yield self
  end

  # --- Регистрация партиалов (compile-time) ----------------------------------
  #
  #   JbuilderTemplate.compile_partials({
  #     "post"        => {path: "app/views/posts/_post.json.jbuilder",
  #                       locals: {"post" => Post}},
  #     "racers/racer" => {path: "app/views/racers/_racer.json.jbuilder",
  #                        locals: {"racer" => Racer}},
  #   })
  #
  # Тело файла вставляется в метод как есть (DSL-вызовы json.* — валидный
  # Crystal); партиал пишет в общий билдер через аргумент json — та же
  # семантика, что options[:locals][:json] = self в Ruby.
  macro compile_partials(partials)
    {% local_types = [] of Nil %}
    {% for _name, defn in partials %}
      {% for _key, t in defn[:locals] %}
        {% local_types << t %}
      {% end %}
    {% end %}
    {% uniq = [] of Nil %}
    {% for t in local_types %}
      {% uniq << t unless uniq.map(&.stringify).includes?(t.stringify) %}
    {% end %}

    # Через alias — см. комментарий в action_view.cr/rendering.cr
    # (compile_partials): макро-склеенный Union в ограничении вызова не
    # унифицируется с тем же union как тип значения Hash (Crystal 1.21).
    alias JBPartialLocal = Union({% for t in uniq %}{{ t.resolve }}, {% end %})

    {% for name, defn in partials %}
      def __jb_partial_{{ name.id.gsub(/[^a-zA-Z0-9_]/, "_").id }}(json : JbuilderTemplate, {% for key, type in defn[:locals] %}{{ key.id }} : {{ type }}, {% end %}) : Nil
        {{ read_file(defn[:path]).id }}
      end
    {% end %}

    def __jb_render_partial(name : String, locals : Hash(String, JBPartialLocal)) : Nil
      case name
      {% for name, defn in partials %}
      when {{ name }} then __jb_partial_{{ name.id.gsub(/[^a-zA-Z0-9_]/, "_").id }}(self, {% for key, type in defn[:locals] %}locals[{{ key }}].as({{ type }}), {% end %})
      {% end %}
      else raise ArgumentError.new("Missing partial #{name.inspect}")
      end
    end
  end

  # --- partial! ----------------------------------------------------------------

  # json.partial! "partial", {"content" => "hello"} — партиал с locals
  # (Ruby-форма "json.partial! 'partial', content: 'hello'" — именованные
  # произвольные ключи в Crystal невыразимы; locals передаются Hash'ем).
  def partial!(partial : String, locals : Hash? = nil) : Nil
    h = {} of String => JBPartialLocal
    locals.try &.each { |k, v| h[k.to_s] = v.as(JBPartialLocal) }
    __jb_render_partial(partial, h)
  end

  # json.partial! "post", collection: posts, as: :post [, cached: true]
  def partial!(partial : String, *, collection : Enumerable?, as_local : String | Symbol? = nil,
               cached : Bool = false, layout : String? = nil, spacer_template : String? = nil) : Nil
    _jb_check_collection_options(layout, spacer_template)
    _jb_render_collection(partial, collection, as_local, cached)
  end

  # json.partial! partial: "post", collection: posts, as: :post
  def partial!(*, partial : String, collection : Enumerable?, as_local : String | Symbol? = nil,
               cached : Bool = false, layout : String? = nil, spacer_template : String? = nil) : Nil
    _jb_check_collection_options(layout, spacer_template)
    _jb_render_collection(partial, collection, as_local, cached)
  end

  # --- array!/set! с партиалами --------------------------------------------------

  # json.array! posts, partial: "post", as: :post
  def array!(collection : Enumerable?, *, partial : String, as_local : String | Symbol? = nil,
             cached : Bool = false, layout : String? = nil, spacer_template : String? = nil) : Nil
    _jb_check_collection_options(layout, spacer_template)
    _jb_render_collection(partial, collection, as_local, cached)
  end

  # json.posts posts, partial: "post", as: :post (inline-партиал под ключом)
  def set!(key : String | Symbol, object : Enumerable, *, partial : String,
           as_local : String | Symbol? = nil, cached : Bool = false,
           layout : String? = nil, spacer_template : String? = nil) : Nil
    _jb_check_collection_options(layout, spacer_template)
    _set_value(_ks(key), _jb_collection_scope(partial, object, as_local, cached))
  end

  # nil-коллекция → [] (Ruby: _set_inline_partial object.nil? → [])
  def set!(key : String | Symbol, object : Nil, *, partial : String,
           as_local : String | Symbol? = nil, cached : Bool = false) : Nil
    _set_value(_ks(key), [] of Node)
  end

  # json.author post, partial: "posts/post", as: :post — одиночный объект
  def set!(key : String | Symbol, object, *, partial : String,
           as_local : String | Symbol? = nil) : Nil
    local = (as_local || File.basename(partial)).to_s
    h = {} of String => JBPartialLocal
    h[local] = object.as(JBPartialLocal)
    _set_value(_ks(key), _scope { __jb_render_partial(partial, h); nil })
  end

  # --- Кэш фрагментов -------------------------------------------------------------

  # json.cache! "cache-key" [, expires_in: span] do ... end
  # Хит — фрагмент из кэша мержится в текущий скоп (Ruby: merge! value).
  def cache!(key : String | Symbol | Array(String | Symbol) | Nil = nil,
             expires_in : Time::Span? = nil, &) : Nil
    if ActionView.perform_caching
      cache_key = _jb_expand_cache_key(key)
      if (hit = ActionView.cache_store.read(cache_key)) && hit != "null"
        _merge_attributes(_to_node(JSON.parse(hit)))
      else
        value = _scope { yield self; nil }
        ActionView.cache_store.write(cache_key, _jb_node_json(value), expires_in)
        _merge_attributes(value)
      end
    else
      yield
    end
  end

  # json.cache! user do ... end — объект-запись вместо строкового ключа:
  # ключ строится из cache_key записи (Rails-форма json.cache! @user).
  def cache!(object, expires_in : Time::Span? = nil, &) : Nil
    if ActionView.perform_caching
      cache_key = _jb_expand_cache_key(_jb_element_cache_key(object))
      if (hit = ActionView.cache_store.read(cache_key)) && hit != "null"
        _merge_attributes(_to_node(JSON.parse(hit)))
      else
        value = _scope { yield self; nil }
        ActionView.cache_store.write(cache_key, _jb_node_json(value), expires_in)
        _merge_attributes(value)
      end
    else
      yield
    end
  end

  # json.cache_if! condition, "cache-key" do ... end
  def cache_if!(condition : Bool,
                key : String | Symbol | Array(String | Symbol) | Nil = nil,
                expires_in : Time::Span? = nil, &) : Nil
    condition ? cache!(key, expires_in) { yield } : yield
  end

  # json.cache_root! "cache-key" do ... end — кэш корневого JSON строкой.
  def cache_root!(key : String | Symbol | Array(String | Symbol) | Nil = nil,
                  expires_in : Time::Span? = nil, &) : Nil
    if ActionView.perform_caching
      if _jb_attributes_present?
        raise RuntimeError.new("cache_root! can't be used after JSON structures have been defined")
      end

      cache_key = _jb_expand_cache_key([:root, key])
      @cached_root = ActionView.cache_store.read(cache_key) || begin
        yield
        json = _jb_node_json(@attributes)
        ActionView.cache_store.write(cache_key, json, expires_in)
        json
      end
    else
      yield
    end
  end

  def target! : String
    @cached_root || super
  end

  # --- Внутреннее ------------------------------------------------------------------

  private def _jb_check_collection_options(layout : String?, spacer_template : String?) : Nil
    if layout
      raise NotImplementedError.new("The `:layout' option is not supported in collection rendering.")
    end
    if spacer_template
      raise NotImplementedError.new("The `:spacer_template' option is not supported in collection rendering.")
    end
  end

  # Рендер коллекции партиалом: элементы → массив, мержится в текущий скоп
  # (root через partial!/array! — корневой массив, через set! — под ключом).
  private def _jb_render_collection(partial : String, collection : Enumerable?,
                                    as_local : String | Symbol?, cached : Bool) : Nil
    _set_array(_jb_collection_scope(partial, collection, as_local, cached))
  end

  private def _jb_collection_scope(partial : String, collection : Enumerable?,
                                   as_local : String | Symbol?, cached : Bool) : Array(Node)
    local = (as_local || File.basename(partial)).to_s
    array = [] of Node
    collection.try &.each do |element|
      array << _jb_render_one(partial, local, element, cached)
    end
    array
  end

  private def _jb_render_one(partial : String, local : String, element, cached : Bool) : Node
    locals = {} of String => JBPartialLocal
    locals[local] = element.as(JBPartialLocal)

    if cached && ActionView.perform_caching
      cache_key = _jb_element_cache_key(element)
      if (hit = ActionView.cache_store.read(cache_key)) && hit != "null"
        return _to_node(JSON.parse(hit))
      end
      node = _scope { __jb_render_partial(partial, locals); nil }
      ActionView.cache_store.write(cache_key, _jb_node_json(node))
      node
    else
      _scope { __jb_render_partial(partial, locals); nil }
    end
  end

  # Ключ элемента коллекции: cache_key-метод (как model_cache_key) либо to_s.
  private def _jb_element_cache_key(element) : String
    if element.responds_to?(:cache_key)
      element.cache_key.to_s
    else
      element.to_s
    end
  end

  # ActiveSupport::Cache.expand_cache_key(key, :jbuilder):
  # "cache-key" → "jbuilder/cache-key", [:root, "key"] → "jbuilder/root/key".
  private def _jb_expand_cache_key(key) : String
    parts = ["jbuilder"]
    _jb_key_parts(key, parts)
    parts.join("/")
  end

  private def _jb_key_parts(key : String | Symbol, parts : Array(String)) : Nil
    parts << key.to_s
  end

  private def _jb_key_parts(key : Array(String | Symbol), parts : Array(String)) : Nil
    key.each { |k| _jb_key_parts(k, parts) }
  end

  private def _jb_key_parts(key : Nil, parts : Array(String)) : Nil
  end

  private def _jb_node_json(node : Node) : String
    String.build do |io|
      builder = JSON::Builder.new(io)
      builder.document do
        _write_json(node, builder)
      end
    end
  end

  # Ruby @attributes.present? — непустая структура уже определена.
  private def _jb_attributes_present? : Bool
    case (attrs = @attributes)
    when Hash(String, Node) then !attrs.empty?
    when Array(Node)        then !attrs.empty?
    else                         false
    end
  end
end
