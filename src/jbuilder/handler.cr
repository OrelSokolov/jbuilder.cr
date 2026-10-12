# JbuilderHandler — порт JbuilderHandler (jbuilder/jbuilder_template.rb
# 2.14.1) для action_pack.cr.
#
# В Ruby railtie гема (lib/jbuilder/railtie.rb) регистрирует хендлер:
#   ActionView::Template.register_template_handler :jbuilder, JbuilderHandler
# и JbuilderHandler.call(template, source) превращает исходник шаблона в
# Ruby-код. В Crystal компиляция шаблонов — обязательно compile-time, поэтому
# аналогом регистрации является кодоген action_pack.cr (src/base.cr): для
# каждого найденного #{action}.json.jbuilder он вызывает JbuilderHandler.call,
# который компилирует тело шаблона в метод.
#
# Тело шаблона вставляется как есть (DSL json.* — валидный Crystal) и
# исполняется в контексте включившего класса: локальная переменная json —
# свежий JbuilderTemplate, инстанс-переменные и хелперы контроллера видны,
# как в Rails. Метод возвращает JSON-строку (target!).
#
# Отличия от Ruby:
#   * рантайм-регистрации хендлеров нет — шаблон обязан существовать на
#     этапе сборки (корень вьюх читается кодогеном из CRAILS_VIEWS);
#   * партиалы внутри шаблона — только зарегистрированные compile-time
#     (JbuilderTemplate.compile_partials), файловой подстановки нет;
#   * явный рендер в контроллере — render(template: "posts/show.json.jbuilder"):
#     позиционная строка render("...") в action_pack.cr занята телом
#     JSON-ответа (в Rails позиционная форма render "posts/show", formats: :json).

require "./jbuilder_template"

class JbuilderHandler
  # Компилирует .json.jbuilder-шаблон в метод возвращающий JSON-строку.
  # Вызывается кодогеном action_pack.cr для шаблонов экшенов; path —
  # относительно каталога запуска crystal (как у compile_partials).
  macro call(name, path)
    def {{ name.id }} : String
      json = JbuilderTemplate.new
      {{ read_file(path).id }}
      json.target!
    end
  end
end
