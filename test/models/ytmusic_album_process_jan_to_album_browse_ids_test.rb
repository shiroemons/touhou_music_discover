# frozen_string_literal: true

require 'test_helper'

class YtmusicAlbumProcessJanToAlbumBrowseIdsTest < ActiveSupport::TestCase
  YtmusicApiAlbum = Struct.new(:title, :playlist_url, :track_total_count, :year, keyword_init: true) do
    def as_json(*)
      {
        'title' => title,
        'playlist_url' => playlist_url,
        'track_total_count' => track_total_count,
        'year' => year
      }
    end
  end

  test 'creates YouTube Music album from JAN_TO_ALBUM_BROWSE_IDS' do
    jan_code = "ytmusic-jan-action-#{SecureRandom.hex(4)}"
    browse_id = "MPREb_#{SecureRandom.hex(8)}"
    album = Album.create!(jan_code:)
    api_album = YtmusicApiAlbum.new(
      title: 'YouTube Music Album',
      playlist_url: 'https://music.youtube.com/playlist?list=test',
      track_total_count: 2,
      year: '2026'
    )

    ytmusic_album_client = Class.new do
      define_singleton_method(:find) { |_| api_album }
    end

    stub_const(YtmusicAlbum, :JAN_TO_ALBUM_BROWSE_IDS, { jan_code => browse_id }) do
      stub_const(YtMusic, :Album, ytmusic_album_client) do
        assert_difference -> { YtmusicAlbum.unscoped.count }, 1 do
          @result = YtmusicAlbum.process_jan_to_album_browse_ids
        end
      end
    end

    ytmusic_album = YtmusicAlbum.find_by!(album:, browse_id:)
    assert_equal 'YouTube Music Album', ytmusic_album.name
    assert_equal "https://music.youtube.com/browse/#{browse_id}", ytmusic_album.url
    assert_equal 'https://music.youtube.com/playlist?list=test', ytmusic_album.playlist_url
    assert_equal 2, ytmusic_album.total_tracks
    assert_equal '2026', ytmusic_album.release_year
    assert_equal 1, @result[:created]
  end

  test 'skips already registered albums' do
    jan_code = "ytmusic-jan-skip-#{SecureRandom.hex(4)}"
    browse_id = "MPREb_#{SecureRandom.hex(8)}"
    album = Album.create!(jan_code:)
    YtmusicAlbum.create!(
      album:,
      browse_id:,
      name: 'Registered Album',
      url: "https://music.youtube.com/browse/#{browse_id}"
    )

    ytmusic_album_client = Class.new do
      define_singleton_method(:find) { |_| raise 'already registered album should not be fetched' }
    end

    stub_const(YtmusicAlbum, :JAN_TO_ALBUM_BROWSE_IDS, { jan_code => browse_id }) do
      stub_const(YtMusic, :Album, ytmusic_album_client) do
        assert_no_difference -> { YtmusicAlbum.unscoped.count } do
          @result = YtmusicAlbum.process_jan_to_album_browse_ids
        end
      end
    end

    assert_equal 1, @result[:skipped]
    assert_equal 0, @result[:created]
  end
end
