# frozen_string_literal: true

module Admin
  ActionUploadedFile = Data.define(:path, :content_type, :original_filename)
end
