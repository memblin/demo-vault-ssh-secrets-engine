# Vault: SSH secrets engine

## Links to open

- The demo Repo
  https://github.com/memblin/demo-vault-ssh-secrets-engine.git

- The upstream documentation covering the Vault SSH secrets engine  
  https://developer.hashicorp.com/vault/docs/secrets/ssh  
  https://developer.hashicorp.com/vault/docs/secrets/ssh/signed-ssh-certificates

- Vault Terraform provider docs
  https://registry.terraform.io/providers/hashicorp/vault/latest/docs

- Vault Auth Methods: userpass
  https://developer.hashicorp.com/vault/docs/auth

## Intro

Greetings and hello!

Today I have a technical overview to share about how to use HashiCorp Vault
with its SSH secrets engine to issue signed SSH certificates for Linux system
authentication.

This tutorial builds on the foundational information from a prior demo
available on my channel named, "Introduction to SSH CA signed certificates for
authentication".

During this lab I will perform the following operations:

  - Configure Vault with 2 SSH CAs using Terraform
    - one CA for host key signing
    - one CA for user key signing.
  - Configure a target OpenSSH server to trust the user signing CA
  - Configure an OpenSSH client server to trust the host signing CA
  - Issue a signed SSH certificate and use it for authentication
    to the OpenSSH target server

We'll wrap-up the demo by exploring some Vault policy examples that can be
used to restrict the signing request parameters that a user can submit.

## Vault Configuration

First let's discuss the Vault configuration.

**SHOW Upstream Docs**:
https://developer.hashicorp.com/vault/docs/secrets/ssh/signed-ssh-certificates

When looking at the docs for the SSH secrets backend we see links for both
signed SSH certificates and One-time SSH passwords.

We'll be exploring the signed SSH certificates approach in this demo.

**Upstream WalkThrough**:

The Terraform module I use to configure Vault for this demo runs the same
operations we can see here as CLI operations.

I've included some small naming changes to help with context of each managed
resource.

### Walk through the Terraform Module

> [!WARNING]
> Vault "dev" mode servers are insecure and will lose data on every restart  
> (since it stores data in-memory).

I'll be using Vault in development mode to avoid having to deal with certain
aspects of securing Vault which are outside the scope of this lab.

The Terraform module for this configuration is available in the
[terraform](./terraform) sub-directory.

- Show `secrets enable` is `resource "vault_mount" "ssh_client_signer"`
- Show `vault write ssh-client-signer` is
  `resource "vault_ssh_secret_backend_ca" "client"`

## Demonstration and Exploration

Now let's put all this into action.

### Preface

I'm running this demonstration using three containers.

- `client.local` is our client machine
- `target.local` is our OpenSSH server target
- `vault.local`  is a Vault server container started in development mode

**SSL Oddities**

I've skipped SSL certificates on the Vault server to allow us to focus
almost completely on the SSH secrets backend in Vault.

This choice will manifest as environment variables and config flags to
ignore and override SSL validation protections.  This should NEVER be
done in production.

**Lab Machines**

When I first named the two lab machines I intended them to be specifically
used as client and SSH target but as the lab evolved I decided to go ahead
and configure both machines in the same way; as clients and hosts.

Don't let the configuration combined with the naming confuse you; they're
just lab machines.

While we're in AlmaLinux systemd containers this lab could just as well be
run on VMs and likely other distros that run OpenSSH with a few adjustments
for pathing, package, and utility names.

### Configure Vault with Terraform

In a separate terminal I'll configure Vault.

This is run from my laptop, the one running these containers.

The vault.local container publishes port 8200 so we should be
able to connect to Vault on http://localhost:8200 to apply the
configuration.

```bash
# Export the VAULT_SKIP_VERIFY to bypass TLS validation since we did not
# deploy with SSL configured on Vault
export VAULT_SKIP_VERIFY=1

# Export the Vault Address and Root token
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="RootToken"

# Check Vault Status
vault status

# Example Output
#
#  crow@laptop01:~$ vault status
#  Key             Value
#  ---             -----
#  Seal Type       shamir
#  Initialized     true
#  Sealed          false
#  Total Shares    1
#  Threshold       1
#  Version         1.21.4
#  Build Date      2026-03-04T17:40:05Z
#  Storage Type    inmem
#  Cluster Name    vault-cluster-249368e6
#  Cluster ID      70b3e29e-27d7-066b-1e41-46ef06f9ca4d
#  HA Enabled      false
```

