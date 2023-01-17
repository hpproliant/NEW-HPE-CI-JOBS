#!/bin/bash
set -x

echo "Cherry-picking patch inside ironic containers"
sed -i -e "s|reference|$1|g" /home/citest/NEW-HPE-CI-JOBS/Dockerfiles/ironic-conductor-dockerfile
sed -i -e "s|reference|$1|g" /home/citest/NEW-HPE-CI-JOBS/Dockerfiles/ironic-api-dockerfile

echo "Build new ironic containers"
docker build -t kolla/ironic-conductor:14.6.0 - </home/citest/NEW-HPE-CI-JOBS/Dockerfiles/ironic-conductor-dockerfile --network host
docker build -t kolla/ironic-api:14.6.0 - </home/citest/NEW-HPE-CI-JOBS/Dockerfiles/ironic-api-dockerfile --network host

echo "Deploy ironic."
export ANSIBLE_LOG_PATH=/home/citest/gate_logs/ansible_ironic_reconfigure.log
sudo sed -i "s/enable_ironic: \"no\"/enable_ironic: \"yes\"/g" /etc/kolla/globals.yml
kolla-ansible -i /home/citest/all-in-one deploy -t ironic
