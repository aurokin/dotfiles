#!/bin/bash

wget -O jdtls.tar.gz "https://www.eclipse.org/downloads/download.php?file=/jdtls/milestones/1.9.0/jdt-language-server-1.9.0-202203031534.tar.gz"

mkdir -p jdtls
tar -xf jdtls.tar.gz -C jdtls
rm -f jdtls.tar.gz

rm -rf /usr/local/lib/jdtls
cp -r jdtls /usr/local/lib/jdtls
rm -rf jdtls
