listener "tcp" {
  address = "0.0.0.0"
  purpose = "proxy"
  tls_cert_file = "/etc/boundary.d/tls/boundary-cert.pem"
  tls_key_file  = "/etc/boundary.d/tls/boundary-key.pem"
}

worker {
  name = "boundary-worker"

  controllers = [
    "127.0.0.1"
  ]

  public_addr = "boundary.vx"
}

# must be same key as used on controller config

kms "transit" {
  purpose            = "worker-auth"
  address            = "https://vault.vx:8200"
  token              = "<boundary-token>"
  disable_renewal    = "false"

  // Key configuration
  key_name           = "worker-auth"
  mount_path         = "boundary/"

  // TLS Configuration
  tls_ca_cert        = "/etc/boundary.d/tls/vault-ca.pem"
  tls_server_name    = "vault.vx"
  tls_skip_verify    = "false"
}