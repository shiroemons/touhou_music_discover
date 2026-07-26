# frozen_string_literal: true

module SpotifyClient
  class Album
    # rspotify (RSpotify::*) 経由でアルバムを取得する旧経路。
    # SpotifyApi への移行完了後、Issue #563 でこのファイルごと削除する。
    class RspotifyBackend
      def self.search_and_save_albums(keyword, year)
        offset = 0
        loop do
          s_albums = ::RSpotify::Album.search(keyword, limit: SEARCH_LIMIT, offset:, market: 'JP')
          s_albums.each do |s_album|
            process_album(s_album)
          end
          offset += s_albums.size
          break if s_albums.size < SEARCH_LIMIT

          puts "year:#{year}\toffset: #{offset}"
          # リクエスト間に短いディレイを追加
          sleep 1
        rescue RestClient::Exceptions::OpenTimeout, RestClient::Exceptions::ReadTimeout, Net::OpenTimeout => e
          puts "Timeout error during search at offset #{offset} for year:#{year}. Retrying after 10 seconds..."
          puts "Error: #{e.message}"
          sleep 10
          retry
        end
      end

      def self.process_album(s_album)
        spotify_album = SpotifyAlbum.exists?(spotify_id: s_album.id) ? SpotifyAlbum.find_by(spotify_id: s_album.id) : SpotifyAlbum.save_album(s_album)
        return if spotify_album.nil? || spotify_album.total_tracks == spotify_album.spotify_tracks.count

        s_tracks = s_album.tracks
        Album.save_tracks(spotify_album, s_tracks)
      rescue RestClient::Exceptions::OpenTimeout, RestClient::Exceptions::ReadTimeout, Net::OpenTimeout => e
        puts "Timeout error processing album #{s_album.id}. Skipping..."
        puts "Error: #{e.message}"
      end

      def self.update_albums(spotify_albums)
        s_albums = ::RSpotify::Album.find(spotify_albums.map(&:spotify_id))
        s_albums.each do |s_album|
          spotify_album = spotify_albums.find { it.spotify_id == s_album.id }
          next unless spotify_album

          spotify_album.update(
            album_type: s_album.album_type,
            name: s_album.name,
            url: s_album.external_urls['spotify'],
            total_tracks: s_album.total_tracks,
            payload: spotify_album.payload_preserving_available_markets(s_album.as_json)
          )
        end
      rescue *SpotifyRetry::RATE_LIMIT_ERRORS => e
        SpotifyRateLimit.record_from_error!(e, source: 'SpotifyClient::Album.update_albums')
        raise
      end

      def self.fetch_and_process_album(spotify_id)
        Array(::RSpotify::Album.find([spotify_id])).each { |s_album| process_album(s_album) }
      end

      def self.search_and_save_album_by_jan(album, logger:)
        s_album = ::RSpotify::Album.search("upc:#{album.jan_code}", limit: JAN_SEARCH_LIMIT, market: 'JP')
                                   .find { |candidate| candidate.external_ids&.fetch('upc', nil) == album.jan_code }
        return :missing if s_album.blank?

        if s_album.label != ::Album::TOUHOU_MUSIC_LABEL
          logger.info "Spotify album skipped because label is not #{::Album::TOUHOU_MUSIC_LABEL}: JAN #{album.jan_code}, Spotify ID #{s_album.id}, label #{s_album.label}"
          return :missing
        end

        existing_spotify_album = SpotifyAlbum.unscoped.find_by(spotify_id: s_album.id)
        if existing_spotify_album.present?
          return :skipped if existing_spotify_album.album_id == album.id

          logger.warn "Spotify album ID #{s_album.id} is already linked to another album: JAN #{album.jan_code}, existing album_id #{existing_spotify_album.album_id}"
          return :errors
        end

        process_album(s_album)
        spotify_album = SpotifyAlbum.unscoped.find_by(spotify_id: s_album.id)
        return :created if spotify_album&.album_id == album.id

        logger.warn "Spotify album was not saved for JAN #{album.jan_code}: Spotify ID #{s_album.id}"
        :errors
      end

      # rspotify 固有の tracks_cache を使ったページング実装。process_album からは呼ばれない
      # （既存の挙動をそのまま維持するため）。#563 で削除するまで元のコードをそのまま残す。
      def self.fetch_tracks(s_album)
        s_tracks = []
        track_offset = 0
        loop do
          tracks = if track_offset.zero?
                     s_album.tracks_cache
                   else
                     s_album.tracks(limit: LIMIT, offset: track_offset)
                   end
          s_tracks.push(*tracks)
          break if tracks.count < LIMIT

          track_offset += LIMIT
        end
        s_tracks
      end
      private_class_method :fetch_tracks
    end
  end
end
