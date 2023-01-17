#!/bin/bash
while [[ ! -f "/home/ci_test/ci_ready" && ! -f "/home/ci_test/ci_failed" ]];do sleep 1; done
if [ -f "/home/citest/ci_failed" ];then exit 1; fi
