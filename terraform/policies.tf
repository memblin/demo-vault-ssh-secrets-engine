/*
    Certificates requested with this policy applied will be able to
    request the "tkcadmin" or "root" principals during signing.
*/
resource "vault_policy" "ssh_client_role_admin" {
  name = "ssh_client_role_admin"

  policy = <<EOT
path "ssh-client-signer/sign/admin" {
  capabilities = ["create", "update"]
  allowed_parameters = {
    "public_key"       = []
    "ttl"              = []
    "valid_principals" = ["tkcadmin","root"]
  }
}
EOT
}

/*
    Certificates requested with this policy applied will only be able to
    request the "tkcadmin" principal. It also denies access to the
    "extensions" and "critical_options" parameters, which can be used to
    request additional permissions on the signed certificate.
    
    This is a more restrictive policy compared to "ssh_client_role_admin".
*/
resource "vault_policy" "ssh_client_role_admin_restricted" {
  name = "ssh_client_role_admin_restricted"

  policy = <<EOT
path "ssh-client-signer/sign/admin" {
  capabilities = ["create", "update"]

  allowed_parameters = {
    "public_key"       = []
    "ttl"              = []
    "valid_principals" = ["tkcadmin"]
  }

  # Optionally block dangerous overrides
  denied_parameters = {
    "extensions"        = []
    "critical_options"  = []
  }
}
EOT
}

/*
   This policy is wide open and allows signing by any role,
   on the ssh-client-signer CA. It is not recommended for production use,
   but can be useful for testing.
*/
resource "vault_policy" "ssh_client_role_all" {
  name = "ssh_client_role_all"

  policy = <<EOT
path "ssh-client-signer/sign/*" {
  capabilities = ["create", "update"]
}
EOT
}

/*
    This policy allows signing of host keys with the "host" role on the
    ssh-host-signer CA
*/
resource "vault_policy" "ssh_host_role_admin" {
  name = "ssh_host_role_admin"

  policy = <<EOT
path "ssh-host-signer/sign/host" {
  capabilities = ["create", "update"]
}
EOT
}
