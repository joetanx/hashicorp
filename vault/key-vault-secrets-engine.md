## 1. Enable the secrets engine and write the secrets

### 1.1. K/V Version 1

```console
[root@vault ~]# vault secrets enable -path=database kv
Success! Enabled the kv secrets engine at: database/
[root@vault ~]# vault secrets list
Path          Type         Accessor              Description
----          ----         --------              -----------
cubbyhole/    cubbyhole    cubbyhole_e3e6364d    per-token private secret storage
database/     kv           kv_9987612d           n/a
identity/     identity     identity_ab367d6b     identity store
sys/          system       system_6d121c48       system endpoints used for control, policy and debugging
[root@vault ~]# vault kv put -mount=database svr_1 address=sql_1.local username=db_user_1 password=Pass_1
Success! Data written to: database/svr_1
[root@vault ~]# vault kv put -mount=database svr_2 address=sql_2.local username=db_user_2 password=Pass_2
Success! Data written to: database/svr_2
```

### 1.2. K/V Version 2

```console
[root@vault ~]# vault secrets enable -path=database-v2 kv-v2
Success! Enabled the kv-v2 secrets engine at: database-v2/
[root@vault ~]# vault secrets list
Path            Type         Accessor              Description
----            ----         --------              -----------
cubbyhole/      cubbyhole    cubbyhole_e3e6364d    per-token private secret storage
database-v2/    kv           kv_54d12318           n/a
database/       kv           kv_9987612d           n/a
identity/       identity     identity_ab367d6b     identity store
sys/            system       system_6d121c48       system endpoints used for control, policy and debugging
[root@vault ~]# vault kv put -mount=database-v2 svr_1 address=sql_1.local username=db_user_1 password=Pass_1
===== Secret Path =====
database-v2/data/svr_1

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:11:06.964492241Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1
[root@vault ~]# vault kv put -mount=database-v2 svr_2 address=sql_2.local username=db_user_2 password=Pass_2
===== Secret Path =====
database-v2/data/svr_2

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:11:07.025483797Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1
```

## 2. Configure policies

|Operation|App 1|App 2|Db admin|Super user|
|---|---|---|---|---|
|Read Svr 1 secrets|✅|❌|❌|✅|
|Read Svr 2 secrets|❌|✅|❌|✅|
|List databases|❌|❌|✅|✅|

### 2.1. K/V Version 1

#### 2.1.1. Policy to allow read Svr 1 secrets:

```console
[root@vault ~]# vault policy write app_1 -<< EOF
path "database/svr_1" {
  capabilities = ["read"]
}
EOF
Success! Uploaded policy: app_1
```

#### 2.1.2. Policy to allow read Svr 2 secrets:

```console
[root@vault ~]# vault policy write app_2 -<< EOF
path "database/svr_2" {
  capabilities = ["read"]
}
EOF
Success! Uploaded policy: app_2
```

#### 2.1.3. Policy to allow list databases:

```console
[root@vault ~]# vault policy write db_admin -<< EOF
path "database" {
  capabilities = ["list"]
}
EOF
Success! Uploaded policy: db_admin
```

### 2.2. K/V Version 2

#### 2.2.1. Policy to allow read Svr 1 secrets:

```console
[root@vault ~]# vault policy write app_1_v2 -<< EOF
path "database-v2/data/svr_1" {
  capabilities = ["read"]
}
EOF
Success! Uploaded policy: app_1_v2
```

#### 2.2.2. Policy to allow read Svr 2 secrets:

```console
[root@vault ~]# vault policy write app_2_v2 -<< EOF
path "database-v2/data/svr_2" {
  capabilities = ["read"]
}
EOF
Success! Uploaded policy: app_2_v2
```

#### 2.2.3. Policy to allow list databases:

```console
[root@vault ~]# vault policy write db_admin_v2 -<< EOF
path "database-v2/metadata" {
  capabilities = ["list"]
}
EOF
Success! Uploaded policy: db_admin_v2
```

## 3. Create tokens to test access for each use case

### 3.1. K/V Version 1

#### 3.1.1. App 1

Create token with `app_1` policy and set in `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# export VAULT_TOKEN=$(vault token create -field=token -policy=app_1)
```

Read Svr 1 secrets ✅:

```console
[root@vault ~]# vault kv get -mount=database svr_1
====== Data ======
Key         Value
---         -----
address     sql_1.local
password    Pass_1
username    db_user_1
```

Read Svr 2 secrets ❌:

```console
[root@vault ~]# vault kv get -mount=database svr_2
Error reading database/svr_2: Error making API request.

URL: GET https://127.0.0.1:8200/v1/database/svr_2
Code: 403. Errors:

* 1 error occurred:
        * permission denied


```

List databases ❌:

