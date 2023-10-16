## 1. Configure pki secret engine

> [!Note]
>
> 1. Vault runs external to the Kubernetes cluster
> 2. At the point of writing, the vault-cert-manager integration only works with `auth/kubernetes`, `auth/jwt` is not supported

Ref: https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-external-vault

### 1.1. Enable pki secret engine

```console
[root@vault ~]# vault secrets enable pki
Success! Enabled the pki secrets engine at: pki/
```

### 1.2. Configure pki URLs

```console
[root@vault ~]# vault write pki/config/urls issuing_certificates=http://vault.vx:8200/v1/pki/ca crl_distribution_points=http://vault.vx:8200/v1/pki/crl
Key                        Value
---                        -----
crl_distribution_points    [http://vault.vx:8200/v1/pki/crl]
enable_templating          false
issuing_certificates       [http://vault.vx:8200/v1/pki/ca]
ocsp_servers               []
```

### 1.3. Import lab certificate chain

Ref: https://developer.hashicorp.com/vault/api-docs/secret/pki#import-ca-certificates-and-keys

Import root certificate authority

```console
[root@vault ~]# curl -sLO https://github.com/joetanx/lab-certs/raw/main/ca/lab_root.pem
[root@vault ~]# vault write /pki/config/ca pem_bundle=@lab_root.pem
Key                 Value
---                 -----
existing_issuers    <nil>
existing_keys       <nil>
imported_issuers    [4e849dbe-a4e5-9d82-891c-b5b8929f22fb]
imported_keys       <nil>
mapping             map[4e849dbe-a4e5-9d82-891c-b5b8929f22fb:]
```

Import issuer certificate + key bundle

```console
[root@vault ~]# curl -sL https://github.com/joetanx/lab-certs/raw/main/ca/lab_issuer.pem > lab_issuer_bundle.pem
[root@vault ~]# curl -sL https://github.com/joetanx/lab-certs/raw/main/ca/lab_issuer.key >> lab_issuer_bundle.pem
[root@vault ~]# vault write /pki/issuers/import/bundle pem_bundle=@lab_issuer_bundle.pem
WARNING! The following warnings were returned from Vault:

  * Warning 1 during CRL rebuild: warning from local CRL rebuild:
  Issuer equivalency set with associated keys lacked an issuer with CRL
  Signing KeyUsage; refusing to rebuild CRL for this group of issuers:
  c4779615-b052-f065-2c00-62b71bdd284e

Key                 Value
---                 -----
existing_issuers    <nil>
existing_keys       <nil>
imported_issuers    [c4779615-b052-f065-2c00-62b71bdd284e]
imported_keys       [b9f13783-d41c-129a-e91c-249b382bc716]
mapping             map[c4779615-b052-f065-2c00-62b71bdd284e:b9f13783-d41c-129a-e91c-249b382bc716]
```

### 1.4. Configure pki role

Ref: https://developer.hashicorp.com/vault/api-docs/secret/pki#create-update-role

```console
[root@vault ~]# vault write pki/roles/vx allowed_domains=vx allow_subdomains=true key_bits=384 key_type=ec max_ttl=72h
Key                                   Value
---                                   -----
allow_any_name                        false
allow_bare_domains                    false
allow_glob_domains                    false
allow_ip_sans                         true
allow_localhost                       true
allow_subdomains                      true
allow_token_displayname               false
allow_wildcard_certificates           true
allowed_domains                       [vx]
allowed_domains_template              false
allowed_other_sans                    []
allowed_serial_numbers                []
allowed_uri_sans                      []
allowed_uri_sans_template             false
allowed_user_ids                      []
basic_constraints_valid_for_non_ca    false
client_flag                           true
cn_validations                        [email hostname]
code_signing_flag                     false
country                               []
email_protection_flag                 false
enforce_hostnames                     true
ext_key_usage                         []
ext_key_usage_oids                    []
generate_lease                        false
issuer_ref                            default
key_bits                              384
key_type                              ec
key_usage                             [DigitalSignature KeyAgreement KeyEncipherment]
locality                              []
max_ttl                               72h
no_store                              false
not_after                             n/a
not_before_duration                   30s
organization                          []
ou                                    []
policy_identifiers                    []
postal_code                           []
province                              []
require_cn                            true
server_flag                           true
signature_bits                        0
street_address                        []
ttl                                   0s
use_csr_common_name                   true
use_csr_sans                          true
use_pss                               false
```

