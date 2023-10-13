disable_mlock = true

controller {
  name = "boundary-controller"

  database {
      url = "postgresql://boundary:Boundary123@localhost/boundary"
  }
}

listener "tcp" {
  address = "0.0.0.0"
  purpose = "api"
  tls_cert_file = "/etc/boundary.d/tls/boundary-cert.pem"
  tls_key_file  = "/etc/boundary.d/tls/boundary-key.pem"
}

listener "tcp" {
  address = "0.0.0.0"
  purpose = "cluster"
  tls_cert_file = "/etc/boundary.d/tls/boundary-cert.pem"
  tls_key_file  = "/etc/boundary.d/tls/boundary-key.pem"
}

kms "transit" {
  purpose            = "root"
  address            = "https://vault.vx:8200"
  token              = "<boundary-token>"
  disable_renewal    = "false"

  // Key configuration
  key_name           = "root"
  mount_path         = "boundary/"

  // TLS Configuration
  tls_ca_cert        = "/etc/boundary.d/tls/vault-ca.pem"
  tls_server_name    = "vault.vx"
  tls_skip_verify    = "false"
}

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

kms "transit" {
  purpose            = "recovery"
  address            = "https://vault.vx:8200"
  token              = "<boundary-token>"
  disable_renewal    = "false"

  // Key configuration
  key_name           = "recovery"
  mount_path         = "boundary/"

  // TLS Configuration
  tls_ca_cert        = "/etc/boundary.d/tls/vault-ca.pem"
  tls_server_name    = "vault.vx"
  tls_skip_verify    = "false"
}