#!/bin/bash -ex
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1


# Add current hostname to hosts file
tee /etc/hosts <<EOL
127.0.0.1   localhost localhost.localdomain `hostname`
EOL

for i in {1..7}
do
  echo "Attempt: ---- " $i
  yum -y update  && break || sleep 60
done

#yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
#restart amazon-ssm-agent
yum install -y amazon-ssm-agent || true

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart amazon-ssm-agent || true
else
  service amazon-ssm-agent restart || true
fi

${logging}

${gitlab_runner}

# -----------------------------
# Scheduled Docker cleanup
# -----------------------------
# Ensure required tools exist (flock is usually in util-linux; install if missing)
command -v flock >/dev/null 2>&1 || yum -y install util-linux || true

cat >/etc/cron.d/docker-prune <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 3 * * * root /usr/bin/flock -n /var/run/docker-prune.lock /usr/bin/docker system prune -af --volumes --filter "until=24h" >> /var/log/docker-prune.log 2>&1
EOF

chmod 0644 /etc/cron.d/docker-prune

# Ensure cron service is running (Amazon Linux / RHEL family)
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable crond || true
  systemctl restart crond || true
else
  chkconfig crond on || true
  service crond restart || true
fi
