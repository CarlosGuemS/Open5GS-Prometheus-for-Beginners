#!/bin/bash
n=901700000000001

key='465B5CE8B199B49FAA5F0A2EE238A6BC'
opc='E8ED289DEBA952E4283B54E88E6183CA'

for i in $(seq 0 {NUM_UES}); do
    {PATH_2_open5gs}/open5gs/misc/db/open5gs-dbctl add $n $key $opc
    n=$(($n+1))
done