## 1. Prepare SSH secret engine

Ref: https://developer.hashicorp.com/vault/docs/secrets/ssh/one-time-ssh-passwords

Enable SSH secret engine

```console
[root@vault ~]# vault secrets enable -path=ssh-otp ssh
Success! Enabled the ssh secrets engine at: ssh-otp/
```

Configure OTP role for the target linux host

> The example linux target host `foxtrot.vx` has IP address `192.168.17.80`

```console
[root@vault ~]# vault write ssh-otp/roles/foxtrot key_type=otp default_user=vault cidr_list=192.168.17.80/32
Success! Data written to: ssh-otp/roles/foxtrot
```

## 2. Prepare test user

Create access policy to allow access to SSH credentials

```console
[root@vault ~]# vault policy write ssh-otp-access -<< EOF
path "ssh-otp/*" {
  capabilities = [ "list" ]
}
path "ssh-otp/creds/foxtrot" {
  capabilities = ["create", "read", "update"]
}
EOF
Success! Uploaded policy: foxtrot
```

Enable userpass auth method

```console
[root@vault ~]# vault auth enable userpass
Success! Enabled userpass auth method at: userpass/
```

Create user `test` with the `foxtrot` access policy

```console
[root@vault ~]# vault write auth/userpass/users/test password=P@ssw0rd policies=ssh-otp-access
Success! Data written to: auth/userpass/users/test
```

## 3. Setup vault-ssh-helper on target linux host

> [!Note]
>
> Example commands below are for RHEL 9

### 3.1. "Install" vault-ssh-helper

```console
[root@foxtrot ~]# VERSION=$(curl -sI https://github.com/hashicorp/vault-ssh-helper/releases/latest | grep location: | cut -d / -f 8 | tr -d '\r' | tr -d 'v')
[root@foxtrot ~]# curl -sLO https://releases.hashicorp.com/vault-ssh-helper/$VERSION/vault-ssh-helper_$VERSION\_linux_amd64.zip
[root@foxtrot ~]# unzip -q vault-ssh-helper_$VERSION\_linux_amd64.zip -d /usr/local/bin && rm -f vault-ssh-helper_$VERSION\_linux_amd64.zip
```

### 3.2. Configure vault-ssh-helper

> [!Note]
>
> The vault-ssh-helper configuration can point to a pem certificate to verify the vault certificate chain
>
> This is the `lab_issuer.pem` downloaded to `/etc/vault-ssh-helper.d/` in the commands below

```console
[root@foxtrot ~]# mkdir /etc/vault-ssh-helper.d/
[root@foxtrot ~]# curl -sLo /etc/vault-ssh-helper.d/lab_issuer.pem https://github.com/joetanx/lab-certs/raw/main/ca/lab_issuer.pem
[root@foxtrot ~]# cat << EOF > /etc/vault-ssh-helper.d/config.hcl
vault_addr = "https://vault.vx:8200"
tls_skip_verify = false
ca_cert = "/etc/vault-ssh-helper.d/lab_issuer.pem"
ssh_mount_point = "ssh-otp"
allowed_roles = "*"
EOF
```

### 3.3. Edit the sshd pam module `/etc/pam.d/sshd`

Refs:
- https://support.hashicorp.com/hc/en-us/articles/14145105093011-Red-Hat-Linux-RHEL-PAM-configuration-for-vault-ssh-helper-otp-authentication
- https://github.com/hashicorp/vault-ssh-helper/blob/main/README.md#pam-configuration

```
# auth       substack     password-auth
auth requisite pam_exec.so quiet expose_authtok log=/var/log/vault-ssh.log /usr/local/bin/vault-ssh-helper -config=/etc/vault-ssh-helper.d/config.hcl
auth optional pam_unix.so use_first_pass nodelay
⋮
```

### 3.4. Edit the sshd configuration `/etc/ssh/sshd_config`

Ref: https://github.com/hashicorp/vault-ssh-helper/blob/main/README.md#sshd-configuration

Uncomment `#KbdInteractiveAuthentication yes` to `KbdInteractiveAuthentication yes`
- This setting used to be `ChallengeResponseAuthentication`, which is deprecated

`UsePAM yes` should be already enabled by default

> [!Note]
>
> Setting `PasswordAuthentication no` results in `Permission denied` error without any prompt for password for some reason
>
> ```console
> [root@client ~]# ssh -o PubkeyAuthentication=no vault@foxtrot.vx
> Warning: Permanently added 'foxtrot.vx' (ED25519) to the list of known hosts.
> vault@foxtrot.vx: Permission denied (publickey,gssapi-keyex,gssapi-with-mic).
> ```
>
> Leaving the setting as-is allows the SSH OTP to work, with a trail of logs showing the attempt to verify the password locally failing before succeeding aginst vault
>
> ```
> Oct 06 09:11:51 foxtrot.vx unix_chkpwd[1347]: password check failed for user (vault)
> Oct 06 09:11:51 foxtrot.vx sshd[1335]: pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=192.168.17.100  user=vault
> Oct 06 09:11:51 foxtrot.vx sshd[1335]: Accepted password for vault from 192.168.17.100 port 42266 ssh2
> ```

### 3.5. Configure SELinux

vault-ssh-helper requires SELinux permissions to write logs and connect to Vault

Ref: https://github.com/hashicorp/vault-ssh-helper/issues/31

