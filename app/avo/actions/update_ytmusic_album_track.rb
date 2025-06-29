# frozen_string_literal: true

class UpdateYtmusicAlbumTrack < Avo::BaseAction
  self.name = 'YouTube Music アルバム・トラックを更新'
  self.standalone = true
  self.visible = -> { view == :index }

  def handle(_args)
    YtmusicAlbum.find_each do |ytmusic_album|
      album = YtMusic::Album.find(ytmusic_album.browse_id)
      url = "https://music.youtube.com/browse/#{ytmusic_album.browse_id}"
      ytmusic_album.update_album(album, url) if album

      tracks = ytmusic_album.payload['tracks']
      ytmusic_album.ytmusic_tracks.each do |ytm_track|
        track = tracks.find { _1['track_number'] == ytm_track.track_number }
        ytm_track.update_track(track) if track
      end
    end

    succeed 'Done!'
    reload
  end
end
