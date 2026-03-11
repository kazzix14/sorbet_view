# typed: strict
# frozen_string_literal: true

module SorbetView
  module Lsp
    # Translates positions between template and generated Ruby using SourceMaps
    class PositionTranslator
      extend T::Sig

      sig { void }
      def initialize
        @source_maps = T.let({}, T::Hash[String, SourceMap::SourceMap])
      end

      sig { params(template_path: String, source_map: SourceMap::SourceMap).void }
      def register(template_path, source_map)
        @source_maps[template_path] = source_map
      end

      sig { params(template_path: String).void }
      def unregister(template_path)
        @source_maps.delete(template_path)
      end

      sig { params(template_path: String).returns(T.nilable(SourceMap::SourceMap)) }
      def source_map_for(template_path)
        @source_maps[template_path]
      end

      sig { returns(T::Array[String]) }
      def registered_paths
        @source_maps.keys
      end

      # Translate an LSP position from template coordinates to Ruby coordinates
      sig do
        params(
          template_path: String,
          lsp_position: T::Hash[String, T.untyped]
        ).returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def template_to_ruby(template_path, lsp_position)
        sm = @source_maps[template_path]
        return nil unless sm

        pos = SourceMap::Position.new(
          line: lsp_position['line'] || lsp_position[:line] || 0,
          column: lsp_position['character'] || lsp_position[:character] || 0
        )

        ruby_pos = sm.template_to_ruby(pos)
        return nil unless ruby_pos

        ruby_pos.to_lsp
      end

      # Translate an LSP position from Ruby coordinates to template coordinates
      sig do
        params(
          template_path: String,
          lsp_position: T::Hash[String, T.untyped]
        ).returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def ruby_to_template(template_path, lsp_position)
        sm = @source_maps[template_path]
        return nil unless sm

        pos = SourceMap::Position.new(
          line: lsp_position['line'] || lsp_position[:line] || 0,
          column: lsp_position['character'] || lsp_position[:character] || 0
        )

        template_pos = sm.ruby_to_template(pos)
        return nil unless template_pos

        template_pos.to_lsp
      end

      # Translate an LSP range from Ruby coordinates to template coordinates
      sig do
        params(
          template_path: String,
          lsp_range: T::Hash[String, T.untyped]
        ).returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def ruby_range_to_template(template_path, lsp_range)
        start_pos = ruby_to_template(template_path, lsp_range['start'] || lsp_range[:start])
        end_pos = ruby_to_template(template_path, lsp_range['end'] || lsp_range[:end])
        return nil unless start_pos && end_pos

        { 'start' => start_pos, 'end' => end_pos }
      end
    end
  end
end
