#!/usr/bin/python3
import subprocess
import json
import time
import sys

print("Molteniron dynamic allocation of node")
owner_name = sys.argv[1]
nodepool = sys.argv[2]
sflag = sys.argv[3]

hardware_info = open("/home/citest/hardware_info", "w")
while True:
    try:
        out = json.loads(subprocess.check_output(['bash', '-c', "molteniron allocate %s 1 %s" %(owner_name, nodepool)]))
        if int(out['status']) == 200:
            node = out['nodes'][list(out['nodes'].keys())[0]]
            if sflag == "strict" and node['node_pool'] != nodepool:
                subprocess.check_output(['bash', '-c', "molteniron release '%s'" % owner_name])
                raise Exception('No nodes')
            blob = json.loads(node['blob'])
            ip = node['ipmi_ip']
            hardware_info.write(ip + " ")
            mac = blob['port_hwaddr']
            hardware_info.write(mac + " ")
            allocation_pool = node['allocation_pool']
            hardware_info.write(allocation_pool)
            hardware_info.close()
            print("Node allocated Successfully")
            break
        else:
            raise Exception('No nodes')
    except:
        print("All nodes are busy. Waiting for node.")
        time.sleep(60)
