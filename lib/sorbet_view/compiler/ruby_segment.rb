# typed: strict
# frozen_string_literal: true

module SorbetView
  module Compiler
    class RubySegment < T::Struct
      const :code, String
      const :line, Integer    # 0-based line in the template
      const :column, Integer  # 0-based column in the template
      const :type, Symbol     # :statement (<% %>), :expression (<%= %>), :comment (<%# %>)
    end
  end
end
