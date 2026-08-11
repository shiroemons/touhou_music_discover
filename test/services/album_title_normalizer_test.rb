# frozen_string_literal: true

require 'test_helper'

class AlbumTitleNormalizerTest < ActiveSupport::TestCase
  test 'normalizes unicode and whitespace without changing the title language' do
    assert_equal 'ABC タイトル', AlbumTitleNormalizer.normalize(" ＡＢＣ　タイトル\n")
    assert AlbumTitleNormalizer.japanese?('月夜 feat. English Artist')
    assert_not AlbumTitleNormalizer.japanese?('Moonlight (feat. 月の人)')
  end
end
