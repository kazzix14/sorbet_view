# typed: strict
# frozen_string_literal: true

module SorbetView
  module Compiler
    module Adapters
      class ErbAdapter
        extend T::Sig
        include ParserAdapter

        INDICATOR_PATTERN = /<%([=#-]?)(.*?)[-]?%>/m

        sig { override.params(source: String).returns(T::Array[RubySegment]) }
        def extract_segments(source)
          Perf.measure('erb.extract_segments') do
            if herb_available?
              Perf.measure('erb.extract_with_herb') { extract_with_herb(source) }
            else
              Perf.measure('erb.extract_with_stdlib') { extract_with_stdlib(source) }
            end
          end
        end

        private

        sig { returns(T::Boolean) }
        def herb_available?
          @herb_available = T.let(@herb_available, T.nilable(T::Boolean))
          if @herb_available.nil?
            @herb_available = begin
              require 'herb'
              true
            rescue LoadError
              false
            end
          end
          T.must(@herb_available)
        end

        sig { params(source: String).returns(T::Array[RubySegment]) }
        def extract_with_herb(source)
          result = Herb.parse(source)
          segments = T.let([], T::Array[RubySegment])
          visit_herb_node(result.value, segments)
          segments
        end

        sig { params(node: T.untyped, segments: T::Array[RubySegment]).void }
        def visit_herb_node(node, segments)
          class_name = node.class.name.to_s

          if class_name.include?('ERBContentNode')
            add_herb_segment(node, segments)
            return
          end

          if class_name.include?('ERBEndNode')
            add_herb_end_segment(node, segments)
            return
          end

          erb_block = class_name.include?('ERBBlockNode') ||
                      class_name.include?('ERBIfNode') || class_name.include?('ERBUnlessNode') ||
                      class_name.include?('ERBCaseNode') || class_name.include?('ERBForNode') ||
                      class_name.include?('ERBWhileNode') || class_name.include?('ERBUntilNode') ||
                      class_name.include?('ERBBeginNode')

          erb_clause = class_name.include?('ERBElsifNode') || class_name.include?('ERBElseNode') ||
                       class_name.include?('ERBWhenNode') || class_name.include?('ERBRescueNode') ||
                       class_name.include?('ERBEnsureNode')

          if erb_block || erb_clause
            add_herb_segment(node, segments)
            node.statements.each { |s| visit_herb_node(s, segments) } if node.respond_to?(:statements)
            node.body.each { |s| visit_herb_node(s, segments) } if node.respond_to?(:body)
            visit_herb_node(node.subsequent, segments) if node.respond_to?(:subsequent) && node.subsequent
            add_herb_end_segment(node.end_node, segments) if erb_block && node.respond_to?(:end_node) && node.end_node
            return
          end

          # Non-ERB nodes: recurse into children and body
          node.children.each { |child| visit_herb_node(child, segments) } if node.respond_to?(:children)
          node.body.each { |child| visit_herb_node(child, segments) } if node.respond_to?(:body)
        end

        sig { params(node: T.untyped, segments: T::Array[RubySegment]).void }
        def add_herb_segment(node, segments)
          return unless node.respond_to?(:content) && node.content

          content_token = node.content
          code = content_token.value.to_s.strip
          return if code.empty?

          # Herb lines are 1-based, we use 0-based
          loc = content_token.location
          line = loc.start.line - 1
          column = loc.start.column

          tag = node.respond_to?(:tag_opening) ? node.tag_opening.value.to_s : '<%'
          type = case tag
          when '<%=' then :expression
          when '<%#' then :comment
          else :statement
          end

          segments << RubySegment.new(code: code, line: line, column: column, type: type)
        end

        sig { params(node: T.untyped, segments: T::Array[RubySegment]).void }
        def add_herb_end_segment(node, segments)
          return unless node.respond_to?(:content) && node.content

          loc = node.content.location
          segments << RubySegment.new(
            code: 'end',
            line: loc.start.line - 1,
            column: loc.start.column,
            type: :statement
          )
        end

        # Fallback: regex-based extraction when Herb is not available
        sig { params(source: String).returns(T::Array[RubySegment]) }
        def extract_with_stdlib(source)
          segments = T.let([], T::Array[RubySegment])
          line_offsets = build_line_offsets(source)

          source.scan(INDICATOR_PATTERN) do
            match = T.must(Regexp.last_match)
            indicator = match[1] || ''
            code = (match[2] || '').strip
            offset = T.must(match.begin(0))

            next if code.empty?

            line, column = offset_to_line_column(line_offsets, offset)
            tag_prefix_len = 2 + indicator.length
            code_column = column + tag_prefix_len

            type = case indicator
            when '#' then :comment
            when '=' then :expression
            else :statement
            end

            segments << RubySegment.new(code: code, line: line, column: code_column, type: type)
          end

          segments
        end

        sig { params(source: String).returns(T::Array[Integer]) }
        def build_line_offsets(source)
          offsets = [0]
          source.each_char.with_index do |char, i|
            offsets << (i + 1) if char == "\n"
          end
          offsets
        end

        sig { params(line_offsets: T::Array[Integer], offset: Integer).returns([Integer, Integer]) }
        def offset_to_line_column(line_offsets, offset)
          line = line_offsets.rindex { |o| o <= offset } || 0
          column = offset - (line_offsets[line] || 0)
          [line, column]
        end
      end
    end
  end
end
