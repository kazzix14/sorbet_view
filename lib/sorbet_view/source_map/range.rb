# typed: strict
# frozen_string_literal: true

module SorbetView
  module SourceMap
    class Range < T::Struct
      const :start, Position
      const :end_, Position

      extend T::Sig

      sig { returns(T::Hash[Symbol, T::Hash[Symbol, Integer]]) }
      def to_lsp
        { start: start.to_lsp, end: end_.to_lsp }
      end

      sig { params(lsp_hash: T::Hash[String, T.untyped]).returns(Range) }
      def self.from_lsp(lsp_hash)
        new(
          start: Position.from_lsp(lsp_hash['start'] || lsp_hash[:start]),
          end_: Position.from_lsp(lsp_hash['end'] || lsp_hash[:end])
        )
      end

      sig { params(position: Position).returns(T::Boolean) }
      def contains?(position)
        return false if position.line < start.line || position.line > end_.line
        return false if position.line == start.line && position.column < start.column
        return false if position.line == end_.line && position.column > end_.column

        true
      end
    end
  end
end
