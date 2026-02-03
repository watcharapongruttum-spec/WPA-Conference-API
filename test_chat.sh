#!/bin/bash

TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJkZWxlZ2F0ZV9pZCI6MjA2LCJleHAiOjE3ODY5NzY2Mjk2LCJpc3MiOiJ3cGEtY29uZmVyZW5jZS1hcGkifQ.ncy_rpKHz6uOl-dXfMJE6tbS1V7uEc6knm_81dANrE4"

wscat -w 5 -c "ws://localhost:3000/cable?token=$TOKEN" \
  -H "Origin: http://localhost:3000" <<WSEOF
{"command":"subscribe","identifier":"{\"channel\":\"ChatChannel\"}"}
WSEOF
