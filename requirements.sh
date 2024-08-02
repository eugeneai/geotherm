#!/bin/bash

while read pkg; do
	echo $pkg
	echo julia -e "import Pkg; Pkg.add($pkg)"
	julia -e "import Pkg; Pkg.add($pkg)"
done < requirements.txt