### 1.5. Configure pki policy

```sh
vault policy write pki - <<EOF
path "pki*" {
  capabilities = ["read", "list"]
}
path "pki/sign/vx" {
  capabilities = ["create", "update"]
}
path "pki/issue/vx" {
  capabilities = ["create"]
}
EOF
```

## 2. Configure Kubernetes authentication

### 2.1. Enable auth/kubernetes method

```console
[root@vault ~]# vault auth enable kubernetes
Success! Enabled jwt auth method at: kubernetes/
```

### 2.2. Configure the auth method (using the Vault client's JWT as the reviewer JWT)

Ref: https://developer.hashicorp.com/vault/docs/auth/kubernetes#use-the-vault-client-s-jwt-as-the-reviewer-jwt

#### 2.2.1. Retrieve Kubernetes information required to configure the auth method

```sh
KUBE_CA_CERT=$(kubectl config view --raw -o jsonpath={.clusters[].cluster.certificate-authority-data} | base64 -d)
KUBE_HOST=$(kubectl config view --raw -o jsonpath={.clusters[].cluster.server})
ISSUER=$(kubectl get --raw /.well-known/openid-configuration | jq -r '.issuer')
```

#### 2.2.2. Configure the auth method

```sh
vault write auth/kubernetes/config \
kubernetes_host=$KUBE_HOST \
kubernetes_ca_cert="$KUBE_CA_CERT" \
issuer=$ISSUER
```

### 2.3. Install vault helm chart in the Kubernetes cluster

Install the vault helm chart with `global.externalVaultAddr` set to the vault URL

Optional:
- Use `--namespace` to specify the namespace to install to
- Use `--dry-run` to preview the changes before actual deployment

```console
[root@kube ~]# helm repo add hashicorp https://helm.releases.hashicorp.com
"hashicorp" has been added to your repositories
[root@kube ~]# helm install vault hashicorp/vault --set "global.externalVaultAddr=https://vault.vx:8200"
NAME: vault
LAST DEPLOYED: Tue Sep 26 07:59:24 2023
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
vault-agent-injector-6b45644b98-jwqm8   1/1     Running   0          24s
```

```sh
vault write auth/kubernetes/config \
kubernetes_host=$KUBE_HOST \
kubernetes_ca_cert="$KUBE_CA_CERT" \
issuer=$ISSUER
```

### 2.4. Configure role for the issuer

```sh
vault write auth/kubernetes/role/issuer \
bound_service_account_names=issuer \
bound_service_account_namespaces=cert-manager \
policies=pki \
ttl=20m
```

## 3. Setup NGINX ingress controller and cert-manager

### 3.1. Setup NGINX ingress controller

Ref: https://kubernetes.github.io/ingress-nginx/deploy/

```sh
kubectl apply -f https://github.com/kubernetes/ingress-nginx/raw/main/deploy/static/provider/baremetal/deploy.yaml
```

### 3.2. Set as default ingress class

```sh
kubectl -n ingress-nginx annotate ingressclasses nginx ingressclass.kubernetes.io/is-default-class="true"
```

### 3.3. Expose the ingress controller with `hostPort` on HTTP (`80`) and HTTPS (`443`)

- The NGINX ingress controller will be the only ingress to the cluster and the deployment runs only 1 replica
- The commands below deletes the default ingress controller service and update the deployment ports configuration to `hostPort`

```sh
kubectl -n ingress-nginx delete service ingress-nginx-controller
kubectl -n ingress-nginx patch deploy ingress-nginx-controller --patch '{"spec":{"template":{"spec":{"containers":[{"name": "controller","ports":[{"containerPort": 80,"hostPort":80,"name":"http","protocol":"TCP"},{"containerPort": 443,"hostPort":443,"name":"https","protocol":"TCP"}]}]}}}}'
```

### 3.4.. Setup cert-manager

```sh
VERSION=$(curl -sI https://github.com/cert-manager/cert-manager/releases/latest | grep location: | cut -d / -f 8 | tr -d '\r')
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/$VERSION/cert-manager.yaml
```

## 4. Configure certificate issuer

