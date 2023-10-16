## .1 Prepare Vault to allow access from Boundary

Ref: https://developer.hashicorp.com/boundary/tutorials/credential-management/oss-vault-cred-brokering-quickstart

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

### 1.2. Create user on target Windows host

Create user `vault` with password `P@ssw0rd`

```cmd
net user vault P@ssw0rd /add
```

Onboard credential to Vault and configure `rdp-kv-access` policy

```console
[root@vault ~]# vault secrets enable -path=rdp-kv kv-v2
Success! Enabled the kv-v2 secrets engine at: rdp-kv/
[root@vault ~]# vault kv put -mount=rdp-kv quebec system=windows address=quebec.vx username=vault password=P@ssw0rd
=== Secret Path ===
rdp-kv/data/quebec

======= Metadata =======
Key                Value
---                -----
created_time       2023-10-09T05:39:45.606487063Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1
[root@vault ~]# vault policy write rdp-kv-access -<< EOF
path "rdp-kv/metadata" {
  capabilities = ["list"]
}
path "rdp-kv/data/*" {
  capabilities = ["read"]
}
EOF
Success! Uploaded policy: rdp-kv-access
```

### 1.3. Generate token for Boundary

```console
[root@vault ~]# vault token create -no-default-policy=true -policy=boundary-controller -policy=rdp-kv-access -orphan=true -period=20m -renewable=true
Key                  Value
---                  -----
token                hvs.CAESIKJyFfImn7ay8VUYPDTbLPIrncx-x5vEZjovf-YeVwA0Gh4KHGh2cy5SUWt6UzZIMGRnM2pFQ0pVNTRXTWpudnI
token_accessor       hVdDzd2I96fztDo8BF92FYCR
token_duration       20m
token_renewable      true
token_policies       ["boundary-controller" "rdp-kv-access"]
identity_policies    []
policies             ["boundary-controller" "rdp-kv-access"]
```

## 2. Configure Boundary

Prepare the necessary environment variables:
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
  Created Time:        Mon, 09 Oct 2023 13:42:05 +08
  ID:                  csvlt_srK8ShsX1o
  Type:                vault
  Updated Time:        Mon, 09 Oct 2023 13:42:05 +08
  Version:             1
⋮
```

Save the credential store ID in the `CREDENTIAL_STORE_ID` to be used in the next step

```sh
CREDENTIAL_STORE_ID=csvlt_srK8ShsX1o
```

### 2.2. Create credential library

```console
[root@boundary ~]# boundary credential-libraries create vault -credential-store-id=$CREDENTIAL_STORE_ID -vault-path=rdp-kv/data/quebec
⋮
Credential Library information:
  Created Time:          Mon, 09 Oct 2023 13:25:09 +08
  Credential Store ID:   csvlt_srK8ShsX1o
  ID:                    clvlt_ciJOw7u8DF
  Type:                  vault-generic
  Updated Time:          Mon, 09 Oct 2023 13:25:09 +08
  Version:               1
⋮
```

Save the credential library ID in the `CREDENTIAL_LIBRARY_ID` to be used later

```sh
CREDENTIAL_LIBRARY_ID=clvlt_ciJOw7u8DF
```

### 2.3. Create target

```console
[root@boundary ~]# boundary targets create tcp -name=quebec-rdp -scope-id=$BOUNDARY_SCOPE_ID -default-port=3389 -address=quebec.vx
⋮
Target information:
  Address:                    quebec.vx
  Created Time:               Mon, 09 Oct 2023 13:44:11 +08
  ID:                         ttcp_chIqepdZ3B
  Name:                       quebec-rdp
  Session Connection Limit:   -1
  Session Max Seconds:        28800
  Type:                       tcp
  Updated Time:               Mon, 09 Oct 2023 13:44:11 +08
  Version:                    1
⋮
```

Save the credential target ID in the `TARGET_ID` to be used in the next step

```sh
TARGET_ID=ttcp_chIqepdZ3B
```

### 2.4. Add the credential library to brokered credential source of the target

```console
[root@boundary ~]# boundary targets add-credential-sources -id=$TARGET_ID -brokered-credential-source=$CREDENTIAL_LIBRARY_ID
⋮
Target information:
  Address:                    quebec.vx
  Created Time:               Mon, 09 Oct 2023 13:44:11 +08
  ID:                         ttcp_chIqepdZ3B
  Name:                       quebec-rdp
  Session Connection Limit:   -1
  Session Max Seconds:        28800
  Type:                       tcp
  Updated Time:               Mon, 09 Oct 2023 13:44:44 +08
  Version:                    2
⋮
  Brokered Credential Sources:
    Credential Store ID:      csvlt_srK8ShsX1o
    ID:                       clvlt_ciJOw7u8DF
⋮
```

## 3. Connect to target

Install Boundary Desktop and connect to the Boundary instance

Ref: https://developer.hashicorp.com/boundary/tutorials/oss-getting-started/oss-getting-started-desktop-app#install-boundary-desktop

![image](https://github.com/joetanx/hashicorp/assets/90442032/19bf17b9-d07a-4fcc-b6a2-fde9948b4e0a)

![image](https://github.com/joetanx/hashicorp/assets/90442032/6c58b743-dd3c-43ae-acd2-cf18c87cb4ce)

Select connect on the RDP target

![image](https://github.com/joetanx/hashicorp/assets/90442032/551c691d-342b-467d-b7be-c8ae91487180)

Note the proxy URL created by Boundary Desktop and the credential retrieved from Vault

![image](https://github.com/joetanx/hashicorp/assets/90442032/500c358d-4114-4653-8a10-6bddc3dc44e5)

Open `mstsc` and connect with the information from Boundary

![image](https://github.com/joetanx/hashicorp/assets/90442032/6e950561-6438-4dff-9aa5-f688219de817)

![image](https://github.com/joetanx/hashicorp/assets/90442032/39097802-5b40-4d5b-a6ab-d402beb91286)

Connection to target is made through a local port forwarding

![image](https://github.com/joetanx/hashicorp/assets/90442032/db442abb-620d-437c-80a3-ca7be6312a87)

Notice that from the target perspective, the connection is made from Boundary worker

```cmd
C:\Users\vault>netstat -an | findstr 3389
  ⋮
  TCP    192.168.17.81:3389     192.168.17.90:37474    ESTABLISHED
  ⋮
```

And from the client perspective, it is connecting through itself

```cmd
C:\Users\Rimuru>netstat -an | findstr 127.0.0.1
  TCP    127.0.0.1:49784        0.0.0.0:0              LISTENING
  TCP    127.0.0.1:49784        127.0.0.1:49794        ESTABLISHED
  ⋮
```
