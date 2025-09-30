# frozen_string_literal: true

require 'csv'

puts '=' * 80
puts '原作・原曲データのUpsert開始'
puts '=' * 80

# Originals (原作)
puts "\n【原作データの処理】"
now = Time.zone.now
originals_data = CSV.table('db/fixtures/originals.tsv', col_sep: "\t", converters: nil).map do |o|
  {
    code: o[:code],
    title: o[:title],
    short_title: o[:short_title],
    original_type: o[:original_type],
    series_order: o[:series_order],
    created_at: now,
    updated_at: now
  }
end

before_count = Original.count
Original.upsert_all(originals_data, unique_by: :code) # rubocop:disable Rails/SkipsModelValidations
after_count = Original.count
puts "  処理前: #{before_count}件"
puts "  処理後: #{after_count}件"
puts "  追加: #{[after_count - before_count, 0].max}件"
puts "  TSVファイルの総件数: #{originals_data.size}件"

# Original Songs (原曲)
puts "\n【原曲データの処理】"
original_songs_data = CSV.table('db/fixtures/original_songs.tsv', col_sep: "\t", converters: nil).map do |os|
  {
    code: os[:code],
    original_code: os[:original_code],
    title: os[:title],
    composer: os[:composer].to_s,
    track_number: os[:track_number].to_i,
    is_duplicate: os[:is_duplicate].to_s == '1',
    created_at: now,
    updated_at: now
  }
end

before_count = OriginalSong.count
OriginalSong.upsert_all(original_songs_data, unique_by: :code) # rubocop:disable Rails/SkipsModelValidations
after_count = OriginalSong.count
puts "  処理前: #{before_count}件"
puts "  処理後: #{after_count}件"
puts "  追加: #{[after_count - before_count, 0].max}件"
puts "  TSVファイルの総件数: #{original_songs_data.size}件"

puts "\n" + '=' * 80
puts '完了'
puts '=' * 80