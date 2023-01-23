#!/bin/bash

for i in {0..50}; do
	curl 10.2.0.193:10180/bounce
	sleep 0.1
done

