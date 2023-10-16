## 1. Enable auth/kubernetes method

> [!Note]
>
> Vault runs external to the Kubernetes cluster

Ref: https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-external-vault

```console
[root@vault ~]# vault auth enable kubernetes
Success! Enabled jwt auth method at: kubernetes/
```

## 2. Install vault helm chart in the Kubernetes cluster

Install the vault helm chart with `global.externalVaultAddr` set to the vault URL

Optional:
- Use `--namespace` to specify the namespace to install to
- Use `--dry-run` to preview the changes before actual deployment

```console
[root@kube ~]# helm repo add hashicorp https://helm.releases.hashicorp.com
"hashicorp" has been added to your repositories
[root@kube ~]# helm install vault hashicorp/vault --set "global.externalVaultAddr=https://vault.vx:8200"
NAME: vault
LAST DEPLOYED: Sun Sep 24 08:03:04 2023
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Thank you for installing HashiCorp Vault!

Now that you have deployed Vault, you should look over the docs on using
Vault with Kubernetes available here:

https://www.vaultproject.io/docs/


Your release is named vault. To learn more about the release, try:

  $ helm status vault
  $ helm get manifest vault
[root@kube ~]# kubectl get pods
NAME                                    READY   STATUS    RESTARTS   AGE
vault-agent-injector-6b45644b98-pwdrc   1/1     Running   0          22s
```

## 3. Configure the auth method (option 1) - using long-lived tokens

Ref: https://developer.hashicorp.com/vault/docs/auth/kubernetes#continue-using-long-lived-tokens

### 3.1. Create long-live token secret for `vault` service account

Token secret manifest example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vault-token
  annotations:
    kubernetes.io/service-account.name: vault
type: kubernetes.io/service-account-token
```

> [!Note]
>
> The `vault` service account would have already been granted rights to `system:auth-delegator` ClusterRole when deployed with the vault helm chart
>
> To create a separate service account, use the example manifest below:
> 
> ```yaml
> apiVersion: v1
> kind: ServiceAccount
> metadata:
>   name: <sa-name>
> ---
> apiVersion: rbac.authorization.k8s.io/v1
> kind: ClusterRoleBinding
> metadata:
>   name: role-tokenreview-binding
> roleRef:
>   apiGroup: rbac.authorization.k8s.io
>   kind: ClusterRole
>   name: system:auth-delegator
> subjects:
> - kind: ServiceAccount
>   name: <sa-name>
>   namespace: <sa-namespace>
> ```

### 3.2. Retrieve Kubernetes information required to configure the auth method

```sh
TOKEN_REVIEW_JWT=$(kubectl get secret <vault-sa-name> -o jsonpath={.data.token} | base64 -d)
KUBE_CA_CERT=$(kubectl config view --raw -o jsonpath={.clusters[].cluster.certificate-authority-data} | base64 -d)
KUBE_HOST=$(kubectl config view --raw -o jsonpath={.clusters[].cluster.server})
ISSUER=$(kubectl get --raw /.well-known/openid-configuration | jq -r '.issuer')
```

### 3.3. Configure the auth method

```sh
vault write auth/kubernetes/config \
token_reviewer_jwt=$TOKEN_REVIEW_JWT \
kubernetes_host=$KUBE_HOST \
kubernetes_ca_cert="$KUBE_CA_CERT" \
issuer=$ISSUER
```

### 3.4. Test integration

The test pod access secrets created in [section 3.1.2.](#312-kv-version-2) and uses the policies configured in created in [section 3.2.2.](#322-kv-version-2)

#### 3.4.1. Create a test role

```sh
vault write auth/kubernetes/role/test \
bound_service_account_names=test \
bound_service_account_namespaces=default \
policies=app_1_v2 \
ttl=1h
```

#### 3.4.2. Deploy test pods

If the vault uses TLS and is signed by a private CA, create the issuer CA in a Kubernetes secret

The vault annotations will reference this secret for the vault client to verify vault certificate

Example:

```sh
curl -sLO https://github.com/joetanx/lab-certs/raw/main/ca/lab_issuer.pem
kubectl create secret generic vault-tls --from-file=ca-bundle.crt=./lab_issuer.pem
```

Test pod example:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: test
---
apiVersion: v1
kind: Pod
metadata:
  name: test
  labels:
    app: test
  annotations:
    # https://developer.hashicorp.com/vault/docs/platform/k8s/injector/annotations
    vault.hashicorp.com/agent-inject: 'true'
    vault.hashicorp.com/agent-inject-status: 'update'
    vault.hashicorp.com/auth-type: 'kubernetes'
    vault.hashicorp.com/auth-path: 'auth/kubernetes'
    vault.hashicorp.com/namespace: 'default'
    vault.hashicorp.com/role: 'test'
    # secrets are mounted at '/vault/secrets/', the string behind 'agent-inject-secret-' is the name of the file
    vault.hashicorp.com/agent-inject-secret-credentials.txt: 'database-v2/data/svr_1'
    vault.hashicorp.com/ca-cert: /vault/tls/ca-bundle.crt
    vault.hashicorp.com/tls-secret: vault-tls
spec:
  serviceAccountName: test
  containers:
    - name: app
      image: nginx:alpine
      volumeMounts:
        - mountPath: /var/run/secrets/tokens
          name: oidc-token
        - mountPath: /vault/tls
          name: vault-tls
  volumes:
    - name: oidc-token
      projected:
        sources:
          - serviceAccountToken:
              path: oidc-token
              expirationSeconds: 7200
              audience: vault
    - name: vault-tls
      secret:
        secretName: vault-tls
```