```console
[root@vault ~]# vault kv list -mount=database /
Error listing database: Error making API request.

URL: GET https://127.0.0.1:8200/v1/database?list=true
Code: 403. Errors:

* 1 error occurred:
        * permission denied


```

Unset the `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# unset VAULT_TOKEN
```

#### 3.1.2. App 2

Create token with `app_2` policy and set in `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# export VAULT_TOKEN=$(vault token create -field=token -policy=app_2)
```

Read Svr 1 secrets ❌:

```console
[root@vault ~]# vault kv get -mount=database svr_1
Error reading database/svr_1: Error making API request.

URL: GET https://127.0.0.1:8200/v1/database/svr_1
Code: 403. Errors:

* 1 error occurred:
        * permission denied


```

Read Svr 2 secrets ✅:

```console
[root@vault ~]# vault kv get -mount=database svr_2
====== Data ======
Key         Value
---         -----
address     sql_2.local
password    Pass_2
username    db_user_2
```

List databases ❌:

```console
[root@vault ~]# vault kv list -mount=database /
Error listing database: Error making API request.

URL: GET https://127.0.0.1:8200/v1/database?list=true
Code: 403. Errors:

* 1 error occurred:
        * permission denied


```

Unset the `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# unset VAULT_TOKEN
```

#### 3.1.3. Db admin

Create token with `db_admin` policy and set in `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# export VAULT_TOKEN=$(vault token create -field=token -policy=db_admin)
```

Read Svr 1 secrets ❌:

```console
[root@vault ~]# vault kv get -mount=database svr_1
Error reading database/svr_1: Error making API request.

URL: GET https://127.0.0.1:8200/v1/database/svr_1
Code: 403. Errors:

* 1 error occurred:
        * permission denied


```

Read Svr 2 secrets ❌:

```console
[root@vault ~]# vault kv get -mount=database svr_2
Error reading database/svr_2: Error making API request.

URL: GET https://127.0.0.1:8200/v1/database/svr_2
Code: 403. Errors:

* 1 error occurred:
        * permission denied


```

List databases ✅:

```console
[root@vault ~]# vault kv list -mount=database /
Keys
----
svr_1
svr_2
```

Unset the `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# unset VAULT_TOKEN
```

#### 3.1.4. Super user

Create token with all `app_1`, `app_2` and `db_admin` policies and set in `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# export VAULT_TOKEN=$(vault token create -field=token -policy=app_1 -policy=app_2 -policy=db_admin)
```

Read Svr 1 secrets ✅:

```console
[root@vault ~]# vault kv get -mount=database svr_1
====== Data ======
Key         Value
---         -----
address     sql_1.local
password    Pass_1
username    db_user_1
```

Read Svr 2 secrets ✅:

```console
[root@vault ~]# vault kv get -mount=database svr_2
====== Data ======
Key         Value
---         -----
address     sql_2.local
password    Pass_2
username    db_user_2
```
List databases ✅:

```console
[root@vault ~]# vault kv list -mount=database /
Keys
----
svr_1
svr_2
```

Unset the `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# unset VAULT_TOKEN
```

### 3.2. K/V Version 2

#### 3.2.1. App 1

Create token with `app_1` policy and set in `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# export VAULT_TOKEN=$(vault token create -field=token -policy=app_1_v2)
```

Read Svr 1 secrets ✅:

```console
[root@vault ~]# vault kv get -mount=database-v2 svr_1
===== Secret Path =====
database-v2/data/svr_1

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:11:06.964492241Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

====== Data ======
Key         Value
---         -----
address     sql_1.local
password    Pass_1
username    db_user_1
```

Read Svr 2 secrets ❌:

```console
[root@vault ~]# vault kv get -mount=database-v2 svr_2
Error reading database-v2/data/svr_2: Error making API request.

URL: GET https://127.0.0.1:8200/v1/database-v2/data/svr_2
Code: 403. Errors:

* 1 error occurred:
        * permission denied


```

List databases ❌:

```console
[root@vault ~]# vault kv list -mount=database-v2 /
Error listing database-v2/metadata: Error making API request.

URL: GET https://127.0.0.1:8200/v1/database-v2/metadata?list=true
Code: 403. Errors:

* 1 error occurred:
        * permission denied


```

Unset the `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# unset VAULT_TOKEN
```

#### 3.2.2. App 2

Create token with `app_2` policy and set in `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# export VAULT_TOKEN=$(vault token create -field=token -policy=app_2_v2)
```

Read Svr 1 secrets ❌:

```console
[root@vault ~]# vault kv get -mount=database-v2 svr_1
Error reading database-v2/data/svr_1: Error making API request.

URL: GET https://127.0.0.1:8200/v1/database-v2/data/svr_1
Code: 403. Errors:

* 1 error occurred:
        * permission denied


```

Read Svr 2 secrets ✅:

