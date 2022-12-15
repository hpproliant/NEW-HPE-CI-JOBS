#!/bin/bash
env
set -e
set -x
set -o pipefail

echo "Deploy Kolla ansible."
kolla-ansible -i /home/citest/all-in-one deploy

echo "Configure Neutron."

echo "Configure Tempest."
