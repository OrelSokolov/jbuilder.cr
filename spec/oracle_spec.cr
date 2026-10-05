# Oracle spec: порт обязан воспроизвести oracle/expected.yml (снятом с
# настоящего jbuilder 2.14.1 через oracle/cases.rb) — 1:1 те же case id.
# Значения — escape-протокол \n/\t/\r, как в остальных шардах.

require "spec"
require "../src/jbuilder_cr"

EXPECTED = begin
  hash = {} of String => String
  File.read("#{__DIR__}/../oracle/expected.yml").each_line do |line|
    if line.includes?('\t')
      id, value = line.split('\t', 2)
      hash[id] = value.chomp
    end
  end
  hash
end

def check(id, value)
  # Значения oracle — JSON-строки без сырых \n/\t (контрольные символы
  # экранированы самим JSON), сравнение напрямую.
  (EXPECTED[id]? || "MISSING #{id}").should eq value.to_s
end

def jb(&block : Jbuilder -> _)
  Jbuilder.new(&block)
end

def jb
  Jbuilder.new
end

record Person, name : String, age : Int32, email : String?
record Comment, content : String, created_at : String

DAVID  = Person.new("David", 32, "david@loudthinking.com")
JAMIE  = Person.new("Jamie", 31, nil)
PEOPLE = [DAVID, JAMIE]
COMMENTS = [Comment.new("hello", "2026-01-01"), Comment.new("world", "2026-01-02")]