Now that we have Vault connectivity we can init, plan,
and apply the code from demo repository.

If I haven't mentioned it already, this Terraform module is available in the
companion GitHub repository for this demo.

https://github.com/memblin/demo-vault-ssh-secrets-engine

```bash
# Clone the repo if the code isn't present
git clone https://github.com/memblin/demo-vault-ssh-secrets-engine.git

# Change directory into the terraform sub-directory
cd demo-vault-ssh-secrets-engine/terraform

# Initialize Terraform to download the modules
terraform init

# Terraform Plan
terraform plan -out=tfplan

# Terraform Apply
terraform apply tfplan
```

The terraform Plan and Apply should have created our SSH CA endpoints
in our Vault server as well as a few other resources.

Let's check our public keys; the public key is accessible via the API and
does not require authentication. We'll look at both keys here using `curl`
and the Vault CLI.

```bash
# Client signing CA via curl
curl --insecure http://localhost:8200/v1/ssh-client-signer/public_key

# Host signing CA via curl
curl --insecure http://localhost:8200/v1/ssh-host-signer/public_key

# Client signing CA via vault CLI
vault read -field=public_key ssh-client-signer/config/ca

# Host signing CA via vault CLI
vault read -field=public_key ssh-host-signer/config/ca
```

From our client and target containers we can use the `vault.local` hostname.

```bash
# Client signing CA
curl --insecure http://vault.local:8200/v1/ssh-client-signer/public_key

# Host Signing CA
curl --insecure http://vault.local:8200/v1/ssh-host-signer/public_key
```

Let's take a look at http://localhost:8200 Web GUI running on the container.

**SHOW Vault Server UI**

  - Look at User and Host SSH CAs
  - Look at SSH CA Roles
  - Look at Policies

Up until now we've been operating with the root token. That's ok for testing
but in our case we need additional user types to be able to mock the existence
of user entities that have access to SSH key signing through Vault.

To accomplish this we'll create a set of users in the `userpass` auth method
that our terraform code makes available.

```bash
# Add the Vault users we'll be using in the demo
#
# ssh_client_role_admin as admin-user
vault write auth/userpass/users/admin-user \
    password="AdminUser!" \
    policies="ssh_client_role_admin"

# ssh_client_role_admin_restricted as some-user
vault write auth/userpass/users/some-user \
    password="SomeUser!" \
    policies="ssh_client_role_admin_restricted"

# ssh_client_role_all as super-user
vault write auth/userpass/users/super-user \
    password="SuperUser!" \
    policies="ssh_client_role_all"

# ssh_host_role_admin as host-admin
vault write auth/userpass/users/host-admin \
    password="HostAdmin!" \
    policies="ssh_host_role_admin"
```

Many of other supported authentication methods exist.

**Show Vault Auth methods**
- https://developer.hashicorp.com/vault/docs/auth

Most, if not all, of these methods should be able to provide similar
authentication to policy mapping.

### Configure Client and Target to trust User signing CA

Now we'll configure our Client and Target machines to trust the User signing
CA.

We'll also disable password authentication here so that when we reach untrusted
evaluations we get an authentication denial rather than a prompt for a password.

```bash
# curl the CA public key into /etc/ssh/
curl --insecure -o /etc/ssh/trusted-ssh-ca-keys http://vault.local:8200/v1/ssh-client-signer/public_key

# Write the /etc/ssh/sshd_config.d/60-TrustedUserCAKeys.conf
cat <<EOF > /etc/ssh/sshd_config.d/60-TrustedUserCAKeys.conf
TrustedUserCAKeys /etc/ssh/trusted-ssh-ca-keys
PasswordAuthentication no
EOF

# Restart sshd to apply config extension
systemctl restart sshd
```

