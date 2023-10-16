## 1. Enable auth/jwt method

> [!Note]
>
> Vault runs external to the Kubernetes cluster

Ref:
- https://developer.hashicorp.com/vault/docs/auth/jwt/oidc-providers/kubernetes
- https://developer.hashicorp.com/vault/api-docs/auth/jwt

```console
[root@vault ~]# vault auth enable jwt
Success! Enabled jwt auth method at: jwt/
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
vault-agent-injector-6b45644b98-8hsh5   1/1     Running   0          25s
```

## 3. Configure the auth method (option 1) - using service account issuer discovery

### 3.1. Configure the OIDC discovery URL on the Kubernetes cluster to allow unauthenticated calls

Ref: https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/

The OIDC discovery URL requires authentication by default:

```console
[root@vault ~]# curl -k https://kube.vx:6443/.well-known/openid-configuration
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "forbidden: User \"system:anonymous\" cannot get path \"/.well-known/openid-configuration\"",
  "reason": "Forbidden",
  "details": {},
  "code": 403
}
```

Configure the clusterrolebinding to allow unauthenticated calls:

```console
[root@kube ~]# kubectl create clusterrolebinding oidc-reviewer --clusterrole=system:service-account-issuer-discovery --group=system:unauthenticated
clusterrolebinding.rbac.authorization.k8s.io/oidc-reviewer created
```

Vault should be able to reach the OIDC discovery URL:

```console
[root@vault ~]# curl -sk https://kube.vx:6443/.well-known/openid-configuration | jq
{
  "issuer": "https://kube.vx:6443",
  "jwks_uri": "https://192.168.17.91:6443/openid/v1/jwks",
  "response_types_supported": [
    "id_token"
  ],
  "subject_types_supported": [
    "public"
  ],
  "id_token_signing_alg_values_supported": [
    "ES384"
  ]
}
```

### 3.2. Configure the service account issuer on the Kubernetes cluster to an URL that is accessible externally

Ref: https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/

The service account issuer is set to `kubernetes.default.svc.cluster.local` as default for a self-installed cluster using `kubeadm`

```console
[root@kube ~]# kubectl get --raw /.well-known/openid-configuration | jq
{
  "issuer": "https://kubernetes.default.svc.cluster.local",
  "jwks_uri": "https://192.168.17.91:6443/openid/v1/jwks",
  "response_types_supported": [
    "id_token"
  ],
  "subject_types_supported": [
    "public"
  ],
  "id_token_signing_alg_values_supported": [
    "ES384"
  ]
}
```

Change the issuer to a URL that is accessible externally at `/etc/kubernetes/manifests/kube-apiserver.yaml`

```
spec:
  containers:
  - command:
    - kube-apiserver
    ⋮
    - --service-account-issuer=https://kube.vx:6443
```

The `kube-apiserver-<cluster-name>` pod needs to be deleted using `kubectl -n kube-system delete pods kube-apiserver-<cluster-name>` for the setting to take effect

### 3.3. Configure the Vault auth method

```console
[root@vault ~]# vault write auth/jwt/config oidc_discovery_url=https://kube.vx:6443 oidc_discovery_ca_pem=@lab_issuer.pem
Success! Data written to: auth/jwt/config
```

> [!Note]
> 
> Attempting to configure the JWT auth method without both settings above configured on the Kubernetes cluster will result in the error below:
> 
> ```console
> [root@vault ~]# vault write auth/jwt/config oidc_discovery_url=https://kube.vx:6443 oidc_discovery_ca_pem=@lab_issuer.pem
> Error writing data to auth/jwt/config: Error making API request.
> 
> URL: PUT https://127.0.0.1:8200/v1/auth/jwt/config
> Code: 400. Errors:
> 
> * error checking oidc discovery URL
> ```

## 4. Configure the auth method (option 2) - using JWKS URL

### 4.1. Configure the JWKS URL on the Kubernetes cluster to allow unauthenticated calls

Ref: https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/

The JWKS URL requires authentication by default:

```console
[root@vault ~]#curl -k https://kube.vx:6443/openid/v1/jwks
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "forbidden: User \"system:anonymous\" cannot get path \"/openid/v1/jwks\"",
  "reason": "Forbidden",
  "details": {},
  "code": 403
}
```

