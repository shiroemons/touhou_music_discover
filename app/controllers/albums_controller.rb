# frozen_string_literal: true

class AlbumsController < ApplicationController
  include Pagy::Backend
  def index
    @pagy, @records = pagy(Album.includes(:circles, :spotify_album, :apple_music_album, :ytmusic_album, :line_music_album).order(:jan_code), items: 100)
  end
end
