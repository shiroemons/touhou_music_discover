# frozen_string_literal: true

class Circle < ApplicationRecord
  has_many :circles_albums, dependent: :destroy
  has_many :albums, through: :circles_albums

  SPOTIFY_ARTIST_TO_CIRCLE = {
    'Astral Sky vs. 非可逆リズム' => ['Astral Sky', '非可逆リズム'],
    'C-CLAYS & K2 SOUND' => ['C-CLAYS', 'K2 SOUND'],
    'digital wing' => 'DiGiTAL WiNG',
    'Hachimitsu-Lemon × Aftergrow' => %w[はちみつれもん/Hachimitsu-Lemon Aftergrow],
    'Jerico' => 'ジェリコの法則',
    'KAI' => 'ぷろじぇくとかいにゃん',
    'LSDとactivity' => %w[LSD activity],
    'Lunatico_fEs(ヤヤネヒロコ)' => 'Lunatico_fEs',
    'Namaha' => 'CC姫工',
    'RoundLoudness with.タンタル' => 'RoundLoudness',
    'SOUND HOLIC Vs. Eurobeat Union' => ['SOUND HOLIC', 'Eurobeat Union'],
    'SWING HOLIC (from SOUND HOLIC)' => 'SWING HOLIC',
    't0m0h1r0' => 'Blackscreen',
    'UNDEAD CORPORATION DOUJIN WORKS' => 'UNDEAD CORPORATION',
    'はちみつれもん' => 'はちみつれもん/Hachimitsu-Lemon',
    'ねこみりん' => 'nekomimi style',
    'まりつみ' => 'maritumix',
    'オノ - axeempty' => '斧家',
    'オノ・コーヘイ' => '斧家',
    'ナオキ' => '渡り鳥のほとり',
    'パンマン' => 'アベニュールーム',
    '凋叶棕&ホシニセ' => %w[凋叶棕 ホシニセ],
    '天宮みや(少女フラクタル)' => '少女フラクタル',
    '天音' => 'Rolling Contact',
    '柚木梨沙(少女フラクタル)' => '少女フラクタル',
    '森羅万象 × COOL&CREATE × DiGiTAL WiNG' => ['森羅万象', 'COOL&CREATE', 'DiGiTAL WiNG'],
    '狐夢想屋×ゼッケン屋' => %w[狐夢想屋 ゼッケン屋],
    '白鳳(Ende der Welt)' => 'Ende der Welt'
  }.freeze

  JAN_TO_CIRCLE = {
    '4580547313864' => '少女フラクタル', # トロイメライ
    '4580547313901' => '少女フラクタル', # 言葉の裏側の約束
    '4580547315165' => "Wotamin's Room", # KUMI the BEST -Wotamin's Toho Arrange Selection-
    '4580547315783' => 'Blackscreen', # Parallels
    '4580547316063' => 'CrazyBeats', # 黒崎れおん東方ベスト 東方紅女物語
    '4580547316131' => 'CrazyBeats', # 加藤ありさ東方ベスト 東方魔猫娘伝
    '4580547316148' => 'CrazyBeats', # 花たん東方ベスト CrazyFlowerBEST
    '4580547316162' => 'CrazyBeats', # うさ東方ベスト 東方兎々歌抄
    '4580547319644' => '舞音KAGURA', # Edge
    '4580547322583' => 'れいんふぉれすと', # 暗闇の中で
    '4580547322590' => 'れいんふぉれすと', # 弦想郷
    '4580547331974' => 'Login Records', # We Are Gensou Bangers Vol.1
    '4580547333695' => 'COOL&CREATE', # 東方オトハナビ
    '4580547334814' => '東方LostWord', # 指先の熱 (feat.島みやえい子 & 幽閉サテライト)
    '4580547334821' => '東方LostWord', # NAЯAKA (feat.カグラナナ & SOUND HOLIC)
    '4580547334838' => '東方LostWord', # 白銀の風 (feat.相川七瀬 & 豚乙女)
    '4580547334845' => '東方LostWord', # 月と十六夜 (feat.ナノ & 岸田教団&THE明星ロケッツ)
    '4580547334852' => '東方LostWord', # 斑にマーガレット (feat. konoco & 森羅万象)
    '4580547334869' => '東方LostWord'  # サヨナラはどこか蒼い (feat.田原俊彦 & 豚乙女)
  }.freeze
end
