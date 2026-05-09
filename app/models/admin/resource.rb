# frozen_string_literal: true

module Admin
  class Resource
    include ActiveModel::Model

    DEFAULT_ITEMS = 50
    INDEX_ATTRIBUTE_LABEL_OVERRIDES = {
      'album_id' => :jan_code,
      'track_id' => :track_reference,
      'spotify_track_id' => :spotify_track_reference,
      'spotify_album_id' => :spotify_album_reference,
      'apple_music_album_id' => :apple_music_album_reference,
      'line_music_album_id' => :line_music_album_reference,
      'ytmusic_album_id' => :ytmusic_album_reference
    }.freeze

    attr_accessor :key, :model_class_name, :index_attributes, :detail_attributes, :form_attributes,
                  :search_attributes, :search_scope, :filter_definitions, :includes, :hidden_relations,
                  :default_order, :action_class_names

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

      def spotify_track_audio_feature_order(scope)
        scope
          .left_joins(:track, :spotify_track)
          .reorder(
            Arel.sql("#{Track.quoted_table_name}.#{Track.connection.quote_column_name(:jan_code)} DESC"),
            Arel.sql("#{SpotifyTrack.quoted_table_name}.#{SpotifyTrack.connection.quote_column_name(:disc_number)} ASC NULLS LAST"),
            Arel.sql("#{SpotifyTrack.quoted_table_name}.#{SpotifyTrack.connection.quote_column_name(:track_number)} ASC NULLS LAST"),
            Arel.sql("#{SpotifyTrackAudioFeature.quoted_table_name}.#{SpotifyTrackAudioFeature.connection.quote_column_name(:spotify_id)} ASC")
          )
      end

      def spotify_track_audio_feature_search(scope, query)
        pattern = "%#{SpotifyTrackAudioFeature.sanitize_sql_like(query)}%"

        scope
          .left_joins(:track, spotify_track: :spotify_album)
          .where(
            <<~SQL.squish,
              #{SpotifyTrackAudioFeature.quoted_table_name}.#{SpotifyTrackAudioFeature.connection.quote_column_name(:spotify_id)} ILIKE :query OR
              #{SpotifyTrackAudioFeature.quoted_table_name}.#{SpotifyTrackAudioFeature.connection.quote_column_name(:analysis_url)} ILIKE :query OR
              #{Track.quoted_table_name}.#{Track.connection.quote_column_name(:isrc)} ILIKE :query OR
              #{Track.quoted_table_name}.#{Track.connection.quote_column_name(:jan_code)} ILIKE :query OR
              #{SpotifyTrack.quoted_table_name}.#{SpotifyTrack.connection.quote_column_name(:name)} ILIKE :query OR
              #{SpotifyAlbum.quoted_table_name}.#{SpotifyAlbum.connection.quote_column_name(:name)} ILIKE :query
            SQL
            query: pattern
          )
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
              %w[true 東方のみ],
              %w[false 東方以外]
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
              %w[missing 楽曲なし],
              %w[incomplete 不足あり],
              %w[complete 取得済み]
            ],
            apply: lambda { |scope, value|
              Admin::Resource.streaming_album_track_status_scope(scope, association_name, value)
            }
          }
        }
        album_circle_filter = {
          key: 'circle_status',
          label_key: 'admin.filters.circle_status.label',
          include_blank: true,
          options: [
            %w[missing 未設定],
            %w[present 設定済み]
          ],
          apply: lambda { |scope, value|
            case value
            when 'missing'
              scope.missing_circles
            when 'present'
              scope.where.associated(:circles).distinct
            else
              scope
            end
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
            %w[none 0曲],
            %w[present 1曲以上],
            %w[multiple 2曲以上]
          ],
          apply: lambda { |scope, value|
            Admin::Resource.track_original_songs_count_scope(scope, value)
          }
        }
        track_catalog_type_filter = {
          key: 'catalog_type',
          label_key: 'admin.filters.catalog_type.label',
          include_blank: true,
          options: [
            %w[original_or_other オリジナル・その他],
            %w[touhou_arrangement 東方アレンジ]
          ],
          apply: lambda { |scope, value|
            case value
            when 'original_or_other'
              scope.original_or_other
            when 'touhou_arrangement'
              scope.touhou_arrangements
            else
              scope
            end
          }
        }
        audio_feature_profile_filter = {
          key: 'audio_feature_profile',
          label_key: 'admin.filters.audio_feature_profile.label',
          include_blank: true,
          options: [
            %w[high_energy 高エネルギー],
            %w[low_energy 低エネルギー],
            %w[danceable 踊りやすい],
            %w[positive 明るい],
            %w[melancholic 暗め],
            %w[acoustic アコースティック],
            %w[instrumental インスト寄り],
            %w[live ライブ感あり],
            %w[speechy 語り多め]
          ],
          apply: lambda { |scope, value|
            case value
            when 'high_energy'
              scope.where(energy: 0.7..)
            when 'low_energy'
              scope.where(energy: ..0.3)
            when 'danceable'
              scope.where(danceability: 0.7..)
            when 'positive'
              scope.where(valence: 0.7..)
            when 'melancholic'
              scope.where(valence: ..0.3)
            when 'acoustic'
              scope.where(acousticness: 0.7..)
            when 'instrumental'
              scope.where(instrumentalness: 0.5..)
            when 'live'
              scope.where(liveness: 0.8..)
            when 'speechy'
              scope.where(speechiness: 0.33..)
            else
              scope
            end
          }
        }
        audio_tempo_filter = {
          key: 'audio_tempo',
          label_key: 'admin.filters.audio_tempo.label',
          include_blank: true,
          options: [
            ['slow', 'ゆったり（90 BPM未満）'],
            ['medium', '標準（90-139 BPM）'],
            ['fast', '速い（140 BPM以上）']
          ],
          apply: lambda { |scope, value|
            case value
            when 'slow'
              scope.where(tempo: ...90)
            when 'medium'
              scope.where(tempo: 90...140)
            when 'fast'
              scope.where(tempo: 140..)
            else
              scope
            end
          }
        }
        audio_mode_filter = {
          key: 'audio_mode',
          label_key: 'admin.filters.audio_mode.label',
          include_blank: true,
          options: [
            %w[major メジャー],
            %w[minor マイナー]
          ],
          apply: lambda { |scope, value|
            case value
            when 'major'
              scope.where(mode: 1)
            when 'minor'
              scope.where(mode: 0)
            else
              scope
            end
          }
        }
        audio_loudness_filter = {
          key: 'audio_loudness',
          label_key: 'admin.filters.audio_loudness.label',
          include_blank: true,
          options: [
            ['quiet', '静かめ（-20 dB未満）'],
            ['standard', '標準（-20〜-8 dB）'],
            ['loud', '大きめ（-8 dB以上）']
          ],
          apply: lambda { |scope, value|
            case value
            when 'quiet'
              scope.where(loudness: ...-20)
            when 'standard'
              scope.where(loudness: -20...-8)
            when 'loud'
              scope.where(loudness: -8..)
            else
              scope
            end
          }
        }
        audio_duration_filter = {
          key: 'audio_duration',
          label_key: 'admin.filters.audio_duration.label',
          include_blank: true,
          options: [
            ['short', '短い（2分未満）'],
            ['standard', '標準（2〜6分）'],
            ['long', '長い（6分以上）']
          ],
          apply: lambda { |scope, value|
            case value
            when 'short'
              scope.where(duration_ms: ...120_000)
            when 'standard'
              scope.where(duration_ms: 120_000...360_000)
            when 'long'
              scope.where(duration_ms: 360_000..)
            else
              scope
            end
          }
        }
        audio_time_signature_filter = {
          key: 'audio_time_signature',
          label_key: 'admin.filters.audio_time_signature.label',
          include_blank: true,
          options: [
            ['triple', '3拍子'],
            ['common', '4拍子'],
            ['irregular', '変拍子（5拍子以上）']
          ],
          apply: lambda { |scope, value|
            case value
            when 'triple'
              scope.where(time_signature: 3)
            when 'common'
              scope.where(time_signature: 4)
            when 'irregular'
              scope.where(time_signature: 5..)
            else
              scope
            end
          }
        }
        audio_data_quality_filter = {
          key: 'audio_data_quality',
          label_key: 'admin.filters.audio_data_quality.label',
          include_blank: true,
          options: [
            %w[missing_analysis_url 解析URLなし],
            %w[missing_payload ペイロードなし]
          ],
          apply: lambda { |scope, value|
            case value
            when 'missing_analysis_url'
              scope.where(analysis_url: [nil, ''])
            when 'missing_payload'
              scope.where(payload: nil)
            else
              scope
            end
          }
        }
        album_original_songs_filter = {
          key: 'tracks_original_songs',
          label_key: 'admin.filters.tracks_original_songs.label',
          include_blank: true,
          options: [
            %w[missing 未設定の楽曲あり]
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
              album_circle_filter,
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
            filter_definitions: [missing_streaming_track_filter, original_songs_count_filter, track_catalog_type_filter],
            includes: track_preview_includes,
            hidden_relations: %i[tracks_original_songs],
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
            search_attributes: %i[code original_code title composer],
            hidden_relations: %i[tracks_original_songs]
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
            action_class_names: %w[FetchMissingSpotifyTracks UpdateSpotifyTrack]
          ),
          new(
            key: 'spotify_track_audio_features',
            model_class_name: 'SpotifyTrackAudioFeature',
            index_attributes: %i[spotify_id track_id spotify_track_id tempo loudness energy danceability valence],
            form_attributes: %i[
              track_id spotify_track_id spotify_id acousticness analysis_url danceability duration_ms energy instrumentalness
              key liveness loudness mode speechiness tempo time_signature valence payload
            ],
            search_scope: ->(scope, query) { Admin::Resource.spotify_track_audio_feature_search(scope, query) },
            filter_definitions: [
              audio_feature_profile_filter,
              audio_tempo_filter,
              audio_mode_filter,
              audio_loudness_filter,
              audio_duration_filter,
              audio_time_signature_filter,
              audio_data_quality_filter
            ],
            includes: [
              { track: track_preview_includes },
              { spotify_track: [{ album: album_preview_includes }, :spotify_album, { track: track_preview_includes }] }
            ],
            default_order: ->(scope) { Admin::Resource.spotify_track_audio_feature_order(scope) },
            action_class_names: %w[FetchSpotifyAudioFeatures FetchMissingSpotifyAudioFeatures]
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
            action_class_names: %w[FetchAppleMusicTrack FetchMissingAppleMusicTracks FetchAppleMusicTrackByIsrc UpdateAppleMusicTrack]
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
            action_class_names: %w[FetchLineMusicTrack FetchMissingLineMusicTracks UpdateLineMusicTrack]
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
            action_class_names: %w[FetchYtmusicTrack FetchMissingYtmusicTracks]
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
      return scope if query.blank?
      return search_scope.call(scope, query) if search_scope.present?
      return scope if search_attributes.blank?

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

      normalized_filters = filters.to_h do |filter|
        value = values.fetch(filter[:attribute], filter[:default]).to_s.strip
        [filter[:attribute], value]
      end
      normalized_filters.compact_blank
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

    def hidden_relation?(name)
      name.to_sym.in?(Array(hidden_relations))
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