describe "Jbuilder oracle" do
  # --- Базовый DSL ----------------------------------------------------------

  it "simple" do
    check "simple", jb { |json| json.name "David"; json.age 32 }.target!
  end

  it "nested" do
    check "nested", jb { |json| json.author { json.name "David"; json.age 32 } }.target!
  end

  it "nested_deep" do
    check "nested_deep", jb { |json|
      json.author { json.address { json.city "Beijing"; json.zip "100000" } }
    }.target!
  end

  it "bool_float_nil_value" do
    check "bool_float_nil_value", jb { |json| json.ok true; json.pi 3.14; json.nothing nil }.target!
  end

  it "unicode" do
    check "unicode", jb { |json| json.имя "Давид"; json.bio "line1\nline2\t\"quoted\"" }.target!
  end

  # --- array! ---------------------------------------------------------------

  it "array_plain" do
    check "array_plain", jb { |json| json.array! [1, 2, 3] }.target!
  end

  it "array_nil" do
    check "array_nil", jb { |json| json.array!(nil) }.target!
  end

  it "array_nil_elements" do
    check "array_nil_elements", jb { |json| json.array! [1, nil, "a"] }.target!
  end

  it "array_block" do
    check "array_block", jb { |json|
      json.array!(PEOPLE) { |p| json.name p.name; json.age p.age }
    }.target!
  end

  it "array_attrs" do
    check "array_attrs", jb { |json| json.array!(PEOPLE, :name, :age) }.target!
  end

  it "array_named_block" do
    check "array_named_block", jb { |json|
      json.people(PEOPLE) { |p| json.name p.name }
    }.target!
  end

  it "array_blank_dropped" do
    check "array_blank_dropped", jb { |json|
      json.array!([1, 2]) { |n| json.n n if n > 1 }
    }.target!
  end

  # --- extract! / set! с атрибутами -----------------------------------------

  it "extract_hash" do
    check "extract_hash", jb { |json|
      json.extract!({ name: "David", age: 32, email: "d@x.com" }, :name, :age)
    }.target!
  end

  it "extract_struct" do
    check "extract_struct", jb { |json| json.extract!(DAVID, :name, :age) }.target!
  end

  it "set_object_attrs" do
    check "set_object_attrs", jb { |json| json.author DAVID, :name, :age }.target!
  end

  it "set_collection_attrs" do
    check "set_collection_attrs", jb { |json| json.comments COMMENTS, :content, :created_at }.target!
  end

  it "call_extract" do
    check "call_extract", jb { |json| json.call({ name: "David", age: 32 }, :name, :age) }.target!
  end

  it "call_array" do
    check "call_array", jb { |json| json.call(PEOPLE) { |p| json.name p.name } }.target!
  end

  # --- child! / merge! / nil! -------------------------------------------------

  it "child" do
    check "child", jb { |json|
      json.comments do
        json.child! { json.content "hello" }
        json.child! { json.content "world" }
      end
    }.target!
  end

  it "merge_hash" do
    check "merge_hash", jb { |json| json.merge!({ a: 1, b: "x" }) }.target!
  end

  it "merge_jbuilder" do
    check "merge_jbuilder", jb { |json| json.merge!(jb { |j| j.inner 1 }) }.target!
  end

  it "nil!" do
    check "nil!", jb { |json| json.nil! }.target!
  end

  it "null!" do
    check "null!", jb { |json| json.null! }.target!
  end

  # --- Повторная установка ключа ----------------------------------------------

  it "double_block_array" do
    check "double_block_array", jb { |json|
      json.comments { json.child! { json.content "hello" } }
      json.comments { json.child! { json.content "world" } }
    }.target!
  end

  it "double_block_hash" do
    check "double_block_hash", jb { |json|
      json.author { json.name "David" }
      json.author { json.age 32 }
    }.target!
  end

  # --- Бланк-семантика --------------------------------------------------------

  it "empty_block_skipped" do
    check "empty_block_skipped", jb { |json| json.foo { }; json.bar 1 }.target!
  end

  it "attributes_blank" do
    check "attributes_blank", jb.attributes!.inspect
  end

  # --- key_format! -------------------------------------------------------------

  it "key_upcase" do
    check "key_upcase", jb { |json| json.key_format! :upcase; json.first_name "David" }.target!
  end

  it "key_downcase" do
    check "key_downcase", jb { |json| json.key_format! :downcase; json.first_name "David" }.target!
  end

  it "key_camelize_lower" do
    check "key_camelize_lower", jb { |json| json.key_format! camelize: :lower; json.first_name "David" }.target!
  end

  it "key_lambda" do
    check "key_lambda", jb { |json| json.key_format! ->(k : String) { "_" + k }; json.first_name "David" }.target!
  end

  it "key_multi" do
    check "key_multi", jb { |json| json.key_format! :capitalize, :swapcase; json.first_name "David" }.target!
  end

  # --- ignore_nil! ---------------------------------------------------------------

  it "ignore_nil_on" do
    check "ignore_nil_on", jb { |json| json.ignore_nil!; json.id nil; json.name "D" }.target!
  end

  it "ignore_nil_off" do
    check "ignore_nil_off", jb { |json| json.id nil; json.name "D" }.target!
  end

  # --- deep_format_keys! ----------------------------------------------------------

  it "deep_off" do
    check "deep_off", jb { |json|
      json.key_format! camelize: :lower
      json.settings({ some_value: "abc", nested_key: { deep_one: 1 } })
    }.target!
  end

  it "deep_on" do
    check "deep_on", jb { |json|
      json.key_format! camelize: :lower
      json.deep_format_keys!
      json.settings({ some_value: "abc", nested_key: { deep_one: 1 } })
    }.target!
  end

  it "deep_on_array" do
    check "deep_on_array", jb { |json|
      json.key_format! camelize: :lower
      json.deep_format_keys!
      json.array!([{ a_b: 1 }, { c_d: [{ e_f: 2 }] }])
    }.target!
  end

  # --- encode / set! другого билдера ---------------------------------------------

  it "encode" do
    check "encode", Jbuilder.encode { |json| json.name "David"; json.age 32 }
  end

  it "set_jbuilder_instance" do
    check "set_jbuilder_instance", jb { |json| json.person jb { |j| j.name "David" } }.target!
  end

  # --- Ошибки -----------------------------------------------------------------------

  it "err_null" do
    e = expect_raises(Jbuilder::NullError) do
      jb { |json| json.nil!; json.age 32 }
    end
    check "err_null", "#{e.class.name}: #{e.message}"
  end

  it "err_array" do
    e = expect_raises(Jbuilder::ArrayError) do
      jb { |json| json.array! [1]; json.age 32 }
    end
    check "err_array", "#{e.class.name}: #{e.message}"
  end

  it "err_merge" do
    e = expect_raises(Jbuilder::MergeError) do
      jb { |json| json.ages [1, 2]; json.ages { json.x 1 } }
    end
    # Hash#inspect различается между Ruby и Crystal — сверяется только класс
    check "err_merge", e.class.name
  end
end
