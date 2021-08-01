# frozen_string_literal: true

class SpotifyAlbum < ApplicationRecord
  has_many :spotify_tracks,
           -> { order(Arel.sql('spotify_tracks.track_number ASC')) },
           inverse_of: :spotify_album,
           dependent: :destroy

  belongs_to :album

  delegate :jan_code, :is_touhou, to: :album, allow_nil: true

  scope :is_touhou, -> { eager_load(:album).where(albums: { is_touhou: true }) }
  scope :non_touhou, -> { eager_load(:album).where(albums: { is_touhou: false }) }
  scope :spotify_id, ->(spotify_id) { find_by(spotify_id: spotify_id) }
end
