# Oracle spec: рендер .json.jbuilder-шаблонов контроллерами action_pack.cr
# через JbuilderHandler — зеркало oracle/expected_controller.yml (снято с
# Rails 8.1.4 + jbuilder 2.14.1, oracle/cases_controller.rb), 1:1 те же
# case id. Шаблоны oracle/views и spec/fixtures/app/views байт-в-байт
# одинаковы.
#
# Запуск: make spec — корень вьюх (CRAILS_VIEWS) читается кодогеном
# action_pack.cr на этапе компиляции, как в rails.cr/action_pack.cr.
# Без CRAILS_VIEWS файл компилируется в пустоту: вьюхи не найдены, тесты
# не собираются (bare `crystal spec` остальных спеков не ломает).

{% if (env("CRAILS_VIEWS") || "") != "" %}
require "spec"
require "http"
require "../src/jbuilder_cr"
require "action_pack_cr"

EXPECTED_CONTROLLER = begin
  hash = {} of String => String
  File.read("#{__DIR__}/../oracle/expected_controller.yml").each_line do |line|
    if line.includes?('\t')
      id, value = line.split('\t', 2)
      hash[id] = value.chomp
    end
  end
  hash
end

def check_controller(id, value)
  (EXPECTED_CONTROLLER[id]? || "MISSING #{id}").should eq value.to_s
end

class JbPost
  property id : Int32
  property body : String
  property author_name : String

  def initialize(@id, @body, @author_name)
  end
end

abstract class ApplicationController < ActionController::Base
end

class PostsController < ApplicationController
  # Ивары шаблона инициализируются дефолтами: initialize базового
  # ActionController::Base их не задаёт, а Nil-union ломает читателей в
  # шаблоне (@post.author_name). Присваивание в экшене перекрывает дефолт.
  @post : JbPost = JbPost.new(0, "", "")
  @posts : Array(JbPost) = [] of JbPost

  def show
    @post = JbPost.new(1, "Post #1", "David Heinemeier Hansson")
  end

  def index
    @posts = [JbPost.new(1, "Post #1", "David"),
              JbPost.new(2, "Post #2", "Pavel")]
  end

  # Rails: render "posts/show", formats: :json — позиционная строка в порте
  # занята телом JSON-ответа, полный путь передаётся в render(template:).
  def explicit
    @post = JbPost.new(2, "Post #2", "Pavel Pravosud")
    render(template: "posts/show.json.jbuilder")
  end
end

# GET-запрос через контроллер (как spec/action_pack_spec.cr в rails.cr):
# "-> status|Content-Type|body" — формат записей expected_controller.yml.
private def jb_run(action : String, query : String? = nil, accept : String? = nil) : String
  path = "/#{action}"
  path += "?#{query}" if query
  headers = HTTP::Headers.new
  headers["Accept"] = accept if accept
  request = HTTP::Request.new("GET", path, headers)
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  context = HTTP::Server::Context.new(request, response)
  controller = PostsController.new(context)
  controller.__set_params({} of String => String)
  controller.__run_action(action)
  response.close
  raw = io.to_s
  body = raw.includes?("\r\n\r\n") ? raw.split("\r\n\r\n", 2)[1] : ""
  "#{response.status_code}|#{response.headers["Content-Type"]?}|#{body}"
end

describe "JbuilderHandler / action_pack" do
  it "implicit render show.json.jbuilder по ?format=json" do
    check_controller("show_format_json", jb_run("show", query: "format=json"))
  end

  it "implicit render show.json.jbuilder по Accept: application/json" do
    check_controller("show_accept_header", jb_run("show", accept: "application/json"))
  end

  it "implicit render index.json.jbuilder (коллекция, блок)" do
    check_controller("index_format_json", jb_run("index", query: "format=json"))
  end

  it "явный render(template:) шаблона другого экшена" do
    check_controller("explicit_render", jb_run("explicit"))
  end
end
{% end %}
