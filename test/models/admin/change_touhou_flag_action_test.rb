# frozen_string_literal: true

require 'test_helper'

module Admin
  module Actions
    class ChangeTouhouFlagActionTest < ActiveSupport::TestCase
      test 'does not mark tracks or albums without original song links as non touhou' do
        album = Album.create!(jan_code: '4999999999999')
        track = Track.create!(jan_code: album.jan_code, isrc: 'JPABC260001')

        ChangeTouhouFlag.new.handle({})

        assert_predicate track.reload, :is_touhou?
        assert_predicate album.reload, :is_touhou?
      end

      test 'updates flags only when original song links exist for every album track' do
        original = Original.create!(
          code: 'admin-action-original',
          title: 'Admin Action Original',
          short_title: 'Admin',
          original_type: 'other',
          series_order: 999
        )
        original_song = OriginalSong.create!(
          code: 'admin-action-original-song',
          original:,
          title: 'オリジナル',
          composer: 'unknown',
          track_number: 1
        )
        album = Album.create!(jan_code: '4888888888888')
        track = Track.create!(jan_code: album.jan_code, isrc: 'JPABC260002')
        TracksOriginalSong.create!(track:, original_song:)

        ChangeTouhouFlag.new.handle({})

        assert_not_predicate track.reload, :is_touhou?
        assert_not_predicate album.reload, :is_touhou?
      end
    end
  end
end
