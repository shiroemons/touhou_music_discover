# frozen_string_literal: true

class User < ApplicationRecord
  # OmniAuth の auth_hash から User を作成または更新する。
  #
  # Spotify のプロフィールは画像が 0 件だったり email が返らないことがあるため、
  # すべて nil ガードを通す(users.email / users.image_url は null: false default '')。
  # 属性の代入を find_or_create_by! のブロックの外に出しているのは、ブロックが
  # 新規作成時にしか実行されず、既存ユーザーの表示名や画像が永久に更新されな
  # かったため。
  def self.find_or_create_from_auth_hash(auth_hash)
    info = auth_hash[:info] || {}

    user = find_or_initialize_by(provider: auth_hash[:provider], uid: auth_hash[:uid])
    user.name = info[:id].to_s
    user.nickname = info[:display_name].presence || info[:id].to_s
    user.email = info[:email].to_s
    image = Array(info[:images]).first
    user.image_url = (image.is_a?(Hash) ? (image[:url] || image['url']) : nil).to_s
    user.save!
    user
  end
end
