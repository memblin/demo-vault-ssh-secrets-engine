/* Client or User Key Signing CA */

/*
  This resource enables a new secrets engine of type ssh at ssh-client-signer
  path.
*/
resource "vault_mount" "ssh_client_signer" {
  path        = "ssh-client-signer"
  type        = "ssh"
  description = "Sign public keys for SSH client authentication."
}

/*
  This resource defines the CA information for the SSH secret
  backend. It generates a signing key of the specified type.
*/
resource "vault_ssh_secret_backend_ca" "client" {
  backend              = vault_mount.ssh_client_signer.path
  generate_signing_key = true
  key_type             = "ed25519"
}

/*
  This resource defines a role named "admin" for the SSH secret
  backend. It specifies various parameters for signing client keys,
  such as allowed domains, extensions, and key configurations.
*/
resource "vault_ssh_secret_backend_role" "admin" {
  name                    = "admin"
  backend                 = vault_mount.ssh_client_signer.path
  key_type                = "ca"
  allow_bare_domains      = true
  allow_host_certificates = false
  allow_subdomains        = true
  allow_user_certificates = true
  allow_user_key_ids      = true
  allowed_domains         = "local"
  allowed_extensions      = "permit-pty,permit-port-forwarding,permit-agent-forwarding"
  default_extensions     = { "permit-pty" = "" }
  allowed_users          = "*"
  max_ttl                = 86400 /* 1  Day     */
  ttl                    = 900 /* 15 Minutes */
  not_before_duration    = 30 /* 30 Seconds */
  allow_empty_principals = false

  allowed_user_key_config {
    type    = "ed25519"
    lengths = [0]
  }
  allowed_user_key_config {
    type    = "ssh-ed25519"
    lengths = [0]
  }
  allowed_user_key_config {
    type    = "rsa"
    lengths = [2048, 4096]
  }
  allowed_user_key_config {
    type    = "ssh-rsa"
    lengths = [2048, 4096]
  }
}

/* Host Key Signing CA Definition */

/*
  This resource enables a new secrets engine of type ssh at
  ssh-host-signer path.
*/
resource "vault_mount" "ssh_host_signer" {
  path        = "ssh-host-signer"
  type        = "ssh"
  description = "Signed SSH certificates for Host key signing."
}

/*
  This resource defines the CA information for the SSH secret
  backend. It generates a signing key of the specified type.
*/
resource "vault_ssh_secret_backend_ca" "host" {
  backend              = vault_mount.ssh_host_signer.path
  generate_signing_key = true
  key_type             = "ed25519"
}

/*
  This resource defines a role named "host" for the SSH secret
  backend. It specifies various parameters for signing host keys,
  such as allowed domains, extensions, and key configurations.
*/
resource "vault_ssh_secret_backend_role" "host" {
  name                    = "host"
  backend                 = vault_mount.ssh_host_signer.path
  key_type                = "ca"
  ttl                     = 31536000 /* 1  Year    */
  max_ttl                 = 315360000 /* 10 Years   */
  allow_host_certificates = true
  allowed_domains         = "local"
  allow_subdomains        = true
}

/*
  We also enabled the userpass backend for demo and testing purposes. This auth
  method is not directly related to SSH CA signed certificates but provides an
  additional way emulate logging in as a user for a specific policy that can
  then be used for key signing requests.
*/
resource "vault_auth_backend" "userpass" {
  type = "userpass"
}
