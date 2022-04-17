# frozen_string_literal: true

require 'amatch'

class Similar
  attr_reader :src, :dest, :levenshtein_similar, :damerau_levenshtein_similar,
              :pair_distance_similar, :longest_subsequence_similar,
              :jaro_similar, :jarowinkler_similar

  def initialize(src, dest)
    return unless src.is_a?(String) && dest.is_a?(String)

    @src = src
    @dest = dest
    @levenshtein_similar = src.levenshtein_similar(dest)
    @damerau_levenshtein_similar = src.damerau_levenshtein_similar(dest)
    @pair_distance_similar = src.pair_distance_similar(dest)
    @longest_subsequence_similar = src.longest_subsequence_similar(dest)
    @jaro_similar = src.jaro_similar(dest)
    @jarowinkler_similar = src.jarowinkler_similar(dest)
  end

  def average
    similars = [
      @levenshtein_similar,
      @damerau_levenshtein_similar,
      @pair_distance_similar,
      @longest_subsequence_similar,
      @jaro_similar,
      @jarowinkler_similar
    ]
    similars.sum.fdiv(similars.length)
  end
end
