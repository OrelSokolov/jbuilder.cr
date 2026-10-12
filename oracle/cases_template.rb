#!/usr/bin/env ruby
# Oracle cases for JbuilderTemplate — порт jbuilder/jbuilder_template.rb 2.14.1.
#
# Запуск против ОРИГИНАЛЬНОГО гема (см. AGENTS.md, oracle-first):
#   ruby oracle/cases_template.rb > oracle/expected_template.yml
#
# Без Rails (railtie гема не грузится): view собран на чистом ActionView
# (FixtureResolver), контроллер — фейк с perform_caching, Rails.cache —
# MemoryStore-стаб (его же использует CollectionRenderer для cached:).
# Кейсы зеркалят test/jbuilder_template_test.rb гема: partials, collection
# rendering, cache!/cache_if!/cache_root!, ошибки :layout/:spacer_template.
#
# Value — target! (JSON-строка); записи кэша — JSON.dump (в Crystal-порте
# фрагмент кэша хранится JSON-строкой — документированное отклонение).

gem "jbuilder", "= 2.14.1"
gem "actionview", "= 8.1.4"
# ВАЖНО: сначала "jbuilder" (ядро в lib/jbuilder.rb) — lib/jbuilder/jbuilder.rb
# это 3-строчный стаб, без него JbuilderTemplate наследует пустой класс.
require "jbuilder"
require "jbuilder/jbuilder_template"
require "active_support/cache/memory_store"
require "active_support/core_ext/integer/time"
require "action_view/base"
require "action_view/testing/resolvers"
require "json"

# Регистрация хендлера (то, что без Rails делает railtie гема).
ActionView::Template.register_template_handler :jbuilder, JbuilderHandler

# --- Стабы Rails (без railtie) ----------------------------------------------

module Rails
  @cache = ActiveSupport::Cache::MemoryStore.new
  def self.cache = @cache
end

Jbuilder::CollectionRenderer.collection_cache = Rails.cache

class FakeController
  attr_accessor :perform_caching

  def initialize(perform_caching: false)
    @perform_caching = perform_caching
  end

  # jbuilder: @context.controller.instrument_fragment_cache(:read_fragment, key) { .. }
  def instrument_fragment_cache(*)
    yield
  end
end

Post = Struct.new(:id, :body, :author_name) do
  def cache_key = "post-#{id}"
end

AUTHORS = ["David Heinemeier Hansson", "Pavel Pravosud"].cycle
POSTS = (1..3).collect { |i| Post.new(i, "Post ##{i}", AUTHORS.next) }.freeze
PARTIALS = {
  "_partial.json.jbuilder"      => "json.content content",
  "_post.json.jbuilder"         => <<~JBUILDER,
    json.extract! post, :id, :body
    json.author do
      first_name, last_name = post.author_name.split(nil, 2)
      json.first_name first_name
      json.last_name last_name
    end
  JBUILDER
  "racers/_racer.json.jbuilder" => "json.extract! racer, :id, :name",
}.freeze

def case_run(id, value)
  puts "#{id}\t#{value}"
end

def build_view(source, assigns = {}, perform_caching: false)
  fixtures = PARTIALS.merge("source.json.jbuilder" => source)
  resolver = ActionView::FixtureResolver.new(fixtures)
  lookup_context = ActionView::LookupContext.new([resolver], {}, [""])
  view = ActionView::Base.with_empty_template_cache.new(
    lookup_context, assigns, FakeController.new(perform_caching: perform_caching)
  )

  # Как в тестах гема (build_view): явные ключи фрагментов, без digest.
  def view.view_cache_dependencies = []
  def view.combined_fragment_cache_key(key) = [key]
  def view.cache_fragment_name(key, *) = key
  def view.fragment_name_with_digest(key) = key

  view
end

def render(source, assigns = {}, perform_caching: false)
  build_view(source, assigns, perform_caching: perform_caching).render(template: "source")
end

# --- Партиалы -----------------------------------------------------------------

case_run "tpl_basic", render('json.content "hello"')
case_run "tpl_partial_locals_top", render('json.partial! "partial", content: "hello"')
case_run "tpl_partial_locals_nested", render('json.partial! "partial", locals: { content: "hello" }')
case_run "tpl_partial_by_options", render('json.partial! partial: "partial", locals: { content: "hello" }')
Racer = Struct.new(:id, :name)
case_run "tpl_partial_subdir", render('json.partial! "racers/racer", racer: @racer', {racer: Racer.new(123, "Chris Harris")})

# --- Коллекции ----------------------------------------------------------------

