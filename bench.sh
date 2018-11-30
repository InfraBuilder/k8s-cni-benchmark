#!/bin/bash

BENCH_CYCLE="3"
IPERFTIME="120"

function log { echo $(date "+%Y-%m-%d %H:%M:%S") $@; }
function info { log INFO "$@"; }
function warning { log WARNING "$@"; }
function error { log ERROR "$@"; }
function fatal { log FATAL "$@"; exit 2; }

#==============================================================================
# Pre-flight checks
#==============================================================================

cd $(dirname $0)

source lib/ssh.sh

export KUBE_CONFIG="$(pwd)/kubeconfig"

function bench_kubectl {
	kubectl run --restart=Never --rm \
		--overrides='{"apiVersion":"v1","spec":{"nodeSelector":{"kubernetes.io/hostname":"s03"}}}' $@
}

function mon_start {
	TIME=$(date +%s)
}
function mon_end {
	TIME=$(( $(date +%s) - $TIME ))
	echo -e "$(lssh s03 ./stats.sh $TIME 2>/dev/null)\t$(lssh s02 ./stats.sh $TIME 2>/dev/null)"
}

SUMMARY=""


info "Waiting for systems to be idle ..."
sleep 60

info "Getting idle consumption (1min poll)"
mon_start
sleep 60
SUMMARY="$SUMMARY\t$(mon_end)"

#==============================================================================
# Iperf
#==============================================================================
info "Starting iperf3 server"
kubectl apply -f kubernetes/server-iperf3.yml > /dev/null

info "Waiting for pod to be alive"
while true; do kubectl get pod|grep iperf-srv |grep Running >/dev/null && break; sleep 1; done

# Retrieving Pod IP address
IP=$(kubectl get pod/iperf-srv -o jsonpath='{.status.podIP}')
info "Server iperf3 is listening on $IP"

#===[ TCP ]=======
info "Launching benchmark for TCP"
TOT_TCP=0
for i in $(seq 1 $BENCH_CYCLE)
do
	mon_start
	RES_TCP=$(bench_kubectl bench -it --image=infrabuilder/netbench:client -- iperf3 -c $IP -O $(( $IPERFTIME / 10 )) -f m -t $IPERFTIME 2>/dev/null \
		| grep receiver| awk '{print $7}')
	[ "$i" = "1" ] && MON="$(mon_end)"
	TOT_TCP=$(( $TOT_TCP + $RES_TCP ))
	info "TCP $i/$BENCH_CYCLE : $RES_TCP Mbit/s"
	sleep 1
done
RES_TCP=$(( $TOT_TCP / $BENCH_CYCLE ))
info "TCP result $RES_TCP Mbit/s"
SUMMARY="$SUMMARY\t$RES_TCP\t$MON"

#===[ UDP ]=======
info "Launching benchmark for UDP"
TOT_UDP=0
TOT_JIT=0
TOT_DROP=0
for i in $(seq 1 $BENCH_CYCLE)
do
	mon_start
	read RES_UDP JITTER_UDP DROP_UDP <<< $(bench_kubectl bench -it --image=infrabuilder/netbench:client -- iperf3 -u -b 0 -c $IP -O $(( $IPERFTIME / 10 )) -w 256K -f m -t $IPERFTIME 2>/dev/null \
		| grep receiver| sed 's/.* sec//'|awk '{print $3" "$5" "$8}' | tr -d "()%")
	[ "$i" = "1" ] && MON="$(mon_end)"
	TOT_UDP=$(( $TOT_UDP + $RES_UDP ))
	PART_JIT=$(printf "%.3f" $JITTER_UDP| tr -d "."| sed 's/^0*//')
	TOT_JIT=$(( $TOT_JIT + $PART_JIT ))
	TOT_DROP=$(( $TOT_DROP + $( printf "%.0f" $DROP_UDP) ))
	info "UDP $i/$BENCH_CYCLE : $RES_UDP Mbit/s ${PART_JIT}us jitter ${DROP_UDP}% drop"
	sleep 1
done
RES_UDP=$(( $TOT_UDP / $BENCH_CYCLE ))
JIT_UDP=$(( $TOT_JIT / $BENCH_CYCLE ))
DROP_UDP=$(( $TOT_DROP / $BENCH_CYCLE ))
info "UDP result $RES_UDP Mbit/s ${JIT_UDP}us jitter ${DROP_UDP}% drop"
SUMMARY="$SUMMARY\t$RES_UDP\t$JIT_UDP\t$DROP_UDP\t$MON"

info "Cleaning resources"
kubectl delete -f kubernetes/server-iperf3.yml >/dev/null

#==============================================================================
# HTTP
#==============================================================================
info "Starting HTTP server"
kubectl apply -f kubernetes/server-http.yml >/dev/null

