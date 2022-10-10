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
       label: '東方アルバム総数',
       options: {
         is_touhou: true
       }
  card TracksCount
  card TracksCount,
       label: '東方トラック総曲数',
       options: {
         is_touhou: true
       }

  divider label: 'Spotify'
  card SpotifyAlbumsCount
  card SpotifyAlbumsCount,
       label: 'Spotify 東方アルバム総数',
       options: {
         is_touhou: true
       }
  card SpotifyTracksCount
  card SpotifyTracksCount,
       label: 'Spotify 東方トラック総曲数',
       options: {
         is_touhou: true
       }

  divider label: 'AppleMusic'
  card AppleMusicAlbumsCount
  card AppleMusicAlbumsCount,
       label: 'AppleMusic 東方アルバム総数',
       options: {
         is_touhou: true
       }
  card AppleMusicTracksCount
  card AppleMusicTracksCount,
       label: 'AppleMusic 東方トラック総曲数',
       options: {
         is_touhou: true
       }

  divider label: 'YouTube Music'
  card YtmusicAlbumsCount
  card YtmusicAlbumsCount,
       label: 'YouTube Music 東方アルバム総数',
       options: {
         is_touhou: true
       }
  card YtmusicTracksCount
  card YtmusicTracksCount,
       label: 'YouTube Music 東方トラック総曲数',
       options: {
         is_touhou: true
       }

  divider label: 'LINE MUSIC'
  card LineMusicAlbumsCount
  card LineMusicAlbumsCount,
       label: 'LINE MUSIC 東方アルバム総数',
       options: {
         is_touhou: true
       }
  card LineMusicTracksCount
  card LineMusicTracksCount,
       label: 'LINE MUSIC 東方トラック総曲数',
       options: {
         is_touhou: true
       }
end
