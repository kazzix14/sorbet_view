# typed: true
# frozen_string_literal: true

require 'test_helper'

class UriMapperTest < Minitest::Test
  def setup
    @mapper = SorbetView::Lsp::UriMapper.new(config: SorbetView::Configuration.new)
  end

  def test_template_uri_detection
    assert @mapper.template_uri?('file:///app/views/users/show.html.erb')
    assert @mapper.template_uri?('file:///app/views/users/_partial.html.erb')
    refute @mapper.template_uri?('file:///app/models/user.rb')
    refute @mapper.template_uri?('file:///Gemfile')
  end

  def test_generated_ruby_uri_detection
    assert @mapper.generated_ruby_uri?('file:///project/sorbet/templates/app/views/show.html.erb.rb')
    refute @mapper.generated_ruby_uri?('file:///app/models/user.rb')
  end

  def test_template_to_ruby_uri
    template_uri = 'file:///app/views/users/show.html.erb'
    ruby_uri = @mapper.template_to_ruby_uri(template_uri)

    assert ruby_uri.end_with?('.html.erb.rb')
    assert ruby_uri.include?('sorbet/templates')
  end

  def test_uri_to_path
    assert_equal '/app/views/users/show.html.erb',
                 @mapper.uri_to_path('file:///app/views/users/show.html.erb')
  end

  def test_plain_path_passthrough
    assert_equal 'app/views/users/show.html.erb',
                 @mapper.uri_to_path('app/views/users/show.html.erb')
  end
end
