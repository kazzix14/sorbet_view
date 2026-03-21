# typed: strict
# frozen_string_literal: true

require 'uri'

module SorbetView
  module Lsp
    # Maps between template file URIs and generated Ruby file URIs
    class UriMapper
      extend T::Sig

      TEMPLATE_EXTENSIONS = T.let(%w[.erb .haml .slim].freeze, T::Array[String])

      sig { params(config: Configuration).void }
      def initialize(config:)
        @output_dir = config.output_dir
        @editor_root = T.let(nil, T.nilable(String))
        @local_root = T.let(nil, T.nilable(String))
      end

      # Auto-detect path mapping from LSP rootUri vs local working directory.
      sig { params(editor_root: String, local_root: String).void }
      def set_roots(editor_root:, local_root:)
        return if editor_root == local_root

        @editor_root = editor_root
        @local_root = local_root
      end

      sig { params(uri: String).returns(T::Boolean) }
      def template_uri?(uri)
        path = uri_to_path(uri)
        TEMPLATE_EXTENSIONS.any? { |ext| path.end_with?(ext) }
      end

      sig { params(uri: String).returns(T::Boolean) }
      def generated_ruby_uri?(uri)
        path = uri_to_path(uri)
        path.start_with?(@output_dir) || path.include?("/#{@output_dir}/")
      end

      # template URI -> generated ruby URI
      sig { params(template_uri: String).returns(String) }
      def template_to_ruby_uri(template_uri)
        path = uri_to_path(template_uri)
        ruby_path = File.join(@output_dir, "#{path}.rb")
        path_to_uri(ruby_path)
      end

      # component .rb URI -> generated __erb_template.rb URI
      sig { params(component_uri: String).returns(String) }
      def component_to_ruby_uri(component_uri)
        path = uri_to_path(component_uri)
        ruby_path = File.join(@output_dir, "#{path}__erb_template.rb")
        path_to_uri(ruby_path)
      end

      # generated ruby URI -> template URI
      sig { params(ruby_uri: String).returns(T.nilable(String)) }
      def ruby_to_template_uri(ruby_uri)
        path = uri_to_path(ruby_uri)

        # Remove output_dir prefix and .rb suffix
        relative = path.sub(%r{^.*/#{Regexp.escape(@output_dir)}/}, '')
                       .sub(%r{^#{Regexp.escape(@output_dir)}/}, '')
        return nil unless relative.end_with?('.rb')

        # Component heredoc: output is foo.rb__erb_template.rb → source is foo.rb
        if relative.end_with?('__erb_template.rb')
          template_path = relative.chomp('__erb_template.rb')
          return path_to_uri(template_path)
        end

        template_path = relative.chomp('.rb')
        path_to_uri(template_path)
      end

      sig { params(uri: String).returns(String) }
      def uri_to_path(uri)
        path = if uri.start_with?('file://')
          URI.decode_www_form_component(URI.parse(uri).path || '')
        else
          uri
        end
        # Map editor root -> local root
        if @editor_root && @local_root && path.start_with?(@editor_root)
          path = path.sub(@editor_root, @local_root)
        end
        # Make relative to CWD
        cwd = Dir.pwd
        if path.start_with?("#{cwd}/")
          path = path.delete_prefix("#{cwd}/")
        end
        path
      end

      sig { params(path: String).returns(String) }
      def path_to_uri(path)
        absolute = File.expand_path(path)
        # Map local root -> editor root
        if @editor_root && @local_root && absolute.start_with?(@local_root)
          absolute = absolute.sub(@local_root, @editor_root)
        end
        "file://#{URI.encode_www_form_component(absolute).gsub('%2F', '/')}"
      end
    end
  end
end
