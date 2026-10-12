#!/usr/bin/env ruby
# Oracle cases для JbuilderHandler/railtie: рендер .json.jbuilder-шаблонов
# контроллерами (implicit render по ?format=json / Accept, явный
# render "show.json.jbuilder") — проверяется полный HTTP-стек.
#
#   ruby oracle/cases_controller.rb > oracle/expected_controller.yml
#
# Минимальное инлайн-приложение Rails 8.1.4 без `rails new` (тот же приём,
# что oracle/integration_cases.rb в railties.cr). Хендлер регистрируется
# руками — без Gemfile railtie гема не подхватывается (это и делает в
# настоящем приложении lib/jbuilder/railtie.rb).
#
# Каждая строка: "<case_id>\t<status>|<Content-Type>|<body>" (\n, \t, \r
# экранированы). Те же case id зеркалятся 1:1 в spec/railtie_spec.cr
# (порт через action_pack.cr + JbuilderHandler из этого шарда); шаблоны
# oracle/views и spec/fixtures/app/views байт-в-байт одинаковы.

gem "jbuilder", "= 2.14.1"
gem "actionpack", "= 8.1.4"

ENV["RAILS_ENV"] = "test"

require "rails"
require "action_controller/railtie"
require "jbuilder"
require "jbuilder/jbuilder_template"

abort "need rails 8.1.4, got #{Rails::VERSION::STRING}" unless Rails::VERSION::STRING == "8.1.4"
abort "need jbuilder 2.14.1, got #{Jbuilder::VERSION}" unless Jbuilder::VERSION == "2.14.1"

# То, что в приложении делает jbuilder/railtie.rb:
ActionView::Template.register_template_handler :jbuilder, JbuilderHandler

module OracleApp
  class Application < Rails::Application
    config.secret_key_base = "a" * 128 # transcript-stable dummy
    config.logger = Logger.new(IO::NULL)
    config.eager_load = false
    config.cache_store = :memory_store
    config.hosts.clear
  end
end

class OraclePost
  attr_reader :id, :body, :author_name

  def initialize(id, body, author_name)
    @id = id
    @body = body
    @author_name = author_name
  end
end

class PostsController < ActionController::Base
  append_view_path File.expand_path("views", __dir__)

  def show
    @post = OraclePost.new(1, "Post #1", "David Heinemeier Hansson")
  end

  def index
    @posts = [
      OraclePost.new(1, "Post #1", "David"),
      OraclePost.new(2, "Post #2", "Pavel"),
    ]
  end

  # Явный рендер шаблона другого экшена: в Rails 8.1 позиционная строка с
  # полным именем файла шаблона ("posts/show.json.jbuilder") не проходит —
  # канонична форма "posts/show" + formats: :json (позиционная строка в
  # action_pack.cr занята телом JSON-ответа, порт принимает полный путь в
  # render(template:) — документированное отклонение).
  def explicit
    @post = OraclePost.new(2, "Post #2", "Pavel Pravosud")
    render "posts/show", formats: :json
  end
end

OracleApp::Application.initialize!

OracleApp::Application.routes.draw do
  get "/posts/show",     to: "posts#show"
  get "/posts",          to: "posts#index"
  get "/posts/explicit", to: "posts#explicit"
end

def escape(value)
  value.to_s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

def case_run(id)
  puts "#{id}\t#{escape(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class}"
end

def run
  @run ||= ActionDispatch::Integration::Session.new(OracleApp::Application)
end

def response_line
  "#{run.response.status}|#{run.response.headers['Content-Type']}|#{run.response.body}"
end

# --- transcript ---------------------------------------------------------

case_run("show_format_json") do
  run.get "/posts/show", params: {format: "json"}
  response_line
end

case_run("show_accept_header") do
  run.get "/posts/show", headers: {"Accept" => "application/json"}
  response_line
end

case_run("index_format_json") do
  run.get "/posts", params: {format: "json"}
  response_line
end

case_run("explicit_render") do
  run.get "/posts/explicit"
  response_line
end
