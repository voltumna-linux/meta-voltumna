#!/bin/sh

declare -a connectedPorts=($(xrandr | grep " connected" | sed 's/ connected.*//'))
for i in "${!connectedPorts[@]}"; do
    if [ $i -eq 0 ]; then
        xrandr --output ${connectedPorts[i]} --auto
    fi
    if [ -n "${connectedPorts[i+1]}" ]; then
        xrandr --output ${connectedPorts[i+1]} --auto --same-as ${connectedPorts[0]}
    fi
done

disconnectedPorts=$(xrandr | grep " disconnected" | sed 's/ disconnected.*//')
for port in $disconnectedPorts ; do
    xrandr --output $port --off
done
