resource "aws_ecr_repository" "backend" {
  name         = "${local.name_prefix}-backend"
  force_delete = true # チュートリアル用。destroy 時にイメージごと削除する

  # IMMUTABLE: 既存タグの上書き push を禁止する。
  # digest への新規タグ追加 (crane tag による GA 昇格) は可能。
  # 「一度公開したタグは動かさない」規約をレジストリ側でも強制する。
  image_tag_mutability = "IMMUTABLE"
}
