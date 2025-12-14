mkdir -p /etc/gitlab-runner
cat > /etc/gitlab-runner/config.toml <<- EOF

${runners_config}

EOF

${pre_install}

if [[ `echo ${runners_executor}` == "docker" ]]
then
  yum install docker -y
  usermod -a -G docker ec2-user
  service docker start
fi

curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh | bash
yum install gitlab-runner -y
curl -L https://github.com/docker/machine/releases/download/v${docker_machine_version}/docker-machine-`uname -s`-`uname -m` >/tmp/docker-machine && \
  chmod +x /tmp/docker-machine && \
  cp /tmp/docker-machine /usr/local/bin/docker-machine && \
  ln -s /usr/local/bin/docker-machine /usr/bin/docker-machine


token=$(aws ssm get-parameters --names "${secure_parameter_store_runner_token_key}" --with-decryption --region "${secure_parameter_store_region}" | jq -r ".Parameters | .[0] | .Value")
if [[ `echo ${runners_token}` == "__REPLACED_BY_USER_DATA__" && `echo $token` == "null" ]]
then
  reg_token_len=$${#gitlab_runner_registration_token}
  reg_token_prefix="$${gitlab_runner_registration_token:0:4}"

  echo "GitLab registration token length: $reg_token_len" >> /var/log/user-data.log
  echo "GitLab registration token prefix (masked): ${reg_token_prefix}****" >> /var/log/user-data.log
  resp=$(curl -sS --request POST -L "${runners_gitlab_url}/api/v4/runners" \
    --form "token=${gitlab_runner_registration_token}" \
    --form "tag_list=${gitlab_runner_tag_list}" \
    --form "description=${giltab_runner_description}" \
    --form "locked=${gitlab_runner_locked_to_project}" \
    --form "run_untagged=${gitlab_runner_run_untagged}" \
    --form "maximum_timeout=${gitlab_runner_maximum_timeout}")

  echo "GitLab runner register response: $resp" >> /var/log/user-data.log

  token=$(echo "$resp" | jq -r '.token // empty')
  aws ssm put-parameter --overwrite --type SecureString  --name "${secure_parameter_store_runner_token_key}" --value $token --region "${secure_parameter_store_region}"
fi

sed -i.bak "s/__REPLACED_BY_USER_DATA__/$token/g" /etc/gitlab-runner/config.toml

${post_install}

service gitlab-runner restart
chkconfig gitlab-runner on
