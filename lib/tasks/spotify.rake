# frozen_string_literal: true

namespace :spotify do
  desc 'SpotifyAlbumの重複を整理（デフォルトはdry-run）'
  task dedupe_albums: :environment do
    mode = ENV.fetch('MODE', 'same_spotify_id')
    apply = ENV.fetch('APPLY', '0') == '1'
    sample_limit = ENV.fetch('SAMPLE_LIMIT', '20').to_i
    verbose = ENV.fetch('VERBOSE', '0') == '1'
    safe_only = ENV.fetch('SAFE_ONLY', mode == 'same_jan' ? '1' : '0') == '1'

    unless %w[same_spotify_id same_jan].include?(mode)
      abort 'MODE must be same_spotify_id or same_jan'
    end

    group_key =
      case mode
      when 'same_spotify_id'
        :spotify_id
      when 'same_jan'
        :album_id
      end

    duplicate_keys = SpotifyAlbum.unscoped
                                 .group(group_key)
                                 .having('COUNT(*) > 1')
                                 .pluck(group_key)

    puts "mode: #{mode}"
    puts "apply: #{apply}"
    puts "verbose: #{verbose}"
    puts "safe_only: #{safe_only}"
    puts "duplicate groups: #{duplicate_keys.size}"

    removed_albums = 0
    removed_tracks = 0
    moved_tracks = 0
    skipped_groups = 0

    duplicate_keys.each_with_index do |key, index|
      spotify_albums = SpotifyAlbum.unscoped
                                   .includes(:album, spotify_tracks: %i[track spotify_track_audio_feature])
                                   .where(group_key => key)
                                   .to_a

      track_counts = spotify_albums.map { |spotify_album| spotify_album.spotify_tracks.size }
      isrc_sets = spotify_albums.map do |spotify_album|
        spotify_album.spotify_tracks.map(&:track).map(&:isrc).compact.sort
      end

      if mode == 'same_jan' && safe_only && (!track_counts.uniq.one? || !isrc_sets.uniq.one?)
        skipped_groups += 1
        if index < sample_limit || verbose
          jan_code = spotify_albums.first.album&.jan_code
          puts [
            'skip_manual_review',
            jan_code,
            "track_counts=#{track_counts.join('/')}",
            "spotify_ids=#{spotify_albums.map(&:spotify_id).join('/')}"
          ].join("\t")
        end
        next
      end

      keep =
        if mode == 'same_jan'
          SpotifyAlbum.preferred_active_album(spotify_albums)
        else
          spotify_albums.max_by do |spotify_album|
            audio_feature_count = spotify_album.spotify_tracks.count do |spotify_track|
              spotify_track.spotify_track_audio_feature.present?
            end

            [
              audio_feature_count,
              spotify_album.spotify_tracks.size,
              spotify_album.total_tracks.to_i,
              spotify_album.updated_at.to_i,
              spotify_album.created_at.to_i,
              spotify_album.id
            ]
          end
        end
      duplicates = spotify_albums - [keep]

      if index < sample_limit || verbose
        jan_code = keep.album&.jan_code
        puts [
          'keep',
          jan_code,
          keep.spotify_id,
          keep.name,
          "tracks=#{keep.spotify_tracks.size}",
          "created_at=#{keep.created_at}"
        ].join("\t")

        duplicates.each do |spotify_album|
          puts [
            apply ? 'remove' : 'would_remove',
            jan_code,
            spotify_album.spotify_id,
            spotify_album.name,
            "tracks=#{spotify_album.spotify_tracks.size}",
            "created_at=#{spotify_album.created_at}"
          ].join("\t")
        end
      end

      next unless apply

      duplicates.each do |spotify_album|
        ActiveRecord::Base.transaction do
          spotify_album.spotify_tracks.find_each do |spotify_track|
            existing_track = SpotifyTrack.unscoped.find_by(
              spotify_album_id: keep.id,
              spotify_id: spotify_track.spotify_id
            )

            if mode == 'same_spotify_id' && existing_track.nil?
              spotify_track.update!(
                album_id: keep.album_id,
                spotify_album_id: keep.id
              )
              moved_tracks += 1
            else
              removed_tracks += 1
              spotify_track.destroy!
            end
          end

          spotify_album.destroy!
          removed_albums += 1
        end
      end
    end

    puts "removed albums: #{removed_albums}"
    puts "removed tracks: #{removed_tracks}"
    puts "moved tracks: #{moved_tracks}"
    puts "skipped groups: #{skipped_groups}"
    puts 'dry-run only. Set APPLY=1 to delete duplicates.' unless apply
  end

  desc 'Spotify label:東方同人音楽流通 のアルバムとトラックを年代ごとに取得'
  task fetch_touhou_albums: :environment do
    SpotifyClient::Album.fetch_touhou_albums
    puts "\n完了しました。"
  end

  desc 'SpotifyAlbumのactiveフラグを同一JANごとに1件へ正規化（デフォルトはdry-run）'
  task normalize_active_albums: :environment do
    apply = ENV.fetch('APPLY', '0') == '1'
    delete_markets_zero = ENV.fetch('DELETE_MARKETS_ZERO', '0') == '1'
    sample_limit = ENV.fetch('SAMPLE_LIMIT', '20').to_i
    verbose = ENV.fetch('VERBOSE', '0') == '1'

    duplicate_album_ids = SpotifyAlbum.unscoped
                                      .group(:album_id)
                                      .having('COUNT(*) > 1')
                                      .pluck(:album_id)

    puts "apply: #{apply}"
    puts "delete_markets_zero: #{delete_markets_zero}"
    puts "duplicate groups: #{duplicate_album_ids.size}"

    activated_albums = 0
    deactivated_albums = 0
    removed_albums = 0
    removed_tracks = 0

    duplicate_album_ids.each_with_index do |album_id, index|
      spotify_albums = SpotifyAlbum.unscoped
                                   .includes(:album, :spotify_tracks)
                                   .where(album_id:)
                                   .to_a
      active_album = SpotifyAlbum.preferred_active_album(spotify_albums)
      inactive_albums = spotify_albums - [active_album]

      if index < sample_limit || verbose
        jan_code = active_album.album&.jan_code
        active_action = active_album.active? ? 'keep_active' : 'activate'
        puts [
          apply ? active_action : "would_#{active_action}",
          jan_code,
          active_album.spotify_id,
          active_album.name,
          "markets=#{active_album.available_markets.size}",
          "jp=#{active_album.jp_available?}",
          "tracks=#{active_album.spotify_tracks.size}",
          "created_at=#{active_album.created_at}"
        ].join("\t")

        inactive_albums.each do |spotify_album|
          action =
            if delete_markets_zero && spotify_album.available_markets.empty?
              'remove_markets_zero'
            elsif spotify_album.active?
              'deactivate'
            else
              'keep_inactive'
            end
          puts [
            apply ? action : "would_#{action}",
            jan_code,
            spotify_album.spotify_id,
            spotify_album.name,
            "markets=#{spotify_album.available_markets.size}",
            "jp=#{spotify_album.jp_available?}",
            "tracks=#{spotify_album.spotify_tracks.size}",
            "created_at=#{spotify_album.created_at}"
          ].join("\t")
        end
      end

      next unless apply

      ActiveRecord::Base.transaction do
        inactive_albums.each do |spotify_album|
          if spotify_album.active?
            spotify_album.update!(active: false)
            deactivated_albums += 1
          end

          next unless delete_markets_zero && spotify_album.available_markets.empty?

          removed_tracks += spotify_album.spotify_tracks.size
          spotify_album.destroy!
          removed_albums += 1
        end

        unless active_album.active?
          active_album.update!(active: true)
          activated_albums += 1
        end
      end
    end

    puts "activated albums: #{activated_albums}"
    puts "deactivated albums: #{deactivated_albums}"
    puts "removed albums: #{removed_albums}"
    puts "removed tracks: #{removed_tracks}"
    puts 'dry-run only. Set APPLY=1 to update active flags.' unless apply
  end

  desc 'available_marketsが空のSpotifyAlbumを削除（デフォルトはdry-run）'
  task prune_unavailable_albums: :environment do
    apply = ENV.fetch('APPLY', '0') == '1'
    sample_limit = ENV.fetch('SAMPLE_LIMIT', '20').to_i

    spotify_albums = SpotifyAlbum.unscoped
                                 .includes(:album, :spotify_tracks)
                                 .where(
                                   "jsonb_typeof(payload->'available_markets') = 'array' " \
                                   "AND jsonb_array_length(payload->'available_markets') = 0"
                                 )
                                 .to_a

    puts "apply: #{apply}"
    puts "unavailable albums: #{spotify_albums.size}"

    removed_tracks = 0
    spotify_albums.each_with_index do |spotify_album, index|
      if index < sample_limit
        puts [
          apply ? 'remove' : 'would_remove',
          spotify_album.album&.jan_code,
          spotify_album.spotify_id,
          spotify_album.name,
          "active=#{spotify_album.active?}",
          "tracks=#{spotify_album.spotify_tracks.size}",
          "created_at=#{spotify_album.created_at}"
        ].join("\t")
      end

      next unless apply

      removed_tracks += spotify_album.spotify_tracks.size
      spotify_album.destroy!
    end

    puts "removed albums: #{apply ? spotify_albums.size : 0}"
    puts "removed tracks: #{removed_tracks}"
    puts 'dry-run only. Set APPLY=1 to delete unavailable albums.' unless apply
  end

  desc 'Spotify Audio Featuresを取得'
  task fetch_audio_features: :environment do
    count = 0
    max_count = SpotifyTrack.count
    print "\rSpotify 楽曲: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
    SpotifyTrack.eager_load(:album, :spotify_album, :track).find_in_batches(batch_size: 100) do |spotify_tracks|
      Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
        puts "try #{retries} failed with exception: #{exception}" if retries.positive?

        SpotifyClient::AudioFeatures.fetch_by_spotify_tracks(spotify_tracks)
      end
      count += spotify_tracks.size
      print "\rSpotify 楽曲: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
      sleep 0.5
    end
    puts "\n完了しました。"
  end

  desc 'Spotify SpotifyAlbumの情報を更新'
  task update_spotify_albums: :environment do
    count = 0
    max_count = SpotifyAlbum.count
    SpotifyAlbum.eager_load(:album).find_in_batches(batch_size: 20) do |spotify_albums|
      Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
        puts "try #{retries} failed with exception: #{exception}" if retries.positive?

        SpotifyClient::Album.update_albums(spotify_albums)
      end
      count += spotify_albums.size
      print "\rSpotify アルバム: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
      sleep 0.5
    end
  end

  desc 'Spotify SpotifyTrackの情報を更新'
  task update_spotify_tracks: :environment do
    count = 0
    max_count = SpotifyTrack.count
    SpotifyTrack.eager_load(:album, :spotify_album, :track).find_in_batches(batch_size: 50) do |spotify_tracks|
      Retryable.retryable(tries: 5, sleep: 15, on: [RestClient::TooManyRequests, RestClient::InternalServerError]) do |retries, exception|
        puts "try #{retries} failed with exception: #{exception}" if retries.positive?

        SpotifyClient::Track.update_tracks(spotify_tracks)
      end
      count += spotify_tracks.size
      print "\rSpotify 楽曲: #{count}/#{max_count} Progress: #{(count * 100.0 / max_count).round(1)}%"
      sleep 0.5
    end
  end
end