case_run "tpl_partial_collection", render('json.partial! "post", collection: @posts, as: :post', {posts: POSTS})
case_run "tpl_partial_collection_string_as", render('json.partial! "post", collection: @posts, as: "post"', {posts: POSTS})
case_run "tpl_partial_collection_by_options", render('json.partial! partial: "post", collection: @posts, as: :post', {posts: POSTS})
case_run "tpl_nil_collection", render('json.partial! "post", collection: @posts, as: :post', {posts: nil})
case_run "tpl_array_partials", render('json.array! @posts, partial: "post", as: :post', {posts: POSTS})
case_run "tpl_array_partials_empty", render('json.array! @posts, partial: "post", as: :post', {posts: []})
case_run "tpl_array_partials_nil", render('json.array! @posts, partial: "post", as: :post', {posts: nil})
case_run "tpl_array_partials_under_key", render('json.posts @posts, partial: "post", as: :post', {posts: POSTS})
case_run "tpl_array_partials_under_key_nil", render('json.posts @posts, partial: "post", as: :post', {posts: nil})

# --- cached: true (CollectionRenderer + collection_cache) ---------------------

Rails.cache.clear
case_run "tpl_cached_option", render('json.array! @posts, partial: "post", as: :post, cached: true', {posts: POSTS}, perform_caching: true)
case_run "tpl_cached_entry", JSON.dump(Rails.cache.read("post-1"))
# Повторный рендер — из кэша коллекции.
case_run "tpl_cached_option_hit", render('json.array! @posts, partial: "post", as: :post, cached: true', {posts: POSTS}, perform_caching: true)

# --- cache! / cache_if! / cache_root! ------------------------------------------

Rails.cache.clear
case_run "tpl_cache_off_passthrough", render(<<~JBUILDER, perform_caching: false)
  json.cache! "cache-key" do
    json.name "Fresh"
  end
JBUILDER
case_run "tpl_cache_off_stored_nil", Rails.cache.read("jbuilder/cache-key").inspect

Rails.cache.clear
case_run "tpl_cache_miss", render(<<~JBUILDER, perform_caching: true)
  json.cache! "cache-key" do
    json.name "Hit"
  end
JBUILDER
case_run "tpl_cache_hit", render('json.cache! "cache-key" do; end', perform_caching: true)
case_run "tpl_cache_entry", JSON.dump(Rails.cache.read("jbuilder/cache-key"))

Rails.cache.clear
case_run "tpl_cache_array", render(<<~JBUILDER, perform_caching: true)
  json.cache! "cache-key" do
    json.array! %w[ a b c ]
  end
JBUILDER
case_run "tpl_cache_array_hit", render('json.cache! "cache-key" do; end', perform_caching: true)

Rails.cache.clear
case_run "tpl_cache_expiry_zero", render(<<~JBUILDER, perform_caching: true)
  json.cache! "expiry-key", expires_in: 0.seconds do
    json.name "Miss"
  end
JBUILDER

case_run "tpl_empty_fragment", render(<<~JBUILDER, perform_caching: true)
  json.foo "bar"
  json.cache! "nothing" do; end
JBUILDER

Rails.cache.clear
case_run "tpl_cache_if", render(<<~JBUILDER, perform_caching: true)
  json.cache_if! true, "cache-key" do
    json.a "Hit"
  end

  json.cache_if! false, "cache-key" do
    json.b "Fresh"
  end
JBUILDER
case_run "tpl_cache_if_miss", render(<<~JBUILDER, perform_caching: true)
  json.cache_if! true, "cache-key" do
    json.a "Miss"
  end
JBUILDER

Rails.cache.clear
case_run "tpl_cache_root", render(<<~JBUILDER, perform_caching: true)
  json.cache_root! "cache-key" do
    json.name "Hit"
  end
JBUILDER
case_run "tpl_cache_root_entry", JSON.dump(Rails.cache.read("jbuilder/root/cache-key"))
case_run "tpl_cache_root_hit", render(<<~JBUILDER, perform_caching: true)
  json.cache_root! "cache-key" do
    json.name "Miss"
  end
JBUILDER
case_run "tpl_cache_root_array", render(<<~JBUILDER, perform_caching: true)
  json.cache_root! "arr-key" do
    json.array! %w[ d e f ]
  end
JBUILDER

begin
  render(<<~JBUILDER, perform_caching: true)
    json.name "Kaboom"
    json.cache_root! "cache-key" do
      json.name "Miss"
    end
  JBUILDER
rescue => e
  # Класс — ActionView::Template::Error (обёртка Rails); в Crystal-порту это
  # RuntimeError с тем же сообщением — сравнивается только сообщение.
  case_run "tpl_cache_root_error", e.message
end

# --- Ошибки опций коллекций -----------------------------------------------------

begin
  render('json.array! @posts, partial: "post", as: :post, layout: "layout"', {posts: POSTS})
rescue NotImplementedError => e
  case_run "tpl_layout_error", "#{e.class.name}: #{e.message}"
end

begin
  render('json.array! @posts, partial: "post", as: :post, spacer_template: "template"', {posts: POSTS})
rescue NotImplementedError => e
  case_run "tpl_spacer_error", "#{e.class.name}: #{e.message}"
end