```console
[root@vault ~]# vault kv get -mount=database-v2 svr_2
===== Secret Path =====
database-v2/data/svr_2

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:11:07.025483797Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

====== Data ======
Key         Value
---         -----
address     sql_2.local
password    Pass_2
username    db_user_2
```

List databases ❌:

```console
[root@vault ~]# vault kv list -mount=database-v2 /
Error listing database-v2/metadata: Error making API request.

URL: GET https://127.0.0.1:8200/v1/database-v2/metadata?list=true
Code: 403. Errors:

* 1 error occurred:
        * permission denied


```

Unset the `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# unset VAULT_TOKEN
```

#### 3.2.3. Db admin

Create token with `db_admin` policy and set in `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# export VAULT_TOKEN=$(vault token create -field=token -policy=db_admin_v2)
```

Read Svr 1 secrets ❌:

```console
[root@vault ~]# vault kv get -mount=database-v2 svr_1
Error reading database-v2/data/svr_1: Error making API request.

URL: GET https://127.0.0.1:8200/v1/database-v2/data/svr_1
Code: 403. Errors:

* 1 error occurred:
        * permission denied


```

Read Svr 2 secrets ❌:

```console
[root@vault ~]# vault kv get -mount=database-v2 svr_2
Error reading database-v2/data/svr_2: Error making API request.

URL: GET https://127.0.0.1:8200/v1/database-v2/data/svr_2
Code: 403. Errors:

* 1 error occurred:
        * permission denied


```

List databases ✅:

```console
[root@vault ~]# vault kv list -mount=database-v2 /
Keys
----
svr_1
svr_2
```

Unset the `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# unset VAULT_TOKEN
```

#### 3.2.4. Super user

Create token with all `app_1`, `app_2` and `db_admin` policies and set in `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# export VAULT_TOKEN=$(vault token create -field=token -policy=app_1_v2 -policy=app_2_v2 -policy=db_admin_v2)
```

Read Svr 1 secrets ✅:

```console
[root@vault ~]#
===== Secret Path =====
database-v2/data/svr_1

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:11:06.964492241Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

====== Data ======
Key         Value
---         -----
address     sql_1.local
password    Pass_1
username    db_user_1
```

Read Svr 2 secrets ✅:

```console
[root@vault ~]# vault kv get -mount=database-v2 svr_2
===== Secret Path =====
database-v2/data/svr_2

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:11:07.025483797Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

====== Data ======
Key         Value
---         -----
address     sql_2.local
password    Pass_2
username    db_user_2
```

List databases ✅:

```console
[root@vault ~]# vault kv list -mount=database-v2 /
Keys
----
svr_1
svr_2
```

Unset the `VAULT_TOKEN` environment variable:

```console
[root@vault ~]# unset VAULT_TOKEN
```

## 4. Versioned Key/Value Secrets Engine (for K/V Version 2)

Updating a secret with `put` method replaces the entire secret:

```console
[root@vault ~]# vault kv put -mount=database-v2 svr_1 wrong-method=oh-no
===== Secret Path =====
database-v2/data/svr_1

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:20:13.862742103Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            2
[root@vault ~]# vault kv get -mount=database-v2 svr_1
===== Secret Path =====
database-v2/data/svr_1

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:20:13.862742103Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            2

======== Data ========
Key             Value
---             -----
wrong-method    oh-no
```

In k/v v2, versioning retains the secret in earlier versions

```console
[root@vault ~]# vault kv get -mount=database-v2 -version=1 svr_1
===== Secret Path =====
database-v2/data/svr_1

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:11:06.964492241Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

====== Data ======
Key         Value
---         -----
address     sql_1.local
password    Pass_1
username    db_user_1
```

The correct method to update a secret value is `patch`:

```console
[root@vault ~]# vault kv patch -mount=database-v2 svr_2 password=Pass_2_New
===== Secret Path =====
database-v2/data/svr_2

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:21:24.77978352Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            2
[root@vault ~]# vault kv get -mount=database-v2 svr_2
===== Secret Path =====
database-v2/data/svr_2

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:21:24.77978352Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            2

====== Data ======
Key         Value
---         -----
address     sql_2.local
password    Pass_2_New
username    db_user_2
```

The `patch` method can also be used to add additional values to a secret:

```console
[root@vault ~]# vault kv patch -mount=database-v2 svr_2 comment=very-critical
===== Secret Path =====
database-v2/data/svr_2

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:21:52.258179216Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            3
[root@vault ~]# vault kv get -mount=database-v2 svr_2
===== Secret Path =====
database-v2/data/svr_2

======= Metadata =======
Key                Value
---                -----
created_time       2023-09-13T08:21:52.258179216Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            3

====== Data ======
Key         Value
---         -----
address     sql_2.local
comment     very-critical
password    Pass_2_New
username    db_user_2
```
