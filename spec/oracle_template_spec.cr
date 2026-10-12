# Oracle spec: JbuilderTemplate обязан воспроизвести
# oracle/expected_template.yml (снятом с настоящего jbuilder 2.14.1 через
# oracle/cases_template.rb) — 1:1 те же case id.

require "spec"
require "../src/jbuilder_cr"

EXPECTED_TEMPLATE = begin
  hash = {} of String => String
  File.read("#{__DIR__}/../oracle/expected_template.yml").each_line do |line|
    if line.includes?('\t')
      id, value = line.split('\t', 2)
      hash[id] = value.chomp
    end
  end
  hash
end

def check_tpl(id, value)
  (EXPECTED_TEMPLATE[id]? || "MISSING #{id}").should eq value.to_s
end

class TplPost
  property id : Int32
  property body : String
  property author_name : String

  def initialize(@id, @body, @author_name)
  end

  def cache_key : String
    "post-#{@id}"
  end
end

class TplRacer
  property id : Int32
  property name : String

  def initialize(@id, @name)
  end
end

TPL_POSTS = (1..3).map { |i| TplPost.new(i, "Post ##{i}", i.odd? ? "David Heinemeier Hansson" : "Pavel Pravosud") }

class JbuilderTemplate
  compile_partials({
    "partial"      => {path: "spec/fixtures/_partial.json.jbuilder",       locals: {"content" => String}},
    "post"         => {path: "spec/fixtures/_post.json.jbuilder",          locals: {"post" => TplPost}},
    "racers/racer" => {path: "spec/fixtures/racers/_racer.json.jbuilder",  locals: {"racer" => TplRacer}},
  })
end

def tpl(&block : JbuilderTemplate -> _)
  JbuilderTemplate.new(&block)
end

def tpl
  JbuilderTemplate.new
end

def with_memory_cache
  ActionView.cache_store = ActiveSupport::Cache.lookup_store(:memory_store)
  ActionView.cache_store.clear
  ActionView.perform_caching = false
end

