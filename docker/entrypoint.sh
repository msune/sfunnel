#!/bin/bash

set -e
#set -x

#Env variables
N_ATTEMPTS=${N_ATTEMPTS:-6}
RETRY_DELAY=${RETRY_DELAY:-3}

_IFACES=$(ls /sys/class/net | tr "\n" " " | sed 's/\s*$//g')
IFACES=${IFACES:-$_IFACES}

PROG=/opt/sfunnel/src/tc_sfunnel.o

#Compile eBPF program only if rulesset are defined at load time
#either via file or ENV
compile(){
	cd /opt/sfunnel/src
	make
}

#$1: PROG
#$2: IFACE
load_prog(){
	tc qdisc add dev $2 clsact
	tc filter add dev $2 ingress bpf da obj $1 sec funnel verbose
}

# Splash and useful info
echo "[INFO] sfunnel "
echo "[INFO] ENVs:"
echo "  \$N_ATTEMPTS='$N_ATTEMPTS'"
echo "  \$RETRY_DELAY='$RETRY_DELAY'"
echo "  \$IFACES='$IFACES'"
echo "[INFO] Container info:"
echo "  Kernel: $(uname -a)"
echo "  Debian: $(cat /etc/debian_version)"
echo "  python3: $(python3 --version)"
echo "  clang: $(clang --version)"
echo "  iproute2: $(ip -V)"

#If SFUNNEL_RULESET is defined, create the file
if [[ "$SFUNNEL_RULESET" != "" ]]; then
	echo "[INFO] SFUNNEL_RULESET='$SFUNNEL_RULESET'"
	echo $SFUNNEL_RULESET > /opt/sfunnel/src/ruleset
fi

#Compile sfunnel only if new ruleset is specified
if test -f /opt/sfunnel/src/ruleset; then
	echo "[INFO] Compiling sfunnel with custom ruleset..."
	echo "==="
	cat /opt/sfunnel/src/ruleset
	echo "==="
	compile
else
	echo "[INFO] Using default ruleset..."
	echo "==="
	cat /opt/sfunnel/src/ruleset.default
	echo "==="
fi

#Load

echo ""
echo -e "[INFO] Attaching BPF program '$PROG' to IFACES={$IFACES} using clsact qdisc...\n"
for IFACE in $IFACES; do
	for ((i=1; i<=$N_ATTEMPTS; i++)); do
		echo "[INFO] Attaching BPF program to '$IFACE'..."
		load_prog $PROG $IFACE && break
		echo "[WARNING] attempt $i failed on iface '$IFACE'. Retrying in $RETRY_DELAY seconds..."
		sleep 5
	done
	if [[ $i -ge $N_ATTEMPTS ]]; then
		echo "[ERROR] unable to attach BPF program to '$IFACE'!"
		exit 1
	fi
	echo -e "[INFO] Successfully attached BPF program to '$IFACE'.\n"
done
echo "[INFO] Successfully attached '$PROG' to interfaces {$IFACES}"