### 4.1. Create service account and token for the issuer

Service account and token manifest example:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: issuer
  namespace: cert-manager
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
  name: issuer
  namespace: cert-manager
---
apiVersion: v1
kind: Secret
metadata:
  name: issuer-token
  namespace: cert-manager
  annotations:
    kubernetes.io/service-account.name: issuer
type: kubernetes.io/service-account-token
```

### 4.2. Configure the certificate issuer

Ref: https://cert-manager.io/docs/configuration/vault/

> [!Note]
>
> The `caBundle` parameter is required if vault uses TLS and is signed by a private issuer
>
> Otherwise, this error occurs:
> 
> ```
> "message": "Failed to initialize Vault client: while requesting a Vault token using the Kubernetes auth: error calling Vault server: Post \"https://vault.vx:8200/v1/auth/kubernetes/login\": tls: failed to verify certificate: x509: certificate signed by unknown authority
> ```
> 
> This parameter expects a the certificate pem file in a base64 encoded single-line format (hence, the `base64 | tr -d '\n'`)

```console
[root@kube ~]# CA_CERT=$(curl -sL https://github.com/joetanx/lab-certs/raw/main/ca/lab_issuer.pem | base64 | tr -d '\n')
[root@kube ~]# kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
  namespace: cert-manager
spec:
  vault:
    server: https://vault.vx:8200
    path: pki/sign/vx
    caBundle: $CA_CERT
    auth:
      kubernetes:
        mountPath: /v1/auth/kubernetes
        role: issuer
        secretRef:
          name: issuer-token
          key: token
EOF
clusterissuer.cert-manager.io/vault-issuer created
```

Verify that the issuer is ready:

```console
[root@kube ~]# kubectl -n cert-manager get clusterissuers
NAME           READY   AGE
vault-issuer   True    10s
```

## 5. Create test certificate

Certificate manifest example:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: www-lab-vx
spec:
  secretName: www-lab-vx
  issuerRef:
    kind: ClusterIssuer
    name: vault-issuer
  privateKey:
    algorithm: ECDSA
    encoding: PKCS1
    size: 384
  commonName: www.lab.vx
  dnsNames:
  - www.lab.vx
```

Verify certificate issued:

```console
[root@kube ~]# kubectl get certificates
NAME         READY   SECRET       AGE
www-lab-vx   True    www-lab-vx   3s
[root@kube ~]# kubectl describe certificates www-lab-vx
Name:         www-lab-vx
Namespace:    default
Labels:       <none>
Annotations:  <none>
API Version:  cert-manager.io/v1
Kind:         Certificate
Metadata:
  Creation Timestamp:  2023-09-26T00:47:34Z
  Generation:          1
  Resource Version:    5565
  UID:                 80a4a98b-c004-4f11-a09b-fc0c8623ea37
Spec:
  Common Name:  www.lab.vx
  Dns Names:
    www.lab.vx
  Issuer Ref:
    Kind:  ClusterIssuer
    Name:  vault-issuer
  Private Key:
    Algorithm:  ECDSA
    Encoding:   PKCS1
    Size:       384
  Secret Name:  www-lab-vx
Status:
  Conditions:
    Last Transition Time:  2023-09-26T00:47:34Z
    Message:               Certificate is up to date and has not expired
    Observed Generation:   1
    Reason:                Ready
    Status:                True
    Type:                  Ready
  Not After:               2023-09-29T00:47:34Z
  Not Before:              2023-09-26T00:47:04Z
  Renewal Time:            2023-09-28T00:47:24Z
  Revision:                1
Events:
  Type    Reason     Age   From                                       Message
  ----    ------     ----  ----                                       -------
  Normal  Issuing    16s   cert-manager-certificates-trigger          Issuing certificate as Secret does not exist
  Normal  Generated  16s   cert-manager-certificates-key-manager      Stored new private key in temporary Secret resource "www-lab-vx-2k7rt"
  Normal  Requested  16s   cert-manager-certificates-request-manager  Created new CertificateRequest resource "www-lab-vx-1"
  Normal  Issuing    16s   cert-manager-certificates-issuing          The certificate has been successfully issued
```

## 6. Test cert-manager with NGINX ingress controller

