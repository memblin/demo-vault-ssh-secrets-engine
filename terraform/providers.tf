terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.8.0"
    }
  }

  required_version = ">= v1.14.8"
}
