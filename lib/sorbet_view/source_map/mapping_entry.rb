# typed: strict
# frozen_string_literal: true

module SorbetView
  module SourceMap
    class MappingEntry < T::Struct
      const :template_range, Range  # position in the template file
      const :ruby_range, Range      # position in the generated .rb file
      const :type, Symbol           # :code, :expression, :boilerplate
    end
  end
end
