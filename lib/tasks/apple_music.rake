# frozen_string_literal: true

namespace :apple_music do
  desc 'Apple Music MasterArtistからアーティスト情報を取得'
  task master_artist_fetch: :environment do
    artists = MasterArtist.apple_music
    master_artist_count = 0
    max_master_artist_count = artists.count
    artists.each do |artist|
      AppleMusicClient::Artist.fetch(artist.key) unless AppleMusicArtist.exists?(apple_music_id: artist.key)
      master_artist_count += 1
      print "\rマスターアーティスト: #{master_artist_count}/#{max_master_artist_count} Progress: #{(master_artist_count * 100.0 / max_master_artist_count).round(1)}%"
    end
  end
end
