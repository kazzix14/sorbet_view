# typed: strict
# frozen_string_literal: true

module SorbetView
  module Compiler
    class HeredocExtraction < T::Struct
      const :erb_source, String
      const :line_offset, Integer
      const :column_offset, Integer
      const :class_name, String
      const :component_path, String
    end

    class HeredocExtractor
      extend T::Sig

      ERB_TEMPLATE_PATTERN = /erb_template\s+<<~([A-Z_]+)/

      sig { params(source: String).returns(T::Boolean) }
      def self.contains_erb_template?(source)
        ERB_TEMPLATE_PATTERN.match?(source)
      end

      sig { params(source: String, file_path: String).returns(T::Array[HeredocExtraction]) }
      def self.extract(source, file_path)
        extractions = T.let([], T::Array[HeredocExtraction])
        lines = source.lines

        i = 0
        while i < lines.length
          line = T.must(lines[i])
          match = ERB_TEMPLATE_PATTERN.match(line)
          if match
            delimiter = T.must(match[1])
            heredoc_start = i + 1
            heredoc_lines = T.let([], T::Array[String])

            j = heredoc_start
            while j < lines.length
              heredoc_line = T.must(lines[j])
              break if heredoc_line.strip == delimiter

              heredoc_lines << heredoc_line
              j += 1
            end

            erb_source, column_offset = dedent_heredoc(heredoc_lines)
            class_name = class_name_from_source(source)

            extractions << HeredocExtraction.new(
              erb_source: erb_source,
              line_offset: heredoc_start,
              column_offset: column_offset,
              class_name: class_name,
              component_path: file_path
            )

            i = j + 1
          else
            i += 1
          end
        end

        extractions
      end

      class << self
        extend T::Sig

        private

        sig { params(lines: T::Array[String]).returns([String, Integer]) }
        def dedent_heredoc(lines)
          # Reproduce Ruby's <<~ indent stripping behavior
          non_empty_lines = lines.reject { |l| l.strip.empty? }
          return [lines.join, 0] if non_empty_lines.empty?

          min_indent = T.let(nil, T.nilable(Integer))
          non_empty_lines.each do |line|
            indent = T.must(line.match(/^(\s*)/))[1]&.length || 0
            min_indent = indent if min_indent.nil? || indent < min_indent
          end
          min_indent ||= 0

          dedented = lines.map do |line|
            if line.strip.empty?
              "\n"
            else
              line[min_indent..] || line
            end
          end.join

          [dedented, min_indent]
        end

        sig { params(source: String).returns(String) }
        def class_name_from_source(source)
          parts = T.let([], T::Array[String])
          source.each_line do |line|
            if (m = line.match(/^\s*module\s+([A-Z][\w:]*)/))
              parts << T.must(m[1])
            elsif (m = line.match(/^\s*class\s+([A-Z][\w:]*)/))
              parts << T.must(m[1])
              break
            end
          end
          parts.join('::')
        end
      end
    end
  end
end
