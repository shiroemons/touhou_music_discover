import 'settings.just'

# Rubocopを実行（just lint）
[default]
run:
    devbox run rubocop

# Rubocop自動修正を実行
fix:
    devbox run rubocop:fix

# Rubocop自動修正（全て）を実行
fix-all:
    devbox run rubocop:fix:all
