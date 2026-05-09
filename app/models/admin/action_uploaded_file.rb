# frozen_string_literal: true

module Admin
  ACTION_UPLOADED_FILE_MARKER = '_admin_action_uploaded_file'

  ActionUploadedFile = Data.define(:path, :content_type, :original_filename) do
    def self.from_h(attributes)
      new(
        path: attributes.fetch('path'),
        content_type: attributes.fetch('content_type'),
        original_filename: attributes.fetch('original_filename')
      )
    end

    def as_job_argument
      {
        ACTION_UPLOADED_FILE_MARKER => true,
        'path' => path,
        'content_type' => content_type,
        'original_filename' => original_filename
      }
    end
  end
end
