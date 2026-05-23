Host bastion
    HostName ${bastion_public_ip}
    User ubuntu
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host 10.0.1.* 10.0.2.*
    ProxyJump bastion
    User ubuntu
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null