# frozen_string_literal: true

require_relative 'lib/sorbet_view/version'

Gem::Specification.new do |spec|
  spec.name = 'sorbet_view'
  spec.version = SorbetView::VERSION
  spec.authors = ['kazuma']
  spec.summary = 'Sorbet type-checking for Rails view templates'
  spec.description = 'Extracts Ruby code from view templates (ERB, etc.) for Sorbet type-checking, with LSP support'
  spec.homepage = 'https://github.com/kazzix14/sorbet_view'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = ['sv']
  spec.require_paths = ['lib']

  spec.add_dependency 'herb'
  spec.add_dependency 'listen', '~> 3.0'
  spec.add_dependency 'psych'
  spec.add_dependency 'sorbet-runtime'
  spec.add_dependency 'srb_lens', '~> 0.3.0'
end