info "Waiting for pod to be alive"
while true; do kubectl get pod|grep http-srv |grep Running >/dev/null && break; sleep 1; done

IP=$(kubectl get pod/http-srv -o jsonpath='{.status.podIP}')
info "Server HTTP is listening on $IP"

info "Launching benchmark for HTTP"
TOT_HTTP=0
for i in $(seq 1 $BENCH_CYCLE)
do
	mon_start
	RES_HTTP=$(bench_kubectl bench -it --image=infrabuilder/netbench:client \
		-- curl -o /dev/null -skw "%{speed_download}" http://$IP/10G.dat 2>/dev/null| sed 's/\..*//' )
	[ "$i" = "1" ] && MON="$(mon_end)"
	TOT_HTTP=$(( $TOT_HTTP + RES_HTTP ))
	info "HTTP $i/$BENCH_CYCLE : $(( $RES_HTTP * 8 / 1024/ 1024 )) Mbit/s"
	sleep 1
done
RES_HTTP=$(( $TOT_HTTP * 8 / $BENCH_CYCLE / 1024 / 1024 ))

info "HTTP result $RES_HTTP Mbit/s"
SUMMARY="$SUMMARY\t$RES_HTTP\t$MON"

info "Cleaning resources"
kubectl delete -f kubernetes/server-http.yml >/dev/null


#==============================================================================
# FTP
#==============================================================================
info "Starting FTP server"
kubectl apply -f kubernetes/server-ftp.yml >/dev/null

info "Waiting for pod to be alive"
while true; do kubectl get pod|grep ftp-srv |grep Running >/dev/null && break; sleep 1; done

IP=$(kubectl get pod/ftp-srv -o jsonpath='{.status.podIP}')
info "Server FTP is listening on $IP"

info "Launching benchmark for FTP with $BENCH_CYCLE cycles"
TOT_FTP=0
for i in $(seq 1 $BENCH_CYCLE)
do
	mon_start
	RES_FTP=$(bench_kubectl bench -it --image=infrabuilder/netbench:client \
		-- curl -o /dev/null -skw "%{speed_download}" ftp://$IP/10G.dat 2>/dev/null| sed 's/\..*//' )
	[ "$i" = "1" ] && MON="$(mon_end)"
	TOT_FTP=$(( $TOT_FTP + RES_FTP ))
	info "FTP $i/$BENCH_CYCLE : $(( $RES_FTP * 8 / 1024/ 1024 )) Mbit/s"
	sleep 1
done
RES_FTP=$(( $TOT_FTP * 8 / $BENCH_CYCLE / 1024 / 1024 ))

info "FTP result $RES_FTP Mbit/s"
SUMMARY="$SUMMARY\t$RES_FTP\t$MON"

info "Cleaning resources"
kubectl delete -f kubernetes/server-ftp.yml >/dev/null


#==============================================================================
# SCP
#==============================================================================
info "Starting SCP server"
kubectl apply -f kubernetes/server-ssh.yml >/dev/null

info "Waiting for pod to be alive"
while true; do kubectl get pod|grep ssh-srv |grep Running >/dev/null && break; sleep 1; done

IP=$(kubectl get pod/ssh-srv -o jsonpath='{.status.podIP}')
info "Server SCP is listening on $IP"

info "Launching benchmark for SCP with $BENCH_CYCLE cycles"
TOT_SCP=0
for i in $(seq 1 $BENCH_CYCLE)
do
	mon_start
	RES_SCP=$(bench_kubectl bench -it --image=infrabuilder/netbench:client \
		-- sshpass -p root scp  -o UserKnownHostsFile=/dev/null \
		-o StrictHostKeyChecking=no -v root@$IP:/root/10G.dat ./ 2>/dev/null\
		| grep "Bytes per second" |sed -e 's/.*received //' -e 's/\..*$//' )
	[ "$i" = "1" ] && MON="$(mon_end)"
	TOT_SCP=$(( $TOT_SCP + RES_SCP ))
	info "SCP $i/$BENCH_CYCLE : $(( $RES_SCP * 8 / 1024/ 1024 )) Mbit/s"
	sleep 1
done
RES_SCP=$(( $TOT_SCP * 8 / $BENCH_CYCLE / 1024 / 1024 ))

info "SCP result $RES_SCP Mbit/s"
SUMMARY="$SUMMARY\t$RES_SCP\t$MON"

info "Cleaning resources"
kubectl delete -f kubernetes/server-ssh.yml >/dev/null


#==============================================================================
# SUMMARY
#==============================================================================
echo "========================================================================="
#echo -e "SUMMARY: $RES_TCP\t$RES_UDP\t$JIT_UDP\t$DROP_UDP\t$RES_HTTP\t$RES_FTP\t$RES_SCP"
echo -e "SUMMARY: $SUMMARY"
echo "========================================================================="
