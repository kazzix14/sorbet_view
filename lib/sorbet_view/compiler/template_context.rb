# typed: strict
# frozen_string_literal: true

module SorbetView
  module Compiler
    class TemplateContext < T::Struct
      const :class_name, String
      const :superclass, T.nilable(String)
      const :includes, T::Array[String]
      const :template_path, String
      const :ruby_path, String

      extend T::Sig

      sig { returns(String) }
      def superclass_clause
        superclass ? " < #{superclass}" : ''
      end

      sig { params(component_path: String, class_name: String, config: Configuration).returns(TemplateContext) }
      def self.resolve_component(component_path, class_name, config)
        ruby_path = File.join(config.output_dir, "#{component_path}__erb_template.rb")
        new(
          class_name: class_name,
          superclass: nil,
          includes: [],
          template_path: component_path,
          ruby_path: ruby_path
        )
      end

      sig { params(template_path: String, config: Configuration).returns(TemplateContext) }
      def self.resolve(template_path, config)
        ruby_path = File.join(config.output_dir, "#{template_path}.rb")
        classification = classify(template_path)

        case classification
        when :mailer_view
          resolve_mailer_view(template_path, ruby_path, config)
        when :layout
          resolve_layout(template_path, ruby_path, config)
        when :partial
          resolve_partial(template_path, ruby_path, config)
        when :controller_view
          resolve_controller_view(template_path, ruby_path, config)
        else
          resolve_generic(template_path, ruby_path, config)
        end
      end

      class << self
        extend T::Sig

        private

        sig { params(path: String).returns(Symbol) }
        def classify(path)
          basename = File.basename(path)

          if path.include?('_mailer/') || path.include?('mailers/')
            :mailer_view
          elsif path.include?('app/views/layouts/')
            :layout
          elsif basename.start_with?('_')
            :partial
          elsif path.include?('app/views/')
            :controller_view
          else
            :generic
          end
        end

        sig { params(path: String).returns(String) }
        def path_to_class_name(path)
          # /abs/path/app/views/users/show.html.erb -> Users::Show
          relative = path
            .sub(%r{.*app/views/}, '')
            .sub(%r{.*app/}, '')
          basename = File.basename(relative).sub(/\..*$/, '') # strip all extensions
          basename = basename.delete_prefix('_') # strip partial prefix
          dir = File.dirname(relative)

          parts = if dir == '.'
            [basename]
          else
            dir.split('/') + [basename]
          end

          parts.map { |p| camelize(p) }.join('::')
        end

        sig { params(str: String).returns(String) }
        def camelize(str)
          str.split('_').map(&:capitalize).join
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_controller_view(path, ruby_path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path)}",
            superclass: nil,
            includes: [
              '::ActionView::Helpers',
              '::ApplicationController::HelperMethods',
              *config.extra_includes
            ],
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_mailer_view(path, ruby_path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path)}",
            superclass: nil,
            includes: [
              '::ActionView::Helpers',
              '::ActionMailer::Base',
              *config.extra_includes
            ],
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_layout(path, ruby_path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path)}",
            superclass: nil,
            includes: [
              '::ActionView::Helpers',
              '::ApplicationController::HelperMethods',
              *config.extra_includes
            ],
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_partial(path, ruby_path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path)}",
            superclass: nil,
            includes: [
              '::ActionView::Helpers',
              '::ApplicationController::HelperMethods',
              *config.extra_includes
            ],
            template_path: path,
            ruby_path: ruby_path
          )
        end

        sig { params(path: String, ruby_path: String, config: Configuration).returns(TemplateContext) }
        def resolve_generic(path, ruby_path, config)
          new(
            class_name: "SorbetView::Generated::#{path_to_class_name(path)}",
            superclass: nil,
            includes: config.extra_includes,
            template_path: path,
            ruby_path: ruby_path
          )
        end
      end
    end
  end
end
