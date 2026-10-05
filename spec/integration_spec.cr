# Интеграционные тесты — порт официального сьюта rails/jbuilder v2.14.1
# (test/jbuilder_test.rb), адаптированный под Crystal:
#   * json.(obj, :attr) → json.call(obj, :attr) (в Crystal нет call-синтаксиса .());
#   * ассерты через JSON.parse(target!) вместо Ruby-хеша;
#   * исключены тесты на руби-метапрограммирование (BasicObject-обёртка,
#     NonEnumerable с delegate :map/:count), :pluralize-инфлектор,
#     Time#as_json и инспекцию внутреннего кеша форматтера;
#   * 'handles nil-collections as empty arrays' добавляет явную семантику
#     set!(key, nil, &block) → [].

require "spec"
require "json"
require "../src/jbuilder_cr"

def jbuild(&block : Jbuilder -> _)
  Jbuilder.new(&block)
end

# Оригинальный Person: не Struct (Struct в Ruby Enumerable), только ридеры.
class JBPerson
  getter name : String
  getter age : Int32

  def initialize(@name, @age)
  end
end

class JBComment
  getter content : String
  getter id : Int32

  def initialize(@content, @id)
  end
end

class RelationMock
  include Enumerable(JBPerson)

  def each(&)
    yield JBPerson.new("Bob", 30)
    yield JBPerson.new("Frank", 50)
  end
end

INT_COMMENTS = [JBComment.new("hello", 1), JBComment.new("world", 2)]

def result(builder : Jbuilder) : JSON::Any
  JSON.parse(builder.target!)
end