Deployment manifest example:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  clusterIP: None
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
  annotations:
    cert-manager.io/cluster-issuer: vault-issuer
    cert-manager.io/common-name: kube.vx
    cert-manager.io/private-key-algorithm: ECDSA
    cert-manager.io/private-key-size: '384'
spec:
  ingressClassName: nginx
  rules:
  - host: kube.vx
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80
  tls:
  - hosts:
    - kube.vx
    secretName: nginx-cert
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: docker.io/nginx:alpine
        imagePullPolicy: IfNotPresent
```

Verify certificate issued:

```console
[root@kube ~]# kubectl get certificates
NAME         READY   SECRET       AGE
nginx-cert   True    nginx-cert   19s
www-lab-vx   True    www-lab-vx   2m44s
[root@kube ~]# kubectl describe certificates nginx-cert
Name:         nginx-cert
Namespace:    default
Labels:       <none>
Annotations:  <none>
API Version:  cert-manager.io/v1
Kind:         Certificate
Metadata:
  Creation Timestamp:  2023-09-26T00:49:59Z
  Generation:          1
  Owner References:
    API Version:           networking.k8s.io/v1
    Block Owner Deletion:  true
    Controller:            true
    Kind:                  Ingress
    Name:                  nginx
    UID:                   894e9f29-714e-4fdd-a8fe-6042a95cba8a
  Resource Version:        5835
  UID:                     799ff1a3-7a79-4907-85bb-fc94c6748984
Spec:
  Common Name:  kube.vx
  Dns Names:
    kube.vx
  Issuer Ref:
    Group:  cert-manager.io
    Kind:   ClusterIssuer
    Name:   vault-issuer
  Private Key:
    Algorithm:  ECDSA
    Size:       384
  Secret Name:  nginx-cert
  Usages:
    digital signature
    key encipherment
Status:
  Conditions:
    Last Transition Time:  2023-09-26T00:49:59Z
    Message:               Certificate is up to date and has not expired
    Observed Generation:   1
    Reason:                Ready
    Status:                True
    Type:                  Ready
  Not After:               2023-09-29T00:49:59Z
  Not Before:              2023-09-26T00:49:29Z
  Renewal Time:            2023-09-28T00:49:49Z
  Revision:                1
Events:
  Type    Reason     Age   From                                       Message
  ----    ------     ----  ----                                       -------
  Normal  Issuing    36s   cert-manager-certificates-trigger          Issuing certificate as Secret does not exist
  Normal  Generated  36s   cert-manager-certificates-key-manager      Stored new private key in temporary Secret resource "nginx-cert-hh6gm"
  Normal  Requested  36s   cert-manager-certificates-request-manager  Created new CertificateRequest resource "nginx-cert-1"
  Normal  Issuing    36s   cert-manager-certificates-issuing          The certificate has been successfully issued
```

![image](https://github.com/joetanx/hashicorp/assets/90442032/ad59823e-cc64-4f96-bead-8a113ea8638a)

![image](https://github.com/joetanx/hashicorp/assets/90442032/57c589e3-70e4-4c82-9f32-0a2d39db99ad)

![image](https://github.com/joetanx/hashicorp/assets/90442032/4c5481a3-d891-4417-af33-d919af742d05)

## 7. Review configured settings in vault UI

Overview:

![image](https://github.com/joetanx/hashicorp/assets/90442032/12e29594-caf5-4930-bf0e-57a4c17b4eaf)

Issuers:

![image](https://github.com/joetanx/hashicorp/assets/90442032/bbda5c59-3484-4361-9f0c-e47f5dd65872)

![image](https://github.com/joetanx/hashicorp/assets/90442032/535057a7-981c-4f34-b0ea-0b5ab218f93e)

![image](https://github.com/joetanx/hashicorp/assets/90442032/cc3ece10-23ab-4887-8fb0-5d5d07a4b5be)

Issued certificates:

![image](https://github.com/joetanx/hashicorp/assets/90442032/bf8ad80d-f6e8-4309-a0f6-c0bb6339f5fb)

![image](https://github.com/joetanx/hashicorp/assets/90442032/25daa6f6-8166-4703-b467-1404e5c773e3)

![image](https://github.com/joetanx/hashicorp/assets/90442032/7d636b26-08ec-4d5e-8598-349ae8a045b3)
