# frozen_string_literal: true

class AlbumResource < Avo::BaseResource
  self.title = :jan_code
  self.description = 'アルバム'
  self.includes = %i[circles
                     tracks
                     apple_music_album
                     apple_music_tracks
                     line_music_album
                     spotify_album
                     spotify_tracks
                     ytmusic_album
                     ytmusic_tracks]
  self.record_selector = false
  self.search_query = lambda {
    scope.ransack(jan_code_cont: params[:q], m: 'or').result(distinct: false)
  }

  field :id, as: :id, hide_on: [:index]
  field :jan_code, as: :text, sortable: true
  field :is_touhou, as: :boolean
  field :circle_name, as: :text, hide_on: [:forms]

  field :circles, as: :has_many, through: :circles_albums, searchable: true
  field :tracks, as: :has_many, searchable: true

  field :apple_music_album, as: :has_one, searchable: true
  field :apple_music_tracks, as: :has_many, searchable: true
  field :line_music_album, as: :has_one, searchable: true
  field :line_music_tracks, as: :has_many, searchable: true
  field :spotify_album, as: :has_one, searchable: true
  field :spotify_tracks, as: :has_many, searchable: true
  field :ytmusic_album, as: :has_one, searchable: true
  field :ytmusic_tracks, as: :has_many, searchable: true
end
