rm -rf scripts_laptop_MONAN/ .spack/

git clone https://github.com/monanadmin/scripts_laptop_MONAN.git

cd scripts_laptop_MONAN/

git tag

git checkout 0.1.0

git switch -c vB0.1.0

cd scripts

./install_spack.bash

source spack/env.sh