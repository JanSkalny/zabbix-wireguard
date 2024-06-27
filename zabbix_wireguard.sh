#!/bin/bash

fail() {
    echo "$*" 1>&2
    exit 1
}

usage() {
    fail "usage: $0 (discover-peers|latest-handshake PEER|count-peers)"
    exit 1
}

[ $# -lt 1 ] && usage

case "$1" in
discover-peers)
    [ $# -ne 1 ] && usage

    for IFACE in $( wg show interfaces ); do
        # validate interface name
        [[ $IFACE =~ ^wg[0-9]+$ ]] || fail "invalid iface"
        [[ -f "/etc/wireguard/$IFACE.conf" ]] || fail "missing iface config file"

        for RAW_PEER in $( wg show $IFACE peers ); do
            # get peer PublicKey and convert to name from a commentary
            PEER=$(grep -B 2 "PublicKey.*=.*$RAW_PEER" /etc/wireguard/$IFACE.conf | grep '^#' | cut -d ' ' -f 2)
            [ "x$PEER" == "x" ] && fail "peer without name"

            echo "$IFACE $PEER"
        done
    done | jq -Rs 'split("\n")[:-1] | map(split(" ")) | map({"{#WG_PEER}": .[1], "{#WG_IFACE}": .[0]}) | {data: .}'
    ;;

tx|rx)
    [ $# -ne 2 ] && usage
    PEER="$2"
    OP="$1"

    for IFACE in $( wg show interfaces ); do
        # validate interface name
        [[ $IFACE =~ ^wg[0-9]+$ ]] || fail "invalid iface"
        [[ -f "/etc/wireguard/$IFACE.conf" ]] || fail "missing iface config file"

        # check if peer is defined in iface
        RAW_PEER=$(grep -A 2 "^#.*$PEER" /etc/wireguard/$IFACE.conf | grep PublicKey | cut -d = -f 2 | awk '{print $1}')
        [ "x$RAW_PEER" == "x" ] && continue

        # peer found!
        TRANSFER=$( wg show $IFACE transfer | grep "$RAW_PEER" | awk '{print $2" "$3}' )
    done

    [ -z ${TRANSFER+x} ] && fail "peer not found"

    [ $OP == "rx" ] && echo "$TRANSFER" | awk '{print $1}'
    [ $OP == "tx" ] && echo "$TRANSFER" | awk '{print $2}'
    ;;

latest-handshake)
    [ $# -ne 2 ] && usage
    PEER="$2"

    for IFACE in $( wg show interfaces ); do
        # validate interface name
        [[ $IFACE =~ ^wg[0-9]+$ ]] || fail "invalid iface"
        [[ -f "/etc/wireguard/$IFACE.conf" ]] || fail "missing iface config file"

        # check if peer is defined in iface
        RAW_PEER=$(grep -A 2 "^#.*$PEER" /etc/wireguard/$IFACE.conf | grep PublicKey | cut -d = -f 2 | awk '{print $1}')
        [ "x$RAW_PEER" == "x" ] && continue

        # peer found!
        LATEST=$( wg show $IFACE latest-handshakes | grep "$RAW_PEER" | awk '{print $2}' )
        NOW=$(date "+%s")
        DELTA=$(( $NOW - $LATEST ))
    done

    [ -z ${DELTA+x} ] && fail "peer not found"
    echo $DELTA
    ;;

count-peers)
    [ $# -ne 1 ] && usage

    CNT=0
    NOW=$(date "+%s")
    for LATEST in $( wg show all latest-handshakes | awk '{print $3}' ); do
        DELTA=$(( $NOW - $LATEST ))
        # only consider peers with handshake in last 3 minutes
        [[ $DELTA -lt 180 ]] && ((CNT++))
    done

    echo $CNT
    ;;

*)
    usage
    ;;
esac
