## 1. Preparation

### 1.1. 📌 Vault: create secrets and policies

The Jenkins pipelines requires the K/V v2 secrets and policies created in [Key/Value Secrets Engine](vault/key-vault-secrets-engine.md)

### 1.2. 📌 Vault: enable app role authentication method

> [!Note]
> 
> The authentication method can enabled on a customer path with `vault auth enable -path=<path> approle`
> 
> If the authentication method is on a custom path, update the `Path` parameter from `approle` to the custom when configuring the app role credentials in Jenkins later

```console
[root@vault ~]# vault auth enable approle
Success! Enabled approle auth method at: approle/
```

### 1.3. 📌 Jenkins: install vault plugin

![image](https://github.com/joetanx/hashicorp/assets/90442032/38c6efd8-693b-49af-af6d-d9b8a352a236)

## 2. Pipeline 1 - Generate Role and Secret IDs and use directly

### 2.1. 📌 Vault: create app role for pipeline 1 and get role and secret IDs

```console
[root@vault ~]# vault write auth/approle/role/pipeline_1 token_policies=app_1_v2 secret_id_num_uses=10  secret_id_ttl=5m token_ttl=5m token_max_ttl=10m
Success! Data written to: auth/approle/role/pipeline_1
[root@vault ~]# vault read auth/approle/role/pipeline_1/role-id
Key        Value
---        -----
role_id    a396dc60-97b3-b39d-fdab-969c8494ba6a
[root@vault ~]# vault write -force auth/approle/role/pipeline_1/secret-id
Key                   Value
---                   -----
secret_id             9e707c4a-7983-d139-24a8-b3c999dfede3
secret_id_accessor    f3727148-c9e3-802c-a56f-5b85ee757db3
secret_id_num_uses    10
secret_id_ttl         5m
```

### 2.2. 📌 Jenkins: store role and secret IDs for pipeline 1 in Jenkins credentials

![image](https://github.com/joetanx/hashicorp/assets/90442032/e1efea91-d9a1-4e46-b32e-4e8c841649ce)

![image](https://github.com/joetanx/hashicorp/assets/90442032/73efb794-86af-4f95-ba8d-85c45cdcf7ab)

### 2.3. 📌 Jenkins: Create pipeline

![image](https://github.com/joetanx/hashicorp/assets/90442032/2c02fc3f-65e9-4783-9014-0c6e9c1ff4dd)

### 2.3.1. Pipeline Example 1 - Using Vault Plugin

```groovy
def SECRETS = [
  [
    path: 'database-v2/svr_1',
    engineVersion: 2,
    secretValues: [
      [envVar: 'ADDRESS', vaultKey: 'address'],
      [envVar: 'USERNAME', vaultKey: 'username'],
      [envVar: 'PASSWORD', vaultKey: 'password']
    ]
  ]
]
def CONFIGURATION = [
  vaultUrl: 'https://vault.vx:8200',
  vaultCredentialId: 'pipeline_1',
  engineVersion: 2
]
pipeline {
  agent any
  stages{   
    stage('Vault') {
      steps {
        withVault([configuration: CONFIGURATION, vaultSecrets: SECRETS]) {
          sh 'echo $ADDRESS | base64'
          sh 'echo $USERNAME | base64'
          sh 'echo $PASSWORD | base64'
        }
      }
    }
  }
}
```

![image](https://github.com/joetanx/hashicorp/assets/90442032/62bced54-9cfd-4efd-841d-8e1b7a03813c)

The secret values are masked in Jenkins console output, the pipeline code pipes the secrets to `base64`, which can be decoded as below:

```console
[root@vault ~]# echo c3FsXzEubG9jYWwK | base64 -d
sql_1.local
[root@vault ~]# echo ZGJfdXNlcl8xCg== | base64 -d
db_user_1
[root@vault ~]# echo UGFzc18xCg== | base64 -d
Pass_1
```

### 2.3.2. Pipeline Example 2 - Using Vault CLI

```groovy
env.VAULT_ADDR = 'https://vault.vx:8200'
pipeline {
  agent any
  stages{
    stage('Vault') {
      steps {
        script {
          withCredentials([[$class: 'VaultTokenCredentialBinding', credentialsId: 'pipeline_1', vaultAddr: VAULT_ADDR]]) {
            env.ADDRESS=sh(
              returnStdout: true,
              script: 'vault kv get -field=address -mount=database-v2 svr_1'
            )
            env.USERNAME=sh(
              returnStdout: true,
              script: 'vault kv get -field=username -mount=database-v2 svr_1'
            )
            env.PASSWORD=sh(
              returnStdout: true,
              script: 'vault kv get -field=password -mount=database-v2 svr_1'
            )
          }
        }
        echo ADDRESS
        echo USERNAME
        echo PASSWORD
      }
    }
  }
}
```

![image](https://github.com/joetanx/hashicorp/assets/90442032/71d07356-0faa-496f-985d-9bc3e54db5bf)

## 3. Pipeline 2 - Response Wrapping

### 3.1. 📌 Vault: Create policy to allow wrapper to generate wrapped secret IDs

```console
[root@vault ~]# vault policy write wrapper -<< EOF
path "auth/approle/role/pipeline_2/secret-id" {
  policy = "write"
  min_wrapping_ttl   = "60s"
  max_wrapping_ttl   = "120s"
}
EOF
Success! Uploaded policy: wrapper
```

### 3.2. 📌 Vault: Create app role for wrapper and get role and secret IDs

```console
[root@vault ~]# vault write auth/approle/role/wrapper token_policies=wrapper
Success! Data written to: auth/approle/role/wrapper
[root@vault ~]# vault read auth/approle/role/wrapper/role-id
Key        Value
---        -----
role_id    ee8b991d-0c99-349c-da5a-bc7d1a27b131
[root@vault ~]# vault write -force auth/approle/role/wrapper/secret-id
Key                   Value
---                   -----
secret_id             a6dc3eb6-dcba-dce1-0f7a-e2f33134cb4c
secret_id_accessor    efe3b2e9-6125-dcc6-6e56-8ac97b82596e
secret_id_num_uses    0
secret_id_ttl         0s
```

### 3.3. 📌 Vault: Create app role for pipeline 2 and get role ID

```console
[root@vault ~]# vault write auth/approle/role/pipeline_2 token_policies=app_2_v2 secret_id_num_uses=1  secret_id_ttl=1m token_ttl=1m token_max_ttl=5m
Success! Data written to: auth/approle/role/pipeline_2
[root@vault ~]# vault read auth/approle/role/pipeline_2/role-id
Key        Value
---        -----
role_id    c4a2bb30-2abd-7f70-d945-c9fe3c36e41b
```

### 3.4. 📌 Jenkins: store role and secret IDs for wrapper in Jenkins credentials

![image](https://github.com/joetanx/hashicorp/assets/90442032/124ba06a-f00d-4e33-9838-986f3d5782b0)

### 3.5. 📌 Jenkins: Create pipeline

```groovy
env.PIPELINE_2_ROLE_ID = 'c4a2bb30-2abd-7f70-d945-c9fe3c36e41b'
env.VAULT_ADDR = 'https://vault.vx:8200'
pipeline {
  agent any
  stages{
    stage('Get wrapping token with wrapper') {
      steps {
        script {
          withCredentials([[$class: 'VaultTokenCredentialBinding', credentialsId: 'wrapper', vaultAddr: VAULT_ADDR]]) {
            env.WRAPPING_TOKEN=sh(
              returnStdout: true,
              script: 'vault write -field=wrapping_token -wrap-ttl=60s -force auth/approle/role/pipeline_2/secret-id'
            )
          }
        }
      }
    }
    stage('Unwrap wrapping token') {
      steps {
        script {
          env.PIPELINE_2_SECRET_ID=sh(
            returnStdout: true,
            script: 'VAULT_TOKEN=$WRAPPING_TOKEN vault unwrap -field=secret_id'
          )
        }
      }
    }
    stage('Login to vault') {
      steps {
        script {
          env.PIPELINE_2_VAULT_TOKEN=sh(
            returnStdout: true,
            script: 'vault write -field=token auth/approle/login role_id=$PIPELINE_2_ROLE_ID secret_id=$PIPELINE_2_SECRET_ID'
          )
        }
      }
    }
    stage('Retrieve secrets') {
      steps {
        sh 'VAULT_TOKEN=$PIPELINE_2_VAULT_TOKEN vault kv get -mount=database-v2 svr_2'
      }
    }
  }
}
```

![image](https://github.com/joetanx/hashicorp/assets/90442032/f1c9e070-ff02-4059-93a1-8e477275a1b8)
