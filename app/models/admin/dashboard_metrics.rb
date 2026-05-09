# frozen_string_literal: true

module Admin
  class DashboardMetrics
    MISSING_TRACK_SAMPLE_LIMIT = 3

    SERVICE_CONFIGS = [
      {
        key: :spotify,
        label: 'Spotify',
        album_association: :spotify_album,
        track_association: :spotify_tracks,
        album_class: SpotifyAlbum,
        track_class: SpotifyTrack,
        album_track_association: :spotify_tracks,
        album_scope: -> { SpotifyAlbum.unscoped.where(active: true) },
        album_resource_key: 'spotify_albums',
        track_resource_key: 'tracks',
        missing_album_filter: { not_delivered: 'spotify' },
        missing_track_filter: { missing_streaming_track: 'spotify' },
        missing_track_action_resource_key: 'spotify_tracks',
        missing_track_action_key: 'fetch_missing_spotify_tracks'
      },
      {
        key: :apple_music,
        label: 'Apple Music',
        album_association: :apple_music_album,
        track_association: :apple_music_tracks,
        album_class: AppleMusicAlbum,
        track_class: AppleMusicTrack,
        album_track_association: :apple_music_tracks,
        album_resource_key: 'apple_music_albums',
        track_resource_key: 'tracks',
        missing_album_filter: { not_delivered: 'apple_music' },
        missing_track_filter: { missing_streaming_track: 'apple_music' },
        missing_track_action_resource_key: 'apple_music_tracks',
        missing_track_action_key: 'fetch_missing_apple_music_tracks'
      },
      {
        key: :line_music,
        label: 'LINE MUSIC',
        album_association: :line_music_album,
        track_association: :line_music_tracks,
        album_class: LineMusicAlbum,
        track_class: LineMusicTrack,
        album_track_association: :line_music_tracks,
        album_resource_key: 'line_music_albums',
        track_resource_key: 'tracks',
        missing_album_filter: { not_delivered: 'line_music' },
        missing_track_filter: { missing_streaming_track: 'line_music' },
        missing_track_action_resource_key: 'line_music_tracks',
        missing_track_action_key: 'fetch_missing_line_music_tracks'
      },
      {
        key: :ytmusic,
        label: 'YouTube Music',
        album_association: :ytmusic_album,
        track_association: :ytmusic_tracks,
        album_class: YtmusicAlbum,
        track_class: YtmusicTrack,
        album_track_association: :ytmusic_tracks,
        album_resource_key: 'ytmusic_albums',
        track_resource_key: 'tracks',
        missing_album_filter: { not_delivered: 'ytmusic' },
        missing_track_filter: { missing_streaming_track: 'ytmusic' },
        missing_track_action_resource_key: 'ytmusic_tracks',
        missing_track_action_key: 'fetch_missing_ytmusic_tracks'
      }
    ].freeze

    def self.call
      new.call
    end

    def call
      album_total = Album.unscoped.count
      track_total = Track.unscoped.count

      service_coverages = SERVICE_CONFIGS.map { |config| service_coverage(config, album_total, track_total) }
      data_quality = data_quality_items

      {
        totals: totals(album_total, track_total, service_coverages, data_quality),
        service_coverages:,
        work_queue: work_queue_items(service_coverages),
        data_quality:,
        playlist_sync: playlist_sync,
        generated_at: Time.current
      }
    end

    private

    def totals(album_total, track_total, service_coverages, data_quality)
      {
        albums: album_total,
        tracks: track_total,
        touhou_albums: Album.unscoped.where(is_touhou: true).count,
        non_touhou_albums: Album.unscoped.where(is_touhou: false).count,
        average_album_coverage: average_percentage(service_coverages.pluck(:album_coverage_percent)),
        open_quality_issues: data_quality.sum { |item| item[:count] }
      }
    end

    def service_coverage(config, album_total, track_total)
      album_count = Album.unscoped.where.associated(config.fetch(:album_association)).distinct.count
      track_count = Track.unscoped.where.associated(config.fetch(:track_association)).distinct.count
      completion = album_track_completion(config)

      {
        key: config.fetch(:key),
        label: config.fetch(:label),
        album_count:,
        album_total:,
        album_missing_count: album_total - album_count,
        album_coverage_percent: percentage(album_count, album_total),
        track_count:,
        track_total:,
        track_missing_count: track_total - track_count,
        track_coverage_percent: percentage(track_count, track_total),
        album_resource_key: config.fetch(:album_resource_key),
        track_resource_key: config.fetch(:track_resource_key),
        missing_album_filter: config.fetch(:missing_album_filter),
        missing_track_filter: config.fetch(:missing_track_filter),
        missing_track_action_resource_key: config.fetch(:missing_track_action_resource_key),
        missing_track_action_key: config.fetch(:missing_track_action_key),
        missing_album_tracks_count: completion.fetch(:missing),
        incomplete_album_tracks_count: completion.fetch(:incomplete),
        complete_album_tracks_count: completion.fetch(:complete),
        missing_track_samples: missing_track_samples(config)
      }
    end

    def missing_track_samples(config)
      Track
        .unscoped
        .includes(:album)
        .where
        .missing(config.fetch(:track_association))
        .order(jan_code: :desc, isrc: :asc)
        .limit(MISSING_TRACK_SAMPLE_LIMIT)
        .map do |track|
          {
            id: track.id,
            jan_code: track.jan_code,
            isrc: track.isrc,
            name: track.name.presence
          }
        end
    end

    def album_track_completion(config)
      scope = config.fetch(:album_scope, -> { config.fetch(:album_class).unscoped }).call
      association_name = config.fetch(:album_track_association)

      {
        missing: Admin::Resource.streaming_album_track_status_scope(scope, association_name, 'missing').count,
        incomplete: Admin::Resource.streaming_album_track_status_scope(scope, association_name, 'incomplete').count,
        complete: Admin::Resource.streaming_album_track_status_scope(scope, association_name, 'complete').count
      }
    end

    def work_queue_items(service_coverages)
      service_items = service_coverages.flat_map do |coverage|
        [
          queue_item(
            key: "#{coverage[:key]}_missing_albums",
            label: "#{coverage[:label]}アルバム未取得",
            count: coverage[:album_missing_count],
            description: 'アルバム単位の配信カタログ差分',
            resource_key: 'albums',
            filters: coverage.fetch(:missing_album_filter),
            severity: :warning
          ),
          queue_item(
            key: "#{coverage[:key]}_missing_tracks",
            label: "#{coverage[:label]}楽曲未取得",
            count: coverage[:track_missing_count],
            description: '既存楽曲に対する配信サービス未取得',
            resource_key: 'tracks',
            filters: coverage.fetch(:missing_track_filter),
            severity: :danger
          ),
          queue_item(
            key: "#{coverage[:key]}_incomplete_album_tracks",
            label: "#{coverage[:label]}楽曲不足アルバム",
            count: coverage[:incomplete_album_tracks_count],
            description: '総トラック数より取得済み楽曲が少ないアルバム',
            resource_key: coverage.fetch(:album_resource_key),
            filters: { track_status: 'incomplete' },
            severity: :warning
          )
        ]
      end

      catalog_items = [
        queue_item(
          key: 'tracks_missing_original_songs',
          label: '原曲未紐付け楽曲',
          count: Track.unscoped.where.missing(:original_songs).count,
          description: '原曲との関連がない楽曲',
          resource_key: 'tracks',
          filters: { original_songs_count: 'none' },
          severity: :danger
        ),
        queue_item(
          key: 'albums_missing_original_songs',
          label: '原曲未設定を含むアルバム',
          count: Album.unscoped.where(jan_code: Track.unscoped.where.missing(:original_songs).select(:jan_code)).count,
          description: '原曲入力の優先対象アルバム',
          resource_key: 'albums',
          filters: { tracks_original_songs: 'missing' },
          severity: :warning
        ),
        queue_item(
          key: 'albums_missing_circles',
          label: 'サークル未設定アルバム',
          count: Album.unscoped.where.missing(:circles).count,
          description: 'サークル情報が未登録のアルバム',
          resource_key: 'albums',
          severity: :notice
        )
      ]

      (catalog_items + service_items).select { |item| item[:count].positive? }.sort_by { |item| -item[:count] }.first(10)
    end

    def data_quality_items
      spotify_duplicate_album_ids = SpotifyAlbum.unscoped
                                                .select(:album_id)
                                                .group(:album_id)
                                                .having('COUNT(*) > 1')

      [
        quality_item(
          key: 'spotify_tracks_missing_audio_features',
          label: 'Spotify音響特徴未取得',
          count: SpotifyTrack.unscoped.where.missing(:spotify_track_audio_feature).count,
          description: 'テンポ・エネルギーなどの分析に使う特徴量がないSpotify楽曲',
          resource_key: 'spotify_tracks',
          severity: :warning
        ),
        quality_item(
          key: 'audio_features_missing_analysis_url',
          label: '解析URLなし',
          count: SpotifyTrackAudioFeature.unscoped.where(analysis_url: [nil, '']).count,
          description: 'Spotify音響特徴のanalysis_urlが空',
          resource_key: 'spotify_track_audio_features',
          filters: { audio_data_quality: 'missing_analysis_url' },
          severity: :notice
        ),
        quality_item(
          key: 'audio_features_missing_payload',
          label: '音響特徴payloadなし',
          count: SpotifyTrackAudioFeature.unscoped.where(payload: nil).count,
          description: '再取得や検証に使う元レスポンスがない音響特徴',
          resource_key: 'spotify_track_audio_features',
          filters: { audio_data_quality: 'missing_payload' },
          severity: :notice
        ),
        quality_item(
          key: 'spotify_duplicate_histories',
          label: 'Spotifyアルバム重複履歴',
          count: SpotifyAlbum.unscoped.where(album_id: spotify_duplicate_album_ids).count,
          description: '同じアルバムに複数のSpotify候補がある履歴',
          resource_key: 'spotify_albums',
          filters: { display: 'duplicated_all' },
          severity: :notice
        ),
        quality_item(
          key: 'inactive_spotify_albums',
          label: '非アクティブSpotifyアルバム',
          count: SpotifyAlbum.unscoped.where(active: false).count,
          description: '候補選定から外されたSpotifyアルバム',
          resource_key: 'spotify_albums',
          filters: { display: 'inactive' },
          severity: :notice
        )
      ].select { |item| item[:count].positive? }
    end

    def playlist_sync
      scope = SpotifyPlaylist.unscoped
      stale_scope = scope.where(synced_at: nil).or(scope.where(synced_at: ...24.hours.ago))
      total = scope.count
      stale = stale_scope.count

      {
        total:,
        synced: scope.where.not(synced_at: nil).count,
        never_synced: scope.where(synced_at: nil).count,
        stale:,
        latest_synced_at: scope.maximum(:synced_at),
        stale_percent: percentage(stale, total),
        resource_key: 'spotify_playlists'
      }
    end

    def queue_item(key:, label:, count:, **options)
      description = options.fetch(:description)
      resource_key = options.fetch(:resource_key)
      severity = options.fetch(:severity)
      filters = options.fetch(:filters, {})

      {
        key:,
        label:,
        count:,
        description:,
        resource_key:,
        filters:,
        severity:
      }
    end

    alias quality_item queue_item

    def percentage(value, total)
      return 0 if total.to_i.zero?
      return 100.0 if value.to_i >= total.to_i

      ((value.to_f / total) * 1000).floor / 10.0
    end

    def average_percentage(percentages)
      return 0 if percentages.empty?

      ((percentages.sum.to_f / percentages.size) * 10).floor / 10.0
    end
  end
end
