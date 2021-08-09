# frozen_string_literal: true

class User < ApplicationRecord
  def self.find_or_create_from_auth_hash(auth_hash)
    provider = auth_hash[:provider]
    uid = auth_hash[:uid]
    nickname = auth_hash[:info][:display_name]
    name = auth_hash[:info][:id]
    email = auth_hash[:info][:email]
    image_url = auth_hash[:info][:images][0][:url]
    find_or_create_by!(provider: provider, uid: uid) do |user|
      user.nickname = nickname
      user.name = name
      user.email = email
      user.image_url = image_url
    end
  end
end
