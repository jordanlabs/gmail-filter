#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo "Starting Email Filter Generator, go to https://hostname:8443"

cd $DIR
nohup ruby filterweb.rb -e production > $DIR/filterweb.log 2>&1 &
echo "$!" > $DIR/filterweb.pid
