# frozen_string_literal: true

require 'fileutils'

module Admin
  module Actions
    class BaseAction
      class << self
        attr_accessor :action_name
      end

      attr_reader :response

      def initialize
        @response = { messages: [] }
      end

      def inform(message = nil)
        add_message(:info, message)
      end

      def succeed(message = nil)
        add_message(:success, message)
      end

      def warn(message = nil)
        add_message(:warning, message)
      end

      def error(message = nil)
        add_message(:error, message)
      end

      def reload; end

      private

      def add_message(type, message)
        response[:messages] << { type:, body: message.to_s }
      end

      def progress_percent(count, total)
        return 100 if total.zero?

        (count * 100.0 / total).round(1)
      end

      def record_progress(current:, total:, message:, reset: false)
        if reset
          Admin::ActionProgress.start(total:, message:)
        else
          Admin::ActionProgress.update(current:, total:, message:)
        end
      end

      def albums_with_missing_tracks(track_scope, album_association:, includes: [])
        scope = Album
                .unscoped
                .where(jan_code: track_scope.select(:jan_code))
                .where
                .associated(album_association)

        includes.present? ? scope.includes(*includes) : scope
      end

      def fetch_missing_tracks_by_album(service_name:, track_scope:, album_association:, target_association:, includes: [])
        albums = albums_with_missing_tracks(track_scope, album_association:, includes:)
        total_count = albums.count
        stats = {
          target_albums: total_count,
          acquired_tracks: 0,
          completed_albums: 0,
          partial_albums: 0,
          not_found_albums: 0,
          errors: 0,
          acquired_examples: [],
          not_found_examples: [],
          partial_examples: [],
          error_examples: []
        }
        Admin::ActionProgress.start(total: total_count, message: "#{service_name}の未取得楽曲を取得しています")

        albums.find_each.with_index(1) do |album, index|
          before_count = missing_track_count(album, target_association)
          missing_tracks = missing_track_examples(album, target_association)
          Admin::ActionProgress.update(
            current: index - 1,
            total: total_count,
            message: "#{service_name}: #{index}/#{total_count} #{album_display_name(album)} を処理中 " \
                     "(未取得#{before_count}件: #{missing_tracks})"
          )

          begin
            yield album
            after_count = missing_track_count(album, target_association)
            record_album_fetch_outcome(stats, album:, before_count:, after_count:, target_association:)
            progress_context = {
              service_name:,
              index:,
              total_count:,
              album:,
              before_count:,
              after_count:,
              stats:
            }
            Admin::ActionProgress.update(
              current: index,
              total: total_count,
              message: album_fetch_progress_message(progress_context)
            )
          rescue RestClient::TooManyRequests
            raise
          rescue StandardError => e
            stats[:errors] += 1
            append_example(stats, :error_examples, "#{album_display_name(album)}: #{e.class}")
            Rails.logger.error("[Admin::Actions] #{service_name} missing track fetch failed for JAN #{album.jan_code}: #{e.class} - #{e.message}")
            Admin::ActionProgress.update(
              current: index,
              total: total_count,
              message: "#{service_name}: #{index}/#{total_count} #{album_display_name(album)} エラー (#{e.class})"
            )
          end
        end

        stats
      end

      def missing_track_count(album, target_association)
        Track.unscoped.where(jan_code: album.jan_code).where.missing(target_association).count
      end

      def record_album_fetch_outcome(stats, album:, before_count:, after_count:, target_association:)
        acquired_count = [before_count - after_count, 0].max
        stats[:acquired_tracks] += acquired_count
        append_example(stats, :acquired_examples, "#{album_display_name(album)}: 取得#{acquired_count}件") if acquired_count.positive?

        if after_count.zero?
          stats[:completed_albums] += 1
        elsif acquired_count.positive?
          stats[:partial_albums] += 1
          append_example(
            stats,
            :partial_examples,
            album_track_example(album, count_label: "残り#{after_count}件", target_association:)
          )
        else
          stats[:not_found_albums] += 1
          append_example(
            stats,
            :not_found_examples,
            album_track_example(album, count_label: "未取得#{after_count}件", target_association:)
          )
        end
      end

      def album_fetch_progress_message(context)
        service_name = context.fetch(:service_name)
        index = context.fetch(:index)
        total_count = context.fetch(:total_count)
        album = context.fetch(:album)
        before_count = context.fetch(:before_count)
        after_count = context.fetch(:after_count)
        stats = context.fetch(:stats)
        acquired_count = [before_count - after_count, 0].max
        outcome = if after_count.zero?
                    '取得完了'
                  elsif acquired_count.positive?
                    "一部取得(取得#{acquired_count}件/残り#{after_count}件)"
                  else
                    "未検出(残り#{after_count}件)"
                  end

        "#{service_name}: #{index}/#{total_count} #{album_display_name(album)} #{outcome} " \
          "(累計 取得#{stats[:acquired_tracks]}件 / 完了#{stats[:completed_albums]}アルバム / " \
          "一部#{stats[:partial_albums]}アルバム / 未検出#{stats[:not_found_albums]}アルバム / エラー#{stats[:errors]}件)"
      end

      def album_display_name(album)
        name = album.line_music_album&.name ||
               album.ytmusic_album&.name ||
               album.spotify_album&.name ||
               album.apple_music_album&.name
        name.present? ? "#{name} (JAN #{album.jan_code})" : "JAN #{album.jan_code}"
      end

      def track_display_name(track)
        name = track.name.presence || '曲名未取得'
        "#{track.isrc} - #{name}"
      end

      def spotify_track_display_name(spotify_track)
        name = spotify_track.name.presence || spotify_track.track&.name.presence || '曲名未取得'
        isrc = spotify_track.track&.isrc
        isrc.present? ? "#{isrc} - #{name}" : "#{spotify_track.spotify_id} - #{name}"
      end

      def missing_track_examples(album, target_association, limit: 3)
        missing_tracks(album, target_association, limit:).map { |track| track_display_name(track) }.presence&.join(', ') || 'なし'
      end

      def album_track_example(album, count_label:, target_association:)
        lines = ["#{album_display_name(album)}: #{count_label}"]
        lines.concat(missing_tracks(album, target_association).map { |track| "    - #{track_display_name(track)}" })
        lines.join("\n")
      end

      def missing_tracks(album, target_association, limit: nil)
        scope = Track
                .unscoped
                .where(jan_code: album.jan_code)
                .where
                .missing(target_association)
                .includes(:spotify_tracks, :apple_music_tracks)
                .order(:isrc)
        scope = scope.limit(limit) if limit.present?
        scope.to_a
      end

      def album_fetch_summary(service_name, stats)
        lines = [
          "#{service_name}未取得楽曲",
          "- 対象: #{stats[:target_albums]}アルバム",
          "- 取得: #{stats[:acquired_tracks]}件",
          "- 完了: #{stats[:completed_albums]}アルバム",
          "- 一部取得: #{stats[:partial_albums]}アルバム",
          "- 未検出: #{stats[:not_found_albums]}アルバム",
          "- エラー: #{stats[:errors]}件",
          *fetch_summary_example_lines(stats)
        ]
        lines.join("\n")
      end

      def fetch_summary_example_lines(stats)
        [
          summary_example_line('取得一覧', stats[:acquired_examples]),
          summary_example_line('一部取得一覧', stats[:partial_examples]),
          summary_example_line('未検出一覧', stats[:not_found_examples]),
          summary_example_line('エラー一覧', stats[:error_examples])
        ].compact
      end

      def summary_example_line(label, examples)
        return if examples.blank?

        ["- #{label}:", *examples.map { |example| "  - #{example}" }].join("\n")
      end

      def append_example(stats, key, value)
        stats[key] << value
      end

      def finish_with_summary(message, errors:)
        errors.positive? ? warn(message) : succeed(message)
      end
    end

    class BulkRetrieval < BaseAction
      self.action_name = '一括取得'

      def handle(**_args)
        Admin::ActionProgress.start(total: 7, message: 'Spotify アルバムを取得しています')

        SpotifyClient::Album.fetch_touhou_albums
        Admin::ActionProgress.advance(message: 'Apple Music アルバムとトラックを取得しています')

        AppleMusicTrack.fetch_tracks_and_albums
        Admin::ActionProgress.advance(message: 'YouTube Music アルバムを取得しています')

        YtmusicAlbum.fetch_albums
        Admin::ActionProgress.advance(message: 'YouTube Music トラックを取得しています')

        YtmusicTrack.fetch_tracks
        Admin::ActionProgress.advance(message: 'LINE MUSIC アルバムを取得しています')

        LineMusicAlbum.fetch_albums
        Admin::ActionProgress.advance(message: 'LINE MUSIC トラックを取得しています')

        LineMusicTrack.fetch_tracks
        Admin::ActionProgress.advance(message: 'サークルを設定しています')

        CircleAssignmentService.new.assign_missing
        Admin::ActionProgress.advance(message: '一括取得が完了しました')

        succeed 'Done!'
      end
    end

    class ChangeTouhouFlag < BaseAction
      self.action_name = '東方フラグを変更'

      def handle(_args)
        total_count = Track.count + Album.count
        Admin::ActionProgress.start(total: total_count, message: '楽曲の東方フラグを再判定しています')

        Track.includes(:original_songs).find_each do |track|
          original_songs = track.original_songs
          if original_songs.present?
            is_touhou = original_songs.all? { it.title != 'オリジナル' } && !original_songs.all? { it.title == 'その他' }
            track.update(is_touhou:) if track.is_touhou != is_touhou
          end
          Admin::ActionProgress.advance(message: "楽曲を処理しています: #{track.jan_code}")
        end

        Album.includes(tracks: :original_songs).find_each do |album|
          if album.tracks.present? && album.tracks.none? { |track| track.original_songs.empty? }
            is_touhou = album.tracks.map(&:is_touhou).any?
            album.update!(is_touhou:) if album.is_touhou != is_touhou
          end
          Admin::ActionProgress.advance(message: "アルバムを処理しています: #{album.jan_code}")
        end

        succeed 'Done!'
      end
    end

    class ExportMissingOriginalSongsTracks < BaseAction
      self.action_name = '原曲未設定の楽曲一覧をエクスポート'

      def handle(_args)
        tsv_data = CSV.generate(col_sep: "\t") do |csv|
          csv << %w[jan_code isrc circle_name album_name track_name original_songs]
          Track.includes(:spotify_tracks, :apple_music_tracks).missing_original_songs.order(jan_code: :desc).order(isrc: :asc).each do |track|
            csv << [
              track.jan_code,
              track.isrc,
              track.circle_name,
              track.album_name,
              track.name,
              track.original_songs.map(&:title).join('/')
            ]
          end
        end

        export_path = Rails.root.join('tmp/admin_exports/missing_original_songs_tracks.tsv')
        FileUtils.mkdir_p(export_path.dirname)
        File.write(export_path, tsv_data)
        succeed "TSVを作成しました: #{export_path.relative_path_from(Rails.root)}"
      end
    end

    class FetchAppleMusicAlbum < BaseAction
      self.action_name = 'Apple Musicアルバムを取得'

      def handle(_args)
        master_artist_count = MasterArtist.apple_music.count
        Admin::ActionProgress.start(total: master_artist_count, message: 'Apple Musicアーティストを取得しています')
        processed_count = 0

        MasterArtist.apple_music.find_in_batches(batch_size: 25) do |master_artists|
          AppleMusicClient::Artist.fetch(master_artists.map(&:key))
          processed_count += master_artists.size
          Admin::ActionProgress.update(
            current: processed_count,
            total: master_artist_count,
            message: "Apple Musicアーティストを処理しています: #{processed_count}/#{master_artist_count}"
          )
        end

        am_artist_ids = AppleMusicArtist.pluck(:apple_music_id)
        Admin::ActionProgress.start(total: am_artist_ids.size, message: 'Apple Musicアルバムを取得しています')
        am_artist_ids.each do |am_artist_id|
          AppleMusicClient::Album.fetch_artists_albums(am_artist_id)
          Admin::ActionProgress.advance(message: "Apple MusicアーティストIDを処理しています: #{am_artist_id}")
        end

        succeed 'Done!'
      end
    end

    class FetchAppleMusicAlbumById < BaseAction
      self.action_name = 'Apple MusicアルバムIDから取得'

      def handle(**args)
        field = args.values_at(:fields).first
        album_id = field['album_id']
        return error('アルバムIDを入力してください') if album_id.blank?

        begin
          am_album = AppleMusic::Album.find(album_id)
          return error('アルバムが見つかりませんでした') if am_album.nil?
        rescue AppleMusic::ApiError
          return error('アルバムが見つかりませんでした')
        end

        if AppleMusicAlbum.exists?(apple_music_id: album_id)
          apple_music_album = AppleMusicAlbum.find_by(apple_music_id: album_id)
          album = ::Album.find_or_create_by!(jan_code: am_album.upc)
          apple_music_album.update(album_id: album.id, payload: am_album.as_json)
        else
          am_album = AppleMusicClient::Album.fetch(album_id)
          return error('アルバムが見つかりませんでした') if am_album.nil?

          apple_music_album = AppleMusicAlbum.find_by(apple_music_id: album_id)
        end

        AppleMusicClient::Track.fetch_album_tracks(apple_music_album)

        succeed 'アルバム情報とトラックの取得が完了しました'
      end
    end

    class FetchAppleMusicTrack < BaseAction
      self.action_name = 'Apple Music トラックを取得'

      def handle(_args)
        total_count = AppleMusicAlbum.count
        Admin::ActionProgress.start(total: total_count, message: 'Apple Musicアルバムのトラックを取得しています')

        AppleMusicAlbum.find_each do |apple_music_album|
          AppleMusicClient::Track.fetch_album_tracks(apple_music_album)
          Admin::ActionProgress.advance(message: "アルバムを処理しています: #{apple_music_album.name}")
        end

        succeed 'Done!'
      end
    end

    class FetchAppleMusicTrackByIsrc < BaseAction
      self.action_name = 'ISRCからApple Music トラックを取得'

      def handle(_args)
        total_count = Track.missing_apple_music_tracks.count
        Admin::ActionProgress.start(total: total_count, message: 'ISRCからApple Musicトラックを取得しています')

        Track.missing_apple_music_tracks.find_each do |track|
          AppleMusicClient::Track.fetch_tracks_by_isrc(track.isrc)
          Admin::ActionProgress.advance(message: "ISRCを処理しています: #{track.isrc}")
        end

        succeed 'Done!'
      end
    end

    class FetchMissingAppleMusicTracks < BaseAction
      self.action_name = 'Apple Music未取得楽曲だけ取得'

      def handle(_args)
        total_count = Track.missing_apple_music_tracks.count
        stats = {
          target_tracks: total_count,
          acquired_tracks: 0,
          not_found_tracks: 0,
          errors: 0,
          acquired_examples: [],
          not_found_examples: [],
          error_examples: []
        }
        Admin::ActionProgress.start(total: total_count, message: 'Apple Music未取得楽曲をISRCから取得しています')

        Track.missing_apple_music_tracks.find_each.with_index(1) do |track, index|
          Admin::ActionProgress.update(
            current: index - 1,
            total: total_count,
            message: "Apple Music: #{index}/#{total_count} #{track_display_name(track)} を処理中"
          )

          begin
            AppleMusicClient::Track.fetch_tracks_by_isrc(track.isrc)
            if AppleMusicTrack.unscoped.exists?(track_id: track.id)
              stats[:acquired_tracks] += 1
              append_example(stats, :acquired_examples, track_display_name(track))
              outcome = '取得成功'
            else
              stats[:not_found_tracks] += 1
              append_example(stats, :not_found_examples, track_display_name(track))
              outcome = '未検出'
            end
            Admin::ActionProgress.update(
              current: index,
              total: total_count,
              message: "Apple Music: #{index}/#{total_count} #{track_display_name(track)} #{outcome} " \
                       "(累計 取得#{stats[:acquired_tracks]}件 / 未検出#{stats[:not_found_tracks]}件 / エラー#{stats[:errors]}件)"
            )
          rescue RestClient::TooManyRequests
            raise
          rescue StandardError => e
            stats[:errors] += 1
            append_example(stats, :error_examples, "#{track_display_name(track)}: #{e.class}")
            Rails.logger.error("[Admin::Actions] Apple Music missing track fetch failed for ISRC #{track.isrc}: #{e.class} - #{e.message}")
            Admin::ActionProgress.update(
              current: index,
              total: total_count,
              message: "Apple Music: #{index}/#{total_count} #{track_display_name(track)} エラー (#{e.class})"
            )
          end
        end

        message = [
          'Apple Music未取得楽曲',
          "- 対象: #{stats[:target_tracks]}件",
          "- 取得: #{stats[:acquired_tracks]}件",
          "- 未検出: #{stats[:not_found_tracks]}件",
          "- エラー: #{stats[:errors]}件",
          *fetch_summary_example_lines(stats)
        ].join("\n")
        finish_with_summary(message, errors: stats[:errors])
      end
    end

    class FetchAppleMusicVariousArtistsAlbum < BaseAction
      self.action_name = 'Apple Music Various Artistsアルバムを取得'

      def handle(_args)
        album_ids = AppleMusicAlbum::VARIOUS_ARTISTS_ALBUMS_IDS
        Admin::ActionProgress.start(total: album_ids.size, message: 'Various Artistsアルバムを取得しています')

        album_ids.each do |album_id|
          apple_music_album = AppleMusicClient::Album.fetch(album_id)
          AppleMusicClient::Track.fetch_album_tracks(apple_music_album) if apple_music_album
          Admin::ActionProgress.advance(message: "アルバムを処理しています: #{album_id}")
        end

        succeed 'Done!'
      end
    end

    class FetchLineMusicAlbum < BaseAction
      self.action_name = 'LINE MUSIC アルバムを取得'

      def handle(_args)
        LineMusicAlbum.fetch_albums(progress_callback: method(:record_progress))

        succeed 'Done!'
      end
    end

    class FetchLineMusicTrack < BaseAction
      self.action_name = 'LINE MUSIC トラックを取得'

      def handle(_args)
        LineMusicTrack.fetch_tracks(progress_callback: method(:record_progress))

        succeed 'Done!'
      end
    end

    class FetchMissingLineMusicTracks < BaseAction
      self.action_name = 'LINE MUSIC未取得楽曲だけ取得'

      def handle(_args)
        stats = fetch_missing_tracks_by_album(
          service_name: 'LINE MUSIC',
          track_scope: Track.missing_line_music_tracks,
          album_association: :line_music_album,
          target_association: :line_music_tracks,
          includes: [:line_music_album, { spotify_album: :spotify_tracks }, { apple_music_album: :apple_music_tracks }]
        ) do |album|
          LineMusicTrack.process_album(album)
        end

        finish_with_summary(album_fetch_summary('LINE MUSIC', stats), errors: stats[:errors])
      end
    end

    class FetchMissingSpotifyAlbumByAppleMusicJan < BaseAction
      self.action_name = 'Apple Music JANでSpotifyアルバムを補完'

      def handle(_args)
        progress_callback = lambda do |result, album|
          next unless (result[:processed] % 5).zero? || result[:processed] == result[:total] || result[:rate_limited]

          inform "Spotify JAN補完: #{result[:processed]}/#{result[:total]} JAN #{album.jan_code}"
        end

        result = SpotifyClient::Album.fetch_missing_albums_by_apple_music_jan(progress_callback:)

        message = "処理完了: 作成#{result[:created]}件, スキップ#{result[:skipped]}件, 未検出#{result[:missing]}件, エラー#{result[:errors]}件"
        if result[:rate_limited]
          retry_after = result[:retry_after].presence || '不明'
          message = "#{message}, レート制限で中断(Retry-After: #{retry_after}秒)"
        end

        succeed message
      end
    end

    class FetchSpotifyAlbum < BaseAction
      self.action_name = 'Spotify アルバムを取得'

      def handle(_args)
        SpotifyClient::Album.fetch_touhou_albums(progress_callback: method(:record_progress))

        succeed 'Done!'
      end
    end

    class FetchMissingSpotifyTracks < BaseAction
      self.action_name = 'Spotify未取得楽曲だけ取得'

      def handle(_args)
        stats = {
          target_albums: 0,
          acquired_tracks: 0,
          completed_albums: 0,
          partial_albums: 0,
          not_found_albums: 0,
          errors: 0,
          acquired_examples: [],
          not_found_examples: [],
          partial_examples: [],
          error_examples: []
        }
        spotify_albums = SpotifyAlbum
                         .unscoped
                         .active
                         .joins(:album)
                         .where(albums: { jan_code: Track.missing_spotify_tracks.select(:jan_code) })
                         .includes(:album, :spotify_tracks)
                         .distinct
        total_count = spotify_albums.count
        stats[:target_albums] = total_count
        Admin::ActionProgress.start(total: total_count, message: 'Spotify未取得楽曲を取得しています')

        spotify_albums.find_each.with_index(1) do |spotify_album, index|
          before_count = missing_track_count(spotify_album.album, :spotify_tracks)
          Admin::ActionProgress.update(
            current: index - 1,
            total: total_count,
            message: "Spotify: #{index}/#{total_count} #{album_display_name(spotify_album.album)} を処理中 " \
                     "(未取得#{before_count}件: #{missing_track_examples(spotify_album.album, :spotify_tracks)})"
          )

          begin
            Array(RSpotify::Album.find([spotify_album.spotify_id])).each do |api_album|
              SpotifyClient::Album.process_album(api_album)
            end
            after_count = missing_track_count(spotify_album.album, :spotify_tracks)
            record_album_fetch_outcome(stats, album: spotify_album.album, before_count:, after_count:, target_association: :spotify_tracks)
            progress_context = {
              service_name: 'Spotify',
              index:,
              total_count:,
              album: spotify_album.album,
              before_count:,
              after_count:,
              stats:
            }
            Admin::ActionProgress.update(
              current: index,
              total: total_count,
              message: album_fetch_progress_message(progress_context)
            )
          rescue RestClient::TooManyRequests
            raise
          rescue StandardError => e
            stats[:errors] += 1
            append_example(stats, :error_examples, "#{album_display_name(spotify_album.album)}: #{e.class}")
            Rails.logger.error("[Admin::Actions] Spotify missing track fetch failed for JAN #{spotify_album.jan_code}: #{e.class} - #{e.message}")
            Admin::ActionProgress.update(
              current: index,
              total: total_count,
              message: "Spotify: #{index}/#{total_count} #{album_display_name(spotify_album.album)} エラー (#{e.class})"
            )
          end
        end

        finish_with_summary(album_fetch_summary('Spotify', stats), errors: stats[:errors])
      end
    end

    class FetchSpotifyAudioFeatures < BaseAction
      self.action_name = 'Spotify オーディオ特性を取得'

      def handle(_args)
        count = 0
        max_count = SpotifyTrack.count
        inform "Spotify 楽曲: #{count}/#{max_count} Progress: #{progress_percent(count, max_count)}%"
        SpotifyTrack.eager_load(:album, :spotify_album, :track).find_in_batches(batch_size: 100) do |spotify_tracks|
          Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
            warn "try #{retries} failed with exception: #{exception}" if retries.positive?

            SpotifyClient::AudioFeatures.fetch_by_spotify_tracks(spotify_tracks)
          end
          count += spotify_tracks.size
          inform "Spotify 楽曲: #{count}/#{max_count} Progress: #{progress_percent(count, max_count)}%"
          sleep 0.5
        end

        succeed 'Done!'
      end
    end

    class FetchMissingSpotifyAudioFeatures < BaseAction
      self.action_name = 'Spotify未取得オーディオ特性だけ取得'

      def handle(_args)
        count = 0
        stats = {
          target_tracks: 0,
          acquired_tracks: 0,
          not_found_tracks: 0,
          errors: 0,
          acquired_examples: [],
          not_found_examples: [],
          error_examples: []
        }
        spotify_tracks = SpotifyTrack
                         .unscoped
                         .where
                         .missing(:spotify_track_audio_feature)
                         .includes(:album, :spotify_album, :track)
        total_count = spotify_tracks.count
        stats[:target_tracks] = total_count
        inform "Spotify オーディオ特性未取得楽曲: #{count}/#{total_count} Progress: #{progress_percent(count, total_count)}%"

        spotify_tracks.find_in_batches(batch_size: 100) do |batch|
          inform "Spotify オーディオ特性取得中: #{batch.first&.album&.spotify_album_name || batch.first&.spotify_album&.name || 'アルバム名未取得'} / " \
                 "#{batch.first(3).map { |spotify_track| spotify_track_display_name(spotify_track) }.join(', ')}"
          begin
            Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
              warn "try #{retries} failed with exception: #{exception}" if retries.positive?

              SpotifyClient::AudioFeatures.fetch_by_spotify_tracks(batch)
            end
            batch.each do |spotify_track|
              if SpotifyTrackAudioFeature.unscoped.exists?(spotify_track_id: spotify_track.id)
                stats[:acquired_tracks] += 1
                append_example(stats, :acquired_examples, spotify_track_display_name(spotify_track))
              else
                stats[:not_found_tracks] += 1
                append_example(stats, :not_found_examples, spotify_track_display_name(spotify_track))
              end
            end
          rescue RestClient::TooManyRequests
            raise
          rescue StandardError => e
            stats[:errors] += batch.size
            append_example(stats, :error_examples, "#{spotify_track_display_name(batch.first)}: #{e.class}") if batch.first
            Rails.logger.error("[Admin::Actions] Spotify audio features fetch failed: #{e.class} - #{e.message}")
          end
          count += batch.size
          inform "Spotify オーディオ特性未取得楽曲: #{count}/#{total_count} Progress: #{progress_percent(count, total_count)}% " \
                 "(取得#{stats[:acquired_tracks]}件 / 未検出#{stats[:not_found_tracks]}件 / エラー#{stats[:errors]}件)"
          sleep 0.5
        end

        message = [
          'Spotify未取得オーディオ特性',
          "- 対象: #{stats[:target_tracks]}件",
          "- 取得: #{stats[:acquired_tracks]}件",
          "- 未検出: #{stats[:not_found_tracks]}件",
          "- エラー: #{stats[:errors]}件",
          *fetch_summary_example_lines(stats)
        ].join("\n")
        finish_with_summary(message, errors: stats[:errors])
      end
    end

    class FetchYtmusicAlbum < BaseAction
      self.action_name = 'YouTube Music アルバムを取得'

      def handle(_args)
        YtmusicAlbum.fetch_albums(progress_callback: method(:record_progress))

        succeed 'Done!'
      end
    end

    class FetchYtmusicTrack < BaseAction
      self.action_name = 'YouTube Music トラックを取得'

      def handle(_args)
        YtmusicTrack.fetch_tracks(progress_callback: method(:record_progress))

        succeed 'Done!'
      end
    end

    class FetchMissingYtmusicTracks < BaseAction
      self.action_name = 'YouTube Music未取得楽曲だけ取得'

      def handle(_args)
        stats = fetch_missing_tracks_by_album(
          service_name: 'YouTube Music',
          track_scope: Track.missing_ytmusic_tracks,
          album_association: :ytmusic_album,
          target_association: :ytmusic_tracks,
          includes: [:ytmusic_album, { spotify_album: :spotify_tracks }, { apple_music_album: :apple_music_tracks }]
        ) do |album|
          YtmusicTrack.process_album(album)
        end

        finish_with_summary(album_fetch_summary('YouTube Music', stats), errors: stats[:errors])
      end
    end

    class ImportTracksWithOriginalSongs < BaseAction
      self.action_name = 'TSVファイルから楽曲と原曲の関連付けをインポート'

      def handle(**args)
        field = args.values_at(:fields).first
        tsv_file = field['tsv_file']
        return error('Import error.') unless tsv_file&.content_type&.in?(['text/tab-separated-values'])

        songs = CSV.table(tsv_file.path, col_sep: "\t", converters: nil, liberal_parsing: true)
        Admin::ActionProgress.start(total: songs.size, message: 'TSVの楽曲紐づけをインポートしています')
        songs.each do |song|
          jan_code = song[:jan_code]
          isrc = song[:isrc]
          original_songs = song[:original_songs]
          track = Track.find_by(jan_code:, isrc:)
          if track.present? && original_songs.present?
            original_song_list = OriginalSong.where(title: original_songs.split('/'), is_duplicate: false)
            track.original_songs = original_song_list
          end
          Admin::ActionProgress.advance(message: "楽曲を処理しています: #{jan_code} / #{isrc}")
        end
        succeed('Completed!')
      end
    end

    class ProcessLineMusicJanToAlbumIds < BaseAction
      self.action_name = 'JAN_TO_ALBUM_IDS を処理'

      def handle(_args)
        created_count = 0
        updated_count = 0
        skipped_count = 0
        error_count = 0
        missing_count = 0

        Admin::ActionProgress.start(
          total: LineMusicAlbum::JAN_TO_ALBUM_IDS.size,
          message: 'JAN_TO_ALBUM_IDS を処理しています'
        )

        LineMusicAlbum::JAN_TO_ALBUM_IDS.each do |jan_code, line_music_album_id|
          album = Album.find_by(jan_code:)

          if album.nil?
            missing_count += 1
            Rails.logger.warn "JAN: #{jan_code} のアルバムが見つかりません"
            Admin::ActionProgress.advance(message: "JANを処理しています: #{jan_code}")
            next
          end

          line_music_album = LineMusicAlbum.find_by(line_music_id: line_music_album_id)

          if line_music_album.nil? || line_music_album.album_id != album.id
            begin
              lm_album = LineMusicAlbum.with_retry(max_attempts: 3) do
                LineMusic::Album.find(line_music_album_id)
              end

              if lm_album.blank?
                error_count += 1
                Rails.logger.warn "エラー: JAN #{jan_code} - LINE MUSIC アルバムが見つかりません: #{line_music_album_id}"
                Admin::ActionProgress.advance(message: "JANを処理しています: #{jan_code}")
                next
              end

              saved_line_music_album = LineMusicAlbum.save_album(album.id, lm_album)
              if saved_line_music_album.blank?
                error_count += 1
                Rails.logger.warn "エラー: JAN #{jan_code} - LINE MUSIC アルバム情報が不完全なため保存をスキップしました: #{line_music_album_id}"
                Admin::ActionProgress.advance(message: "JANを処理しています: #{jan_code}")
                next
              end

              if line_music_album.nil?
                created_count += 1
                Rails.logger.info "作成: JAN #{jan_code} → LINE MUSIC ID #{line_music_album_id}"
              else
                updated_count += 1
                Rails.logger.info "更新: JAN #{jan_code} → LINE MUSIC ID #{line_music_album_id}"
              end
            rescue StandardError => e
              error_count += 1
              Rails.logger.error "エラー: JAN #{jan_code} - #{e.class}: #{e.message}"
            end
          else
            skipped_count += 1
          end
          Admin::ActionProgress.advance(message: "JANを処理しています: #{jan_code}")
        end

        succeed "処理完了: 作成#{created_count}件, 更新#{updated_count}件, スキップ#{skipped_count}件, エラー#{error_count}件, 未検出#{missing_count}件"
      end
    end

    class ProcessYtmusicJanToAlbumBrowseIds < BaseAction
      self.action_name = 'JAN_TO_ALBUM_BROWSE_IDS を処理'

      def handle(_args)
        result = YtmusicAlbum.process_jan_to_album_browse_ids

        succeed "処理完了: 作成#{result[:created]}件, スキップ#{result[:skipped]}件, エラー#{result[:errors]}件, 未検出#{result[:missing]}件"
      end
    end

    class SetCircles < BaseAction
      self.action_name = 'サークルを設定'

      def handle(_args)
        CircleAssignmentService.new.assign_missing
        succeed 'Done!'
      end
    end

    class UpdateAllYtmusicAlbumPayloads < BaseAction
      self.action_name = 'すべてのYouTube Music アルバムのペイロードを更新'

      def handle(_args)
        total_count = YtmusicAlbum.count
        success_count = 0
        error_count = 0
        errors = []
        mutex = Mutex.new

        Admin::ActionProgress.start(total: total_count, message: 'YouTube Musicアルバムのペイロードを更新しています')
        inform "#{total_count}件のアルバムのペイロード更新を開始します...(3並列で実行)"

        processed = 0
        progress = Admin::ActionProgress.current

        YtmusicAlbum.find_in_batches(batch_size: 100) do |batch|
          Parallel.each(batch, in_threads: 3) do |ytmusic_album|
            current_index = nil
            mutex.synchronize do
              processed += 1
              current_index = processed
            end

            Rails.logger.info "YouTube Music アルバムのペイロードを更新 (#{current_index}/#{total_count}): #{ytmusic_album.browse_id}"

            album = YtMusic::Album.find(ytmusic_album.browse_id)

            if album.nil?
              mutex.synchronize do
                error_count += 1
                errors << "#{ytmusic_album.name}: YouTube Musicからアルバム情報を取得できませんでした"
              end
              next
            end

            url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
            ytmusic_album.update_album(album, url)

            mutex.synchronize { success_count += 1 }
            Rails.logger.info "ペイロード更新成功: #{album.title}"

            sleep 0.5
          rescue StandardError => e
            mutex.synchronize do
              error_count += 1
              errors << "#{ytmusic_album.name}: #{e.message}"
            end
            Rails.logger.error "ペイロード更新エラー: #{e.class} - #{e.message}"
          ensure
            progress&.update(
              current: current_index,
              total: total_count,
              message: "YouTube Music アルバムを処理しています: #{current_index}/#{total_count} #{ytmusic_album.name}"
            )
          end
        end

        message = "更新完了: 成功 #{success_count}件 / エラー #{error_count}件 / 合計 #{total_count}件"

        if error_count.positive?
          message += "\n\nエラー詳細:\n"
          errors.first(10).each do |error_msg|
            message += "• #{error_msg}\n"
          end
          message += "...他#{errors.size - 10}件のエラー" if errors.size > 10
        end

        if error_count.zero?
          succeed message
        elsif success_count.positive?
          warn message
        else
          error message
        end
      end
    end

    class UpdateAppleMusicAlbum < BaseAction
      self.action_name = 'Apple Music アルバムを更新'

      def handle(_args)
        count = 0
        total_count = AppleMusicAlbum.count
        Admin::ActionProgress.start(total: total_count, message: 'Apple Musicアルバムを更新しています')

        AppleMusicAlbum.eager_load(:album).find_in_batches(batch_size: 20) do |apple_music_albums|
          AppleMusicClient::Album.update_albums(apple_music_albums)
          count += apple_music_albums.size
          Admin::ActionProgress.update(
            current: count,
            total: total_count,
            message: "Apple Musicアルバムを更新しています: #{count}/#{total_count}"
          )
          sleep 0.5
        end

        succeed 'Done!'
      end
    end

    class UpdateAppleMusicTrack < BaseAction
      self.action_name = 'Apple Music トラックを更新'

      def handle(_args)
        count = 0
        total_count = AppleMusicTrack.count
        Admin::ActionProgress.start(total: total_count, message: 'Apple Musicトラックを更新しています')

        AppleMusicTrack.eager_load(:album, :apple_music_album, :track).find_in_batches(batch_size: 50) do |apple_music_tracks|
          AppleMusicClient::Track.update_tracks(apple_music_tracks)
          count += apple_music_tracks.size
          Admin::ActionProgress.update(
            current: count,
            total: total_count,
            message: "Apple Musicトラックを更新しています: #{count}/#{total_count}"
          )
          sleep 0.5
        end

        succeed 'Done!'
      end
    end

    class UpdateLineMusicAlbum < BaseAction
      self.action_name = 'LINE MUSIC アルバムを更新'

      def handle(_args)
        updated_count = 0
        error_count = 0
        total_count = LineMusicAlbum.count
        Admin::ActionProgress.start(total: total_count, message: 'LINE MUSICアルバムを更新しています')

        LineMusicAlbum.find_each do |line_music_album|
          Rails.logger.info "Fetching LINE MUSIC album: #{line_music_album.line_music_id}"
          lm_album = LineMusic::Album.find(line_music_album.line_music_id)

          if lm_album.present?
            line_music_album.update(
              name: lm_album.album_title,
              total_tracks: lm_album.track_total_count,
              payload: lm_album.as_json
            )
            updated_count += 1
          end
        rescue Faraday::ConnectionFailed => e
          Rails.logger.error "Connection failed for album #{line_music_album.line_music_id}: #{e.message}"
          error_count += 1
        rescue Faraday::TimeoutError => e
          Rails.logger.error "Timeout for album #{line_music_album.line_music_id}: #{e.message}"
          error_count += 1
        rescue StandardError => e
          Rails.logger.error "Error updating album #{line_music_album.line_music_id}: #{e.class} - #{e.message}"
          error_count += 1
        ensure
          Admin::ActionProgress.advance(message: "アルバムを処理しています: #{line_music_album.name}")
        end

        if error_count.positive?
          warn "更新完了: #{updated_count}件成功、#{error_count}件エラー"
        else
          succeed "更新完了: #{updated_count}件成功"
        end
      end
    end

    class UpdateLineMusicTrack < BaseAction
      self.action_name = 'LINE MUSIC トラックを更新'

      def handle(_args)
        Rails.logger.info 'LINE MUSIC トラック更新処理を開始します'

        album_count = LineMusicAlbum.count
        Rails.logger.info "処理対象アルバム数: #{album_count}件"
        Admin::ActionProgress.start(total: album_count, message: 'LINE MUSICトラックを更新しています')

        processed_count = 0
        updated_count = 0

        LineMusicAlbum.eager_load(:line_music_tracks).find_each do |line_music_album|
          processed_count += 1
          Rails.logger.info "アルバム処理中 (#{processed_count}/#{album_count}): #{line_music_album.name}"

          begin
            with_retry(max_attempts: 3) do
              Rails.logger.info "LINE MUSIC トラック取得: アルバムID #{line_music_album.line_music_id}"
              lm_tracks = LineMusic::Album.tracks(line_music_album.line_music_id)
              Rails.logger.info "LINE MUSIC トラック取得成功: #{lm_tracks.size}件"

              track_count = line_music_album.line_music_tracks.size
              Rails.logger.info "更新対象トラック数: #{track_count}件"

              track_processed = 0
              line_music_album.line_music_tracks.each do |line_music_track|
                track_processed += 1
                Rails.logger.info "トラック処理中 (#{track_processed}/#{track_count}): #{line_music_track.name}"

                lm_track = lm_tracks.find { it.track_id == line_music_track.line_music_id }

                if lm_track.blank?
                  Rails.logger.warn "LINE MUSIC トラックが見つかりませんでした: #{line_music_track.line_music_id}"
                  next
                end

                Rails.logger.info "トラック情報更新: #{lm_track.track_title}"
                line_music_track.update(
                  name: lm_track.track_title,
                  disc_number: lm_track.disc_number,
                  track_number: lm_track.track_number,
                  payload: lm_track.as_json
                )
                updated_count += 1
                Rails.logger.info "トラック情報を更新しました: #{lm_track.track_title}"
              end
            end
          rescue StandardError => e
            Rails.logger.error "アルバム処理中にエラーが発生しました: #{line_music_album.name} - #{e.message}"
          end

          Rails.logger.info "#{processed_count}件のアルバムを処理しました (更新済みトラック: #{updated_count}件)" if (processed_count % 10).zero?
          Admin::ActionProgress.update(
            current: processed_count,
            total: album_count,
            message: "アルバムを処理しています: #{processed_count}/#{album_count} #{line_music_album.name}"
          )
        end

        Rails.logger.info "LINE MUSIC トラック更新処理が完了しました: 合計 #{processed_count}件のアルバム、#{updated_count}件のトラックを処理しました"
        succeed "処理が完了しました！ #{processed_count}件のアルバム、#{updated_count}件のトラックを処理しました。"
      end

      private

      def with_retry(max_attempts: 3, retry_delay: 2)
        attempts = 0
        begin
          attempts += 1
          yield
        rescue Faraday::ConnectionFailed, Net::OpenTimeout => e
          if attempts < max_attempts
            Rails.logger.warn "接続エラーが発生しました。#{attempts}回目のリトライを実行します: #{e.message}"
            sleep retry_delay * attempts
            retry
          end

          Rails.logger.error "最大リトライ回数(#{max_attempts}回)に達しました: #{e.message}"
          raise
        end
      end
    end

    class UpdateSpotifyAlbum < BaseAction
      self.action_name = 'Spotify アルバムを更新'

      def handle(_args)
        count = 0
        max_count = SpotifyAlbum.count
        SpotifyAlbum.eager_load(:album).find_in_batches(batch_size: 20) do |spotify_albums|
          Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
            warn "try #{retries} failed with exception: #{exception}" if retries.positive?

            SpotifyClient::Album.update_albums(spotify_albums)
          end
          count += spotify_albums.size
          inform "Spotify アルバム: #{count}/#{max_count} Progress: #{progress_percent(count, max_count)}%"
          sleep 0.5
        end

        succeed 'Done!'
      end
    end

    class UpdateSpotifyTrack < BaseAction
      self.action_name = 'Spotify トラックを更新'

      def handle(_args)
        count = 0
        max_count = SpotifyTrack.count
        SpotifyTrack.eager_load(:album, :spotify_album, :track).find_in_batches(batch_size: 50) do |spotify_tracks|
          Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
            warn "try #{retries} failed with exception: #{exception}" if retries.positive?

            SpotifyClient::Track.update_tracks(spotify_tracks)
          end
          count += spotify_tracks.size
          inform "Spotify 楽曲: #{count}/#{max_count} Progress: #{progress_percent(count, max_count)}%"
          sleep 0.5
        end

        succeed 'Done!'
      end
    end

    class UpdateYtmusicAlbumPayload < BaseAction
      self.action_name = 'YouTube Music アルバムのペイロードを更新'

      def handle(**args)
        ytmusic_album = args[:models]&.first || ytmusic_album_from_fields(args)
        return error("レコードが見つかりませんでした。args: #{args.keys}") if ytmusic_album.nil?

        begin
          Rails.logger.info "YouTube Music アルバムのペイロードを更新: #{ytmusic_album.browse_id}"

          album = YtMusic::Album.find(ytmusic_album.browse_id)

          if album.nil?
            error('YouTube Musicからアルバム情報を取得できませんでした')
            return
          end

          url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
          ytmusic_album.update_album(album, url)

          Rails.logger.info "ペイロード更新成功: #{album.title}"
          succeed "アルバム「#{album.title}」のペイロードを更新しました"
        rescue StandardError => e
          Rails.logger.error "ペイロード更新エラー: #{e.class} - #{e.message}"
          error "更新中にエラーが発生しました: #{e.message}"
        end
      end

      private

      def ytmusic_album_from_fields(args)
        fields = args.values_at(:fields).first || args[:fields]
        resource_ids = fields&.dig('admin_resource_ids') || fields&.[]('admin_resource_ids')
        return if resource_ids.blank?

        YtmusicAlbum.find(Array(resource_ids).first)
      end
    end

    class UpdateYtmusicAlbumTrack < BaseAction
      self.action_name = 'YouTube Music アルバム・トラックを更新'

      def handle(_args)
        total_count = YtmusicAlbum.count
        Admin::ActionProgress.start(total: total_count, message: 'YouTube Musicアルバム・トラックを更新しています')

        YtmusicAlbum.find_each do |ytmusic_album|
          album = YtMusic::Album.find(ytmusic_album.browse_id)
          url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
          ytmusic_album.update_album(album, url) if album

          tracks = ytmusic_album.payload['tracks']
          ytmusic_album.ytmusic_tracks.each do |ytm_track|
            track = tracks.find { it['track_number'] == ytm_track.track_number }
            ytm_track.update_track(track) if track
          end
          Admin::ActionProgress.advance(message: "アルバムを処理しています: #{ytmusic_album.name}")
        end

        succeed 'Done!'
      end
    end
  end
end
