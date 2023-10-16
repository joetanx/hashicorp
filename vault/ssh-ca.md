## 1. Prepare SSH secret engine

Ref: https://developer.hashicorp.com/vault/docs/secrets/ssh/signed-ssh-certificates

Enable SSH secret engine

```console
[root@vault ~]# vault secrets enable -path=ssh-client-signer ssh
Success! Enabled the ssh secrets engine at: ssh-client-signer/
```

Create a named Vault role for signing client keys

```console
[root@vault ~]# vault write ssh-client-signer/roles/default -<< EOF
{
  "allow_user_certificates": true,
  "allowed_users": "*",
  "allowed_extensions": "permit-pty,permit-port-forwarding",
  "default_extensions": {
    "permit-pty": ""
  },
  "key_type": "ca",
  "default_user": "vault",
  "ttl": "30m0s"
}
EOF
Success! Data written to: ssh-client-signer/roles/default
```

## 2. Setup SSH CA keys

### 2.1 Option 1 - Use Vault to generate CA keys

```console
[root@vault ~]# vault write ssh-client-signer/config/ca generate_signing_key=true key_type=ecdsa-sha2-nistp384
Key           Value
---           -----
public_key    ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBH6emPFqcyOSMPXAKhKR2RyAoqxbAcaOL73qMsfAmGsS46ApSm+vUghwvbv9UmOcZdVn2pQp74oF7u2NzntRUUoa9p7SYIRvY1GmLQ/2dCMUb5oRijXd03WThv0yXUjtQw==
```

### 2.2. Option 2 - Manually generate CA keys and import to Vault

Generate keys with OpenSSH

```console
[root@vault ~]# ssh-keygen -t ecdsa -b 384 -f vault_ca -C "" -N ""
Generating public/private ecdsa key pair.
Your identification has been saved in vault_ca
Your public key has been saved in vault_ca.pub
The key fingerprint is:
SHA256:37phBT0bsTaL2kONfWjbPrkq+J6xmZONA4BCe4jUNc4
The key's randomart image is:
+---[ECDSA 384]---+
|  . .o      .    |
| ...o .    . o   |
|.o o E    . B    |
|. + o .    B B   |
|   o   .S + O .  |
|        .= + +   |
|        .oB+o .. |
|        ..*X..o  |
|         oX=..oo |
+----[SHA256]-----+
```

Import keys to Vault

```console
[root@vault ~]# vault write ssh-client-signer/config/ca private_key=@vault_ca public_key=@vault_ca.pub
Success! Data written to: ssh-client-signer/config/ca
```

## 3. Prepare test user

Create access policy to allow access to SSH credentials

```console
[root@vault ~]# vault policy write key-sign -<< EOF
path "ssh-client-signer/*" {
  capabilities = [ "list" ]
}
path "ssh-client-signer/sign/default" {
  capabilities = ["update"]
  denied_parameters = {
    "key_id" = []
  }
}
EOF
Success! Uploaded policy: key-sign
```

Enable userpass auth method

```console
[root@vault ~]# vault auth enable userpass
Success! Enabled userpass auth method at: userpass/
```

Create user `test` with the `key-sign` access policy

```console
[root@vault ~]# vault write auth/userpass/users/test password=P@ssw0rd policies=key-sign
Success! Data written to: auth/userpass/users/test
```

## 4. Prepare target host

Add the public key to target host's SSH configuration

> [!Note]
>
> The public key is accessible via the API without authentication

```sh
curl -so /etc/ssh/vault_ssh_ca.pub https://vault.vx:8200/v1/ssh-client-signer/public_key
```

Enable `PubkeyAuthentication` and add the path of the public key file to the `TrustedUserCAKeys` option

```console
[root@foxtrot ~]# cat /etc/ssh/sshd_config
⋮
PubkeyAuthentication yes
TrustedUserCAKeys /etc/ssh/vault_ssh_ca.pub
⋮
```

Restart `sshd` service