### Configure Client and Target to trust Host signing CA

Now we'll configure the client.local machine to trust the Host signing CA.

As both the `root` and `tkcadmin` user we'll generate user client key pairs
and configure trust for the Host key signing CA.

```bash
# Generate ed25519 host key forcing no passphrase
ssh-keygen -t ed25519 -C "$(whoami)@$(hostnamectl hostname)-$(date +%Y%m%d)" -f $HOME/.ssh/id_ed25519 -N ""

# curl the CA public key into ~/.ssh/known_hosts with appropriate format
echo "@cert-authority *.local $(curl -s --insecure http://vault.local:8200/v1/ssh-host-signer/public_key)" >> $HOME/.ssh/known_hosts
```

### Sign Our Host keys

Now we'll use the vault CLI command to sign the client and target Host keys
creating signed host certificates.

Then we'll configure sshd to serve the HostCertificate

```bash
# Sign into Vault as host-admin so certs are issued for/by
# the host-admin user instead of the root token id
unset VAULT_TOKEN
export VAULT_TOKEN="$(vault login -field=token -method=userpass username=host-admin)"

# Get a signed host certificate
vault write -field=signed_key ssh-host-signer/sign/host \
  cert_type=host \
  valid_principals="$(hostnamectl hostname)" \
  public_key=@/etc/ssh/ssh_host_ed25519_key.pub > /etc/ssh/ssh_host_ed25519_key-cert.pub

# Show the certificate contents
ssh-keygen -Lf /etc/ssh/ssh_host_ed25519_key-cert.pub

# Set ownership and permissions on the file
chown root:root /etc/ssh/ssh_host_ed25519_key-cert.pub && chmod 0640 /etc/ssh/ssh_host_ed25519_key-cert.pub

# Configure sshd to serve the new host certificate
cat <<EOF > /etc/ssh/sshd_config.d/60-HostCertificate.conf
HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub
EOF

# Restart sshd to apply config extension
systemctl restart sshd
```

### Sign some Client keys

Now that our clients are configured to trust the host signing CA and our
servers are configured to trust the client signing CA we can sign some
user public keys and authenticate with them.

#### Unrestricted Policy from client.local

First up will test a user with access to the `ssh_client_role_admin` policy.

```bash
# Become tkcadmin user
su - tkcadmin

# Export the Vault Address and Skip TLS verification
export VAULT_SKIP_VERIFY=1
export VAULT_ADDR="http://vault.local:8200"

# Login to Vault as admin-user and export the token to env
export VAULT_TOKEN="$(vault login -field=token -method=userpass username=admin-user)"

# Splash the token and policy info on the screen to take a look
vault token lookup

# Sign the current users default public key using the admin role
#
# The request asks to allow login with both root and tkcadmin and requests
# additional extensions.
#
# This should fail for the admin-user; the policy prevents requesting
# extension modifications to the default extensions provided by the admin role.
vault write -field=signed_key ssh-client-signer/sign/admin -<<EOH  > $HOME/.ssh/id_ed25519-cert.pub
{
  "public_key": "$(cat $HOME/.ssh/id_ed25519.pub)",
  "valid_principals": "root,tkcadmin",
  "extensions": {
    "permit-pty": "",
    "permit-port-forwarding": ""
  }
}
EOH

# We remove the extensions from our request
#
# The request still asks to allow login with both root and tkcadmin.
# This should succeed for the admin-user
vault write -field=signed_key ssh-client-signer/sign/admin -<<EOH  > $HOME/.ssh/id_ed25519-cert.pub
{
  "public_key": "$(cat $HOME/.ssh/id_ed25519.pub)",
  "valid_principals": "root,tkcadmin"
  }
}
EOH

# Show the certificate contents
ssh-keygen -Lf ~/.ssh/id_ed25519-cert.pub

# SSH with the certificate directly; can also be added to ~/.ssh/config
ssh -i $HOME/.ssh/id_ed25519 -i $HOME/.ssh/id_ed25519-cert.pub root@target.local

# Test authentication for target.local as root
ssh root@target.local

# Test authentication for target.local as tkcadmin
ssh tkcadmin@target.local
```

