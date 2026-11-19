{
  # nixpkgs にまだ入っていない Ruby のパッチ版を devbox で使うための flake。
  # nixpkgs の ruby_4_0 と同じビルド定義（mkRuby）に、公式の tarball とハッシュだけを差し替える。
  # nixpkgs 側が追いついたら、devbox.json の ruby をコミット指定か nixhub の版指定に戻し、
  # このディレクトリを削除する。
  description = "Ruby 4.0.10 built with nixpkgs' mkRuby";

  inputs = {
    # devbox.json で Ruby に使っていたものと同じコミット。ビルドに使う依存（rustc など）が
    # バイナリキャッシュに揃っているため、ビルドするのは Ruby 本体だけで済む
    nixpkgs.url = "github:NixOS/nixpkgs/5d2b81a7a3be3e2f832879028e4d60abbf58e9a0";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.mkRuby {
          version = pkgs.mkRubyVersion "4" "0" "10" "";
          # https://www.ruby-lang.org/en/news/2026/11/18/ruby-4-0-10-released/ の
          # ruby-4.0.10.tar.gz の SHA256（b53eef33...ed9f1）を SRI 形式にしたもの
          hash = "sha256-tT7vM3H6XT47dDQO3NAV8G1diFOWjU5TmlJk/OQe2fE=";
          # YJIT の Cargo 依存は 4.0.9 から変わっていない
          cargoHash = "sha256-z7NwWc4TaR042hNx0xgRkh/BQEpEJtE53cfrN0qNiE0=";
        };
      });
    };
}
