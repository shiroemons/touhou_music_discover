# frozen_string_literal: true

class MyDashboard < Avo::Dashboards::BaseDashboard
  self.id = 'my_dashboard'
  self.name = 'Dashboard'
  # self.description = "Tiny dashboard description"
  self.grid_cols = 4
  # self.visible = -> do
  #   true
  # end

  card AlbumsCount
  card AlbumsCount,
       label: 'Touhou album count',
       options: {
         is_touhou: true
       }
  card TracksCount
  card TracksCount,
       label: 'Touhou track count',
       options: {
         is_touhou: true
       }

  divider label: 'Spotify'
  card SpotifyAlbumsCount
  card SpotifyAlbumsCount,
       label: 'Spotify touhou album count',
       options: {
         is_touhou: true
       }
  card SpotifyTracksCount
  card SpotifyTracksCount,
       label: 'Spotify touhou track count',
       options: {
         is_touhou: true
       }

  divider label: 'AppleMusic'
  card AppleMusicAlbumsCount
  card AppleMusicAlbumsCount,
       label: 'AppleMusic touhou album count',
       options: {
         is_touhou: true
       }
  card AppleMusicTracksCount
  card AppleMusicTracksCount,
       label: 'AppleMusic touhou track count',
       options: {
         is_touhou: true
       }

  divider label: 'YouTube Music'
  card YtmusicAlbumsCount
  card YtmusicAlbumsCount,
       label: 'YouTube Music touhou album count',
       options: {
         is_touhou: true
       }
  card YtmusicTracksCount
  card YtmusicTracksCount,
       label: 'YouTube Music touhou track count',
       options: {
         is_touhou: true
       }

  divider label: 'LINE MUSIC'
  card LineMusicAlbumsCount
  card LineMusicAlbumsCount,
       label: 'LINE MUSIC touhou album count',
       options: {
         is_touhou: true
       }
  card LineMusicTracksCount
  card LineMusicTracksCount,
       label: 'LINE MUSIC touhou track count',
       options: {
         is_touhou: true
       }
end
