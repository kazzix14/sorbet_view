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
        # path_mapping: { "/host/path" => "/container/path" }
        @path_mapping = T.let(config.path_mapping, T::Hash[String, String])
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

      # generated ruby URI -> template URI
      sig { params(ruby_uri: String).returns(T.nilable(String)) }
      def ruby_to_template_uri(ruby_uri)
        path = uri_to_path(ruby_uri)

        # Remove output_dir prefix and .rb suffix
        relative = path.sub(%r{^.*/#{Regexp.escape(@output_dir)}/}, '')
                       .sub(%r{^#{Regexp.escape(@output_dir)}/}, '')
        return nil unless relative.end_with?('.rb')

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
        # Map host path -> local (container) path
        @path_mapping.each do |from, to|
          if path.start_with?(from)
            path = path.sub(from, to)
            break
          end
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
        # Map local (container) path -> host path
        @path_mapping.each do |from, to|
          if absolute.start_with?(to)
            absolute = absolute.sub(to, from)
            break
          end
        end
        "file://#{URI.encode_www_form_component(absolute).gsub('%2F', '/')}"
      end
    end
  end
end
