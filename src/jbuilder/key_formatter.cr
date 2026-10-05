# KeyFormatter — 1:1 к jbuilder/key_formatter.rb (2.14.1).
# Форматы: Symbol (:upcase, :downcase, :capitalize, :swapcase) и
# Proc(String, String); именованный camelize: :lower (в Ruby метод
# приходит из ActiveSupport, здесь встроен).

class Jbuilder
  class KeyFormatter
    alias Func = Symbol | Proc(String, String)

    def initialize(formats = [] of KeyFormatter::Func, camelize : Symbol? = nil)
      # Параметр без аннотации: restriction Array(Func) из-за бага с
      # union-алиасами матчит Array(Symbol) инвариантно и ломает тип ivar.
      @formats = [] of KeyFormatter::Func
      formats.each do |format|
        if format.is_a?(KeyFormatter::Func)
          @formats << format
        else
          raise ArgumentError.new("KeyFormatter formats must be Symbol or Proc(String, String), got: #{format}")
        end
      end
      @camelize = camelize
      @cache = {} of String => String
    end

    def format(key : String) : String
      cached = @cache[key]?
      return cached if cached

      value = key
      @formats.each do |func|
        value = apply(value, func)
      end
      if mode = @camelize
        value = camelize(value, mode)
      end
      @cache[key] = value
      value
    end

    private def apply(value : String, func : Proc(String, String)) : String
      func.call(value)
    end

    private def apply(value : String, func : Symbol) : String
      case func
      when :upcase      then value.upcase
      when :downcase    then value.downcase
      when :capitalize  then value.capitalize
      when :swapcase    then _swapcase(value)
      else
        raise ArgumentError.new("Unknown key format function: #{func} (supported: :upcase, :downcase, :capitalize, :swapcase, camelize:, Proc)")
      end
    end

    private def _swapcase(value : String) : String
      String.build do |io|
        value.each_char do |ch|
          if ch.uppercase?
            io << ch.downcase
          elsif ch.lowercase?
            io << ch.upcase
          else
            io << ch
          end
        end
      end
    end

    private def camelize(value : String, mode : Symbol) : String
      parts = value.split(/[_\-]/).reject(&.empty?)
      camel = parts.map(&.capitalize).join
      if mode == :lower && !camel.empty?
        camel[0].downcase + camel[1..]
      else
        camel
      end
    end
  end
end
