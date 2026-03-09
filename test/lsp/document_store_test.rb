# typed: true
# frozen_string_literal: true

require 'test_helper'

class DocumentStoreTest < Minitest::Test
  def setup
    @store = SorbetView::Lsp::DocumentStore.new
  end

  def test_open_and_get
    doc = @store.open('file:///test.html.erb', '<%= @foo %>', 1)

    assert_equal 'file:///test.html.erb', doc.uri
    assert_equal '<%= @foo %>', doc.content
    assert_equal 1, doc.version

    fetched = @store.get('file:///test.html.erb')
    assert_equal doc, fetched
  end

  def test_change
    @store.open('file:///test.html.erb', '<%= @foo %>', 1)
    doc = @store.change('file:///test.html.erb', '<%= @bar %>', 2)

    assert doc
    assert_equal '<%= @bar %>', doc.content
    assert_equal 2, doc.version
  end

  def test_change_unknown_returns_nil
    result = @store.change('file:///unknown.html.erb', 'new content', 1)
    assert_nil result
  end

  def test_close
    @store.open('file:///test.html.erb', '<%= @foo %>', 1)
    @store.close('file:///test.html.erb')

    assert_nil @store.get('file:///test.html.erb')
  end

  def test_all
    @store.open('file:///a.html.erb', 'a', 1)
    @store.open('file:///b.html.erb', 'b', 1)

    assert_equal 2, @store.all.length
  end
end