#### 3.4.3. Verify test pods access

```console
[root@kube ~]# kubectl exec test -- cat /vault/secrets/credentials.txt
Defaulted container "app" out of: app, vault-agent, vault-agent-init (init)
data: map[address:sql_1.local password:Pass_1 username:db_user_1]
metadata: map[created_time:2023-09-25T14:06:24.420075926Z custom_metadata:<nil> deletion_time: destroyed:false version:1]
```

<details><summary>Verify vault agent init</summary>

```console
[root@kube ~]# kubectl logs test -c vault-agent-init
==> Note: Vault Agent version does not match Vault server version. Vault Agent version: 1.14.0, Vault server version: 1.14.2
==> Vault Agent started! Log data will stream in below:

==> Vault Agent configuration:

           Api Address 1: http://bufconn
                     Cgo: disabled
               Log Level: info
                 Version: Vault v1.14.0, built 2023-06-19T11:40:23Z
             Version Sha: 13a649f860186dffe3f3a4459814d87191efc321

2023-09-25T14:08:30.050Z [INFO]  agent.sink.file: creating file sink
2023-09-25T14:08:30.050Z [INFO]  agent.sink.file: file sink configured: path=/home/vault/.vault-token mode=-rw-r-----
2023-09-25T14:08:30.050Z [INFO]  agent.sink.server: starting sink server
2023-09-25T14:08:30.050Z [INFO]  agent.exec.server: starting exec server
2023-09-25T14:08:30.050Z [INFO]  agent.exec.server: no env templates or exec config, exiting
2023-09-25T14:08:30.050Z [INFO]  agent.template.server: starting template server
2023-09-25T14:08:30.050Z [INFO] (runner) creating new runner (dry: false, once: false)
2023-09-25T14:08:30.050Z [INFO]  agent.auth.handler: starting auth handler
2023-09-25T14:08:30.050Z [INFO]  agent.auth.handler: authenticating
2023-09-25T14:08:30.050Z [INFO] (runner) creating watcher
2023-09-25T14:08:30.069Z [INFO]  agent.auth.handler: authentication successful, sending token to sinks
2023-09-25T14:08:30.069Z [INFO]  agent.auth.handler: starting renewal process
2023-09-25T14:08:30.069Z [INFO]  agent.sink.file: token written: path=/home/vault/.vault-token
2023-09-25T14:08:30.069Z [INFO]  agent.sink.server: sink server stopped
2023-09-25T14:08:30.069Z [INFO]  agent: sinks finished, exiting
2023-09-25T14:08:30.069Z [INFO]  agent.template.server: template server received new token
2023-09-25T14:08:30.069Z [INFO] (runner) stopping
2023-09-25T14:08:30.069Z [INFO] (runner) creating new runner (dry: false, once: false)
2023-09-25T14:08:30.069Z [INFO] (runner) creating watcher
2023-09-25T14:08:30.069Z [INFO] (runner) starting
2023-09-25T14:08:30.070Z [INFO]  agent.auth.handler: renewed auth token
2023-09-25T14:08:30.077Z [INFO] (runner) rendered "(dynamic)" => "/vault/secrets/credentials.txt"
2023-09-25T14:08:30.077Z [INFO] (runner) stopping
2023-09-25T14:08:30.077Z [INFO]  agent.template.server: template server stopped
2023-09-25T14:08:30.077Z [INFO] (runner) received finish
2023-09-25T14:08:30.077Z [INFO]  agent.auth.handler: shutdown triggered, stopping lifetime watcher
2023-09-25T14:08:30.077Z [INFO]  agent.auth.handler: auth handler stopped
2023-09-25T14:08:30.077Z [INFO]  agent.exec.server: exec server stopped
```

