#!/bin/bash 

# Log in and project tenant

token=$(oc create token ${SA_FROM_RBAC} --duration 1800h)
oc login --token=${token} --server=https://api.XXXX:6443 --kubeconfig kc