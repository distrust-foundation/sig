#!/bin/bash

source /home/test/sig/test/test_helper.bash
setup
eval "$(declare -F | sed -e 's/-f /-fx /')"
bash