</details>

<details><summary>Details on the resultant deployment mutated by the vault annotations</summary>

The vault annotations mutates the pod configuration:
- `vault.hashicorp.com/agent-inject: true` adds the `vault-agent-init` init container that retrieves the secrets before the app container starts
- `vault.hashicorp.com/agent-inject-status: 'update'` adds the `vault-agent` sidecar container that runs alongside the app container to update the secrets if there are any changes

```console
[root@kube ~]# kubectl describe pods test
⋮
Init Containers:
  vault-agent-init:
    Container ID:  cri-o://9ce379a78fe7a56e4797997e08132fb379a22dcc05e32a09ea217e859916b78b
    Image:         hashicorp/vault:1.14.0
    ⋮
    Environment:
      VAULT_LOG_LEVEL:   info
      VAULT_LOG_FORMAT:  standard
      VAULT_CONFIG:      eyJhdXRvX2F1dGgiOnsibWV0aG9kIjp7InR5cGUiOiJrdWJlcm5ldGVzIiwibW91bnRfcGF0aCI6ImF1dGgva3ViZXJuZXRlcyIsIm5hbWVzcGFjZSI6ImRlZmF1bHQiLCJjb25maWciOnsicm9sZSI6InRlc3QiLCJ0b2tlbl9wYXRoIjoiL3Zhci9ydW4vc2VjcmV0cy9rdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3Rva2VuIn19LCJzaW5rIjpbeyJ0eXBlIjoiZmlsZSIsImNvbmZpZyI6eyJwYXRoIjoiL2hvbWUvdmF1bHQvLnZhdWx0LXRva2VuIn19XX0sImV4aXRfYWZ0ZXJfYXV0aCI6dHJ1ZSwicGlkX2ZpbGUiOiIvaG9tZS92YXVsdC8ucGlkIiwidmF1bHQiOnsiYWRkcmVzcyI6Imh0dHBzOi8vdmF1bHQudng6ODIwMCIsImNhX2NlcnQiOiIvdmF1bHQvdGxzL2NhLWJ1bmRsZS5jcnQifSwidGVtcGxhdGUiOlt7ImRlc3RpbmF0aW9uIjoiL3ZhdWx0L3NlY3JldHMvY3JlZGVudGlhbHMudHh0IiwiY29udGVudHMiOiJ7eyB3aXRoIHNlY3JldCBcImRhdGFiYXNlLXYyL2RhdGEvc3ZyXzFcIiB9fXt7IHJhbmdlICRrLCAkdiA6PSAuRGF0YSB9fXt7ICRrIH19OiB7eyAkdiB9fVxue3sgZW5kIH19e3sgZW5kIH19IiwibGVmdF9kZWxpbWl0ZXIiOiJ7eyIsInJpZ2h0X2RlbGltaXRlciI6In19In1dLCJ0ZW1wbGF0ZV9jb25maWciOnsiZXhpdF9vbl9yZXRyeV9mYWlsdXJlIjp0cnVlfX0=
    Mounts:
      /home/vault from home-init (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-6jbgh (ro)
      /vault/secrets from vault-secrets (rw)
      /vault/tls from vault-tls-secrets (ro)
Containers:
  app:
    Container ID:   cri-o://afaee8b17080f0e3292f9ce64598d288abf37a91c486eb5ec56dcd35b9c83752
    Image:          nginx:alpine
    ⋮
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-6jbgh (ro)
      /var/run/secrets/tokens from oidc-token (rw)
      /vault/secrets from vault-secrets (rw)
      /vault/tls from vault-tls (rw)
  vault-agent:
    Container ID:  cri-o://722899519fccde06139ed9096338b8a6eddfd6d8502a492c55134c6c8e366cff
    Image:         hashicorp/vault:1.14.0
   ⋮
    Environment:
      VAULT_LOG_LEVEL:   info
      VAULT_LOG_FORMAT:  standard
      VAULT_CONFIG:      eyJhdXRvX2F1dGgiOnsibWV0aG9kIjp7InR5cGUiOiJrdWJlcm5ldGVzIiwibW91bnRfcGF0aCI6ImF1dGgva3ViZXJuZXRlcyIsIm5hbWVzcGFjZSI6ImRlZmF1bHQiLCJjb25maWciOnsicm9sZSI6InRlc3QiLCJ0b2tlbl9wYXRoIjoiL3Zhci9ydW4vc2VjcmV0cy9rdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3Rva2VuIn19LCJzaW5rIjpbeyJ0eXBlIjoiZmlsZSIsImNvbmZpZyI6eyJwYXRoIjoiL2hvbWUvdmF1bHQvLnZhdWx0LXRva2VuIn19XX0sImV4aXRfYWZ0ZXJfYXV0aCI6ZmFsc2UsInBpZF9maWxlIjoiL2hvbWUvdmF1bHQvLnBpZCIsInZhdWx0Ijp7ImFkZHJlc3MiOiJodHRwczovL3ZhdWx0LnZ4OjgyMDAiLCJjYV9jZXJ0IjoiL3ZhdWx0L3Rscy9jYS1idW5kbGUuY3J0In0sInRlbXBsYXRlIjpbeyJkZXN0aW5hdGlvbiI6Ii92YXVsdC9zZWNyZXRzL2NyZWRlbnRpYWxzLnR4dCIsImNvbnRlbnRzIjoie3sgd2l0aCBzZWNyZXQgXCJkYXRhYmFzZS12Mi9kYXRhL3N2cl8xXCIgfX17eyByYW5nZSAkaywgJHYgOj0gLkRhdGEgfX17eyAkayB9fToge3sgJHYgfX1cbnt7IGVuZCB9fXt7IGVuZCB9fSIsImxlZnRfZGVsaW1pdGVyIjoie3siLCJyaWdodF9kZWxpbWl0ZXIiOiJ9fSJ9XSwidGVtcGxhdGVfY29uZmlnIjp7ImV4aXRfb25fcmV0cnlfZmFpbHVyZSI6dHJ1ZX19
    Mounts:
      /home/vault from home-sidecar (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-6jbgh (ro)
      /vault/secrets from vault-secrets (rw)
      /vault/tls from vault-tls-secrets (ro)
Conditions:
  Type              Status
  Initialized       True
  Ready             True
  ContainersReady   True
  PodScheduled      True
Volumes:
  oidc-token:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  7200
  vault-tls:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  vault-tls
    Optional:    false
  kube-api-access-6jbgh:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
  home-init:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:     Memory
    SizeLimit:  <unset>
  home-sidecar:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:     Memory
    SizeLimit:  <unset>
  vault-secrets:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:     Memory
    SizeLimit:  <unset>
  vault-tls-secrets:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  vault-tls
    Optional:    false
⋮
```