These signed keys work with the ssh-agent.

```bash
# SSH with certificate using ssh-agent
eval $(ssh-agent)

# Add our private key and it should add the associated certificate
ssh-add $HOME/.ssh/id_ed25519

# List the ssh-agent contents
ssh-add -l

# Connect
ssh root@target.local
```

One thing I've found in testing...

Before loading up new certs you'll want to dump the old ones or they'll stack
up and you'll start getting conflicting permissions.

As an example, I issued a certificate for both root and tkcadmin and loaded it.
Then after testing I requested another but just for tkcadmin and then loaded it.

But, I could still login as root because the first certificate was still present
in my agent and was still valid.

When iterating quickly, evict certificates you're done with from the ssh-agent
to avoid unexpected permissions evaluations.

```bash
# Dump ALL identities from ssh-agent
ssh-add -D

# Dump just the identity associated with the default public key
# This should leave other keys in the agent.
ssh-add -d $HOME/.ssh/id_ed25519
```

#### Restricted Policy from target.local

Next we'll test a user with access to the `ssh_client_role_admin_restricted` policy.

```bash
# Become tkcadmin user
su - tkcadmin

# Export the Vault Address and Skip TLS verification
export VAULT_SKIP_VERIFY=1
export VAULT_ADDR="http://vault.local:8200"

# Login to Vault as admin-user and export the token to env
export VAULT_TOKEN="$(vault login -field=token -method=userpass username=some-user)"

# Splash the token and policy info on the screen to take a look
vault token lookup

# Sign the current users default public key using the admin role
#
# The key asks to allow login with both root and tkcadmin; it should fail when
# requested by the some-user due to policy restrictions.
vault write -field=signed_key ssh-client-signer/sign/admin -<<EOH  > $HOME/.ssh/id_ed25519-cert.pub
{
  "public_key": "$(cat $HOME/.ssh/id_ed25519.pub)",
  "valid_principals": "root,tkcadmin"
  }
}
EOH

# Remove the "root" principal, just ask for tkcadmin
vault write -field=signed_key ssh-client-signer/sign/admin -<<EOH  > $HOME/.ssh/id_ed25519-cert.pub
{
  "public_key": "$(cat $HOME/.ssh/id_ed25519.pub)",
  "valid_principals": "tkcadmin"
  }
}
EOH

# Show the certificate contents
ssh-keygen -Lf ~/.ssh/id_ed25519-cert.pub

# Since we used default expected SSH key names we don't need flags
ssh root@client.local

# Test authentication for target.local as tkcadmin
ssh tkcadmin@client.local
```

#### Super-user Policy from client.local

Next we'll test a user with access to the `ssh_client_role_all` policy.

This policy is pretty much wide open for all roles on the CA.

```bash
# Become tkcadmin user
su - tkcadmin

# Export the Vault Address and Skip TLS verification
export VAULT_SKIP_VERIFY=1
export VAULT_ADDR="http://vault.local:8200"

# Login to Vault as admin-user and export the token to env
export VAULT_TOKEN="$(vault login -field=token -method=userpass username=super-user)"

# Splash the token and policy info on the screen to take a look
vault token lookup

# Sign the current users default public key using the admin role
#
# The request asks to allow login with both root and tkcadmin and requests
# additional extensions.
#
# This should succeed for the super-user
vault write -field=signed_key ssh-client-signer/sign/admin -<<EOH  > $HOME/.ssh/id_ed25519-cert.pub
{
  "public_key": "$(cat $HOME/.ssh/id_ed25519.pub)",
  "valid_principals": "root,tkcadmin",
  "extensions": {
    "permit-pty": "",
    "permit-port-forwarding": ""
  }
}
EOH

# Show the certificate contents
ssh-keygen -Lf ~/.ssh/id_ed25519-cert.pub

# Since we used default expected SSH key names we don't need flags
ssh root@target.local

# Test authentication for target.local as tkcadmin
ssh tkcadmin@target.local
```

