## 1. Prepare Policies

The below policies provide access to the secrets created in [Key/Value Secrets Engine](vault/key-vault-secrets-engine.md)

Create access policies `reader` and `manager` to be used for the login users:

```console
[root@vault ~]# vault policy write manager -<< EOF
# Manage k/v secrets
path "/database-v2/data/*" {
    capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
Success! Uploaded policy: manager
[root@vault ~]# vault policy write reader -<< EOF
# Read permission on the k/v secrets
path "/database-v2/data/*" {
    capabilities = ["read", "list"]
}
EOF
Success! Uploaded policy: reader
[root@vault ~]# vault policy list
default
manager
reader
root
```

## 2. LDAP

Enable the LDAP auth method:

> [!Note]
>
> The auth method can also be mounted to a custom path using `vault auth enable -path=<path> ldap`

```console
[root@vault ~]# vault auth enable ldap
Success! Enabled ldap auth method at: ldap/
```

Configure the LDAP auth method:

```console
[root@vault ~]# vault write auth/ldap/config \
url="ldap://contoso.vx" \
userattr=sAMAccountName \
userdn="dc=contoso,dc=vx" \
groupdn="dc=contoso,dc=vx" \
groupfilter="(&(objectClass=person)(uid={{.Username}}))" \
groupattr="memberOf" \
binddn="cn=Bind Account,cn=Users,dc=contoso,dc=vx" \
bindpass='Password123' \
insecure_tls=false \
starttls=true
token_policies=reader
Success! Data written to: auth/ldap/config
```

Login to vault using LDAP:

![image](https://github.com/joetanx/hashicorp/assets/90442032/ceb926d3-77d6-4489-b0d6-7ea0c4f0eaf6)

![image](https://github.com/joetanx/hashicorp/assets/90442032/178c6917-6da4-4f29-92f5-0e7f5376d927)

![image](https://github.com/joetanx/hashicorp/assets/90442032/27f800e4-262a-4017-8270-b90ab2a31a4a)

![image](https://github.com/joetanx/hashicorp/assets/90442032/0c450b06-5aab-4831-bcef-fcbd109ddb7c)

![image](https://github.com/joetanx/hashicorp/assets/90442032/d013b306-4848-40e7-b759-fb03afd6cae7)

## 3. OIDC + ADFS

### 3.1. 📌 ADFS - Setup Application Group

Select `Add Application Group` from ADFS management console:

![image](https://github.com/joetanx/hashicorp/assets/90442032/34e4e971-b124-4561-920b-da1c3c990b00)

Provide a name for the application group and select `Server application accessing a web API` for the template:

![image](https://github.com/joetanx/hashicorp/assets/90442032/5b914754-951b-48b0-ba70-a9bb81e7fb27)

Note the automatically generated `Client Identifier` - this is required to configure the web API and the Vault auth method

Add `https://<vault-fqdn>:8250/oidc/callback` and `https://<vault-fqdn>:8200/ui/vault/auth/oidc/oidc/callback` for the `Redirect URI`:

![image](https://github.com/joetanx/hashicorp/assets/90442032/5a2c083a-0340-4ed2-9edf-535f2851f133)

Note the automatically generated `Secret` - this is required to configure the Vault auth method

![image](https://github.com/joetanx/hashicorp/assets/90442032/f501c6db-ad66-40fe-92d6-ab24eb88a5bb)

Enter the previous noted `Client Identifier` for the web API configuration:

![image](https://github.com/joetanx/hashicorp/assets/90442032/4b37fbec-4e9e-4c9b-b917-2cddd460cb5a)

Edit the access control policy as required:

![image](https://github.com/joetanx/hashicorp/assets/90442032/b1830c7a-757f-49eb-b03d-768bd5161cf9)

Configure the application permission:
- `openid` is selected by default
- `allatclaims` may be required, it lets the application request the claims in the access token to be added to the ID token as well
- More details: https://learn.microsoft.com/en-us/windows-server/identity/ad-fs/development/ad-fs-openid-connect-oauth-concepts#scopes

![image](https://github.com/joetanx/hashicorp/assets/90442032/0763142d-24e3-49e9-be66-9b13cbdf8c93)

Verify the summary and complete the setup:

![image](https://github.com/joetanx/hashicorp/assets/90442032/b19e532a-f2fd-4b94-942b-0dd75fe17277)

### 3.2. 📌 Vault - Setup Auth Method

Set the ADFS IdP information to environment variable:

```console
[root@vault ~]# export ADFS_FQDN=adfs.contoso.vx
[root@vault ~]# export ADFS_CLIENT_ID=24f1322b-b662-40a2-a3a9-02a7a7a61b9c
[root@vault ~]# export ADFS_CLIENT_SECRET=XkfyIY2jAHa2PZKTs-BvB28IX0TzZ2S6bR4LJbk1
```

Enable the OIDC auth method:

> [!Note]
>
> The auth method can also be mounted to a custom path using `vault auth enable -path=<path> oidc`

```console
[root@vault ~]# vault auth enable oidc
Success! Enabled oidc auth method at: oidc/
```

Configure the OIDC auth method:

> [!Note]
> 
> The metadata URL for ADFS OIDC is at `https://<adfs-fqdn>/adfs/.well-known/openid-configuration`, but the discovery URL is at `https://<adfs-fqdn>/adfs`
>
> Browsing to the metadata URL will show the discovery URL under `issuer` field:
> 
> ```json
> {
>     "issuer": "https://adfs.contoso.vx/adfs",
>     ...
> }
> ```
>
> More details on ADFS endpoints: https://learn.microsoft.com/en-us/windows-server/identity/ad-fs/development/ad-fs-openid-connect-oauth-concepts#ad-fs-endpoints

```console
[root@vault ~]# vault write auth/oidc/config \
oidc_discovery_url=https://$ADFS_FQDN/adfs \
oidc_client_id=$ADFS_CLIENT_ID \
oidc_client_secret=$ADFS_CLIENT_SECRET \
default_role=reader
Success! Data written to: auth/oidc/config
```

Create `reader` role for the OIDC login users:

```console
[root@vault ~]# vault write auth/oidc/role/reader \
bound_audiences=$ADFS_CLIENT_ID \
allowed_redirect_uris=https://vault.vx:8200/ui/vault/auth/oidc/oidc/callback \
allowed_redirect_uris=https://vault.vx:8250/oidc/callback \
user_claim=upn \
token_policies=reader
Success! Data written to: auth/oidc/role/reader
```

### 3.3. Test login

![image](https://github.com/joetanx/hashicorp/assets/90442032/1cb4c5d6-843b-4615-91e2-84a3cdb136d3)

![image](https://github.com/joetanx/hashicorp/assets/90442032/42f29c19-7cc7-458b-99b3-03e4b6b0f493)

![image](https://github.com/joetanx/hashicorp/assets/90442032/e2c2c589-4533-44f6-aacf-383a5c8638ab)

![image](https://github.com/joetanx/hashicorp/assets/90442032/d789fd5a-c88d-4459-9018-9352bf78e8de)

![image](https://github.com/joetanx/hashicorp/assets/90442032/77c93e60-b476-494d-b67f-61d45b52100c)

![image](https://github.com/joetanx/hashicorp/assets/90442032/a114bda4-3f81-4c72-9313-0828fc16b355)

![image](https://github.com/joetanx/hashicorp/assets/90442032/d676b6c5-d4e1-4eeb-93d5-c267dc7e5c37)

## 4. OIDC + Keycloak

### 4.1. 📌 Keycloak - Setup authentication client

Select `Create client`

![image](https://github.com/joetanx/hashicorp/assets/90442032/0db9ca9f-52b8-4f15-aa03-ac26f6f77dd1)

Enter a `Client ID` (e.g. `https://<vault-fdqn>:8200/`), this is required for the Vault OIDC config later

![image](https://github.com/joetanx/hashicorp/assets/90442032/f40679ab-d13f-44fa-8eb4-c9c260be9a81)

- Enable `Client authentication`
- Only `Standard flow` (authorization code flow) is needed

![image](https://github.com/joetanx/hashicorp/assets/90442032/c247b867-46c0-4162-a541-ed4b9324556d)

- Enter `https://<vault-fqdn>:8200/` for `Root URL`
- Add `https://<vault-fqdn>:8250/oidc/callback` and `https://<vault-fqdn>:8200/ui/vault/auth/oidc/oidc/callback` for the `Valid redirect URIs`

![image](https://github.com/joetanx/hashicorp/assets/90442032/57f17d3f-28a5-402a-84b0-0681a6a1c073)

![image](https://github.com/joetanx/hashicorp/assets/90442032/f3271ebf-102f-42ee-a797-7bf6c224d11e)

Copy the `Client secret`, this is required for the Vault OIDC config later

![image](https://github.com/joetanx/hashicorp/assets/90442032/b7b5b468-90dc-45aa-8f62-e57e1db6fec8)

### 4.2. 📌 Vault - Setup Auth Method

Set the Keycloak IdP information to environment variable:

```console
[root@vault ~]# export KC_FQDN=keycloak.vx:8443
[root@vault ~]# export KC_CLIENT_ID=https://vault.vx:8200/
[root@vault ~]# export KC_CLIENT_SECRET=T8DWTP1glnDjQQVYivEJWLEhZs0jC3TU
```

Enable the OIDC auth method:

> [!Note]
>
> The auth method can also be mounted to a custom path using `vault auth enable -path=<path> oidc`

```console
[root@vault ~]# vault auth enable oidc
Success! Enabled oidc auth method at: oidc/
```

Configure the OIDC auth method:

> [!Note]
> 
> The metadata URL for Keycloak OIDC is at `https://<keycloak-fqdn>/realms/<realm-name>/.well-known/openid-configuration`, but the discovery URL is at `https://<keycloak-fqdn>/realms/<realm-name>`
>
> Browsing to the metadata URL will show the discovery URL under `issuer` field:
> 
> ```json
> {
>     "issuer": "https://keycloak.vx:8443/realms/master",
>     ...
> }
> ```

```console
[root@vault ~]# vault write auth/oidc/config \
oidc_discovery_url=https://$KC_FQDN/realms/master \
oidc_client_id=$KC_CLIENT_ID \
oidc_client_secret=$KC_CLIENT_SECRET \
default_role=reader
Success! Data written to: auth/oidc/config
```

Create `reader` role for the OIDC login users:

```console
[root@vault ~]# vault write auth/oidc/role/reader \
bound_audiences=$KC_CLIENT_ID \
allowed_redirect_uris=https://vault.vx:8200/ui/vault/auth/oidc/oidc/callback \
allowed_redirect_uris=https://vault.vx:8250/oidc/callback \
user_claim=preferred_username \
token_policies=reader
Success! Data written to: auth/oidc/role/reader
```

### 4.3. Test login

![image](https://github.com/joetanx/hashicorp/assets/90442032/9a7a05df-8a36-4f01-8b22-54c766c34e99)

![image](https://github.com/joetanx/hashicorp/assets/90442032/9b3aec39-1969-4e51-a204-6d79671c5519)

![image](https://github.com/joetanx/hashicorp/assets/90442032/61009ed2-77a0-47c0-b6ac-bb3de1f277bb)

![image](https://github.com/joetanx/hashicorp/assets/90442032/64e7ab6b-4342-4d39-8b1c-4a0bd75063bd)

![image](https://github.com/joetanx/hashicorp/assets/90442032/b6ef13d7-bba2-40eb-8454-1ccdc2b2ee71)

![image](https://github.com/joetanx/hashicorp/assets/90442032/3b6d4943-326f-4870-8f7d-cb596461f6aa)

![image](https://github.com/joetanx/hashicorp/assets/90442032/1ad3f2f8-b662-41d6-b4f8-a228d0360702)

![image](https://github.com/joetanx/hashicorp/assets/90442032/b1baf843-e9c8-45c6-a773-c824308959b6)