describe "jbuilder_test.rb (оригинал, порт)" do
  it "single key" do
    r = result jbuild { |json| json.content "hello" }
    r["content"].as_s.should eq "hello"
  end

  it "single key with false value" do
    r = result jbuild { |json| json.content false }
    r["content"].as_bool.should be_false
  end

  it "single key with nil value" do
    r = result jbuild { |json| json.content nil }
    r["content"].as_nil.should be_nil # ключ присутствует со значением null
  end

  it "multiple keys" do
    r = result jbuild { |json| json.title "hello"; json.content "world" }
    r["title"].as_s.should eq "hello"
    r["content"].as_s.should eq "world"
  end

  it "extracting from object" do
    person = {name: "David", age: 32}
    r = result jbuild { |json| json.extract! person, :name, :age }
    r["name"].as_s.should eq "David"
    r["age"].as_i.should eq 32
  end

  it "extracting from object using call style" do
    person = {name: "David", age: 32}
    r = result jbuild { |json| json.call person, :name, :age }
    r["name"].as_s.should eq "David"
    r["age"].as_i.should eq 32
  end

  it "extracting from hash" do
    person = {name: "Jim", age: 34}
    r = result jbuild { |json| json.extract! person, :name, :age }
    r["name"].as_s.should eq "Jim"
    r["age"].as_i.should eq 34
  end

  it "nesting single child with block" do
    r = result jbuild { |json|
      json.author do
        json.name "David"
        json.age 32
      end
    }
    r["author"]["name"].as_s.should eq "David"
    r["author"]["age"].as_i.should eq 32
  end

  it "empty block handling" do
    r = result jbuild { |json| json.foo "bar"; json.author { } }
    r["foo"].as_s.should eq "bar"
    r.as_h.has_key?("author").should be_false
  end

  it "blocks are additive" do
    r = result jbuild { |json|
      json.author { json.name "David" }
      json.author { json.age 32 }
    }
    r["author"]["name"].as_s.should eq "David"
    r["author"]["age"].as_i.should eq 32
  end

  it "nested blocks are additive" do
    r = result jbuild { |json|
      json.author { json.name { json.first "David" } }
      json.author { json.name { json.last "Heinemeier Hansson" } }
    }
    r["author"]["name"]["first"].as_s.should eq "David"
    r["author"]["name"]["last"].as_s.should eq "Heinemeier Hansson"
  end

  it "support merge! method" do
    r = result jbuild { |json| json.merge!({"foo" => "bar"}) }
    r["foo"].as_s.should eq "bar"
  end

  it "support merge! method in a block" do
    r = result jbuild { |json| json.author { json.merge!({"name" => "Pavel"}) } }
    r["author"]["name"].as_s.should eq "Pavel"
  end

  it "support merge! method with Jbuilder instance" do
    obj = jbuild { |json| json.foo "bar" }
    r = result jbuild { |json| json.merge!(obj) }
    r["foo"].as_s.should eq "bar"
  end

  it "blocks are additive via extract syntax" do
    person = JBPerson.new("Pavel", 27)
    r = result jbuild { |json|
      json.author person, :age
      json.author person, :name
    }
    r["author"]["name"].as_s.should eq "Pavel"
    r["author"]["age"].as_i.should eq 27
  end

  it "arrays are additive" do
    r = result jbuild { |json| json.array! ["foo"]; json.array! ["bar"] }
    r.as_a.map(&.as_s).should eq ["foo", "bar"]
  end

  it "nesting multiple children with block" do
    r = result jbuild { |json|
      json.comments do
        json.child! { json.content "hello" }
        json.child! { json.content "world" }
      end
    }
    r["comments"].as_a.map(&.["content"].as_s).should eq ["hello", "world"]
  end

  it "nesting single child with inline extract" do
    person = JBPerson.new("David", 32)
    r = result jbuild { |json| json.author person, :name, :age }
    r["author"]["name"].as_s.should eq "David"
    r["author"]["age"].as_i.should eq 32
  end

  it "nesting multiple children from array" do
    r = result jbuild { |json| json.comments INT_COMMENTS, :content }
    r["comments"].as_a.map(&.["content"].as_s).should eq ["hello", "world"]
    r["comments"].as_a.first.as_h.keys.should eq ["content"]
  end

  it "nesting multiple children from array when child array is empty" do
    comments = [] of JBComment
    r = result jbuild { |json| json.name "Parent"; json.comments comments, :content }
    r["name"].as_s.should eq "Parent"
    r["comments"].as_a.should be_empty
  end

  it "nesting multiple children from array with inline loop" do
    r = result jbuild { |json|
      json.comments INT_COMMENTS do |comment|
        json.content comment.content
      end
    }
    r["comments"].as_a.map(&.["content"].as_s).should eq ["hello", "world"]
  end

  it "handles nil-collections as empty arrays" do
    r = result jbuild { |json|
      json.comments nil do |comment|
        json.content comment.content
      end
    }
    r["comments"].as_a.should be_empty
  end

  it "nesting multiple children from array with inline loop on root" do
    r = result jbuild { |json|
      json.call INT_COMMENTS do |comment|
        json.content comment.content
      end
    }
    r.as_a.map(&.["content"].as_s).should eq ["hello", "world"]
  end

  it "array nested inside nested hash" do
    r = result jbuild { |json|
      json.author do
        json.name "David"
        json.age 32
        json.comments do
          json.child! { json.content "hello" }
          json.child! { json.content "world" }
        end
      end
    }
    r["author"]["comments"].as_a.map(&.["content"].as_s).should eq ["hello", "world"]
  end

  it "array nested inside array" do
    r = result jbuild { |json|
      json.comments do
        json.child! do
          json.authors do
            json.child! { json.name "david" }
          end
        end
      end
    }
    r["comments"].as_a[0]["authors"].as_a[0]["name"].as_s.should eq "david"
  end

  it "directly set an array nested in another array" do
    data = [{department: "QA", not_in_json: "hello", names: ["John", "David"]}]
    r = result jbuild { |json|
      json.array! data do |object|
        json.department object[:department]
        json.names do
          json.array! object[:names]
        end
      end
    }
    r.as_a[0]["names"].as_a.last.as_s.should eq "David"
    r.as_a.first.as_h.has_key?("not_in_json").should be_false
  end

  it "nested jbuilder objects" do
    to_nest = Jbuilder.new { |json| json.nested_value "Nested Test" }
    r = result jbuild { |json| json.value "Test"; json.nested to_nest }
    r["value"].as_s.should eq "Test"
    r["nested"]["nested_value"].as_s.should eq "Nested Test"
  end

  it "nested jbuilder object via set!" do
    to_nest = Jbuilder.new { |json| json.nested_value "Nested Test" }
    r = result jbuild { |json| json.value "Test"; json.set! :nested, to_nest }
    r["nested"]["nested_value"].as_s.should eq "Nested Test"
  end

  it "top-level array" do
    r = result jbuild { |json|
      json.array! INT_COMMENTS do |comment|
        json.content comment.content
      end
    }
    r.as_a.map(&.["content"].as_s).should eq ["hello", "world"]
  end

  it "it allows using next in array block to skip value" do
    comments = [JBComment.new("hello", 1), JBComment.new("skip", 2), JBComment.new("world", 3)]
    r = result jbuild { |json|
      json.array! comments do |comment|
        next if comment.id == 2
        json.content comment.content
      end
    }
    r.as_a.size.should eq 2
    r.as_a.map(&.["content"].as_s).should eq ["hello", "world"]
  end

  it "extract attributes directly from array" do
    r = result jbuild { |json| json.array! INT_COMMENTS, :content, :id }
    r.as_a[0]["content"].as_s.should eq "hello"
    r.as_a[0]["id"].as_i.should eq 1
    r.as_a[1]["content"].as_s.should eq "world"
    r.as_a[1]["id"].as_i.should eq 2
  end

  it "empty top-level array" do
    comments = [] of JBComment
    r = result jbuild { |json|
      json.array! comments do |comment|
        json.content comment.content
      end
    }
    r.as_a.should be_empty
  end

  it "dynamically set a key/value" do
    r = result jbuild { |json| json.set! :each, "stuff" }
    r["each"].as_s.should eq "stuff"
  end

  it "dynamically set a key/nested child with block" do
    r = result jbuild { |json|
      json.set! :author do
        json.name "David"
        json.age 32
      end
    }
    r["author"]["name"].as_s.should eq "David"
    r["author"]["age"].as_i.should eq 32
  end

  it "dynamically sets a collection" do
    r = result jbuild { |json| json.set! :comments, INT_COMMENTS, :content }
    r["comments"].as_a.map(&.["content"].as_s).should eq ["hello", "world"]
  end

  it "query like object" do
    r = result jbuild { |json| json.relations RelationMock.new, :name, :age }
    r["relations"].as_a.size.should eq 2
    r["relations"].as_a[0]["name"].as_s.should eq "Bob"
    r["relations"].as_a[1]["age"].as_i.should eq 50
  end

  it "initialize via options hash" do
    formatter = Jbuilder::KeyFormatter.new([:upcase])
    builder = Jbuilder.new(key_formatter: formatter, ignore_nil: true)
    builder.set!("x", nil)
    builder.target!.should eq "{}"
  end

  it "key_format! with parameter" do
    r = result jbuild { |json| json.key_format! camelize: :lower; json.camel_style "for JS" }
    r.as_h.keys.should eq ["camelStyle"]
  end

  it "key_format! propagates to child elements" do
    r = result jbuild { |json|
      json.key_format! :upcase
      json.level1 "one"
      json.level2 { json.value "two" }
    }
    r["LEVEL1"].as_s.should eq "one"
    r["LEVEL2"]["VALUE"].as_s.should eq "two"
  end

  it "key_format! resets after child element" do
    r = result jbuild { |json|
      json.level2 { json.key_format! :upcase; json.value "two" }
      json.level1 "one"
    }
    r["level2"]["VALUE"].as_s.should eq "two"
    r["level1"].as_s.should eq "one"
  end

  it "key_format! can be changed in child elements" do
    r = result jbuild { |json|
      json.key_format! camelize: :lower
      json.level_one do
        json.key_format! :upcase
        json.value "two"
      end
    }
    r.as_h.keys.should eq ["levelOne"]
    r["levelOne"].as_h.keys.should eq ["VALUE"]
  end

  it "key_format! can be changed in array!" do
    r = result jbuild { |json|
      json.key_format! camelize: :lower
      json.level_one do
        json.array! [{value: "two"}] do |object|
          json.key_format! :upcase
          json.value object[:value]
        end
      end
    }
    r.as_h.keys.should eq ["levelOne"]
    r["levelOne"].as_a.first.as_h.keys.should eq ["VALUE"]
  end

  it "key_format! with no parameter" do
    r = result jbuild { |json| json.key_format! :upcase; json.lower "Value" }
    r.as_h.keys.should eq ["LOWER"]
  end

  it "key_format! with lambda/proc" do
    r = result jbuild { |json| json.key_format! ->(key : String) { key + " and friends" }; json.oats "foo" }
    r.as_h.keys.should eq ["oats and friends"]
  end

  it "key_format! is not applied deeply by default" do
    names = {first_name: "camel", last_name: "case"}
    r = result jbuild { |json| json.key_format! camelize: :lower; json.set! :all_names, names }
    r["allNames"].as_h.keys.should eq ["first_name", "last_name"]
  end

  it "applying key_format! deeply can be enabled per scope" do
    names = {first_name: "camel", last_name: "case"}
    r = result jbuild { |json|
      json.key_format! camelize: :lower
      json.scope do
        json.deep_format_keys!
        json.set! :all_names, names
      end
      json.set! :all_names, names
    }
    r["scope"]["allNames"].as_h.keys.should eq ["firstName", "lastName"]
    r["allNames"].as_h.keys.should eq ["first_name", "last_name"]
  end

  it "applying key_format! deeply can be disabled per scope" do
    names = {first_name: "camel", last_name: "case"}
    r = result jbuild { |json|
      json.key_format! camelize: :lower
      json.deep_format_keys!
      json.set! :all_names, names
      json.scope do
        json.deep_format_keys! false
        json.set! :all_names, names
      end
    }
    r["allNames"].as_h.keys.should eq ["firstName", "lastName"]
    r["scope"]["allNames"].as_h.keys.should eq ["first_name", "last_name"]
  end

  it "applying key_format! deeply can be enabled globally" do
    names = {first_name: "camel", last_name: "case"}
    Jbuilder.deep_format_keys true
    begin
      r = result jbuild { |json| json.key_format! camelize: :lower; json.set! :all_names, names }
      r["allNames"].as_h.keys.should eq ["firstName", "lastName"]
    ensure
      Jbuilder.deep_format_keys false
    end
  end

  it "deep key_format! with merge!" do
    r = result jbuild { |json| json.key_format! camelize: :lower; json.deep_format_keys!; json.merge!({camel_style: "for JS"}) }
    r.as_h.keys.should eq ["camelStyle"]
  end

  it "deep key_format! with merge! deep" do
    r = result jbuild { |json| json.key_format! camelize: :lower; json.deep_format_keys!; json.merge!({camel_style: {sub_attr: "for JS"}}) }
    r["camelStyle"].as_h.keys.should eq ["subAttr"]
  end

  it "deep key_format! with set! array of hashes" do
    names = [{first_name: "camel", last_name: "case"}]
    r = result jbuild { |json| json.key_format! camelize: :lower; json.deep_format_keys!; json.set! :names, names }
    r["names"].as_a.first.as_h.keys.should eq ["firstName", "lastName"]
  end

  it "deep key_format! with array! of hashes" do
    names = [{first_name: "camel", last_name: "case"}]
    r = result jbuild { |json| json.key_format! camelize: :lower; json.deep_format_keys!; json.array! names }
    r.as_a.first.as_h.keys.should eq ["firstName", "lastName"]
  end

  it "deep key_format! is applied to hash extracted from object" do
    comment = {author: {first_name: "camel", last_name: "case"}}
    r = result jbuild { |json| json.key_format! camelize: :lower; json.deep_format_keys!; json.extract! comment, :author }
    r["author"].as_h.keys.should eq ["firstName", "lastName"]
  end

  it "deep key_format! is applied to hash extracted directly from array" do
    comments = [{author: {first_name: "camel", last_name: "case"}}]
    r = result jbuild { |json| json.key_format! camelize: :lower; json.deep_format_keys!; json.array! comments, :author }
    r.as_a[0]["author"].as_h.keys.should eq ["firstName", "lastName"]
  end

  it "default key_format!" do
    Jbuilder.key_format camelize: :lower
    begin
      r = result jbuild { |json| json.camel_style "for JS" }
      r.as_h.keys.should eq ["camelStyle"]
    ensure
      Jbuilder.key_format
    end
  end

  it "ignore_nil! without a parameter" do
    r = result jbuild { |json| json.ignore_nil!; json.test nil }
    r.as_h.should be_empty
  end

  it "ignore_nil! with parameter" do
    r = result jbuild { |json| json.ignore_nil! true; json.name "Bob"; json.dne nil }
    r.as_h.keys.should eq ["name"]
    r = result jbuild { |json| json.ignore_nil! false; json.name "Bob"; json.dne nil }
    r.as_h.keys.should eq ["name", "dne"]
  end

  it "default ignore_nil!" do
    Jbuilder.ignore_nil
    begin
      r = result jbuild { |json| json.name "Bob"; json.dne nil }
      r.as_h.keys.should eq ["name"]
    ensure
      Jbuilder.ignore_nil false
    end
  end

  it "nil!" do
    jbuild { |json| json.key "value"; json.nil! }.target!.should eq "null"
  end

  it "null!" do
    jbuild { |json| json.key "value"; json.null! }.target!.should eq "null"
  end

  it "null! in a block" do
    r = result jbuild { |json|
      json.author { json.name "David" }
      json.author { json.null! }
    }
    r.as_h.has_key?("author").should be_true
    r["author"].as_nil.should be_nil
  end

  it "empty attributes respond to empty?" do
    Jbuilder.new.attributes!.as(Hash(String, Jbuilder::Node)).empty?.should be_true
  end

  it "throws ArrayError when trying to add a key to an array" do
    expect_raises(Jbuilder::ArrayError) do
      jbuild { |json| json.array! ["foo", "bar"]; json.fizz "buzz" }
    end
  end

  it "throws NullError when trying to add properties to null" do
    expect_raises(Jbuilder::NullError) do
      jbuild { |json| json.null!; json.foo "bar" }
    end
  end

  it "throws NullError when trying to add properties to null using block syntax" do
    expect_raises(Jbuilder::NullError) do
      jbuild { |json|
        json.author { json.null! }
        json.author { json.name "Pavel" }
      }
    end
  end

  it "throws MergeError when trying to merge array with non-empty hash" do
    expect_raises(Jbuilder::MergeError) do
      jbuild { |json| json.name "Daniel"; json.merge! [] of Jbuilder::Node }
    end
  end

  it "throws MergeError when trying to merge hash with array" do
    expect_raises(Jbuilder::MergeError) do
      jbuild { |json| json.array!; json.merge!({} of String => String) }
    end
  end

  it "throws MergeError when trying to merge invalid objects" do
    expect_raises(Jbuilder::MergeError) do
      jbuild { |json| json.name "Daniel"; json.merge! "Nope" }
    end
  end
end