describe "JbuilderTemplate oracle" do
  before_each { with_memory_cache }

  # --- Партиалы ---------------------------------------------------------------

  it "tpl_basic" do
    check_tpl "tpl_basic", tpl { |json| json.content "hello" }.target!
  end

  it "tpl_partial_locals_top" do
    check_tpl "tpl_partial_locals_top", tpl { |json|
      json.partial! "partial", {"content" => "hello"}
    }.target!
  end

  it "tpl_partial_locals_nested" do
    check_tpl "tpl_partial_locals_nested", tpl { |json|
      json.partial! "partial", {"content" => "hello"}
    }.target!
  end

  it "tpl_partial_by_options" do
    check_tpl "tpl_partial_by_options", tpl { |json|
      json.partial! "partial", {"content" => "hello"}
    }.target!
  end

  it "tpl_partial_subdir" do
    check_tpl "tpl_partial_subdir", tpl { |json|
      json.partial! "racers/racer", {"racer" => TplRacer.new(123, "Chris Harris")}
    }.target!
  end

  # --- Коллекции ----------------------------------------------------------------

  it "tpl_partial_collection" do
    check_tpl "tpl_partial_collection", tpl { |json|
      json.partial! "post", collection: TPL_POSTS, as_local: "post"
    }.target!
  end

  it "tpl_partial_collection_string_as" do
    check_tpl "tpl_partial_collection_string_as", tpl { |json|
      json.partial! "post", collection: TPL_POSTS, as_local: "post"
    }.target!
  end

  it "tpl_partial_collection_by_options" do
    check_tpl "tpl_partial_collection_by_options", tpl { |json|
      json.partial! partial: "post", collection: TPL_POSTS, as_local: "post"
    }.target!
  end

  it "tpl_nil_collection" do
    check_tpl "tpl_nil_collection", tpl { |json|
      json.partial! "post", collection: nil, as_local: "post"
    }.target!
  end

  it "tpl_array_partials" do
    check_tpl "tpl_array_partials", tpl { |json|
      json.array! TPL_POSTS, partial: "post", as_local: "post"
    }.target!
  end

  it "tpl_array_partials_empty" do
    check_tpl "tpl_array_partials_empty", tpl { |json|
      json.array! [] of TplPost, partial: "post", as_local: "post"
    }.target!
  end

  it "tpl_array_partials_nil" do
    check_tpl "tpl_array_partials_nil", tpl { |json|
      json.array! nil, partial: "post", as_local: "post"
    }.target!
  end

  it "tpl_array_partials_under_key" do
    check_tpl "tpl_array_partials_under_key", tpl { |json|
      json.posts TPL_POSTS, partial: "post", as_local: "post"
    }.target!
  end

  it "tpl_array_partials_under_key_nil" do
    check_tpl "tpl_array_partials_under_key_nil", tpl { |json|
      json.posts nil, partial: "post", as_local: "post"
    }.target!
  end

  # --- cached: true -------------------------------------------------------------

  it "tpl_cached_option" do
    ActionView.perform_caching = true
    check_tpl "tpl_cached_option", tpl { |json|
      json.array! TPL_POSTS, partial: "post", as_local: "post", cached: true
    }.target!
  end

  it "tpl_cached_entry" do
    ActionView.perform_caching = true
    tpl { |json| json.array! TPL_POSTS, partial: "post", as_local: "post", cached: true }
    # Ruby-оракул хранит Hash и сравнивается через JSON.dump; порт хранит
    # JSON-строку — сравниваем распарсенное содержимое.
    check_tpl "tpl_cached_entry", JSON.parse(ActionView.cache_store.read("post-1").not_nil!).to_json
  end

  it "tpl_cached_option_hit" do
    ActionView.perform_caching = true
    tpl { |json| json.array! TPL_POSTS, partial: "post", as_local: "post", cached: true }
    check_tpl "tpl_cached_option_hit", tpl { |json|
      json.array! TPL_POSTS, partial: "post", as_local: "post", cached: true
    }.target!
  end

  # --- cache! / cache_if! / cache_root! --------------------------------------------

  it "tpl_cache_off_passthrough" do
    check_tpl "tpl_cache_off_passthrough", tpl { |json|
      json.cache! "cache-key" { json.name "Fresh" }
    }.target!
  end

  it "tpl_cache_off_stored_nil" do
    tpl { |json| json.cache! "cache-key" { json.name "Fresh" } }
    check_tpl "tpl_cache_off_stored_nil", ActionView.cache_store.read("jbuilder/cache-key").inspect
  end

  it "tpl_cache_miss_and_hit" do
    ActionView.perform_caching = true
    check_tpl "tpl_cache_miss", tpl { |json|
      json.cache! "cache-key" { json.name "Hit" }
    }.target!
    check_tpl "tpl_cache_hit", tpl { |json|
      json.cache! "cache-key" { }
    }.target!
    check_tpl "tpl_cache_entry", JSON.parse(ActionView.cache_store.read("jbuilder/cache-key").not_nil!).to_json
  end

  it "tpl_cache_array" do
    ActionView.perform_caching = true
    check_tpl "tpl_cache_array", tpl { |json|
      json.cache! "cache-key" { json.array! ["a", "b", "c"] }
    }.target!
    check_tpl "tpl_cache_array_hit", tpl { |json|
      json.cache! "cache-key" { }
    }.target!
  end

  it "tpl_cache_expiry_zero" do
    ActionView.perform_caching = true
    json = JbuilderTemplate.new
    json.cache! "expiry-key", expires_in: Time::Span.zero do
      json.name "Miss"
    end
    check_tpl "tpl_cache_expiry_zero", json.target!
  end

  it "tpl_empty_fragment" do
    ActionView.perform_caching = true
    check_tpl "tpl_empty_fragment", tpl { |json|
      json.foo "bar"
      json.cache! "nothing" { }
    }.target!
  end

  it "tpl_cache_if" do
    ActionView.perform_caching = true
    check_tpl "tpl_cache_if", tpl { |json|
      json.cache_if! true, "cache-key" { json.a "Hit" }
      json.cache_if! false, "cache-key" { json.b "Fresh" }
    }.target!
    check_tpl "tpl_cache_if_miss", tpl { |json|
      json.cache_if! true, "cache-key" { json.a "Miss" }
    }.target!
  end

  it "tpl_cache_root" do
    ActionView.perform_caching = true
    check_tpl "tpl_cache_root", tpl { |json|
      json.cache_root! "cache-key" { json.name "Hit" }
    }.target!
    # Ruby-оракул: JSON.dump хранит фрагмент строкой JSON — так же сравниваем.
    check_tpl "tpl_cache_root_entry", ActionView.cache_store.read("jbuilder/root/cache-key").to_s.to_json
    check_tpl "tpl_cache_root_hit", tpl { |json|
      json.cache_root! "cache-key" { json.name "Miss" }
    }.target!
    check_tpl "tpl_cache_root_array", tpl { |json|
      json.cache_root! "arr-key" { json.array! ["d", "e", "f"] }
    }.target!
  end

  it "tpl_cache_root_error" do
    ActionView.perform_caching = true
    # Ruby оборачивает в ActionView::Template::Error (Rails-артефакт);
    # оракул хранит только сообщение — класс-обёртки в порту нет.
    error = expect_raises RuntimeError, "cache_root! can't be used after JSON structures have been defined" do
      tpl { |json|
        json.name "Kaboom"
        json.cache_root! "cache-key" { json.name "Miss" }
      }
    end
    check_tpl "tpl_cache_root_error", error.message.to_s
  end

  # --- Ошибки опций коллекций ---------------------------------------------------------

  it "tpl_layout_error" do
    error = expect_raises NotImplementedError do
      tpl { |json| json.array! TPL_POSTS, partial: "post", as_local: "post", layout: "layout" }
    end
    # Crystal NotImplementedError добавляет префикс "Not Implemented: ".
    check_tpl "tpl_layout_error", "#{error.class.name}: #{error.message.to_s.sub("Not Implemented: ", "")}"
  end

  it "tpl_spacer_error" do
    error = expect_raises NotImplementedError do
      tpl { |json| json.array! TPL_POSTS, partial: "post", as_local: "post", spacer_template: "template" }
    end
    check_tpl "tpl_spacer_error", "#{error.class.name}: #{error.message.to_s.sub("Not Implemented: ", "")}"
  end
end