Configure the clusterrolebinding to allow unauthenticated calls:

```console
[root@kube ~]# kubectl create clusterrolebinding oidc-reviewer --clusterrole=system:service-account-issuer-discovery --group=system:unauthenticated
clusterrolebinding.rbac.authorization.k8s.io/oidc-reviewer created
```

Vault should be able to reach the OIDC discovery URL:

```console
[root@vault ~]# curl -sk https://kube.vx:6443/openid/v1/jwks | jq
{
  "keys": [
    {
      "use": "sig",
      "kty": "EC",
      "kid": "MT2pX3Fz_QjzG6i62EqLns6cgzAcqhh8E6w81oENd00",
      "crv": "P-384",
      "alg": "ES384",
      "x": "kAWGwbNW-m3QTY8vV0S17tv11-fuP2zrQktvBOU6mRIqO9iUoQPo_X21urlqIER5",
      "y": "8KUaPLTo6_hA4ZvE8bt_2faH-qzetxfo6aNgWJKG__Kvg-eiOub2nbumgsrOU8A8"
    }
  ]
}
```

### 4.2. Configure the Vault auth method

```console
[root@vault ~]# vault write auth/jwt/config jwks_url=https://kube.vx:6443/openid/v1/jwks jwks_ca_pem=@lab_issuer.pem
Success! Data written to: auth/jwt/config
```

> [!Note]
> 
> Attempting to configure the JWT auth method without the setting above configured on the Kubernetes cluster will result in the error below:
> 
> ```console
> [root@vault ~]# vault write auth/jwt/config jwks_url=https://kube.vx:6443/openid/v1/jwks jwks_ca_pem=@lab_issuer.pem
> Error writing data to auth/jwt/config: Error making API request.
> 
> URL: PUT https://127.0.0.1:8200/v1/auth/jwt/config
> Code: 400. Errors:
> 
> * error checking jwks URL
> ```

## 5. Configure the auth method (option 3) - using JWT validation public keys

This method can be useful if Kubernetes' API is not reachable from Vault

### 5.1. Retrieve the JWT validation public keys from the Kubernetes cluster

```console
[root@kube ~]# kubectl get --raw $(kubectl get --raw /.well-known/openid-configuration | jq -r '.jwks_uri')
{"keys":[{"use":"sig","kty":"EC","kid":"MT2pX3Fz_QjzG6i62EqLns6cgzAcqhh8E6w81oENd00","crv":"P-384","alg":"ES384","x":"kAWGwbNW-m3QTY8vV0S17tv11-fuP2zrQktvBOU6mRIqO9iUoQPo_X21urlqIER5","y":"8KUaPLTo6_hA4ZvE8bt_2faH-qzetxfo6aNgWJKG__Kvg-eiOub2nbumgsrOU8A8"}]}
```

Convert the keys from JWK format to PEM using a tool such as: https://8gwifi.org/jwkconvertfunctions.jsp

The PEM-formatted keys should look something like this:

```
-----BEGIN PUBLIC KEY-----
MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEkAWGwbNW+m3QTY8vV0S17tv11+fuP2zr
QktvBOU6mRIqO9iUoQPo/X21urlqIER58KUaPLTo6/hA4ZvE8bt/2faH+qzetxfo
6aNgWJKG//Kvg+eiOub2nbumgsrOU8A8
-----END PUBLIC KEY-----
```

### 5.2. Configure the Vault auth method

```console
[root@vault ~]# vault write auth/jwt/config jwt_validation_pubkeys="-----BEGIN PUBLIC KEY-----
MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEkAWGwbNW+m3QTY8vV0S17tv11+fuP2zr
QktvBOU6mRIqO9iUoQPo/X21urlqIER58KUaPLTo6/hA4ZvE8bt/2faH+qzetxfo
6aNgWJKG//Kvg+eiOub2nbumgsrOU8A8
-----END PUBLIC KEY-----"
Success! Data written to: auth/jwt/config
```

## 6. Test integration

