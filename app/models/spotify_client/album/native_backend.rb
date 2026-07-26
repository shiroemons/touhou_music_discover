# frozen_string_literal: true

module SpotifyClient
  class Album
    # SpotifyApi (lib/spotify_api) 経由でアルバムを取得する新経路。
    class NativeBackend
      TIMEOUT_ERRORS = [Faraday::TimeoutError, Faraday::ConnectionFailed, Net::OpenTimeout].freeze

      def self.search_and_save_albums(keyword, year)
        offset = 0
        loop do
          page = SpotifyApi::Album.search(keyword, limit: SEARCH_LIMIT, offset:)
          page.items.each { |s_album| process_album(s_album) }
          offset += page.items.size
          break if page.last_page? || page.items.empty?

          puts "year:#{year}\toffset: #{offset}"
          # リクエスト間に短いディレイを追加
          sleep 1
        rescue *TIMEOUT_ERRORS => e
          puts "Timeout error during search at offset #{offset} for year:#{year}. Retrying after 10 seconds..."
          puts "Error: #{e.message}"
          sleep 10
          retry
        end
      end

      def self.process_album(s_album)
        spotify_album, album_with_tracks = resolve_spotify_album(s_album)
        return if spotify_album.nil? || spotify_album.total_tracks == spotify_album.spotify_tracks.count

        simplified_tracks = fetch_all_tracks(spotify_album.spotify_id, album_with_tracks)
        Album.save_tracks(spotify_album, fetch_new_tracks(spotify_album, simplified_tracks))
      rescue *TIMEOUT_ERRORS => e
        puts "Timeout error processing album #{s_album.id}. Skipping..."
        puts "Error: #{e.message}"
      end

      def self.update_albums(spotify_albums)
        s_albums = SpotifyApi::Album.find_many(spotify_albums.map(&:spotify_id))
        albums_by_spotify_id = spotify_albums.index_by(&:spotify_id)
        s_albums.each do |s_album|
          spotify_album = albums_by_spotify_id[s_album.id]
          spotify_album&.update(
            album_type: s_album.album_type,
            name: s_album.name,
            url: s_album.external_urls['spotify'],
            total_tracks: s_album.total_tracks,
            payload: s_album.as_json
          )
        end
      rescue *SpotifyRetry::RATE_LIMIT_ERRORS => e
        SpotifyRateLimit.record_from_error!(e, source: 'SpotifyClient::Album.update_albums')
        raise
      end

      def self.fetch_and_process_album(spotify_id)
        process_album(SpotifyApi::Album.find(spotify_id))
      rescue SpotifyApi::NotFoundError
        nil
      end

      def self.search_and_save_album_by_jan(album, logger:)
        s_album = matching_full_candidate(album.jan_code)
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

      # 既存の SpotifyAlbum があれば API を叩かずに再利用する。
      # 新規のときだけフル取得する: GET /search が返す簡易オブジェクトは label と
      # external_ids を含まないため、そのまま SpotifyAlbum.save_album に渡すと
      # レーベル判定と UPC 照合が壊れる。
      #
      # 戻り値の第2要素は tracks の埋め込みを再利用できる可能性があるアルバム。
      # 既存レコードを再利用したときは引数の s_album をそのまま返す:
      # 呼び出し元がフルオブジェクトを渡していれば埋め込み tracks を使い回せるし、
      # 簡易オブジェクトなら tracks キーが無いので従来通り API から取得される。
      def self.resolve_spotify_album(s_album)
        existing = SpotifyAlbum.find_by(spotify_id: s_album.id)
        return [existing, s_album] if existing

        full_album = s_album.key?(:label) ? s_album : SpotifyApi::Album.find(s_album.id)
        [SpotifyAlbum.save_album(full_album), full_album]
      end
      private_class_method :resolve_spotify_album

      def self.fetch_all_tracks(spotify_id, album_with_tracks)
        items = []
        page = embedded_tracks_page(album_with_tracks) || SpotifyApi::Album.tracks(spotify_id, limit: LIMIT, offset: 0)
        loop do
          items.concat(page.items)
          break if page.last_page? || page.items.empty?

          page = SpotifyApi::Album.tracks(spotify_id, limit: LIMIT, offset: items.size)
        end
        items
      end
      private_class_method :fetch_all_tracks

      # GET /albums/{id} のレスポンスには先頭ページ分の tracks が埋め込まれているため、
      # 1リクエスト分を節約できる。
      def self.embedded_tracks_page(album_with_tracks)
        return nil if album_with_tracks.blank?

        tracks_body = album_with_tracks['tracks']
        return nil if tracks_body.blank?

        SpotifyApi::Page.build(tracks_body)
      end
      private_class_method :embedded_tracks_page

      # 未保存のトラックだけ SpotifyApi::Track.find でフル取得する。既存トラックを API で
      # 取得し直して上書きすると、簡易オブジェクトの payload で external_ids (ISRC) を含む
      # 情報が失われるため、既存トラックは触らずスキップする。
      def self.fetch_new_tracks(spotify_album, simplified_tracks)
        existing_ids = SpotifyTrack.unscoped
                                   .where(spotify_album_id: spotify_album.id, spotify_id: simplified_tracks.map(&:id))
                                   .pluck(:spotify_id)
                                   .to_set

        simplified_tracks.filter_map do |simplified_track|
          next if existing_ids.include?(simplified_track.id)

          SpotifyApi::Track.find(simplified_track.id)
        end
      end
      private_class_method :fetch_new_tracks

      # upc: 検索の結果も簡易オブジェクトで external_ids を含まないため、候補を順に
      # フル取得して UPC が一致する最初の1件を返す。lazy により一致した時点で
      # 以降の候補は取得しない。
      def self.matching_full_candidate(jan_code)
        candidates = SpotifyApi::Album.search("upc:#{jan_code}", limit: JAN_SEARCH_LIMIT)
        candidates.lazy.filter_map { |candidate| full_album_if_upc_matches(candidate, jan_code) }.first
      end
      private_class_method :matching_full_candidate

      def self.full_album_if_upc_matches(candidate, jan_code)
        full = SpotifyApi::Album.find(candidate.id)
        full if full.external_ids&.fetch('upc', nil) == jan_code
      end
      private_class_method :full_album_if_upc_matches
    end
  end
end