```sh
systemctl restart sshd
```

Create user

```sh
useradd vault
```

## 5. Connect to target host

### 5.1. Generate client keys

```console
[root@client ~]# ssh-keygen -t ecdsa -b 384 -f id_ecdsa -C "" -N ""
Generating public/private ecdsa key pair.
Your identification has been saved in id_ecdsa
Your public key has been saved in id_ecdsa.pub
The key fingerprint is:
SHA256:b5cVm7Pda7nQypu2bmOB7usT19sH10T0gQ9Bir/QR8I
The key's randomart image is:
+---[ECDSA 384]---+
|            .ooo.|
|          o .o  +|
|         . E .+..|
|          o o  =.|
|        S. o..*..|
|         ..oo=o=+|
|          +.=.o+*|
|         . +.=+++|
|          o+BB=oo|
+----[SHA256]-----+
```

### 5.2. Sign client public key

#### 5.2.1. Option 1 - using CLI

Request Vault to sign key using `test` user

```console
[root@client ~]# USER_TOKEN=$(vault login -method=userpass username=test password=P@ssw0rd -format=json | jq -r '.auth | .client_token')
[root@client ~]# VAULT_TOKEN=$USER_TOKEN vault write ssh-client-signer/sign/default public_key=@id_ecdsa.pub
Key              Value
---              -----
serial_number    f73829a1f9840924
signed_key       ecdsa-sha2-nistp384-cert-v01@openssh.com AAAAKGVjZHNhLXNoYTItbmlzdHAzODQtY2VydC12MDFAb3BlbnNzaC5jb20AAAAgJiWxtqurQKWLb9qhHFOGQnBxIsdEkFLR8UVQYo6zLHgAAAAIbmlzdHAzODQAAABhBHL193TSYPQSl3SrngLrDdVIyEQkbnXFyT33AaI6G37eVHDSK4XewUhyMg0r2hPMwgkfYAxb5q8Z0ph9NggNGJyUHDRjqycGi4bOQAvSpvX0KVPddMWFkwmr62CmRibllPc4KaH5hAkkAAAAAQAAAEt2YXVsdC1yb290LTZmOTcxNTliYjNkZDZiYjlkMGNhOWJiNjZlNjM4MWVlZWIxM2Q3ZGIwN2Q3NDRmNDgxMGY0MThhYmZkMDQ3YzIAAAAJAAAABXZhdWx0AAAAAGUgq4EAAAAAZSCypwAAAAAAAAASAAAACnBlcm1pdC1wdHkAAAAAAAAAAAAAAIgAAAATZWNkc2Etc2hhMi1uaXN0cDM4NAAAAAhuaXN0cDM4NAAAAGEEqfjLOfl1XGr1maPs6AULFcol4/pCudBDFLkEbH1GB+eMKB0q3jx9qy5z3937Zy6NhZZheVUvkRRH9JjbjFPJUSMkxRjElH2tq3ad2m8uwryMnyiBN6FUut5/0PFzcqH3AAAAhQAAABNlY2RzYS1zaGEyLW5pc3RwMzg0AAAAagAAADEAm8GI92kKs1RcB2XBfGFK4o8lnfgwxp+cBDfZuQUbOEZsfq3B1Naz19+E7N6cLgMjAAAAMQCvsYT+qeiGBS1tWL0T0VOaIX0d1uc9z9bWul98O4GfJbq28IelrGPCRDNrAZj0LiE=
```

Save signed key

```console
[root@client ~]# VAULT_TOKEN=$USER_TOKEN vault write -field=signed_key ssh-client-signer/sign/default public_key=@id_ecdsa.pub > id_ecdsa-cert.pub
[root@client ~]# chmod 600 id_ecdsa-cert.pub
```

#### 5.2.2. Option 2 - using UI