</details>

## 4. Configure the auth method (option 2) - using the Vault client's JWT as the reviewer JWT

Ref: https://developer.hashicorp.com/vault/docs/auth/kubernetes#use-the-vault-client-s-jwt-as-the-reviewer-jwt

### 4.1. Retrieve Kubernetes information required to configure the auth method

```sh
KUBE_CA_CERT=$(kubectl config view --raw -o jsonpath={.clusters[].cluster.certificate-authority-data} | base64 -d)
KUBE_HOST=$(kubectl config view --raw -o jsonpath={.clusters[].cluster.server})
ISSUER=$(kubectl get --raw /.well-known/openid-configuration | jq -r '.issuer')
```

### 4.2. Configure the auth method

```sh
vault write auth/kubernetes/config \
kubernetes_host=$KUBE_HOST \
kubernetes_ca_cert="$KUBE_CA_CERT" \
issuer=$ISSUER
```

### 4.3. Test integration

The test pod access secrets created in [section 3.1.2.](#312-kv-version-2) and uses the policies configured in created in [section 3.2.2.](#322-kv-version-2)

#### 4.3.1. Create a test role

```sh
vault write auth/kubernetes/role/test \
bound_service_account_names=test \
bound_service_account_namespaces=default \
policies=app_1_v2 \
ttl=1h
```

#### 4.3.2. Deploy test pods

If the vault uses TLS and is signed by a private CA, create the issuer CA in a Kubernetes secret

The vault annotations will reference this secret for the vault client to verify vault certificate

Example:

```sh
curl -sLO https://github.com/joetanx/lab-certs/raw/main/ca/lab_issuer.pem
kubectl create secret generic vault-tls --from-file=ca-bundle.crt=./lab_issuer.pem
```

Test pod example:

> [!Note]
>
> Notice that the `test` service account is granted rights to `system:auth-delegator` ClusterRole
>
> Using the vault client's JWT as the reviewer JWT offers short-lived credentials to be used for reviewer JWT, but it also means each service account of the pod/deployment needs to be granted rights to `system:auth-delegator` ClusterRole
>
> Compare this to [Section 6.3.1](#631-create-long-live-token-secret-for-vault-service-account) where only the `vault` service account is granted rights to `system:auth-delegator` ClusterRole

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: test
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: test
  namespace: default
---
apiVersion: v1
kind: Pod
metadata:
  name: test
  labels:
    app: test
  annotations:
    # https://developer.hashicorp.com/vault/docs/platform/k8s/injector/annotations
    vault.hashicorp.com/agent-inject: 'true'
    vault.hashicorp.com/agent-inject-status: 'update'
    vault.hashicorp.com/auth-type: 'kubernetes'
    vault.hashicorp.com/auth-path: 'auth/kubernetes'
    vault.hashicorp.com/namespace: 'default'
    vault.hashicorp.com/role: 'test'
    # secrets are mounted at '/vault/secrets/', the string behind 'agent-inject-secret-' is the name of the file
    vault.hashicorp.com/agent-inject-secret-credentials.txt: 'database-v2/data/svr_1'
    vault.hashicorp.com/ca-cert: /vault/tls/ca-bundle.crt
    vault.hashicorp.com/tls-secret: vault-tls
spec:
  serviceAccountName: test
  containers:
    - name: app
      image: nginx:alpine
      volumeMounts:
        - mountPath: /var/run/secrets/tokens
          name: oidc-token
        - mountPath: /vault/tls
          name: vault-tls
  volumes:
    - name: oidc-token
      projected:
        sources:
          - serviceAccountToken:
              path: oidc-token
              expirationSeconds: 7200
              audience: vault
    - name: vault-tls
      secret:
        secretName: vault-tls
```

#### 4.3.3. Verify test pods access

```console
[root@kube ~]# kubectl exec test -- cat /vault/secrets/credentials.txt
Defaulted container "app" out of: app, vault-agent, vault-agent-init (init)
data: map[address:sql_1.local password:Pass_1 username:db_user_1]
metadata: map[created_time:2023-09-25T14:18:44.512967141Z custom_metadata:<nil> deletion_time: destroyed:false version:1]
```

<details><summary>Verify vault agent init</summary>

```console
[root@kube ~]kubectl logs test -c vault-agent-initit
==> Note: Vault Agent version does not match Vault server version. Vault Agent version: 1.14.0, Vault server version: 1.14.2
==> Vault Agent started! Log data will stream in below:

==> Vault Agent configuration:

           Api Address 1: http://bufconn
                     Cgo: disabled
               Log Level: info
                 Version: Vault v1.14.0, built 2023-06-19T11:40:23Z
             Version Sha: 13a649f860186dffe3f3a4459814d87191efc321

2023-09-25T14:26:05.541Z [INFO]  agent.sink.file: creating file sink
2023-09-25T14:26:05.541Z [INFO]  agent.sink.file: file sink configured: path=/home/vault/.vault-token mode=-rw-r-----
2023-09-25T14:26:05.541Z [INFO]  agent.exec.server: starting exec server
2023-09-25T14:26:05.541Z [INFO]  agent.exec.server: no env templates or exec config, exiting
2023-09-25T14:26:05.541Z [INFO]  agent.auth.handler: starting auth handler
2023-09-25T14:26:05.541Z [INFO]  agent.auth.handler: authenticating
2023-09-25T14:26:05.541Z [INFO]  agent.template.server: starting template server
2023-09-25T14:26:05.541Z [INFO] (runner) creating new runner (dry: false, once: false)
2023-09-25T14:26:05.541Z [INFO]  agent.sink.server: starting sink server
2023-09-25T14:26:05.541Z [INFO] (runner) creating watcher
2023-09-25T14:26:05.553Z [INFO]  agent.auth.handler: authentication successful, sending token to sinks
2023-09-25T14:26:05.553Z [INFO]  agent.auth.handler: starting renewal process
2023-09-25T14:26:05.553Z [INFO]  agent.sink.file: token written: path=/home/vault/.vault-token
2023-09-25T14:26:05.553Z [INFO]  agent.template.server: template server received new token
2023-09-25T14:26:05.553Z [INFO] (runner) stopping
2023-09-25T14:26:05.553Z [INFO] (runner) creating new runner (dry: false, once: false)
2023-09-25T14:26:05.553Z [INFO]  agent.sink.server: sink server stopped
2023-09-25T14:26:05.553Z [INFO]  agent: sinks finished, exiting
2023-09-25T14:26:05.553Z [INFO] (runner) creating watcher
2023-09-25T14:26:05.553Z [INFO] (runner) starting
2023-09-25T14:26:05.554Z [INFO]  agent.auth.handler: renewed auth token
2023-09-25T14:26:05.561Z [INFO] (runner) rendered "(dynamic)" => "/vault/secrets/credentials.txt"
2023-09-25T14:26:05.561Z [INFO] (runner) stopping
2023-09-25T14:26:05.561Z [INFO]  agent.template.server: template server stopped
2023-09-25T14:26:05.561Z [INFO] (runner) received finish
2023-09-25T14:26:05.561Z [INFO]  agent.auth.handler: shutdown triggered, stopping lifetime watcher
2023-09-25T14:26:05.561Z [INFO]  agent.auth.handler: auth handler stopped
2023-09-25T14:26:05.561Z [INFO]  agent.exec.server: exec server stopped
```

</details>

<details><summary>Details on the resultant deployment mutated by the vault annotations</summary>

The vault annotations mutates the pod configuration:
- `vault.hashicorp.com/agent-inject: true` adds the `vault-agent-init` init container that retrieves the secrets before the app container starts
- `vault.hashicorp.com/agent-inject-status: 'update'` adds the `vault-agent` sidecar container that runs alongside the app container to update the secrets if there are any changes

```console
[root@kube ~]# kubectl describe pods test
⋮
Init Containers:
  vault-agent-init:
    Container ID:  cri-o://1ae564ecd416c03f3c8fc0eb4707493bb0af834eaf8a5218aaae041e9153fdc0
    Image:         hashicorp/vault:1.14.0
    ⋮
    Environment:
      VAULT_LOG_LEVEL:   info
      VAULT_LOG_FORMAT:  standard
      VAULT_CONFIG:      eyJhdXRvX2F1dGgiOnsibWV0aG9kIjp7InR5cGUiOiJrdWJlcm5ldGVzIiwibW91bnRfcGF0aCI6ImF1dGgva3ViZXJuZXRlcyIsIm5hbWVzcGFjZSI6ImRlZmF1bHQiLCJjb25maWciOnsicm9sZSI6InRlc3QiLCJ0b2tlbl9wYXRoIjoiL3Zhci9ydW4vc2VjcmV0cy9rdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3Rva2VuIn19LCJzaW5rIjpbeyJ0eXBlIjoiZmlsZSIsImNvbmZpZyI6eyJwYXRoIjoiL2hvbWUvdmF1bHQvLnZhdWx0LXRva2VuIn19XX0sImV4aXRfYWZ0ZXJfYXV0aCI6dHJ1ZSwicGlkX2ZpbGUiOiIvaG9tZS92YXVsdC8ucGlkIiwidmF1bHQiOnsiYWRkcmVzcyI6Imh0dHBzOi8vdmF1bHQudng6ODIwMCIsImNhX2NlcnQiOiIvdmF1bHQvdGxzL2NhLWJ1bmRsZS5jcnQifSwidGVtcGxhdGUiOlt7ImRlc3RpbmF0aW9uIjoiL3ZhdWx0L3NlY3JldHMvY3JlZGVudGlhbHMudHh0IiwiY29udGVudHMiOiJ7eyB3aXRoIHNlY3JldCBcImRhdGFiYXNlLXYyL2RhdGEvc3ZyXzFcIiB9fXt7IHJhbmdlICRrLCAkdiA6PSAuRGF0YSB9fXt7ICRrIH19OiB7eyAkdiB9fVxue3sgZW5kIH19e3sgZW5kIH19IiwibGVmdF9kZWxpbWl0ZXIiOiJ7eyIsInJpZ2h0X2RlbGltaXRlciI6In19In1dLCJ0ZW1wbGF0ZV9jb25maWciOnsiZXhpdF9vbl9yZXRyeV9mYWlsdXJlIjp0cnVlfX0=
    Mounts:
      /home/vault from home-init (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-xlhr4 (ro)
      /vault/secrets from vault-secrets (rw)
      /vault/tls from vault-tls-secrets (ro)
Containers:
  app:
    Container ID:   cri-o://e2b730c28394eb7e452a463758612b98a214a2c910ad30b565f5d277f227e13a
    Image:          nginx:alpine
    ⋮
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-xlhr4 (ro)
      /var/run/secrets/tokens from oidc-token (rw)
      /vault/secrets from vault-secrets (rw)
      /vault/tls from vault-tls (rw)
  vault-agent:
    Container ID:  cri-o://24f84f3a0b567fc8c85819822422815f9d903b7ec52f77e2767c3de09e3f696f
    Image:         hashicorp/vault:1.14.0
   ⋮
    Environment:
      VAULT_LOG_LEVEL:   info
      VAULT_LOG_FORMAT:  standard
      VAULT_CONFIG:      eyJhdXRvX2F1dGgiOnsibWV0aG9kIjp7InR5cGUiOiJrdWJlcm5ldGVzIiwibW91bnRfcGF0aCI6ImF1dGgva3ViZXJuZXRlcyIsIm5hbWVzcGFjZSI6ImRlZmF1bHQiLCJjb25maWciOnsicm9sZSI6InRlc3QiLCJ0b2tlbl9wYXRoIjoiL3Zhci9ydW4vc2VjcmV0cy9rdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3Rva2VuIn19LCJzaW5rIjpbeyJ0eXBlIjoiZmlsZSIsImNvbmZpZyI6eyJwYXRoIjoiL2hvbWUvdmF1bHQvLnZhdWx0LXRva2VuIn19XX0sImV4aXRfYWZ0ZXJfYXV0aCI6ZmFsc2UsInBpZF9maWxlIjoiL2hvbWUvdmF1bHQvLnBpZCIsInZhdWx0Ijp7ImFkZHJlc3MiOiJodHRwczovL3ZhdWx0LnZ4OjgyMDAiLCJjYV9jZXJ0IjoiL3ZhdWx0L3Rscy9jYS1idW5kbGUuY3J0In0sInRlbXBsYXRlIjpbeyJkZXN0aW5hdGlvbiI6Ii92YXVsdC9zZWNyZXRzL2NyZWRlbnRpYWxzLnR4dCIsImNvbnRlbnRzIjoie3sgd2l0aCBzZWNyZXQgXCJkYXRhYmFzZS12Mi9kYXRhL3N2cl8xXCIgfX17eyByYW5nZSAkaywgJHYgOj0gLkRhdGEgfX17eyAkayB9fToge3sgJHYgfX1cbnt7IGVuZCB9fXt7IGVuZCB9fSIsImxlZnRfZGVsaW1pdGVyIjoie3siLCJyaWdodF9kZWxpbWl0ZXIiOiJ9fSJ9XSwidGVtcGxhdGVfY29uZmlnIjp7ImV4aXRfb25fcmV0cnlfZmFpbHVyZSI6dHJ1ZX19
    Mounts:
      /home/vault from home-sidecar (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-xlhr4 (ro)
      /vault/secrets from vault-secrets (rw)
      /vault/tls from vault-tls-secrets (ro)
Conditions:
  Type              Status
  Initialized       True
  Ready             True
  ContainersReady   True
  PodScheduled      True
Volumes:
  oidc-token:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  7200
  vault-tls:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  vault-tls
    Optional:    false
  kube-api-access-6jbgh:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
  home-init:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:     Memory
    SizeLimit:  <unset>
  home-sidecar:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:     Memory
    SizeLimit:  <unset>
  vault-secrets:
    Type:       EmptyDir (a temporary directory that shares a pod's lifetime)
    Medium:     Memory
    SizeLimit:  <unset>
  vault-tls-secrets:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  vault-tls
    Optional:    false
⋮
```

</details>
