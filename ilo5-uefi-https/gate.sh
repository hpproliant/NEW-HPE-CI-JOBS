#!/bin/bash
env
set -e
set -x

report_failed() {
  touch /tmp/job-failed
}

trap "report_failed" ERR


echo "*********Started running 'ilo5-uefi-https' gate*************"

echo "Setting gate environment."
myip=$(ip -f inet addr show eth0 | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')
ilo_ip=$(cat /home/citest/hardware_info | awk '{print $1}')
mac=$(cat /home/citest/hardware_info | awk '{print $2}')
pool=$(cat /home/citest/hardware_info | awk '{print $3}')
str=$(echo $pool|cut -d "," -f 1)
end=$(echo $pool|cut -d "," -f 2)
patch_id=$1

echo "Injecting ironic patch."
docker cp /home/citest/NEW-HPE-CI-JOBS/ironic-patch-injection ironic_conductor:/citest
docker cp /home/citest/NEW-HPE-CI-JOBS/ironic-patch-injection ironic_api:/citest
docker exec -u root ironic_conductor bash /citest/ironic-patch-injection $patch_id
docker exec -u root ironic_api bash /citest/ironic-patch-injection $patch_id

echo "Generate TLS cert."
mkdir /home/citest/ssl_files
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /home/citest/ssl_files/uefi_signed.key -out /home/citest/ssl_files/uefi_signed.crt -subj "/C=IN/ST=K/CN=$myip"

echo "Making other ironic changes."
docker exec -u root ironic_conductor mkdir /root/ssl_files
docker cp /home/citest/ssl_files/uefi_signed.crt ironic_conductor:/root/ssl_files/
docker cp /home/citest/ssl_files/uefi_signed.key ironic_conductor:/root/ssl_files/
docker exec -u root ironic_http mkdir /root/ssl_files
docker cp /home/citest/ssl_files/uefi_signed.crt ironic_http:/root/ssl_files/
docker cp /home/citest/ssl_files/uefi_signed.key ironic_http:/root/ssl_files/
sudo rm -f /etc/kolla/ironic-http/httpd.conf
sudo cp /home/citest/NEW-HPE-CI-JOBS/ilo5-uefi-https/files/httpd.conf /etc/kolla/ironic-http/httpd.conf
sudo sed -i "s/8.8.8.8/$myip/g" /etc/kolla/ironic-http/httpd.conf
sudo sed -i '/^\[DEFAULT\]$/,/^\[/ s/^debug = True/webserver_verify_ca = \/root\/ssl_files\/uefi_signed.crt/' /etc/kolla/ironic-conductor/ironic.conf
sudo sed -i '/^\[ilo\]$/,/^\[/ s/^use_web_server_for_images = true/use_web_server_for_images = true\nkernel_append_params = \"ipa-insecure=True ipa-insecure=1\"/' /etc/kolla/ironic-conductor/ironic.conf
sudo sed -i "/^\[deploy\]$/,/^\[/ s/^http_url = http:\/\/$myip:8089/http_url = https:\/\/$myip:443/" /etc/kolla/ironic-conductor/ironic.conf
sudo sed -i "/^\[pxe\]$/,/^\[/ s/^kernel_append_params = nofb nomodeset vga=normal console=tty0 console=ttyS0,115200n8/kernel_append_params = nofb nomodeset vga=normal console=tty0 console=ttyS0,115200n8 ipa-insecure=1/" /etc/kolla/ironic-conductor/ironic.conf
sudo sed -i "/^\[agent\]$/,/^\[/ s/^deploy_logs_collect = always/deploy_logs_collect = always\nverify_ca = False\n/" /etc/kolla/ironic-conductor/ironic.conf

docker restart ironic_http
docker restart ironic_api
docker restart ironic_conductor
sleep 10

echo "Create neutron network."
openstack network create  --provider-network-type flat --provider-physical-network provider --share baremetal
openstack subnet create --allocation-pool start=$str,end=$end --no-dhcp --gateway 169.16.1.40 --network baremetal ext-subnet --subnet-range 169.16.1.0/24

echo "Configure external DHCP."
docker stop ironic_dnsmasq
cat <<EOF >/tmp/dhcpd.conf
allow booting;
default-lease-time 600;
max-lease-time 7200;

subnet 169.16.1.0 netmask 255.255.255.0 {
        deny unknown-clients;
}

host ilo {
                hardware ethernet $mac;
                fixed-address $end;
}
EOF
sudo cp /tmp/dhcpd.conf /etc/dhcp/dhcpd.conf
sudo systemctl restart dhcpd.service

echo "Creating ironic node."
openstack baremetal node create --driver ilo5 --driver-info ilo_address=$ilo_ip --driver-info ilo_username=Administrator --driver-info ilo_password=weg0th@ce@r --driver-info ilo_verify_ca=False --boot-interface ilo-uefi-https --deploy-interface direct --management-interface ilo5 
NODE=$(openstack baremetal node list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)
openstack baremetal node set --driver-info deploy_kernel=https://$myip:443/ironic-agent.kernel --driver-info deploy_ramdisk=https://$myip:443/ironic-agent.initramfs --driver-info bootloader=https://$myip:443/ir-deploy-redfish.efiboot --instance-info image_source=https://$myip:443/rhel009_wholedisk_image.qcow2 --instance-info image_checksum=6d2a8427a4608d1fcc7aa2daed8ad5c6 --instance-info root_gb=25  --property capabilities='boot_mode:uefi' --property cpus=1 --property memory_mb=24288 --property local_gb=40 --property cpu_arch=x86_64 $NODE
openstack baremetal port create --node $NODE $mac
openstack baremetal node manage $NODE
sleep 10
openstack baremetal node provide $NODE
openstack baremetal node power off $NODE

echo "Executing gate test."
cd /home/citest/gate-test/tempest
export OS_TEST_TIMEOUT=3000
net_id=$(openstack network list -f value -c ID)
sed -i "s/11.11.11.11.11/$net_id/g" /home/citest/gate-test/tempest/etc/tempest.conf
sed -i "s/http:\/\/169.16.1.40:9000\/rhel009_wholedisk_image.qcow2/https:\/\/$myip:443\/rhel009_wholedisk_image.qcow2/g" /home/citest/gate-test/tempest/etc/tempest.conf
sudo -E stestr -vvv --debug run --serial ironic_standalone.test_basic_ops.BaremetalIlo5UefiHTTPSWholediskHttpsLink.test_ip_access_to_server
openstack baremetal node list|grep "active"
if [ $? -ne 0 ]; then
    echo "CI has failed. Will purposefully raise error."
    failed
fi
echo "*********ilo5-uefi-https gate: PASSED*************"
