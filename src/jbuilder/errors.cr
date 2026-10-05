# Ошибки jbuilder.cr — 1:1 к jbuilder/errors.rb (2.14.1).
# NullError в Ruby < NoMethodError; в Crystal наследуем Exception —
# сверка по oracle идёт по class.name + message.

class Jbuilder
  class NullError < Exception
    def self.build(key : String) : NullError
      new(%(Failed to add "#{key}" property to null object))
    end
  end

  class ArrayError < Exception
    def self.build(key : String) : ArrayError
      new(%(Failed to add "#{key}" property to an array))
    end
  end

  class MergeError < Exception
    def self.build(current_value, updates) : MergeError
      # В Ruby формат через inspect; Hash#inspect различается между
      # Ruby и Crystal, поэтому сообщение best-effort, сверяется класс.
      new("Can't merge #{updates.inspect} into #{current_value.inspect}")
    end
  end
end
