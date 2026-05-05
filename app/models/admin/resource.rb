# frozen_string_literal: true

module Admin
  class Resource
    include ActiveModel::Model

    DEFAULT_ITEMS = 50

    attr_accessor :key, :model_class_name, :index_attributes, :form_attributes,
                  :search_attributes, :includes, :action_class_names

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

      private

      def build_resources
        album_preview_includes = %i[circles spotify_album apple_music_album ytmusic_album line_music_album]
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
            index_attributes: %i[spotify_album_name apple_music_album_name circle_name jan_code is_touhou],
            form_attributes: %i[jan_code is_touhou],
            search_attributes: %i[jan_code],
            includes: album_preview_includes,
            action_class_names: %w[BulkRetrieval ChangeTouhouFlag SetCircles]
          ),
          new(
            key: 'tracks',
            model_class_name: 'Track',
            index_attributes: %i[name album_name circle_name jan_code isrc is_touhou original_songs_count],
            form_attributes: %i[jan_code isrc is_touhou],
            search_attributes: %i[jan_code isrc],
            includes: track_preview_includes,
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
            index_attributes: %i[name circle_name album_id active release_date total_tracks spotify_id],
            form_attributes: %i[album_id spotify_id album_type name label url release_date total_tracks active payload],
            search_attributes: %i[name spotify_id label],
            includes: [{ album: album_preview_includes }],
            action_class_names: %w[FetchSpotifyAlbum FetchMissingSpotifyAlbumByAppleMusicJan UpdateSpotifyAlbum]
          ),
          new(
            key: 'spotify_tracks',
            model_class_name: 'SpotifyTrack',
            index_attributes: %i[name circle_name album_id track_id spotify_album_id disc_number track_number spotify_id],
            form_attributes: %i[album_id track_id spotify_album_id spotify_id name label url release_date disc_number track_number duration_ms payload],
            search_attributes: %i[name spotify_id label],
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
            index_attributes: %i[name circle_name album_id release_date total_tracks apple_music_id],
            form_attributes: %i[album_id apple_music_id name label url release_date total_tracks payload],
            search_attributes: %i[name apple_music_id label],
            includes: [{ album: album_preview_includes }],
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
            index_attributes: %i[name circle_name album_id release_date total_tracks line_music_id],
            form_attributes: %i[album_id line_music_id name url release_date total_tracks payload],
            search_attributes: %i[name line_music_id],
            includes: [{ album: album_preview_includes }],
            action_class_names: %w[FetchLineMusicAlbum UpdateLineMusicAlbum ProcessLineMusicJanToAlbumIds]
          ),
          new(
            key: 'line_music_tracks',
            model_class_name: 'LineMusicTrack',
            index_attributes: %i[name circle_name album_id track_id line_music_album_id disc_number track_number line_music_id],
            form_attributes: %i[album_id track_id line_music_album_id line_music_id name url disc_number track_number payload],
            search_attributes: %i[name line_music_id],
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
            index_attributes: %i[name circle_name album_id release_year total_tracks browse_id],
            form_attributes: %i[album_id browse_id name url playlist_url release_year total_tracks payload],
            search_attributes: %i[name browse_id],
            includes: [{ album: album_preview_includes }],
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
      includes.present? ? scope.includes(*includes) : scope
    end

    def search(scope, query)
      return scope if query.blank? || search_attributes.blank?

      pattern = "%#{model_class.sanitize_sql_like(query)}%"
      conditions = search_attributes.index_with { pattern }
      scope.where(search_where_clause, conditions)
    end

    def attributes_for_form
      form_attributes.map(&:to_s)
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
