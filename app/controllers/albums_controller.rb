# frozen_string_literal: true

class AlbumsController < ApplicationController
  include Pagy::Method

  def index
    @pagy, @records = pagy(:offset, Album.includes(:circles, :spotify_album, :apple_music_album, :ytmusic_album, :line_music_album).order(:jan_code), limit: 100)
  end
end
