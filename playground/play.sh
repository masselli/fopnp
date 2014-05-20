#!/bin/bash

set -e

if [ "$#" = "0" ]
then
    container=h1
else
    container=$1
    shift
fi
if [ "$#" = "0" ]
then
    set /bin/bash
fi
ppid=$$

if [ ! -d /proc/sys/net/ipv4/conf/playhome ]
then
    echo 'Error: "network.sh" is not yet up and running' >&2
    exit 1
fi

if [ -n "${container/h[1-9]/}" ]
then
    echo 'Error: hostname should be between "h1" and "h9"' >&2
    exit 1
fi

n=${container/h/}

setup () {

    # At the bottom of this script, our parent process uses "exec" to
    # replace itself with an interactive "docker" whose networking we
    # need to configure.  So, as long as our parent process is still
    # running, we watch for the container to appear.

    pid=""
    while [ -z "$pid" ]
    do
        if ! ps -p $ppid >/dev/null
        then
            echo "play.sh: giving up and exiting, because container died"
            exit 1
        fi
        sleep .25
        pid=$(docker inspect -f '{{.State.Pid}}' $container 2>/dev/null ||true)
    done

    # The container now exists, so we can configure its networking.

    if ip link show $container-peer >/dev/null 2>&1
    then
        # Clean up after previous attempt to plumb this container.
        sudo ip link del $container-peer
    fi
    sudo rm -f /var/run/netns/$pid
    sudo ln -s /proc/$pid/ns/net /var/run/netns/$pid
    sudo ip link add $container-eth0 type veth peer name $container-peer
    sudo ip link set $container-peer netns $pid
    sudo ip netns exec $pid ip link set dev $container-peer name eth0
    sudo ip netns exec $pid ip link set dev eth0 up
    sudo ip netns exec $pid ip addr add 192.168.1.1$n/24 dev eth0
    sudo ip netns exec $pid ip route add default via 192.168.1.1
    sudo brctl addif playhome $container-eth0
    sudo ip link set dev $container-eth0 up
    sudo rm /var/run/netns/$pid
}

py3=$(readlink -f ../py3)
sudo true  # make user type password before "setup" goes into background
setup &
exec docker run --name=$container --hostname=$container --privileged=true \
     --net=none --dns=10.1.1.1 --dns-search=example.com \
     --volume=$py3:/py3 --rm -ti fopnp/base "$@"
