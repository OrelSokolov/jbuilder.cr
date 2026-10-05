#!/usr/bin/env ruby
# Oracle cases for jbuilder.cr — порт jbuilder 2.14.1.
#
# Запуск против ОРИГИНАЛЬНОГО гема (см. AGENTS.md, oracle-first):
#   ruby oracle/cases.rb > oracle/expected.yml
#
# Каждая строка: "<case_id>\t<value>". Те же case id зеркалятся 1:1 в
# spec/oracle_spec.cr; порт обязан воспроизвести expected.yml точно.
# Value — почти всегда target! (JSON-строка); кейсы ошибок — "<Класс>" или
# "<Класс>: <message>" (сообщения сравниваются только там, где формат
# детерминирован между Ruby и Crystal; MergeError — только класс, т.к.
# Hash#inspect различается).

gem "jbuilder", "= 2.14.1"
require "jbuilder"
require "active_support/core_ext/string/inflections"

def case_run(id, value)
  puts "#{id}\t#{value}"
end

def jb(&block)
  Jbuilder.new(&block)
end

Person  = Struct.new(:name, :age, :email, keyword_init: true)
Comment = Struct.new(:content, :created_at, keyword_init: true)

david  = Person.new(name: "David", age: 32, email: "david@loudthinking.com")
jamie  = Person.new(name: "Jamie", age: 31, email: nil)
people = [david, jamie]
comments = [Comment.new(content: "hello", created_at: "2026-01-01"),
            Comment.new(content: "world", created_at: "2026-01-02")]

# --- Базовый DSL -----------------------------------------------------------

case_run "simple", jb { |json| json.name "David"; json.age 32 }.target!
case_run "nested", jb { |json| json.author { json.name "David"; json.age 32 } }.target!
case_run "nested_deep", jb { |json|
  json.author { json.address { json.city "Beijing"; json.zip "100000" } }
}.target!

case_run "bool_float_nil_value", jb { |json| json.ok true; json.pi 3.14; json.nothing nil }.target!
case_run "unicode", jb { |json| json.имя "Давид"; json.bio "line1\nline2\t\"quoted\"" }.target!

# --- array! ----------------------------------------------------------------

case_run "array_plain", jb { |json| json.array! [1, 2, 3] }.target!
case_run "array_nil", jb { |json| json.array!(nil) }.target!
case_run "array_nil_elements", jb { |json| json.array! [1, nil, "a"] }.target!
case_run "array_block", jb { |json|
  json.array!(people) { |p| json.name p.name; json.age p.age }
}.target!
case_run "array_attrs", jb { |json| json.array!(people, :name, :age) }.target!
case_run "array_named_block", jb { |json|
  json.people(people) { |p| json.name p.name }
}.target!
case_run "array_blank_dropped", jb { |json|
  json.array!([1, 2]) { |n| json.n n if n > 1 }
}.target!

# --- extract! / set! с атрибутами ------------------------------------------

case_run "extract_hash", jb { |json|
  json.extract!({ name: "David", age: 32, email: "d@x.com" }, :name, :age)
}.target!
case_run "extract_struct", jb { |json| json.extract!(david, :name, :age) }.target!
case_run "set_object_attrs", jb { |json| json.author david, :name, :age }.target!
case_run "set_collection_attrs", jb { |json| json.comments comments, :content, :created_at }.target!
case_run "call_extract", jb { |json| json.({ name: "David", age: 32 }, :name, :age) }.target!
case_run "call_array", jb { |json| json.(people) { |p| json.name p.name } }.target!

# --- child! / merge! / nil! -------------------------------------------------

case_run "child", jb { |json|
  json.comments do
    json.child! { json.content "hello" }
    json.child! { json.content "world" }
  end
}.target!
case_run "merge_hash", jb { |json| json.merge!({ a: 1, b: "x" }) }.target!
case_run "merge_jbuilder", jb { |json| json.merge!(jb { |j| j.inner 1 }) }.target!
case_run "nil!", jb { |json| json.nil! }.target!
case_run "null!", jb { |json| json.null! }.target!

# --- Повторная установка ключа (merge-семантика блоков) ---------------------

case_run "double_block_array", jb { |json|
  json.comments { json.child! { json.content "hello" } }
  json.comments { json.child! { json.content "world" } }
}.target!
case_run "double_block_hash", jb { |json|
  json.author { json.name "David" }
  json.author { json.age 32 }
}.target!

# --- Бланк-семантика --------------------------------------------------------

case_run "empty_block_skipped", jb { |json| json.foo { }; json.bar 1 }.target!
case_run "attributes_blank", jb { }.attributes!.inspect

# --- key_format! ------------------------------------------------------------

case_run "key_upcase", jb { |json| json.key_format! :upcase; json.first_name "David" }.target!
case_run "key_downcase", jb { |json| json.key_format! :downcase; json.first_name "David" }.target!
case_run "key_camelize_lower", jb { |json| json.key_format! camelize: :lower; json.first_name "David" }.target!
case_run "key_lambda", jb { |json| json.key_format! ->(k) { "_" + k }; json.first_name "David" }.target!
case_run "key_multi", jb { |json| json.key_format! :capitalize, :swapcase; json.first_name "David" }.target!

# --- ignore_nil! ------------------------------------------------------------

case_run "ignore_nil_on", jb { |json| json.ignore_nil!; json.id nil; json.name "D" }.target!
case_run "ignore_nil_off", jb { |json| json.id nil; json.name "D" }.target!

# --- deep_format_keys! --------------------------------------------------------

case_run "deep_off", jb { |json|
  json.key_format! camelize: :lower
  json.settings({ some_value: "abc", nested_key: { deep_one: 1 } })
}.target!
case_run "deep_on", jb { |json|
  json.key_format! camelize: :lower
  json.deep_format_keys!
  json.settings({ some_value: "abc", nested_key: { deep_one: 1 } })
}.target!
case_run "deep_on_array", jb { |json|
  json.key_format! camelize: :lower
  json.deep_format_keys!
  json.array!([{ a_b: 1 }, { c_d: [{ e_f: 2 }] }])
}.target!

# --- Jbuilder.encode / set! другого билдера ----------------------------------

case_run "encode", Jbuilder.encode { |json| json.name "David"; json.age 32 }
case_run "set_jbuilder_instance", jb { |json| json.person jb { |j| j.name "David" } }.target!

# --- Ошибки -------------------------------------------------------------------

begin
  jb { |json| json.nil!; json.age 32 }
rescue => e
  case_run "err_null", "#{e.class.name}: #{e.message}"
end

begin
  jb { |json| json.array! [1]; json.age 32 }
rescue => e
  case_run "err_array", "#{e.class.name}: #{e.message}"
end

begin
  jb { |json| json.ages [1, 2]; json.ages { json.x 1 } }
rescue => e
  # Hash#inspect различается между Ruby и Crystal — сверяется только класс
  case_run "err_merge", e.class.name
end
