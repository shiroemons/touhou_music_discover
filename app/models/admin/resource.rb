# frozen_string_literal: true

module Admin
  class Resource
    include ActiveModel::Model

    DEFAULT_ITEMS = 50
    INDEX_ATTRIBUTE_LABEL_OVERRIDES = {
      'album_id' => :jan_code,
      'track_id' => :track_reference,
      'spotify_album_id' => :spotify_album_reference,
      'apple_music_album_id' => :apple_music_album_reference,
      'line_music_album_id' => :line_music_album_reference,
      'ytmusic_album_id' => :ytmusic_album_reference
    }.freeze

    attr_accessor :key, :model_class_name, :index_attributes, :detail_attributes, :form_attributes,
                  :search_attributes, :filter_definitions, :includes, :default_order, :action_class_names

    delegate :count, :primary_key, to: :model_class

    class << self
      def all
        @all ||= build_resources
      end

      def keys
        all.map(&:key)
      end

      def route_constraint
        Regexp.union(keys)
      end

      def find!(key)
        all.find { |resource| resource.key == key.to_s } || raise(ActiveRecord::RecordNotFound, "Unknown admin resource: #{key}")
      end

      def find_by_model_class(model_class)
        all.find { |resource| resource.model_class == model_class }
      end

      def streaming_album_track_status_scope(scope, association_name, value)
        return scope if value.blank?

        model_class = scope.klass
        reflection = model_class.reflect_on_association(association_name)
        return scope if reflection.blank?

        album_table = model_class.quoted_table_name
        track_table = reflection.klass.quoted_table_name
        album_primary_key = "#{album_table}.#{model_class.connection.quote_column_name(model_class.primary_key)}"
        track_primary_key = "#{track_table}.#{reflection.klass.connection.quote_column_name(reflection.klass.primary_key)}"
        total_tracks = "#{album_table}.#{model_class.connection.quote_column_name(:total_tracks)}"
        track_count = "COUNT(#{track_primary_key})"

        matching_ids = model_class
                       .unscoped
                       .left_joins(association_name)
                       .group(album_primary_key)

        matching_ids = case value
                       when 'missing'
                         matching_ids.having("#{track_count} = 0")
                       when 'incomplete'
                         matching_ids.having("#{total_tracks} > 0 AND #{track_count} > 0 AND #{track_count} < #{total_tracks}")
                       when 'complete'
                         matching_ids.having("#{total_tracks} > 0 AND #{track_count} >= #{total_tracks}")
                       else
                         return scope
                       end

        scope.where(model_class.primary_key => matching_ids.select(model_class.primary_key))
      end

      def track_original_songs_count_scope(scope, value)
        return scope if value.blank?

        tracks_table = Track.quoted_table_name
        original_songs_table = OriginalSong.quoted_table_name
        track_primary_key = "#{tracks_table}.#{Track.connection.quote_column_name(Track.primary_key)}"
        original_song_primary_key = "#{original_songs_table}.#{OriginalSong.connection.quote_column_name(OriginalSong.primary_key)}"
        original_songs_count = "COUNT(#{original_song_primary_key})"

        matching_ids = Track
                       .unscoped
                       .left_joins(:original_songs)
                       .group(track_primary_key)

        matching_ids = case value
                       when 'none'
                         matching_ids.having("#{original_songs_count} = 0")
                       when 'present'
                         matching_ids.having("#{original_songs_count} > 0")
                       when 'multiple'
                         matching_ids.having("#{original_songs_count} > 1")
                       else
                         return scope
                       end

        scope.where(Track.primary_key => matching_ids.select(Track.primary_key))
      end

      private

      def build_resources
        album_preview_includes = %i[circles spotify_album apple_music_album ytmusic_album line_music_album]
        touhou_filter = lambda {
          {
            key: 'touhou',
            label_key: 'admin.filters.touhou.label',
            include_blank: true,
            options: [
              ['true', '東方のみ'],
              ['false', '東方以外']
            ],
            apply: lambda { |scope, value|
              case value
              when 'true'
                scope.is_touhou
              when 'false'
                scope.non_touhou
              else
                scope
              end
            }
          }
        }
        track_status_filter = lambda { |association_name|
          {
            key: 'track_status',
            label_key: 'admin.filters.track_status.label',
            include_blank: true,
            options: [
              ['missing', '楽曲なし'],
              ['incomplete', '不足あり'],
              ['complete', '取得済み']
            ],
            apply: lambda { |scope, value|
              Admin::Resource.streaming_album_track_status_scope(scope, association_name, value)
            }
          }
        }
        missing_streaming_track_filter = {
          key: 'missing_streaming_track',
          label_key: 'admin.filters.missing_streaming_track.label',
          include_blank: true,
          options: [
            ['spotify', 'Spotify未取得'],
            ['apple_music', 'Apple Music未取得'],
            ['line_music', 'LINE MUSIC未取得'],
            ['ytmusic', 'YouTube Music未取得']
          ],
          apply: lambda { |scope, value|
            case value
            when 'spotify'
              scope.missing_spotify_tracks
            when 'apple_music'
              scope.missing_apple_music_tracks
            when 'line_music'
              scope.missing_line_music_tracks
            when 'ytmusic'
              scope.missing_ytmusic_tracks
            else
              scope
            end
          }
        }
        original_songs_count_filter = {
          key: 'original_songs_count',
          label_key: 'admin.filters.original_songs_count.label',
          include_blank: true,
          options: [
            ['none', '0曲'],
            ['present', '1曲以上'],
            ['multiple', '2曲以上']
          ],
          apply: lambda { |scope, value|
            Admin::Resource.track_original_songs_count_scope(scope, value)
          }
        }
        album_original_songs_filter = {
          key: 'tracks_original_songs',
          label_key: 'admin.filters.tracks_original_songs.label',
          include_blank: true,
          options: [
            ['missing', '未設定の楽曲あり']
          ],
          apply: lambda { |scope, value|
            case value
            when 'missing'
              scope.tracks_missing_original_songs
            else
              scope
            end
          }
        }
        track_preview_includes = [
          { album: album_preview_includes },
          :original_songs,
          { spotify_tracks: :spotify_album },
          { apple_music_tracks: :apple_music_album },
          { ytmusic_tracks: :ytmusic_album },
          { line_music_tracks: :line_music_album }
        ]

        [
          new(
            key: 'albums',
            model_class_name: 'Album',
            index_attributes: %i[jan_code circle_name spotify_album_name apple_music_album_name ytmusic_album_name line_music_album_name is_touhou],
            form_attributes: %i[jan_code is_touhou],
            search_attributes: %i[jan_code],
            filter_definitions: [
              {
                key: 'not_delivered',
                label_key: 'admin.filters.not_delivered.label',
                include_blank: true,
                options: [
                  ['apple_music', 'Apple Music未配信'],
                  ['spotify', 'Spotify未配信'],
                  ['line_music', 'LINE MUSIC未配信'],
                  ['ytmusic', 'YouTube Music未配信']
                ],
                apply: lambda { |scope, value|
                  case value
                  when 'apple_music'
                    scope.missing_apple_music_album
                  when 'spotify'
                    scope.missing_spotify_album
                  when 'line_music'
                    scope.missing_line_music_album
                  when 'ytmusic'
                    scope.missing_ytmusic_album
                  else
                    scope
                  end
                }
              },
              album_original_songs_filter
            ],
            includes: album_preview_includes,
            action_class_names: %w[BulkRetrieval ChangeTouhouFlag SetCircles]
          ),
          new(
            key: 'tracks',
            model_class_name: 'Track',
            index_attributes: %i[name album_name circle_name jan_code isrc streaming_tracks_status is_touhou original_songs_count],
            detail_attributes: %i[id name album_name circle_name jan_code isrc streaming_tracks_status is_touhou original_songs_count created_at updated_at],
            form_attributes: %i[jan_code isrc is_touhou],
            search_attributes: %i[jan_code isrc],
            filter_definitions: [missing_streaming_track_filter, original_songs_count_filter],
            includes: track_preview_includes,
            default_order: ->(scope) { scope.order(jan_code: :desc, id: :asc) },
            action_class_names: %w[ExportMissingOriginalSongsTracks ImportTracksWithOriginalSongs ChangeTouhouFlag]
          ),
          new(
            key: 'circles',
            model_class_name: 'Circle',
            index_attributes: %i[name albums_count],
            form_attributes: %i[name],
            search_attributes: %i[name]
          ),
          new(
            key: 'originals',
            model_class_name: 'Original',
            index_attributes: %i[code title short_title original_type series_order],
            form_attributes: %i[code title short_title original_type series_order],
            search_attributes: %i[code title short_title original_type]
          ),
          new(
            key: 'original_songs',
            model_class_name: 'OriginalSong',
            index_attributes: %i[code original_code title composer track_number is_duplicate],
            form_attributes: %i[code original_code title composer track_number is_duplicate],
            search_attributes: %i[code original_code title composer]
          ),
          new(
            key: 'master_artists',
            model_class_name: 'MasterArtist',
            index_attributes: %i[name key streaming_type],
            form_attributes: %i[name key streaming_type],
            search_attributes: %i[name key streaming_type]
          ),
          new(
            key: 'spotify_albums',
            model_class_name: 'SpotifyAlbum',
            index_attributes: %i[name circle_name album_id active release_date tracks_status total_tracks spotify_id],
            form_attributes: %i[album_id spotify_id album_type name label url release_date total_tracks active payload],
            search_attributes: %i[name spotify_id label],
            filter_definitions: [
              {
                key: 'display',
                label_key: 'admin.filters.spotify_album_display.label',
                default: 'active',
                options: [
                  ['active', 'アクティブのみ'],
                  ['duplicated_active', '重複あり（アクティブ）'],
                  ['duplicated_all', '重複あり（全履歴）'],
                  ['inactive', '非アクティブ'],
                  ['all', 'すべて']
                ],
                apply: lambda { |scope, value|
                  duplicate_album_ids = SpotifyAlbum.unscoped
                                                    .select(:album_id)
                                                    .group(:album_id)
                                                    .having('COUNT(*) > 1')

                  case value
                  when 'duplicated_active'
                    scope.active.where(album_id: duplicate_album_ids)
                  when 'duplicated_all'
                    scope.where(album_id: duplicate_album_ids)
                  when 'inactive'
                    scope.inactive
                  when 'all'
                    scope
                  else
                    scope.active
                  end
                }
              },
              track_status_filter.call(:spotify_tracks),
              touhou_filter.call
            ],
            includes: [:spotify_tracks, { album: album_preview_includes }],
            action_class_names: %w[FetchSpotifyAlbum FetchMissingSpotifyAlbumByAppleMusicJan UpdateSpotifyAlbum]
          ),
          new(
            key: 'spotify_tracks',
            model_class_name: 'SpotifyTrack',
            index_attributes: %i[name circle_name album_id track_id spotify_album_id disc_number track_number spotify_id],
            form_attributes: %i[album_id track_id spotify_album_id spotify_id name label url release_date disc_number track_number duration_ms payload],
            search_attributes: %i[name spotify_id label],
            filter_definitions: [touhou_filter.call],
            includes: [
              { album: album_preview_includes },
              :spotify_album,
              { track: track_preview_includes }
            ],
            action_class_names: %w[UpdateSpotifyTrack]
          ),
          new(
            key: 'apple_music_albums',
            model_class_name: 'AppleMusicAlbum',
            index_attributes: %i[name circle_name album_id release_date tracks_status total_tracks apple_music_id],
            form_attributes: %i[album_id apple_music_id name label url release_date total_tracks payload],
            search_attributes: %i[name apple_music_id label],
            filter_definitions: [track_status_filter.call(:apple_music_tracks), touhou_filter.call],
            includes: [:apple_music_tracks, { album: album_preview_includes }],
            action_class_names: %w[
              FetchAppleMusicAlbum
              FetchAppleMusicVariousArtistsAlbum
              FetchAppleMusicAlbumById
              UpdateAppleMusicAlbum
            ]
          ),
          new(
            key: 'apple_music_tracks',
            model_class_name: 'AppleMusicTrack',
            index_attributes: %i[name artist_name composer_name circle_name album_id track_id apple_music_album_id disc_number track_number apple_music_id],
            form_attributes: %i[album_id track_id apple_music_album_id apple_music_id name label artist_name composer_name url release_date disc_number track_number duration_ms payload],
            search_attributes: %i[name apple_music_id artist_name composer_name label],
            filter_definitions: [touhou_filter.call],
            includes: [
              { album: album_preview_includes },
              :apple_music_album,
              { track: track_preview_includes }
            ],
            action_class_names: %w[FetchAppleMusicTrack FetchAppleMusicTrackByIsrc UpdateAppleMusicTrack]
          ),
          new(
            key: 'line_music_albums',
            model_class_name: 'LineMusicAlbum',
            index_attributes: %i[name circle_name album_id release_date tracks_status total_tracks line_music_id],
            form_attributes: %i[album_id line_music_id name url release_date total_tracks payload],
            search_attributes: %i[name line_music_id],
            filter_definitions: [track_status_filter.call(:line_music_tracks), touhou_filter.call],
            includes: [:line_music_tracks, { album: album_preview_includes }],
            action_class_names: %w[FetchLineMusicAlbum UpdateLineMusicAlbum ProcessLineMusicJanToAlbumIds]
          ),
          new(
            key: 'line_music_tracks',
            model_class_name: 'LineMusicTrack',
            index_attributes: %i[name circle_name album_id track_id line_music_album_id disc_number track_number line_music_id],
            form_attributes: %i[album_id track_id line_music_album_id line_music_id name url disc_number track_number payload],
            search_attributes: %i[name line_music_id],
            filter_definitions: [touhou_filter.call],
            includes: [
              { album: album_preview_includes },
              :line_music_album,
              { track: track_preview_includes }
            ],
            action_class_names: %w[FetchLineMusicTrack UpdateLineMusicTrack]
          ),
          new(
            key: 'ytmusic_albums',
            model_class_name: 'YtmusicAlbum',
            index_attributes: %i[name circle_name album_id release_year tracks_status total_tracks browse_id],
            form_attributes: %i[album_id browse_id name url playlist_url release_year total_tracks payload],
            search_attributes: %i[name browse_id],
            filter_definitions: [track_status_filter.call(:ytmusic_tracks), touhou_filter.call],
            includes: [:ytmusic_tracks, { album: album_preview_includes }],
            action_class_names: %w[
              FetchYtmusicAlbum
              ProcessYtmusicJanToAlbumBrowseIds
              UpdateYtmusicAlbumTrack
              UpdateYtmusicAlbumPayload
              UpdateAllYtmusicAlbumPayloads
            ]
          ),
          new(
            key: 'ytmusic_tracks',
            model_class_name: 'YtmusicTrack',
            index_attributes: %i[name circle_name album_id track_id ytmusic_album_id track_number video_id playlist_id],
            form_attributes: %i[album_id track_id ytmusic_album_id video_id playlist_id name url track_number payload],
            search_attributes: %i[name video_id playlist_id],
            filter_definitions: [touhou_filter.call],
            includes: [
              { album: album_preview_includes },
              :ytmusic_album,
              { track: track_preview_includes }
            ],
            action_class_names: %w[FetchYtmusicTrack]
          ),
          new(
            key: 'spotify_playlists',
            model_class_name: 'SpotifyPlaylist',
            index_attributes: %i[name spotify_id spotify_user_id original_song_code total followers position synced_at],
            form_attributes: %i[spotify_id spotify_user_id name total followers spotify_url original_song_code synced_at position],
            search_attributes: %i[name spotify_id spotify_user_id original_song_code]
          )
        ]
      end
    end

    def model_class
      model_class_name.constantize
    end

    def singular_key
      key.singularize
    end

    def label
      I18n.t("admin.resources.#{key}.label")
    end

    def description
      I18n.t("admin.resources.#{key}.description")
    end

    def actions
      Array(action_class_names).map { |class_name| Admin::Action.new(resource: self, action_class_name: class_name) }
    end

    def action_for!(key)
      actions.find { |action| action.key == key.to_s } || raise(ActiveRecord::RecordNotFound, "Unknown admin action: #{key}")
    end

    def apply_to(scope)
      scoped = includes.present? ? scope.includes(*includes) : scope
      default_order.present? ? default_order.call(scoped) : scoped
    end

    def search(scope, query)
      return scope if query.blank? || search_attributes.blank?

      pattern = "%#{model_class.sanitize_sql_like(query)}%"
      conditions = search_attributes.index_with { pattern }
      scope.where(search_where_clause, conditions)
    end

    def filter(scope, params)
      normalize_filters(params).reduce(scope) do |filtered_scope, (key, value)|
        filter_definition_for(key).fetch(:apply).call(filtered_scope, value)
      end
    end

    def normalize_filters(params)
      values = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h

      filters.to_h do |filter|
        value = values.fetch(filter[:attribute], filter[:default]).to_s.strip
        [filter[:attribute], value]
      end.select { |_attribute, value| value.present? }
    end

    def filters
      Array(filter_definitions).map do |definition|
        {
          attribute: definition.fetch(:key).to_s,
          label: I18n.t(definition.fetch(:label_key)),
          options: definition.fetch(:options),
          include_blank: definition.fetch(:include_blank, false),
          default: definition[:default].to_s
        }
      end
    end

    def non_default_filters?(params)
      normalize_filters(params).any? do |key, value|
        value != filter_definition_for(key)[:default].to_s
      end
    end

    def attributes_for_form
      form_attributes.map(&:to_s)
    end

    def attributes_for_detail
      Array(detail_attributes.presence || model_class.columns.map(&:name)).map(&:to_s)
    end

    def index_attribute_label(attribute)
      override = INDEX_ATTRIBUTE_LABEL_OVERRIDES[attribute.to_s]
      return attribute_label(override) if override

      attribute_label(attribute)
    end

    def detail_attribute_label(attribute)
      index_attribute_label(attribute)
    end

    def attribute_label(attribute)
      I18n.t(
        "admin.attributes.#{model_class.model_name.i18n_key}.#{attribute}",
        default: I18n.t("admin.attributes.common.#{attribute}", default: attribute.to_s.humanize)
      )
    end

    def json_attribute?(attribute)
      column_for(attribute)&.type.in?(%i[json jsonb])
    end

    def column_for(attribute)
      model_class.columns_hash[attribute.to_s]
    end

    def value_for(record, attribute)
      return nil unless record.respond_to?(attribute)

      record.public_send(attribute)
    end

    private

    def filter_definition_for(key)
      Array(filter_definitions).find { |definition| definition.fetch(:key).to_s == key.to_s } || raise(ArgumentError, "Unknown filter: #{key}")
    end

    def search_where_clause
      search_attributes
        .map { |attribute| "CAST(#{quoted_table_name}.#{model_class.connection.quote_column_name(attribute)} AS TEXT) ILIKE :#{attribute}" }
        .join(' OR ')
    end

    def quoted_table_name
      model_class.connection.quote_table_name(model_class.table_name)
    end
  end
end
