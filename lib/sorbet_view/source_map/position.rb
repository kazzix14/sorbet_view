# typed: strict
# frozen_string_literal: true

module SorbetView
  module SourceMap
    class Position < T::Struct
      const :line, Integer   # 0-based
      const :column, Integer # 0-based

      extend T::Sig

      sig { returns(T::Hash[Symbol, Integer]) }
      def to_lsp
        { line: line, character: column }
      end

      sig { params(lsp_hash: T::Hash[String, Integer]).returns(Position) }
      def self.from_lsp(lsp_hash)
        new(line: lsp_hash['line'] || lsp_hash[:line], column: lsp_hash['character'] || lsp_hash[:character])
      end
    end
  end
end
