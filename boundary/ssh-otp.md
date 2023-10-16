## 1 Prepare Vault to allow access from Boundary

Ref: https://developer.hashicorp.com/boundary/tutorials/credential-management/oss-vault-cred-brokering-quickstart

> [!Note]
>
> This integration requires the database engine and policy configured in [SSH One-Time Password](vault/ssh-otp.md)

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
> The `ssh-otp-access` policy is from [SSH One-Time Password](vault/ssh-otp.md)

```console
[root@vault ~]# vault token create -no-default-policy=true -policy=boundary-controller -policy=ssh-otp-access -orphan=true -period=20m -renewable=true
Key                  Value
---                  -----
token                hvs.CAESIJ4RcdnSjgchQcBnYe5A9D3b3QxsF7OuZ5Gp7k_zG72zGh4KHGh2cy5VazZ5WllPS3UxM0tiMGhZR1BramNDNnc
token_accessor       hf7e1V36VYQKLhJo1mSp0Gj2
token_duration       20m
token_renewable      true
token_policies       ["boundary-controller" "ssh-otp-access"]
identity_policies    []
policies             ["boundary-controller" "ssh-otp-access"]
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
  Created Time:        Mon, 09 Oct 2023 13:18:51 +08
  ID:                  csvlt_TYDeNqvcII
  Type:                vault
  Updated Time:        Mon, 09 Oct 2023 13:18:51 +08
  Version:             1
⋮
```

Save the credential store ID in the `CREDENTIAL_STORE_ID` to be used in the next step

```sh
CREDENTIAL_STORE_ID=csvlt_TYDeNqvcII
```

### 2.2. Create credential library

Ref: https://developer.hashicorp.com/boundary/docs/concepts/domain-model/credential-libraries#vault-generic-credential-library-attributes

Prepare the request body that Boundary will use when calling Vault via `POST` method

```sh
BOUNDARY_VAULT_REQUEST="{\"ip\": \"192.168.17.80\"}"
```

```console
[root@boundary ~]# boundary credential-libraries create vault -credential-store-id=$CREDENTIAL_STORE_ID -vault-path=ssh-otp/creds/foxtrot -vault-http-method=post -vault-http-request-body="$BOUNDARY_VAULT_REQUEST"
⋮
Credential Library information:
  Created Time:          Mon, 09 Oct 2023 13:25:09 +08
  Credential Store ID:   csvlt_TYDeNqvcII
  ID:                    clvlt_6qVMJf7hrm
  Type:                  vault-generic
  Updated Time:          Mon, 09 Oct 2023 13:25:09 +08
  Version:               1
⋮
```

Save the credential library ID in the `CREDENTIAL_LIBRARY_ID` to be used later

```sh
CREDENTIAL_LIBRARY_ID=clvlt_6qVMJf7hrm
```

### 2.3. Create target

```console
[root@boundary ~]# boundary targets create tcp -name=foxtrot-ssh -scope-id=$BOUNDARY_SCOPE_ID -default-port=22 -address=foxtrot.vx
⋮
Target information:
  Address:                    foxtrot.vx
  Created Time:               Mon, 09 Oct 2023 13:25:53 +08
  ID:                         ttcp_MLuApCZ0eN
  Name:                       foxtrot-ssh
  Session Connection Limit:   -1
  Session Max Seconds:        28800
  Type:                       tcp
  Updated Time:               Mon, 09 Oct 2023 13:25:53 +08
  Version:                    1
⋮
```

Save the credential target ID in the `TARGET_ID` to be used in the next step

```sh
TARGET_ID=ttcp_MLuApCZ0eN
```

### 2.4. Add the credential library to brokered credential source of the target

```console
[root@boundary ~]# boundary targets add-credential-sources -id=$TARGET_ID -brokered-credential-source=$CREDENTIAL_LIBRARY_ID
⋮
Target information:
  Address:                    foxtrot.vx
  Created Time:               Mon, 09 Oct 2023 13:25:53 +08
  ID:                         ttcp_MLuApCZ0eN
  Name:                       foxtrot-ssh
  Session Connection Limit:   -1
  Session Max Seconds:        28800
  Type:                       tcp
  Updated Time:               Mon, 09 Oct 2023 13:27:07 +08
  Version:                    2
⋮
  Brokered Credential Sources:
    Credential Store ID:      csvlt_TYDeNqvcII
    ID:                       clvlt_6qVMJf7hrm
⋮
```

## 3. Connect to target

```console
[root@boundary ~]# boundary connect ssh -target-id $TARGET_ID -token=env://BOUNDARY_TOKEN -username vault
Credentials:
  Credential Source ID:  clvlt_6qVMJf7hrm
  Credential Store ID:   csvlt_TYDeNqvcII
  Credential Store Type: vault-generic
  Secret:
      {
          "ip": "192.168.17.80",
          "key": "5d7ce61b-5b51-fe0b-72b4-fd3489889507",
          "key_type": "otp",
          "port": 22,
          "username": "vault"
      }

vault@ttcp_mluapcz0en's password:
Last login: Mon Oct  9 13:28:00 2023 from 192.168.17.90
[vault@foxtrot ~]$ whoami
vault
[vault@foxtrot ~]$ hostname
foxtrot.vx
```
