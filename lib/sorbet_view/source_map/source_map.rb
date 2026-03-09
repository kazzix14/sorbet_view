# typed: strict
# frozen_string_literal: true

module SorbetView
  module SourceMap
    class SourceMap
      extend T::Sig

      sig { returns(String) }
      attr_reader :template_path

      sig { returns(String) }
      attr_reader :ruby_path

      sig { returns(T::Array[MappingEntry]) }
      attr_reader :entries

      sig do
        params(
          template_path: String,
          ruby_path: String,
          entries: T::Array[MappingEntry]
        ).void
      end
      def initialize(template_path:, ruby_path:, entries:)
        @template_path = template_path
        @ruby_path = ruby_path
        @entries = entries
      end

      sig { params(position: Position).returns(T.nilable(Position)) }
      def template_to_ruby(position)
        entry = find_entry_by_template(position)
        return nil unless entry
        return nil if entry.type == :boilerplate

        translate(position, entry.template_range, entry.ruby_range)
      end

      sig { params(position: Position).returns(T.nilable(Position)) }
      def ruby_to_template(position)
        entry = find_entry_by_ruby(position)
        return nil unless entry
        return nil if entry.type == :boilerplate

        translate(position, entry.ruby_range, entry.template_range)
      end

      sig { params(ruby_range: Range).returns(T.nilable(Range)) }
      def ruby_range_to_template(ruby_range)
        start_pos = ruby_to_template(ruby_range.start)
        end_pos = ruby_to_template(ruby_range.end_)
        return nil unless start_pos && end_pos

        Range.new(start: start_pos, end_: end_pos)
      end

      sig { params(template_path: String, ruby_path: String).returns(SourceMap) }
      def self.empty(template_path, ruby_path)
        new(template_path: template_path, ruby_path: ruby_path, entries: [])
      end

      private

      sig { params(position: Position).returns(T.nilable(MappingEntry)) }
      def find_entry_by_template(position)
        @entries.find { |e| e.template_range.contains?(position) }
      end

      sig { params(position: Position).returns(T.nilable(MappingEntry)) }
      def find_entry_by_ruby(position)
        # First try exact match, then fall back to line-only match
        @entries.find { |e| e.ruby_range.contains?(position) } ||
          @entries.find { |e| position.line >= e.ruby_range.start.line && position.line <= e.ruby_range.end_.line }
      end

      sig do
        params(
          position: Position,
          from_range: Range,
          to_range: Range
        ).returns(Position)
      end
      def translate(position, from_range, to_range)
        delta_line = position.line - from_range.start.line
        delta_col = if delta_line == 0
          position.column - from_range.start.column
        else
          position.column
        end

        Position.new(
          line: to_range.start.line + delta_line,
          column: (delta_line == 0 ? to_range.start.column : 0) + delta_col
        )
      end
    end
  end
end