### Discuss KRL and Vault

HashiCorp Vault doesn't appear to implement any kind of key revocation list or KRL
management.

In forums and other findings on this topic, the general feedback seems to be that
one should use policies to keep TTL appropriately low on the signed keys so that
the keys should expire before revocation would ever be required.

#### Example Low TTL Operation

Let's request a 1 minute TTL certificate.

I'll then login to the target machine from the client machine and being "work".

We'll watch for the cert to expire and see that my SSH connection stays connected
but I'm unable to form more without signing my public key again.

Let me split these two terminals one more time.

Then we start watching the sshd logs on the target machine.

```bash
# Open and follow sshd logs
sudo journalctl -xef -u sshd
```

Then we'll login to Vault as `some-user` and issue a very short TTL token.

```bash
# Login to Vault as some-user
export VAULT_TOKEN="$(vault login -field=token -method=userpass username=some-user)"

# Sign the $HOME/.ssh/id_ed25519.pub key to produce $HOME/.ssh/id_ed25519-cert.pub
# with a 1 minute TTL
vault write -field=signed_key ssh-client-signer/sign/admin -<<EOH  > $HOME/.ssh/id_ed25519-cert.pub
{
  "public_key": "$(cat $HOME/.ssh/id_ed25519.pub)",
  "valid_principals": "tkcadmin",
  "ttl": "1m"
  }
}
EOH

# Show the certificate contents; examine the TTL
ssh-keygen -Lf ~/.ssh/id_ed25519-cert.pub

# SSH to target machine
ssh tkcadmin@target.local
```

## Wrap-up

With that, we've covered about as much of the topic as I wanted!

This gives just a few examples of how Vault can be used to help manage Linux
system SSH authentication.

Adding SSL certificates to Vault, additional per-user class roles for the
client CA, more fine grained policies with user name templating or other
valid-principals limiting behavior; would probably be wanted to take this
to a more production-ready state.

Further exploration opportunities exist around Vault integration with
external Authentication sources that link existing identity management
technology and users to Vault policies that manage SSH CA access.

As examples,

Vault auth with..

  - LDAP provided by Active Directory, FreeIPA or RHEL IdM
  - TLS Certificates served by Vault PKI CA

## Lab Container Startup

### Client and Target Containers

These use a custom systemd container.  The Containerfiles are available
in the `[containers](./containers/) directory.

```bash
# Create our podman network
podman network create demo-network

# Start a set of containers for testing
for TGT in "client.local" "target.local"; do podman run -d --name $TGT \
--hostname $TGT --network demo-network systemd-almalinux:10; done
```

### Vault Container

The Vault server uses the upstream container; it is already in a good state
to meet our testing needs.

- https://hub.docker.com/r/hashicorp/vault

We'll publish the standard tcp/8200 port so that the Vault API and UI are
available to the host machine while also being available on the demo-network.

```bash
# This specifies the version used during the demo
podman pull docker.io/hashicorp/vault:1.21

# Run Vault container in Dev mode
podman run -d --cap-add=IPC_LOCK -e 'VAULT_DEV_ROOT_TOKEN_ID=RootToken' \
--name vault.local --hostname vault.local --network demo-network \
--publish 8200:8200 hashicorp/vault

# Show logs to ensure the root token set correctly
podman logs vault.local
```

## Connect to our consoles

Now I'll split the terminal into 2 consoles and connect to the client
and target containers.

Then we'll open a second tab for local workstation to Vault interactions.

### client.local console

```bash
# Connect to client container
podman exec -it client.local bash

# Show processes
ps -ef

# Check Vault status
vault status
```

### target.local console

```bash
# Connect to target container
podman exec -it target.local bash

# Show processes
ps -ef

# Check Vault status
vault status
```

## Cleanup Containers and Network

When done we can clean-up the lab containers and network.

```bash
# Stop and remove the test containers
for TGT in "client.local" "target.local" "vault.local"; do podman stop $TGT; done
for TGT in "client.local" "target.local" "vault.local"; do podman rm $TGT; done

# Create our demo network
podman network remove demo-network
```
