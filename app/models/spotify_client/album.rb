# frozen_string_literal: true

module SpotifyClient
  class Album
    LIMIT = 50
    JAN_SEARCH_LIMIT = 10
    DEFAULT_JAN_SEARCH_SLEEP = 1
    DEFAULT_RATE_LIMIT_MAX_WAIT = 60
    KEYWORD = 'label:東方同人音楽流通'

    def self.fetch_touhou_albums
      Parallel.each(2000..Time.zone.today.year, in_processes: 3) do |year|
        keyword = "#{KEYWORD} year:#{year}"
        retry_count = 0
        max_retries = 5
        begin
          search_and_save_albums(keyword, year)
        rescue RestClient::TooManyRequests => e
          retry_after = e.response.headers[:retry_after]&.to_i || 30
          puts "Rate limit exceeded for year:#{year}. Waiting for #{retry_after} seconds..."
          sleep retry_after
          retry
        rescue RestClient::Exceptions::OpenTimeout, RestClient::Exceptions::ReadTimeout, Net::OpenTimeout => e
          retry_count += 1
          if retry_count <= max_retries
            wait_time = 2**retry_count # 指数バックオフ: 2, 4, 8, 16, 32秒
            puts "Connection timeout for year:#{year}. Retrying in #{wait_time} seconds... (#{retry_count}/#{max_retries})"
            puts "Error: #{e.message}"
            sleep wait_time
            retry
          else
            puts "Max retries reached for year:#{year}. Skipping..."
          end
        end
      end
    end

    def self.search_and_save_albums(keyword, year)
      offset = 0
      loop do
        s_albums = RSpotify::Album.search(keyword, limit: LIMIT, offset:, market: 'JP')
        s_albums.each do |s_album|
          process_album(s_album)
        end
        offset += s_albums.size
        break if s_albums.size < LIMIT

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
      save_tracks(spotify_album, s_tracks)
    rescue RestClient::Exceptions::OpenTimeout, RestClient::Exceptions::ReadTimeout, Net::OpenTimeout => e
      puts "Timeout error processing album #{s_album.id}. Skipping..."
      puts "Error: #{e.message}"
    end

    def self.save_tracks(spotify_album, s_tracks)
      s_tracks.each do |s_track|
        SpotifyTrack.save_track(spotify_album, s_track)
      end
    end

    def self.fetch_missing_albums_by_apple_music_jan(
      max_retry_after: DEFAULT_RATE_LIMIT_MAX_WAIT,
      sleep_interval: DEFAULT_JAN_SEARCH_SLEEP,
      logger: Rails.logger,
      progress_callback: nil
    )
      result = {
        total: missing_spotify_albums_with_apple_music.count,
        processed: 0,
        created: 0,
        skipped: 0,
        missing: 0,
        errors: 0,
        rate_limited: false,
        retry_after: nil
      }

      missing_spotify_albums_with_apple_music.find_each do |album|
        if SpotifyAlbum.unscoped.exists?(album_id: album.id)
          result[:skipped] += 1
          record_jan_search_progress(result, album, progress_callback)
          next
        end

        begin
          status = with_spotify_retry(max_retry_after:) do
            search_and_save_album_by_jan(album, logger:)
          end

          result[status] += 1
        rescue RestClient::TooManyRequests => e
          retry_after = retry_after_seconds(e)
          result[:rate_limited] = true
          result[:retry_after] = retry_after
          logger.warn "Spotify API rate limited while searching JAN #{album.jan_code}. Retry-After: #{retry_after || 'unknown'} seconds"
          break
        rescue StandardError => e
          result[:errors] += 1
          logger.error "Spotify JAN search failed for JAN #{album.jan_code}: #{e.class}: #{e.message}"
        ensure
          record_jan_search_progress(result, album, progress_callback)
        end

        sleep sleep_interval if sleep_interval.to_f.positive?
      end

      result
    end

    def self.fetch_albums(s_artist)
      s_albums = []
      album_offset = 0
      loop do
        albums = s_artist.albums(limit: LIMIT, offset: album_offset)
        s_albums.push(*albums)
        break if albums.count < LIMIT

        album_offset += LIMIT
      end
      # labelが "東方同人音楽流通"のみを絞り込む
      s_albums.select! { it.label == ::Album::TOUHOU_MUSIC_LABEL }
      s_albums
    end

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

    def self.update_albums(spotify_albums)
      s_albums = RSpotify::Album.find(spotify_albums.map(&:spotify_id))
      s_albums.each do |s_album|
        spotify_album = spotify_albums.find { it.spotify_id == s_album.id }
        spotify_album&.update(
          album_type: s_album.album_type,
          name: s_album.name,
          url: s_album.external_urls['spotify'],
          total_tracks: s_album.total_tracks,
          payload: s_album.as_json
        )
      end
    end

    def self.missing_spotify_albums_with_apple_music
      ::Album.joins(:apple_music_album)
             .where.missing(:spotify_albums)
             .includes(:apple_music_album)
    end
    private_class_method :missing_spotify_albums_with_apple_music

    def self.search_and_save_album_by_jan(album, logger:)
      s_album = RSpotify::Album.search("upc:#{album.jan_code}", limit: JAN_SEARCH_LIMIT, market: 'JP')
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
    private_class_method :search_and_save_album_by_jan

    def self.with_spotify_retry(max_retry_after:, max_attempts: 3)
      attempts = 0

      begin
        yield
      rescue RestClient::TooManyRequests => e
        attempts += 1
        retry_after = retry_after_seconds(e)
        raise if retry_after.blank? || retry_after > max_retry_after || attempts >= max_attempts

        sleep retry_after
        retry
      end
    end
    private_class_method :with_spotify_retry

    def self.retry_after_seconds(error)
      retry_after = error.http_headers[:retry_after] || error.http_headers['retry-after'] if error.respond_to?(:http_headers)
      retry_after ||= error.response&.headers&.dig(:retry_after)
      retry_after ||= error.response&.headers&.dig('retry-after')
      retry_after&.to_i
    end
    private_class_method :retry_after_seconds

    def self.record_jan_search_progress(result, album, progress_callback)
      result[:processed] += 1
      progress_callback&.call(result, album)
    end
    private_class_method :record_jan_search_progress
  end
end