```console
[root@foxtrot ~]# yum -y install make selinux-policy-devel
⋮
Complete!
[root@foxtrot ~]# cat << EOF > vault-ssh-helper.te
policy_module(vault-ssh-helper, 1.0)

require {
        type sshd_t;
}

#============= sshd_t ==============
corenet_tcp_connect_trivnet1_port(sshd_t)
logging_create_generic_logs(sshd_t)
EOF
[root@foxtrot ~]# make -f /usr/share/selinux/devel/Makefile vault-ssh-helper.pp
Compiling targeted vault-ssh-helper module
Creating targeted vault-ssh-helper.pp policy package
rm tmp/vault-ssh-helper.mod tmp/vault-ssh-helper.mod.fc
[root@foxtrot ~]# semodule -i vault-ssh-helper.pp
```

<details><summary>Details on finding out the SELinux permissions required</summary>

vault-ssh-helper fails when it doesn't have permissions to write logs:

```console
[root@foxtrot ~]# journalctl | grep pam
⋮
Oct 03 14:19:05 foxtrot.vx sshd[1117]: pam_exec(sshd:auth): open of /var/log/vault-ssh.log failed: Permission denied
Oct 03 14:19:05 foxtrot.vx sshd[1115]: pam_exec(sshd:auth): /usr/local/bin/vault-ssh-helper failed: exit code 13
[root@foxtrot ~]# grep avc /var/log/audit/audit.log | audit2allow -R

require {
        type sshd_t;
}
'

#============= sshd_t ==============
logging_create_generic_logs(sshd_t)
```

The SELinux audit log can be translated into SELinux module to be applied using `audit2allow`

```console
[root@foxtrot ~]# grep avc /var/log/audit/audit.log | audit2allow -R -M vault-ssh-helper
******************** IMPORTANT ***********************
To make this policy package active, execute:

semodule -i vault-ssh-helper.pp

[root@foxtrot ~]# semodule -i vault-ssh-helper.pp
```

But the login fails again, because vault-ssh-helper also need the SELinux permission to connect to Vault

```console
[root@foxtrot ~]# journalctl | grep pam
⋮
Oct 03 14:22:47 foxtrot.vx sshd[1160]: pam_exec(sshd:auth): /usr/local/bin/vault-ssh-helper failed: exit code 1
[root@foxtrot ~]# grep avc /var/log/audit/audit.log | audit2allow -R

require {
        type sshd_t;
}

#============= sshd_t ==============
corenet_tcp_connect_trivnet1_port(sshd_t)
logging_create_generic_logs(sshd_t)
```

Translate the additional SELinux audit log into SELinux module using `audit2allow` and apply again allows vault-ssh-helper to work

```console
[root@foxtrot ~]# grep avc /var/log/audit/audit.log | audit2allow -R -M vault-ssh-helper
******************** IMPORTANT ***********************
To make this policy package active, execute:

semodule -i vault-ssh-helper.pp

[root@foxtrot ~]# semodule -i vault-ssh-helper.pp
```

The `vault-ssh-helper.te` policy generated by `audit2allow`

```console
[root@foxtrot ~]# cat vault-ssh-helper.te

policy_module(vault-ssh-helper, 1.0)

require {
        type sshd_t;
}

#============= sshd_t ==============
corenet_tcp_connect_trivnet1_port(sshd_t)
logging_create_generic_logs(sshd_t)
```

</details>

### 3.6. Verify vault-ssh-helper configuration

```console
[root@foxtrot ~]# vault-ssh-helper -verify-only -config /etc/vault-ssh-helper.d/config.hcl
2023/10/06 09:10:33 [INFO] using SSH mount point: ssh-otp
2023/10/06 09:10:33 [INFO] using namespace:
2023/10/06 09:10:33 [INFO] vault-ssh-helper verification successful!
```

### 3.7. Create user

This is the user specified in `default_user=vault` when configuring the SSH OTP role

```console
[root@foxtrot ~]# useradd vault
```

## 4. Generate OTP and login

### 4.1.Generate OTP 

#### 4.1.1. Option 1 - using CLI

```console
[root@client ~]# USER_TOKEN=$(vault login -method=userpass username=test password=P@ssw0rd -format=json | jq -r '.auth | .client_token')
[root@client ~]# VAULT_TOKEN=$USER_TOKEN vault write ssh-otp/creds/foxtrot ip=192.168.17.80
Key                Value
---                -----
lease_id           ssh-otp/creds/foxtrot/9YOTw7l3NITszU0v576LYeoC
lease_duration     768h
lease_renewable    false
ip                 192.168.17.80
key                30238187-6712-365f-c23b-bd972b269386
key_type           otp
port               22
username           vault
```

#### 4.1.2. Option 2 - using UI

![image](https://github.com/joetanx/hashicorp/assets/90442032/700c03ad-fca3-4ca4-9411-93edd1444dea)

![image](https://github.com/joetanx/hashicorp/assets/90442032/fbae00cd-b9a2-47a1-973d-6bda2600b6c3)

![image](https://github.com/joetanx/hashicorp/assets/90442032/e1ebf898-11be-4b05-972c-04fd963a09b2)

![image](https://github.com/joetanx/hashicorp/assets/90442032/51b01be7-8144-4468-97a0-4da6fb2005e7)

### 4.2. Login to target linux host using OTP

```console
[root@client ~]# ssh -o PubkeyAuthentication=no vault@foxtrot.vx
vault@foxtrot.vx's password:
Last login: Fri Oct  6 09:12:25 2023 from 192.168.17.100
[vault@foxtrot ~]$
```