The test pod access secrets created in [section 3.1.2.](#312-kv-version-2) and uses the policies configured in created in [section 3.2.2.](#322-kv-version-2)

### 6.1. Create vault role for the test pod

> [!Note]
>
> - `user_claim` specifies from which claim in the JWT to check for the `bound_subject`, which is the `sub` claim in this example
> - `bound_audiences` must match the `aud` claim in the JWT
> - `bound_subject` must match the `sub` claim in the JWT (as specified in `user_claim`)

```sh
vault write auth/jwt/role/test \
role_type=jwt \
user_claim=sub \
bound_audiences=vault \
bound_subject=system:serviceaccount:default:test \
policies=app_1_v2
```

### 6.2. Create secret for the CA issuer

The vault agent needs to verify the validity of the vault certificate chain

```console
[root@kube ~]# curl -sLO https://github.com/joetanx/lab-certs/raw/main/ca/lab_issuer.pem
[root@kube ~]# kubectl create secret generic vault-tls --from-file=ca-bundle.crt=./lab_issuer.pem
secret/vault-tls created
```

### 6.3. Deploy the test pod

The Vault Agent Injector works by intercepting pod `CREATE` and `UPDATE` events in Kubernetes.

The controller parses the event and looks for the metadata annotation `vault.hashicorp.com/agent-inject: true`.

If found, the controller will alter the pod specification based on other annotations present.

Ref: https://developer.hashicorp.com/vault/docs/platform/k8s/injector/annotations

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
    vault.hashicorp.com/auth-type: 'jwt'
    vault.hashicorp.com/auth-path: 'auth/jwt'
    vault.hashicorp.com/namespace: 'default'
    vault.hashicorp.com/role: 'test'
    # secrets are mounted at '/vault/secrets/', the string behind 'agent-inject-secret-' is the name of the file
    vault.hashicorp.com/agent-inject-secret-credentials.txt: 'database-v2/data/svr_1'
    vault.hashicorp.com/ca-cert: /vault/tls/ca-bundle.crt
    vault.hashicorp.com/tls-secret: vault-tls
    vault.hashicorp.com/agent-service-account-token-volume-name: 'oidc-token'
    vault.hashicorp.com/auth-config-path: '/var/run/secrets/tokens/oidc-token'
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

> [!Note]
> 
> The manifest above uses [downward API](https://kubernetes.io/docs/concepts/workloads/pods/downward-api/) to project the JWT to a volume
> 
> This allows the `audience` of the JWT to be set to a desired value (`vault` in this example)
> 
> By default, the JWT is located at `/run/secrets/kubernetes.io/serviceaccount/token` with the service account issuer as the `audience` (which will likely be `kubernetes.default.svc.cluster.local` as default for a self-installed cluster using `kubeadm`)

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

2023-09-24T00:54:02.592Z [INFO]  agent.sink.file: creating file sink
2023-09-24T00:54:02.592Z [INFO]  agent.sink.file: file sink configured: path=/home/vault/.vault-token mode=-rw-r-----
2023-09-24T00:54:02.592Z [INFO]  agent.auth.jwt: jwt auth method created: path=/var/run/secrets/tokens/oidc-token
2023-09-24T00:54:02.592Z [INFO]  agent.auth.handler: starting auth handler
2023-09-24T00:54:02.592Z [INFO]  agent.sink.server: starting sink server
2023-09-24T00:54:02.592Z [INFO]  agent.auth.handler: authenticating
2023-09-24T00:54:02.592Z [INFO]  agent.exec.server: starting exec server
2023-09-24T00:54:02.592Z [INFO]  agent.exec.server: no env templates or exec config, exiting
2023-09-24T00:54:02.592Z [INFO]  agent.template.server: starting template server
2023-09-24T00:54:02.592Z [INFO] (runner) creating new runner (dry: false, once: false)
2023-09-24T00:54:02.592Z [ERROR] agent.auth.jwt: error removing jwt file: error="remove /var/run/secrets/tokens/oidc-token: read-only file system"
2023-09-24T00:54:02.593Z [INFO] (runner) creating watcher
2023-09-24T00:54:02.595Z [INFO]  agent.auth.handler: authentication successful, sending token to sinks
2023-09-24T00:54:02.595Z [INFO]  agent.auth.handler: starting renewal process
2023-09-24T00:54:02.595Z [INFO]  agent.template.server: template server received new token
2023-09-24T00:54:02.595Z [INFO] (runner) stopping
2023-09-24T00:54:02.595Z [INFO] (runner) creating new runner (dry: false, once: false)
2023-09-24T00:54:02.595Z [INFO]  agent.sink.file: token written: path=/home/vault/.vault-token
2023-09-24T00:54:02.595Z [INFO]  agent.sink.server: sink server stopped
2023-09-24T00:54:02.595Z [INFO]  agent: sinks finished, exiting
2023-09-24T00:54:02.595Z [INFO] (runner) creating watcher
2023-09-24T00:54:02.595Z [INFO] (runner) starting
2023-09-24T00:54:02.596Z [INFO]  agent.auth.handler: renewed auth token
2023-09-24T00:54:02.603Z [INFO] (runner) rendered "(dynamic)" => "/vault/secrets/credentials.txt"
2023-09-24T00:54:02.603Z [INFO] (runner) stopping
2023-09-24T00:54:02.603Z [INFO]  agent.template.server: template server stopped
2023-09-24T00:54:02.603Z [INFO] (runner) received finish
2023-09-24T00:54:02.603Z [INFO]  agent.auth.handler: shutdown triggered, stopping lifetime watcher
2023-09-24T00:54:02.603Z [INFO]  agent.auth.handler: auth handler stopped
2023-09-24T00:54:02.603Z [INFO]  agent.exec.server: exec server stopped
```

</details>

Verify secrets retrieved:

```console
[root@kube ~]# kubectl exec test -- cat /vault/secrets/credentials.txt
Defaulted container "app" out of: app, vault-agent, vault-agent-init (init)
data: map[address:sql_1.local password:Pass_1 username:db_user_1]
metadata: map[created_time:2023-09-24T00:39:40.375506171Z custom_metadata:<nil> deletion_time: destroyed:false version:1]
```

<details><summary>Details on the resultant deployment mutated by the vault annotations</summary>

The vault annotations mutates the pod configuration:
- `vault.hashicorp.com/agent-inject: true` adds the `vault-agent-init` init container that retrieves the secrets before the app container starts
- `vault.hashicorp.com/agent-inject-status: 'update'` adds the `vault-agent` sidecar container that runs alongside the app container to update the secrets if there are any changes

```console
[root@kube ~]# kubectl describe pods test
⋮
Init Containers:
  vault-agent-init:
    Container ID:  cri-o://767f9c25778db384369dcde032e88f449a565b69f9a92dc365050b5279a352ac
    Image:         hashicorp/vault:1.14.0
    ⋮
    Mounts:
      /home/vault from home-init (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-hzfkc (ro)
      /var/run/secrets/tokens from oidc-token (ro)
      /vault/secrets from vault-secrets (rw)
      /vault/tls from vault-tls-secrets (ro)
Containers:
  app:
    Container ID:   cri-o://236a87dab95a0120ac4ba5abe8b52f140d7ba194b20b32216daec3ab7eaf03d2
    Image:          nginx:alpine
    ⋮
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-hzfkc (ro)
      /var/run/secrets/tokens from oidc-token (rw)
      /vault/secrets from vault-secrets (rw)
      /vault/tls from vault-tls (rw)
  vault-agent:
    Container ID:  cri-o://0dc1da6497e4d1af22fe8294b2d7470f30a20e8a7923db82fbc9c6d1024b54cf
    Image:         hashicorp/vault:1.14.0
   ⋮
    Mounts:
      /home/vault from home-sidecar (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-hzfkc (ro)
      /var/run/secrets/tokens from oidc-token (ro)
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
  kube-api-access-hzfkc:
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

<details><summary>Manually using the JWT</summary>

```console
[root@kube ~]# kubectl exec test -- cat /var/run/secrets/tokens/oidc-token | tee oidc-token
Defaulted container "app" out of: app, vault-agent, vault-agent-init (init)
eyJhbGciOiJFUzM4NCIsImtpZCI6Ik1UMnBYM0Z6X1Fqekc2aTYyRXFMbnM2Y2d6QWNxaGg4RTZ3ODFvRU5kMDAifQ.eyJhdWQiOlsidmF1bHQiXSwiZXhwIjoxNjk1NTI2MDY0LCJpYXQiOjE2OTU1MTg4NjQsImlzcyI6Imh0dHBzOi8va3ViZS52eDo2NDQzIiwia3ViZXJuZXRlcy5pbyI6eyJuYW1lc3BhY2UiOiJkZWZhdWx0IiwicG9kIjp7Im5hbWUiOiJ0ZXN0IiwidWlkIjoiNmM4MmFmNTQtNjQzZS00YWZjLWEyMWEtZjMxM2YzMmExNjJjIn0sInNlcnZpY2VhY2NvdW50Ijp7Im5hbWUiOiJ0ZXN0IiwidWlkIjoiNjI4Njg4NWItNTgyOC00MTc3LWE2ZmMtZjMyMWFiZDM0NjcxIn19LCJuYmYiOjE2OTU1MTg4NjQsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDpkZWZhdWx0OnRlc3QifQ.I1EVsh_WPJSDjmaTOebW4sisjcmaFuXBavACag5FOqbQ-pR0G_iLNmLxpvy2pd7ZF8QVnR2hhy6i0C2Fl6Bo49Ju0HTe3AVZWwoHmVrORxghHN48gj7e2oBgm9glWGsm
```

```console
[root@kube ~]# curl -s https://vault.vx:8200/v1/auth/jwt/login --data "{\"jwt\": \"$(cat oidc-token)\", \"role\": \"test\"}" | tee vault-token | jq
{
  "request_id": "99e8ac2b-e0f8-30b5-c49e-e274314f08dc",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 0,
  "data": null,
  "wrap_info": null,
  "warnings": null,
  "auth": {
    "client_token": "hvs.CAESIMjguoILqW0UkcRdM5FFC37-EJcMrYI_vHAwKaZIKz6hGh4KHGh2cy5vMVZiQ1UzWnBXVEJoaGhQc1JQemFnTWs",
    "accessor": "7ZS3mz67cdYKNSod6Ca8mLM2",
    "policies": [
      "app_1_v2",
      "default"
    ],
    "token_policies": [
      "app_1_v2",
      "default"
    ],
    "metadata": {
      "role": "test"
    },
    "lease_duration": 2764800,
    "renewable": true,
    "entity_id": "24767385-1740-bed3-508e-08fbd7c02336",
    "token_type": "service",
    "orphan": true,
    "mfa_requirement": null,
    "num_uses": 0
  }
}
```

```console
[root@kube ~]# curl -s -H "X-Vault-Token: $(cat vault-token | jq -r .auth.client_token)" https://vault.vx:8200/v1/auth/token/lookup-self | jq
{
  "request_id": "eacbd9e3-53d2-3ee4-6e00-fba7540ba730",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 0,
  "data": {
    "accessor": "7ZS3mz67cdYKNSod6Ca8mLM2",
    "creation_time": 1695519079,
    "creation_ttl": 2764800,
    "display_name": "jwt-system:serviceaccount:default:test",
    "entity_id": "24767385-1740-bed3-508e-08fbd7c02336",
    "expire_time": "2023-10-26T09:31:19.260113122+08:00",
    "explicit_max_ttl": 0,
    "id": "hvs.CAESIMjguoILqW0UkcRdM5FFC37-EJcMrYI_vHAwKaZIKz6hGh4KHGh2cy5vMVZiQ1UzWnBXVEJoaGhQc1JQemFnTWs",
    "issue_time": "2023-09-24T09:31:19.260116427+08:00",
    "meta": {
      "role": "test"
    },
    "num_uses": 0,
    "orphan": true,
    "path": "auth/jwt/login",
    "policies": [
      "app_1_v2",
      "default"
    ],
    "renewable": true,
    "ttl": 2764751,
    "type": "service"
  },
  "wrap_info": null,
  "warnings": null,
  "auth": null
}
```

```console
[root@kube ~]# curl -s -H "X-Vault-Token: $(cat vault-token | jq -r .auth.client_token)" https://vault.vx:8200/v1/database-v2/data/svr_1 | jq
{
  "request_id": "cdbb7ce7-29cb-2202-f1e8-d3a7dfb8056a",
  "lease_id": "",
  "renewable": false,
  "lease_duration": 0,
  "data": {
    "data": {
      "address": "sql_1.local",
      "password": "Pass_1",
      "username": "db_user_1"
    },
    "metadata": {
      "created_time": "2023-09-24T01:27:23.721012916Z",
      "custom_metadata": null,
      "deletion_time": "",
      "destroyed": false,
      "version": 1
    }
  },
  "wrap_info": null,
  "warnings": null,
  "auth": null
}
```

</details>
