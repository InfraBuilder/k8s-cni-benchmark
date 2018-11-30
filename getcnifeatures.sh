#!/bin/bash

K="kubectl run -n netpol --restart=Never"

echo "Initializing"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  creationTimestamp: null
  name: netpol
spec: {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-netpol
  namespace: netpol
spec:
  podSelector:
    matchLabels:
      run: srv
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          run: granted
  egress:
  - to:
    - podSelector:
        matchLabels:
          run: authorized
EOF

echo "Retrieving MTU"
MTU=$($K -it --rm debug --image=infrabuilder/netbench:client -- ip a 2>/dev/null | grep "eth0.*mtu" | sed -e 's/.*mtu //' -e 's/[^0-9]*$//')

# Starting server
function start_srv {
	NAME=$1
	$K $NAME --image=infrabuilder/netbench:server-http >/dev/null 2>/dev/null
	while true; do kubectl -n netpol get pod/$NAME |grep Running >/dev/null && break; sleep 1; done
	kubectl get -n netpol pod/$NAME -o jsonpath='{.status.podIP}'
}
function client {
	NAME=$1
	SRVIP=$2
	$K -it --rm --image=infrabuilder/netbench:client \
	$1 -- curl --connect-timeout 5 $2 2>/dev/null | grep "Welcome to nginx" > /dev/null && echo yes || echo no
}
function del {
	NAME=$1
	kubectl -n netpol delete po/$NAME 2>/dev/null >/dev/null
}
echo "Starting ingress/egress tests"
# Ingress
IP=$(start_srv srv)
INGRESS=no
if [ "$(client granted $IP)" = "yes" ]
then
	echo "ING SUCCESS: 'Granted' client 'can' access protected server"
	if [ "$(client notgranted $IP)" = "no" ]
	then
		echo "ING SUCCESS: 'Not granted' client 'cannot' access protected server"
		INGRESS=yes
	else
		echo "ING FAIL: 'Not granted' client 'can' access protected server"
	fi
else
	echo "ING FAIL: Granted client cannot access protected server"
fi
del srv
echo "INGRESS = $INGRESS"

# Egress
IP=$(start_srv authorized)
EGRESS=no
if [ "$(client srv $IP)" = "yes" ]
then
	echo "EG SUCCESS: Protected client 'can' access 'authorized' server"
	IP=$(start_srv unauthorized)
	if [ "$(client srv $IP)" = "no" ]
	then
		echo "EG SUCCESS: Protected client 'cannot' access 'unauthorized' server"
		EGRESS=yes
	else
		echo "EG FAIL: Protected client 'can' access 'unauthorized' server"
	fi
	del unauthorized
else
	echo "EG FAIL: Protected client 'cannot' access 'authorized' server"
fi
del authorized

echo "Cleaning"
kubectl delete -f kubernetes/test-netpol.yml 2>/dev/null > /dev/null

echo "Result :"
echo -e "MTU : $MTU\nIngress : $INGRESS\t Egress : $EGRESS"
