#!/usr/bin/python3
import subprocess
import json
import time
import sys

print("Molteniron dynamic allocation of node")
owner_name = sys.argv[1]
nodepool = sys.argv[2]
hardware_info = open("/home/citest/hardware_info", "w")
while True:
    try:
        out = subprocess.check_output(['bash', '-c', "molteniron allocate %s 1 %s" %(owner_name, nodepool)])
        d = json.loads(out)
        if int(d['status']) == 200:
            ip = subprocess.check_output(['bash', '-c', "molteniron get_field '%s' 'ipmi_ip'" % owner_name])
            ip_d = json.loads(ip)
            hardware_info.write(ip_d['result'][0]['field'])
            mac = subprocess.check_output(['bash', '-c', "molteniron get_field '%s' 'port_hwaddr'" % owner_name])
            mac_d = json.loads(mac)
            hardware_info.write(" ")
            hardware_info.write(mac_d['result'][0]['field'])
            hardware_info.close()
            print("Node allocated Successfully")
            break
        else:
            raise Exception('No nodes')
    except:
        print("All nodes are busy. Waiting for node.")
        time.sleep(60)
