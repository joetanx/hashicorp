## 1. Prepare Vault to allow access from Boundary

Ref: https://developer.hashicorp.com/boundary/tutorials/credential-management/oss-vault-cred-brokering-quickstart

> [!Note]
>
> This integration requires the database engine and policy configured in [Database / PostgreSQL](vault/db-postgres.md)

### 1.1. Create the boundary-controller policy

Boundary needs to lookup, renew, and revoke tokens and leases in order to broker credentials properly.

```console
vault policy write boundary-controller -<< EOF
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
path "sys/leases/renew" {
  capabilities = ["update"]
}
path "sys/leases/revoke" {
  capabilities = ["update"]
}
path "sys/capabilities-self" {
  capabilities = ["update"]
}
EOF
```

### 1.2. Generate token for Boundary

> [!Note]
>
> The `postgresql-access` policy is from [Database / PostgreSQL](vault/db-postgres.md)

```console
[root@vault ~]# vault token create -no-default-policy=true -policy=boundary-controller -policy=postgresql-access -orphan=true -period=20m -renewable=true
Key                  Value
---                  -----
token                hvs.CAESIKHIG_EG1DpX-1WzkGkgK3Ie7snRzrBQzcCBGnJyoq_QGh4KHGh2cy5ueXJuR1hEQkVobnk3RDExUGtabGp4eno
token_accessor       uIdVRRMOBoPoCOztDB2DIfSO
token_duration       20m
token_renewable      true
token_policies       ["boundary-controller" "postgresql-access"]
identity_policies    []
policies             ["boundary-controller" "postgresql-access"]
```

## 2. Configure Boundary

Prepare the Boundary CLI login information in environment variables:
- `BOUNDARY_AUTH_METHOD_ID`
- `BOUNDARY_ADDR`
- `BOUNDARY_TOKEN`
- `BOUNDARY_SCOPE_ID`
- `BOUNDARY_VAULT_TOKEN`

### 2.1. Create credential store

Credential store contains the information for Boundary to connect to Vault

```console
[root@boundary ~]# boundary credential-stores create vault -vault-address=https://vault.vx:8200 -vault-token=$BOUNDARY_VAULT_TOKEN -vault-ca-cert=file:///etc/boundary.d/tls/vault-ca.pem
⋮
Credential Store information:
  Created Time:        Mon, 09 Oct 2023 11:22:49 +08
  ID:                  csvlt_ABLDvIi1xG
  Type:                vault
  Updated Time:        Mon, 09 Oct 2023 11:22:49 +08
  Version:             1
⋮
```

Save the credential store ID in the `CREDENTIAL_STORE_ID` to be used in the next step

```sh
CREDENTIAL_STORE_ID=csvlt_KdvdZnzOCw
```

### 2.2. Create credential library

```console
[root@boundary ~]# boundary credential-libraries create vault -credential-store-id=$CREDENTIAL_STORE_ID -vault-path=postgresql/creds/monitor
⋮
Credential Library information:
  Created Time:          Mon, 09 Oct 2023 11:30:50 +08
  Credential Store ID:   csvlt_ABLDvIi1xG
  ID:                    clvlt_GwKwIV4QEN
  Type:                  vault-generic
  Updated Time:          Mon, 09 Oct 2023 11:30:50 +08
  Version:               1
⋮
```

Save the credential library ID in the `CREDENTIAL_LIBRARY_ID` to be used later

```sh
CREDENTIAL_LIBRARY_ID=clvlt_GwKwIV4QEN
```

### 2.3. Create target

```console
[root@boundary ~]# boundary targets create tcp -name=foxtrot-psql -scope-id=$BOUNDARY_SCOPE_ID -default-port=5432 -address=foxtrot.vx
⋮
Target information:
  Address:                    foxtrot.vx
  Created Time:               Mon, 09 Oct 2023 11:32:46 +08
  ID:                         ttcp_qigyzid2oc
  Name:                       foxtrot-psql
  Session Connection Limit:   -1
  Session Max Seconds:        28800
  Type:                       tcp
  Updated Time:               Mon, 09 Oct 2023 11:32:46 +08
  Version:                    1
⋮
```

Save the credential target ID in the `TARGET_ID` to be used in the next step

```sh
TARGET_ID=ttcp_qigyzid2oc
```

### 2.4. Add the credential library to brokered credential source of the target

```console
[root@boundary ~]# boundary targets add-credential-sources -id=$TARGET_ID -brokered-credential-source=$CREDENTIAL_LIBRARY_ID
⋮
Target information:
  Address:                    foxtrot.vx
  Created Time:               Mon, 09 Oct 2023 11:32:46 +08
  ID:                         ttcp_qigyzid2oc
  Name:                       foxtrot-psql
  Session Connection Limit:   -1
  Session Max Seconds:        28800
  Type:                       tcp
  Updated Time:               Mon, 09 Oct 2023 11:34:31 +08
  Version:                    2
⋮
  Brokered Credential Sources:
    Credential Store ID:      csvlt_ABLDvIi1xG
    ID:                       clvlt_GwKwIV4QEN
⋮
```

## 3. Connect to target

```console
[root@boundary ~]# boundary connect postgres -target-id $TARGET_ID -dbname postgres
Direct usage of BOUNDARY_TOKEN env var is deprecated; please use "-token env://<env var name>" format, e.g. "-token env://BOUNDARY_TOKEN" to specify an env var to use.
psql (13.10)
Type "help" for help.

postgres=> SELECT current_user;
                  current_user
-------------------------------------------------
 v-token-monitor-Ig4qbng864EkeWZy9uJv-1696822598
(1 row)
postgres=> \conninfo
You are connected to database "postgres" as user "v-token-monitor-Ig4qbng864EkeWZy9uJv-1696822598" on host "127.0.0.1" at port "36203".
```
