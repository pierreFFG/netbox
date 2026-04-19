data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

check "aws_account_target_validation" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == var.account_id
    error_message = "Le compte AWS courant (${data.aws_caller_identity.current.account_id}) ne correspond pas à var.account_id (${var.account_id}). Utiliser le profil TestNetbox."
  }
}
