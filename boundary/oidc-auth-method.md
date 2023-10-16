## 1. 📌 Keycloak - Setup authentication client

Select `Create client`

![image](https://github.com/joetanx/hashicorp/assets/90442032/222376f6-3763-4433-a762-d2366d2d7c9b)

Enter a `Client ID` (e.g. `https://<boundary-fdqn>:9200/`), this is required for the Vault OIDC config later

![image](https://github.com/joetanx/hashicorp/assets/90442032/2efe07c5-276a-4d27-96ec-440f097c25af)

- Enable `Client authentication`
- Only `Standard flow` (authorization code flow) is needed

![image](https://github.com/joetanx/hashicorp/assets/90442032/0398e724-e868-4f48-a195-19af0ffeaa87)

- Enter `https://<boundary-fdqn>:9200/` for `Root URL`
- Add `https://<boundary-fdqn>:9200/v1/auth-methods/oidc:authenticate:callback` for the `Valid redirect URIs`

![image](https://github.com/joetanx/hashicorp/assets/90442032/a8174253-919e-44a3-a966-b846653f8e70)

![image](https://github.com/joetanx/hashicorp/assets/90442032/1314b747-2914-4f7c-be10-15204216ab36)

Copy the `Client secret`, this is required for the Vault OIDC config later

![image](https://github.com/joetanx/hashicorp/assets/90442032/c1a6ac42-9085-47ae-b4a9-4b890ac0b1bf)

## 2. 📌 Keycloak - Configure group to be mapped to Boundary

![image](https://github.com/joetanx/hashicorp/assets/90442032/6900e71f-ed3d-4b37-a78e-506b3a670fee)

![image](https://github.com/joetanx/hashicorp/assets/90442032/2ac7dd7c-4332-4b26-87ef-f966da0f3409)

![image](https://github.com/joetanx/hashicorp/assets/90442032/b32d35b8-5681-4a82-87b5-608fa24c22b8)

![image](https://github.com/joetanx/hashicorp/assets/90442032/4a067f42-9cb0-4475-80d9-5cd5546734d3)

![image](https://github.com/joetanx/hashicorp/assets/90442032/d8867507-f4a5-44a2-ac87-2896f20077da)

## 3. 📌 Keycloak - Configure client scope

![image](https://github.com/joetanx/hashicorp/assets/90442032/76b04a25-34e7-401c-a83e-955c3ddb3557)

![image](https://github.com/joetanx/hashicorp/assets/90442032/73c97592-eebc-4bb7-9346-52a1a2b81933)

![image](https://github.com/joetanx/hashicorp/assets/90442032/4a10dd4d-a055-4441-8cb4-3bb6ce5a9be1)

![image](https://github.com/joetanx/hashicorp/assets/90442032/1fc29ca1-887d-4c43-b6e0-1d747580699b)

![image](https://github.com/joetanx/hashicorp/assets/90442032/fbee587c-891e-4d83-829b-d66499daf69a)

## 4. 📌 Keycloak - Add client scope

![image](https://github.com/joetanx/hashicorp/assets/90442032/781cca94-c8f2-434f-92a6-511bf7d0aec8)

![image](https://github.com/joetanx/hashicorp/assets/90442032/6557946f-a6b1-4b8b-88ac-052d8b4340fe)

## 5. 📌 Boundary - Setup Auth Method

Prepare Boundary CLI login information

```sh
export BOUNDARY_AUTH_METHOD_ID=$(grep 'Auth Method ID' /etc/boundary.d/init.log | cut -d ':' -f 2 | tr -d ' ')
export BOUNDARY_ADDR=https://boundary.vx:9200
export BOUNDARY_AUTHENTICATE_PASSWORD_LOGIN_NAME=admin
export BOUNDARY_AUTHENTICATE_PASSWORD_PASSWORD=$(grep Password /etc/boundary.d/init.log | cut -d ':' -f 2 | tr -d ' ')
export BOUNDARY_TOKEN=$(boundary authenticate password -password=env://BOUNDARY_AUTHENTICATE_PASSWORD_PASSWORD -keyring-type=none | grep at_)
```

Prepare parameters for auth-method configuration

```sh
export KC_FQDN=keycloak.vx:8443
export KC_CLIENT_ID=https://boundary.vx:9200/
export KC_CLIENT_SECRET=UHD0ARqXLOxgcoxJEP7lTNokph8iCdt6
```

Configure OIDC auth-method

```console
[root@boundary ~]# boundary auth-methods create oidc \
-issuer=https://$KC_FQDN/realms/master \
-client-id=$KC_CLIENT_ID \
-client-secret=$KC_CLIENT_SECRET \
-signing-algorithm=RS256 \
-api-url-prefix=$BOUNDARY_ADDR \
-name=keycloak \
-account-claim-maps=preferred_username=name

Auth Method information:
  Created Time:         Sun, 15 Oct 2023 21:27:20 +08
  ID:                   amoidc_ojJ7jX9OZY
  Name:                 keycloak
  Type:                 oidc
  Updated Time:         Sun, 15 Oct 2023 21:27:20 +08
  Version:              1

  Scope:
    ID:                 global
    Name:               global
    Type:               global

  Authorized Actions:
    no-op
    read
    update
    delete
    change-state
    authenticate

  Authorized Actions on Auth Method's Collections:
    accounts:
      create
      list
    managed-groups:
      create
      list

  Attributes:
    account_claim_maps: [preferred_username=name]
    api_url_prefix:     https://boundary.vx:9200
    callback_url:       https://boundary.vx:9200/v1/auth-methods/oidc:authenticate:callback
    client_id:          https://boundary.vx:9200/
    client_secret_hmac: usyZwt3l7_45vIDgRDAP0L4o-VbBpQ3ZC_sEULXG6_k
    issuer:             https://keycloak.vx:8443/realms/master
    signing_algorithms: [RS256]
    state:              inactive
```

Set auth-method to `active-public`

```console
[root@boundary ~]# boundary auth-methods change-state oidc -id amoidc_ojJ7jX9OZY -state active-public

Auth Method information:
  Created Time:         Sun, 15 Oct 2023 21:27:20 +08
  ID:                   amoidc_ojJ7jX9OZY
  Name:                 keycloak
  Type:                 oidc
  Updated Time:         Sun, 15 Oct 2023 21:28:17 +08
  Version:              2
  ⋮
  Attributes:
    ⋮
    state:              active-public
```

Set OIDC as primary auth-method

```console
[root@boundary ~]# boundary scopes update -primary-auth-method-id amoidc_ojJ7jX9OZY -id global

Scope information:
  Created Time:             Fri, 13 Oct 2023 11:45:42 +08
  Description:              Global Scope
  ID:                       global
  Name:                     global
  Primary Auth Method ID:   amoidc_ojJ7jX9OZY
  Updated Time:             Sun, 15 Oct 2023 21:29:56 +08
  Version:                  3

  Scope (parent):
    ID:                     global
    Name:                   global
    Type:                   global

  Authorized Actions:
    no-op
    read
    update
    delete

  Authorized Actions on Scope's Collections:
    auth-methods:
      create
      list
    auth-tokens:
      list
    groups:
      create
      list
    roles:
      create
      list
    scopes:
      create
      list
      list-keys
      rotate-keys
      list-key-version-destruction-jobs
      destroy-key-version
    session-recordings:
      list
    storage-buckets:
      create
      list
    users:
      create
      list
    workers:
      create:controller-led
      create:worker-led
      list
      read-certificate-authority
      reinitialize-certificate-authority
```

Create managed-group to dynamically add members who has `boundary-admins` in `groups` claim (i.e. members of boundary-admins group)

```console
[root@boundary ~]# boundary managed-groups create oidc -auth-method-id amoidc_ojJ7jX9OZY -filter '"boundary-admins" in "/token/groups"' -description "Boundary Admins from Keycloak"

Managed Group information:
  Auth Method ID:      amoidc_ojJ7jX9OZY
  Created Time:        Sun, 15 Oct 2023 21:31:00 +08
  Description:         Boundary Admins from Keycloak
  ID:                  mgoidc_0mB6AcAyKf
  Type:                oidc
  Updated Time:        Sun, 15 Oct 2023 21:31:00 +08
  Version:             1

  Scope:
    ID:                global
    Name:              global
    Type:              global

  Authorized Actions:
    no-op
    read
    update
    delete

  Attributes:
    Filter:            "boundary-admins" in "/token/groups"
```

List roles to get ID of `Administration` role

```console
[root@boundary ~]# boundary roles list

Role information:
  ID:                    r_1tpbWaXVek
    Version:             3
    Name:                Login and Default Grants
    Description:         Role created for login capability, account self-management, and other default grants for users of the global scope at its creation time
    Authorized Actions:
      no-op
      read
      update
      delete
      add-principals
      set-principals
      remove-principals
      add-grants
      set-grants
      remove-grants

  ID:                    r_Li36Z1HClm
    Version:             3
    Name:                Administration
    Description:         Provides admin grants within the "global" scope to the initial user
    Authorized Actions:
      no-op
      read
      update
      delete
      add-principals
      set-principals
      remove-principals
      add-grants
      set-grants
      remove-grants
```

Add the `boundary-admins` managed group to `Administration` role

```console
[root@vault ~]# boundary roles add-principals -id r_Li36Z1HClm -principal=mgoidc_0mB6AcAyKf

Role information:
  Created Time:        Fri, 13 Oct 2023 11:45:44 +08
  Description:         Provides admin grants within the "global" scope to the initial user
  Grant Scope ID:      global
  ID:                  r_Li36Z1HClm
  Name:                Administration
  Updated Time:        Sun, 15 Oct 2023 21:34:06 +08
  Version:             4

  Scope:
    ID:                global
    Name:              global
    Type:              global

  Authorized Actions:
    no-op
    read
    update
    delete
    add-principals
    set-principals
    remove-principals
    add-grants
    set-grants
    remove-grants

  Principals:
    ID:             mgoidc_0mB6AcAyKf
      Type:         managed group
      Scope ID:     global
    ID:             u_jDFaLiTF5I
      Type:         user
      Scope ID:     global

  Canonical Grants:
    id=*;type=*;actions=*
```

## 6. 📌 Boundary - Test login

![image](https://github.com/joetanx/hashicorp/assets/90442032/7a46f9d3-c7be-4339-8b29-e6ee05c5c0ce)

![image](https://github.com/joetanx/hashicorp/assets/90442032/c6a1fe44-5aa7-4078-a502-acdc2be992e1)

![image](https://github.com/joetanx/hashicorp/assets/90442032/9a457fa0-8b57-4709-9df6-f00ba6f5b1a6)

![image](https://github.com/joetanx/hashicorp/assets/90442032/2d6ff088-d7e3-4ef4-a1db-802f6b56acb5)

![image](https://github.com/joetanx/hashicorp/assets/90442032/a90d277a-b7af-4b8e-8a94-8f3f1914da74)

Verify claims of logged in user

> [!Note]
>
> If `Add to userinfo` was selected when creating the client scope mapping, the `groups` claims will also appear under `userinfo_claims:`
>
> The managed group configuration can then also use `-filter '"boundary-admins" in "/userinfo/groups"'` to pick up the group membership

```console
[root@boundary ~]# boundary accounts list -auth-method-id amoidc_ojJ7jX9OZY

Account information:
  ID:                    acctoidc_B0ylthFifc
    Version:             1
    Type:                oidc
    Authorized Actions:
      no-op
      read
      update
      delete
[root@vault ~]# boundary accounts read -id acctoidc_B0ylthFifc
[root@boundary ~]# boundary accounts read -id acctoidc_B0ylthFifc

Account information:
  Auth Method ID:      amoidc_ojJ7jX9OZY
  Created Time:        Sun, 15 Oct 2023 21:41:51 +08
  ID:                  acctoidc_B0ylthFifc
  Type:                oidc
  Updated Time:        Sun, 15 Oct 2023 21:41:51 +08
  Version:             1

  Scope:
    ID:                global
    Name:              global
    Type:              global

  Managed Group IDs:
    mgoidc_0mB6AcAyKf

  Authorized Actions:
    no-op
    read
    update
    delete

  Attributes:
    full_name:         joe.tan
    issuer:            https://keycloak.vx:8443/realms/master
    subject:           80d3aeb7-47f9-446d-9070-df4011d5876f
    token_claims:
    {
    "acr": "1",
    "at_hash": "SrijnJ88tx2dgn3lBkBeLA",
    "aud": "https://boundary.vx:9200/",
    "auth_time": 1697377311,
    "azp": "https://boundary.vx:9200/",
    "email_verified": false,
    "exp": 1697377371,
    "groups": [
    "boundary-admins"
    ],
    "iat": 1697377311,
    "iss": "https://keycloak.vx:8443/realms/master",
    "jti": "6f63b5c2-af17-4b60-9eb7-6f5bbfffa031",
    "nonce": "EgvFHZK9XbKp7yAfBABB",
    "preferred_username": "joe.tan",
    "session_state": "444bd2e6-e41a-4425-9bea-108a98ab86eb",
    "sid": "444bd2e6-e41a-4425-9bea-108a98ab86eb",
    "sub": "80d3aeb7-47f9-446d-9070-df4011d5876f",
    "typ": "ID"
    }
    userinfo_claims:
    {
    "email_verified": false,
    "preferred_username": "joe.tan",
    "sub": "80d3aeb7-47f9-446d-9070-df4011d5876f"
    }
```
