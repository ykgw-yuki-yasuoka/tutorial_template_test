terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.x が必要。lambda.tf の invoked_via_function_url は 5.x に存在しない。
      version = "~> 6.0"
    }
  }
  # チュートリアル用途のためローカル state。実務では S3 backend を使うこと。
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = var.project_name
      # 名前でリソースを絞れないサービス (CloudFront) を、最小権限ポリシーが
      # aws:ResourceTag / aws:RequestTag で絞るために使う。値を変えると
      # docs/assets/setup-policy.template.json から生成したポリシーと食い違い、
      # apply が AccessDenied になる。
      Owner     = var.owner
      ManagedBy = "terraform"
      Purpose   = "git-workflow-tutorial"
    }
  }

  # 組織のタグポリシーが自動付与するガバナンスタグ。設定には書かないため、
  # 放っておくと Terraform が毎回「設定に無い = 削除」と判断し、組織側が再付与し、
  # plan が永久に汚れ続ける (かつタグガバナンスにも反する)。管理対象外として無視する。
  # 自前の AWS アカウントではこれらのタグは付かないので、指定しても実害はない。
  ignore_tags {
    keys = [
      "App",
      "Application",
      "Company",
      "CostCenter",
      "Department",
      "Division",
      "Environment",
      "IntraConnected",
      "PrimaryOwner",
      "SecondaryOwner",
      "System",
      "UsageScope",
    ]
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  environments = toset(["dev", "staging", "production"])

  # 全リソース名の共通プレフィックス。1 つの AWS アカウントを複数人で共有しても
  # owner が違えば名前空間が分かれ、最小権限ポリシーがこのプレフィックスで
  # 「自分のリソースだけ」に許可を絞れる (docs/00-setup.md の「必要な権限」)。
  name_prefix = "${var.project_name}-${var.owner}"
}
