#!/usr/bin/python3
import subprocess
import json

print("Molteniron release node...")
try:
    with open('/tmp/molten_id', 'r') as f:
        owner_name = f.read().replace('\n', '')
    out = subprocess.check_output(['bash', '-c', "molteniron release '%s'" % owner_name])
    out_d = json.loads(out)
    if int(out_d['status']) == 200:
        print("Node released Successfully")
except:
    print("No node to release.")
