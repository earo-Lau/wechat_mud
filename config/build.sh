#!/bin/bash

APP_NAME=$(cat rebar.config | grep app-name-marker | awk '{print $1}' | tr -d ,)
rm -rf _build/default/lib/${APP_NAME}/
rm -rf _build/default/rel/${APP_NAME}/
rm -f ebin/${APP_NAME}.appup
./config/rebar3 release
