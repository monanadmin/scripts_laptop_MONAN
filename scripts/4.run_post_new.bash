#!/bin/bash 
#-----------------------------------------------------------------------------#
# !SCRIPT: run_post
#
# !DESCRIPTION:
#     Script to run the pos-processing of MONAN model over the forecast horizon.
#     
#     Performs the following tasks:
# 
#        o VCheck all input files before
#        o Creates the submition script
#        o Submit the post
#        o Veriffy all files generated
#        
#
#-----------------------------------------------------------------------------#

. functions.bash

if [ $# -ne 4 -a $# -ne 1 ]
then
   print_instructions $0
   exit
fi

if [ $# -eq 1 ]; then
   clean_if_requested "$0" "$1"
   exit $?
fi

. setenv.bash


# Standart directories variables:---------------------------------------
DIRHOMES=${DIR_SCRIPTS}/scripts_laptop_MONAN; mkdir -p ${DIRHOMES}  
DIRHOMED=${DIR_DADOS}/scripts_laptop_MONAN;   mkdir -p ${DIRHOMED}  
export SCRIPTS=${DIRHOMES}/scripts;    mkdir -p ${SCRIPTS}
DATAIN=${DIRHOMED}/datain;             mkdir -p ${DATAIN}
DATAOUT=${DIRHOMED}/dataout;           mkdir -p ${DATAOUT}
SOURCES=${DIRHOMES}/sources;           mkdir -p ${SOURCES}
EXECS=${DIRHOMED}/execs;               mkdir -p ${EXECS}
#----------------------------------------------------------------------


# Input variables:--------------------------------------
EXP=${1};         #EXP=GFS
RES=${2};         #RES=1024002
YYYYMMDDHHi=${3}; #YYYYMMDDHHi=2024012000
FCST=${4};        #FCST=6
#-------------------------------------------------------


# Local variables--------------------------------------
START_DATE_YYYYMMDD="${YYYYMMDDHHi:0:4}-${YYYYMMDDHHi:4:2}-${YYYYMMDDHHi:6:2}"
START_HH="${YYYYMMDDHHi:8:2}"
maxpost=30

# Calculating default parameters for different resolutions
if [ $RES -eq 1024002 ]; then  #24Km
   NLAT=361
   NLON=721
   STARTLAT=-90.25
   STARTLON=-0.25
   ENDLAT=90.25
   ENDLON=360.25
else  #120Km, 240Km, 384Km, 480Km
   NLAT=181
   NLON=361
   STARTLAT=-90.5
   STARTLON=-0.5
   ENDLAT=90.5
   ENDLON=360.5
fi
#-------------------------------------------------------
mkdir -p ${DATAOUT}/${YYYYMMDDHHi}/Post/logs


files_needed=("${DATAIN}/namelists/include_fields.diag" "${DATAIN}/namelists/convert_mpas.nml" "${DATAIN}/namelists/target_domain.TEMPLATE" "${EXECS}/convert_mpas" "${DATAOUT}/${YYYYMMDDHHi}/Pre/x1.${RES}.init.nc")
for file in "${files_needed[@]}"
do
  if [ ! -s "${file}" ]
  then
    echo -e  "\n${RED}==>${NC} ***** ATTENTION *****\n"	  
    echo -e  "${RED}==>${NC} [${0}] At least the file ${file} was not generated. \n"
    exit -1
  fi
done


# EGK: implementacao do paralelismo de MONAN-scripts/egeon_oper para a tarefa 488 pensando em 241 saidas.

# output model interval is 3 hours
export output_interval=3
echo "output_interval=$output_interval"

# laco para checar nome dos arquivos de saida
for i in $(seq 0 $output_interval $FCST)
do
   hh=${YYYYMMDDHHi:8:2}
   currentdate=`date -d "${YYYYMMDDHHi:0:8} ${hh}:00 ${i} hours" +"%Y%m%d%H"`
   diag_name=MONAN_DIAG_G_MOD_GFS_${YYYYMMDDHHi}_${currentdate}.00.00.x${RES}L55.nc
   echo "diag_name=${diag_name}"
done

# cria diretorios e arquivos/links para cada saida do convert_mpas
for i in $(seq 0 $output_interval $FCST)
do
  cd ${SCRIPTS}
  mkdir -p ${SCRIPTS}/dir.${i}
  cd ${SCRIPTS}/dir.${i}

  ln -sf ${DATAIN}/namelists/include_fields.diag  ${SCRIPTS}/dir.${i}/include_fields.diag
  ln -sf ${DATAIN}/namelists/convert_mpas.nml ${SCRIPTS}/dir.${i}/convert_mpas.nml
  #ln -sf ${DATAIN}/namelists/target_domain ${SCRIPTS}/dir.${i}/target_domain   TODO REMOVE
  sed -e "s,#NLAT#,${NLAT},g;s,#NLON#,${NLON},g;s,#STARTLAT#,${STARTLAT},g;s,#ENDLAT#,${ENDLAT},g;s,#STARTLON#,${STARTLON},g;s,#ENDLON#,${ENDLON},g;" \
      ${DATAIN}/namelists/target_domain.TEMPLATE > ${SCRIPTS}/dir.${i}/target_domain

  rm -rf ${SCRIPTS}/dir.${i}/convert_mpas
  ln -sf ${EXECS}/convert_mpas ${SCRIPTS}/dir.${i}
  ln -sf ${DATAOUT}/${YYYYMMDDHHi}/Pre/x1.${RES}.init.nc ${SCRIPTS}/dir.${i}
done

cd ${SCRIPTS}
. ${SCRIPTS}/setenv_python.bash


cat > PostAtmos1_exe.sh <<EOSH
#!/bin/bash

cd ${SCRIPTS}
. ${SCRIPTS}/setenv.bash

datai=$YYYYMMDDHHi
resolution=$RES

#aux=$(echo "$FCST/3" | bc)
aux=$output_interval
echo "aux=$aux"

for i in \$(seq 0 $output_interval $FCST)
do
   hh=\${datai:8:2}
   currentdate=\`date -d "\${datai:0:8} \${hh}:00 \${i} hours" +"%Y%m%d%H"\`
   diag_name=MONAN_DIAG_G_MOD_GFS_\${datai}_\${currentdate}.00.00.x\${resolution}L55.nc

   cd ${SCRIPTS}/dir.\${i}
   rm -f include_fields
   cp include_fields.diag include_fields
   rm -f latlon.nc
   
   time ./convert_mpas x1.\${resolution}.init.nc ${DATAOUT}/${YYYYMMDDHHi}/Model/\$diag_name  > saida_$i.txt
   echo "./convert_mpas x1.\${resolution}.init.nc ${DATAOUT}/${YYYYMMDDHHi}/Model/\$diag_name"

done

echo "Python Script - Begin"
. ${SCRIPTS}/../.venv/bin/activate
for i in \$(seq 0 $output_interval $FCST)
do
   cd ${SCRIPTS}/dir.\${i}
   python ${SCRIPTS}/group_levels.py ${SCRIPTS}/dir.\${i} latlon.nc latlon_\${i}.nc > saida_python_$i.txt
done

# unload the python's environment
deactivate
echo "Python Script - End"

cd ${DATAOUT}/${YYYYMMDDHHi}/Post/
rm -f diag* latlon*

for i in \$(seq 0 $output_interval $FCST)
do
   mv ${SCRIPTS}/dir.\$i/latlon_\${i}.nc ./latlon_\$i.nc 
done

exit 0
EOSH


cat > PostAtmos2_exe.sh <<EOSH
#!/bin/bash

#cd ${SCRIPTS}

cd ${DATAOUT}/${YYYYMMDDHHi}/Post/

datai=$YYYYMMDDHHi
resolution=$RES

#aux=$(echo "$FCST/3" | bc)
aux=$output_interval
echo "aux=$aux"

echo "CDO - Begin"
pwd
ls -ltr
find . -maxdepth 1 -name "latlon_*" | sort -n -t _ -k 2 | cut -c3- | sed ':a;\$!N;s/\n//;ta;' | sed 's/nc/nc /g' | xargs -I "{}"  cdo mergetime {} latlon.nc
#ldd /usr/bin/cdo
#exit
#cdo mergetime latlon_0.nc latlon_3.nc latlon_6.nc latlon_9.nc latlon_12.nc latlon_15.nc latlon_18.nc latlon_21.nc latlon_24.nc latlon.nc
cdo settunits,hours -settaxis,${START_DATE_YYYYMMDD},${START_HH}:00,3hour latlon.nc MONAN_DIAG_G_POS_${EXP}_${YYYYMMDDHHi}.00.00.x${RES}L55.nc
echo "CDO - End"

# remove temporary latlon_i.nc files generated by group_levels.py
#for i in \$(seq 0 $output_interval $FCST)
#do
#   rm -rf ${DATAOUT}/${YYYYMMDDHHi}/Post/latlon_\${i}.nc
#done

#rm -rf ${SCRIPTS}/dir.* ${DATAOUT}/${YYYYMMDDHHi}/Post/latlon.nc
cp ${EXECS}/VERSION.txt ${DATAOUT}/${YYYYMMDDHHi}/Post

exit 0
EOSH


chmod +x PostAtmos1_exe.sh

spack unload
spack env deactivate
spack unload

chmod +x PostAtmos2_exe.sh

./PostAtmos1_exe.sh 2>&1 | tee PostAtmos1_exe.log
./PostAtmos2_exe.sh 2>&1 | tee PostAtmos2_exe.log

#rm -f ${SCRIPTS}/PostAtmos_exe.sh
