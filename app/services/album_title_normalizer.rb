# frozen_string_literal: true

class AlbumTitleNormalizer
  JAPANESE_CHARACTER_PATTERN = /[ぁ-ゖァ-ヺ一-龯々〆〇ヶ]/

  class << self
    def normalize(value)
      normalized = value.to_s.unicode_normalize(:nfkc)
      normalized = normalized.gsub(/\p{Z}+/, ' ').gsub(/\s+/, ' ').strip
      normalized.presence
    end

    def japanese?(value)
      japanese_core(value).to_s.match?(JAPANESE_CHARACTER_PATTERN)
    end

    private

    def japanese_core(value)
      normalized = normalize(value)
      return if normalized.blank?

      normalized = normalized.sub(/\s+(?:feat\.?|ft\.?|with)\s+.+\z/i, '')
      normalized.sub(
        /\s*[（(［\[]\s*(?:feat\.?|ft\.?|with|remix|version|ver\.?|instrumental|inst\.?|cover|original|edit|mix)\b.*\z/i,
        ''
      ).strip
    end
  end
end
