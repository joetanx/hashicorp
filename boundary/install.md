## 1. Setup PostgreSQL

Prepare PostgreSQL for use with Boundary

PostgreSQL setup guide: https://github.com/joetanx/setup/blob/main/postgres.md

## 2. Prepare Vault transit secrets engine

Refs:
- https://developer.hashicorp.com/boundary/docs/configuration/kms/transit
- https://developer.hashicorp.com/vault/docs/secrets/transit
- https://developer.hashicorp.com/vault/tutorials/encryption-as-a-service/eaas-transit

Enable transit secrets engine

```sh
vault secrets enable -path=boundary transit
```

Create encryption key rings for `root`, `worker-auth` and `recovery`

```sh
vault write -f boundary/keys/root
vault write -f boundary/keys/worker-auth
vault write -f boundary/keys/recovery
```

Create policy to allow Boundary to use the transit secrets engine

```sh
vault policy write boundary -<< EOF
path "boundary/encrypt/*" {
  capabilities = ["update"]
}
path "boundary/decrypt/*" {
  capabilities = ["update"]
}
EOF
```

## 3. Install Boundary

Configure Hashicorp repository and install Boundary

```sh
curl -sLo/etc/yum.repos.d/hashicorp.repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
yum -y install boundary
firewall-cmd --permanent --add-port 9200/tcp && firewall-cmd --permanent --add-port 9201/tcp && firewall-cmd --permanent --add-port 9202/tcp && firewall-cmd --reload
```

Prepare TLS with [lab certs](https://github.com/joetanx/lab-certs/)

```sh
mkdir /etc/boundary.d/tls
curl -sLo /etc/boundary.d/tls/boundary-cert.pem https://github.com/joetanx/lab-certs/raw/main/others/boundary.vx.pem
curl -sLo /etc/boundary.d/tls/boundary-key.pem https://github.com/joetanx/lab-certs/raw/main/others/boundary.vx.key
curl -sLo /etc/boundary.d/tls/vault-ca.pem https://github.com/joetanx/lab-certs/raw/main/ca/lab_issuer.pem
```

Prepare Boundary controller and worker configuration files

```sh
curl -sLo /etc/boundary.d/controller.hcl https://github.com/joetanx/hashicorp/raw/main/boundary-controller.hcl
curl -sLo /etc/boundary.d/worker.hcl https://github.com/joetanx/hashicorp/raw/main/boundary-worker.hcl
```

Create vault token for Boundary and replace placeholder `<boundary-token>` with the token in the configuration files

```sh
BOUNDARY_TOKEN=$(vault token create -field=token -policy=boundary)
sed -i "s/<boundary-token>/$BOUNDARY_TOKEN/" /etc/boundary.d/controller.hcl
sed -i "s/<boundary-token>/$BOUNDARY_TOKEN/" /etc/boundary.d/worker.hcl
```

## 4. Initialize Boundary

```console
[root@boundary ~]# boundary database init -config /etc/boundary.d/controller.hcl | tee /etc/boundary.d/init.log
⋮
Migrations successfully run.
Global-scope KMS keys successfully created.

Initial login role information:
  Name:      Login and Default Grants
  Role ID:   r_OCqZDNaKb0

Initial auth information:
  Auth Method ID:     ampw_gGKcGhkAAf
  Auth Method Name:   Generated global scope initial password auth method
  Login Name:         admin
  Password:           kIVsZNrJoTgLNranowWp
  Scope ID:           global
  User ID:            u_sFjBoaHSRZ
  User Name:          admin

Initial org scope information:
  Name:       Generated org scope
  Scope ID:   o_h3POJFbyMp
  Type:       org

Initial project scope information:
  Name:       Generated project scope
  Scope ID:   p_43FrANwugv
  Type:       project

Initial host resources information:
  Host Catalog ID:     hcst_ynnMjhMPKJ
  Host Catalog Name:   Generated host catalog
  Host ID:             hst_Fze0T0LvYC
  Host Name:           Generated host
  Host Set ID:         hsst_xDtqNeQEgs
  Host Set Name:       Generated host set
  Scope ID:            p_43FrANwugv
  Type:                static

Initial target information:
  Default Port:               22
  Name:                       Generated target with a direct address
  Scope ID:                   p_43FrANwugv
  Session Connection Limit:   -1
  Session Max Seconds:        28800
  Target ID:                  ttcp_hjGw0etxaS
  Type:                       tcp

Initial target information:
  Default Port:               22
  Name:                       Generated target using host sources
  Scope ID:                   p_43FrANwugv
  Session Connection Limit:   -1
  Session Max Seconds:        28800
  Target ID:                  ttcp_3yc897kLXO
  Type:                       tcp
⋮
```

Download and run install script

Ref: https://developer.hashicorp.com/boundary/docs/install-boundary/systemd

```console
[root@boundary ~]# curl -sLo install.sh https://github.com/joetanx/hashicorp/raw/main/boundary-install.sh
[root@boundary ~]# chmod +x install.sh
[root@boundary ~]# ./install.sh controller
adduser: user 'boundary' already exists
Created symlink /etc/systemd/system/multi-user.target.wants/boundary-controller.service → /etc/systemd/system/boundary-controller.service.
[root@boundary ~]# ./install.sh worker
adduser: user 'boundary' already exists
Created symlink /etc/systemd/system/multi-user.target.wants/boundary-worker.service → /etc/systemd/system/boundary-worker.service.
```

## 5. Test login

```console
[root@boundary ~]# export BOUNDARY_AUTH_METHOD_ID=$(grep 'Auth Method ID' /etc/boundary.d/init.log | cut -d ':' -f 2 | tr -d ' ')
[root@boundary ~]# export BOUNDARY_ADDR=https://boundary.vx:9200
[root@boundary ~]# export BOUNDARY_AUTHENTICATE_PASSWORD_LOGIN_NAME=admin
[root@boundary ~]# export BOUNDARY_AUTHENTICATE_PASSWORD_PASSWORD=$(grep Password /etc/boundary.d/init.log | cut -d ':' -f 2 | tr -d ' ')
[root@boundary ~]# boundary authenticate password -password=env://BOUNDARY_AUTHENTICATE_PASSWORD_PASSWORD -keyring-type=none

Authentication information:
  Account ID:      acctpw_umWY56jy43
  Auth Method ID:  ampw_gGKcGhkAAf
  Expiration Time: Sat, 14 Oct 2023 16:48:30 +08
  User ID:         u_sFjBoaHSRZ

Storing the token in a keyring was disabled. The token is:
at_PHDQ99isEP_s14u5CYdtXNFMGyq2Zk2irzKc2QRks3P5ir5smmxnydoaUvbVCZWX1iGEbJfV9VCxruETovMQEiXSAg7ezwRfavpudrzBM9Bf8RAgYQoaXoexXxMBwpX7dFtJ5528ZMDhpv4a3fBLiLknk6VKFnQ
Please be sure to store it safely!
```