![image](https://github.com/joetanx/hashicorp/assets/90442032/07e94b32-5361-4dff-af50-17647bc24ed8)

![image](https://github.com/joetanx/hashicorp/assets/90442032/38e896d1-406f-49ec-88ad-440b0860bce5)

![image](https://github.com/joetanx/hashicorp/assets/90442032/eb83dcc4-5962-4694-9dab-912a79246708)

![image](https://github.com/joetanx/hashicorp/assets/90442032/6780d70d-1a3d-4bbe-b22a-b3c03aa07423)

![image](https://github.com/joetanx/hashicorp/assets/90442032/5d00944d-55c5-4c33-9bc4-92038cbfc85f)

Copy and save signed key from UI

```console
[root@client ~]# echo 'ecdsa-sha2-nistp384-cert-v01@openssh.com AAAAKGVjZHNhLXNoYTItbmlzdHAzODQtY2VydC12MDFAb3BlbnNzaC5jb20AAAAgVwsRK0N1kKm4GVl3TYOJ9X0q04JLSORvoE0vB7TZNCoAAAAIbmlzdHAzODQAAABhBHL193TSYPQSl3SrngLrDdVIyEQkbnXFyT33AaI6G37eVHDSK4XewUhyMg0r2hPMwgkfYAxb5q8Z0ph9NggNGJyUHDRjqycGi4bOQAvSpvX0KVPddMWFkwmr62CmRibllPv7/9VZQKlVAAAAAQAAAEt2YXVsdC1yb290LTZmOTcxNTliYjNkZDZiYjlkMGNhOWJiNjZlNjM4MWVlZWIxM2Q3ZGIwN2Q3NDRmNDgxMGY0MThhYmZkMDQ3YzIAAAAJAAAABXZhdWx0AAAAAGUgrP4AAAAAZSC0JAAAAAAAAAASAAAACnBlcm1pdC1wdHkAAAAAAAAAAAAAAIgAAAATZWNkc2Etc2hhMi1uaXN0cDM4NAAAAAhuaXN0cDM4NAAAAGEEqfjLOfl1XGr1maPs6AULFcol4/pCudBDFLkEbH1GB+eMKB0q3jx9qy5z3937Zy6NhZZheVUvkRRH9JjbjFPJUSMkxRjElH2tq3ad2m8uwryMnyiBN6FUut5/0PFzcqH3AAAAhQAAABNlY2RzYS1zaGEyLW5pc3RwMzg0AAAAagAAADEAp3GsiSu3NU4cXiU55yWJskDm6SA1FHnViqNGSBc+NaR9rVWCoMwzLAAHTvBgu9tRAAAAMQCMx4FQelKs8XlPfxxX6RHfItbN5Nac9iEuvMoKKu8UOhbvJKGZ+jI3FoCS4uas82k=' > id_ecdsa-cert.pub
```

### 5.3. Connect to target with signed key

Check signed key

```console
[root@client ~]# ssh-keygen -Lf id_ecdsa-cert.pub
id_ecdsa-cert.pub:
        Type: ecdsa-sha2-nistp384-cert-v01@openssh.com user certificate
        Public key: ECDSA-CERT SHA256:b5cVm7Pda7nQypu2bmOB7usT19sH10T0gQ9Bir/QR8I
        Signing CA: ECDSA SHA256:37phBT0bsTaL2kONfWjbPrkq+J6xmZONA4BCe4jUNc4 (using ecdsa-sha2-nistp384)
        Key ID: "vault-root-6f97159bb3dd6bb9d0ca9bb66e6381eeeb13d7db07d744f4810f418abfd047c2"
        Serial: 18157387614464813397
        Valid: from 2023-10-07T08:57:34 to 2023-10-07T09:28:04
        Principals:
                vault
        Critical Options: (none)
        Extensions:
                permit-pty
```

Connect to target

```console
[root@client ~]# ssh -o CertificateFile=id_ecdsa-cert.pub -i id_ecdsa vault@foxtrot.vx
Last login: Sat Oct  7 09:01:06 2023 from 192.168.17.100
[vault@foxtrot ~]$
```
