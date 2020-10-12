#! /bin/bash


CAMPAIGN_PARAMS_ARRAY=()


while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        --cigri-config)
            CIGRI_CONFIG="$2"
            shift # past argument
            shift # past value
            ;;
        --ctrl-config)
            CTRLR_CONFIG="$2"
            shift # past argument
            shift # past value
            ;;
        -b|--cigri-branch)
            CTRL_CIGRI_BRANCH="$2"
            shift # past argument
            shift # past value
            ;;
        -d|--deploy-config)
            DEPLOY_CONFIG="$2"
            shift # past argument
            shift # past value
            ;;
        -c|--campaign)
            CAMPAIGN_PARAMS_ARRAY+=($2)
            shift # past argument
            shift # past value
            ;;
        *)    # unknown option
            echo "Option: $key not found !"
            shift # past argument
            ;;
    esac
done


generate_exec_file() {
    local sleep_time=$1
    local size_of_fIle=$2
    local exec_file_content="$(cat <<EOF
#!/bin/bash
echo \$2 > \$1
sleep ${sleep_time}
EOF
)"

    if [[ ${size_of_file} -ne 0 ]]; then
        local exec_file_content="$exec_file_content; dd if=/dev/zero of=//mnt/nfs0/file-nfs-\$1 bs=\$3 count=1 oflag=direct"
    fi
    return $exec_file_content
}


###############################################################################
## Generate the Campaign

CAMPAIGN_NAMES_ARRAY=()
CAMPAIGN_CONTENT_ARRAY=()
EXEC_FILE_NAMES_ARRAY=()
EXEC_FLIE_CONTENT_ARRAY=()

for raw_campaign_params in ${CAMPAIGN_PARAMS_ARRAY}; do
    campaign_params=$(echo "${raw_campaign_params}" | tr -d "( )")
    number_of_jobs=$(echo "${campaign_params}" | cut -d "," -f 1)
    sleep_time=$(echo "${campaign_params}" | cut -d "," -f 2)
    size_of_file=$(echo "${campaign_params}" | cut -d "," -f 3)
    heaviness=$(echo "${campaign_params}" | cut -d "," -f 4)

    exec_file_content="$(cat <<EOF
#!/bin/bash
echo \$2 > \$1
sleep ${sleep_time}
EOF
)"

    if [[ ${size_of_file} -ne 0 ]]; then
        exec_file_content="$exec_file_content; dd if=/dev/zero of=//mnt/nfs0/file-nfs-\$1 bs=\$3 count=1 oflag=direct"
    fi
    EXEC_FILE_CONTENT_ARRAY+=($exec_file_content)

    exec_file="$HOME/exec_file_${sleep_time}s_${size_of_file}M.sh"
    EXEC_FILE_NAMES_ARRAY+=($exec_file)

    echo "${exec_file_content}" > ${exec_file}

    if [[ ${size_of_file} -ne 0 ]]; then
        campaign_name="campaign_${number_of_jobs}j_${sleep_time}s_${size_of_file}M"
    else
        campaign_name="campaign_${number_of_jobs}j_${sleep_time}s"
    fi
    campaign_file=$HOME/${campaign_name}.json
    CAMPAIGN_NAMES_ARRAY+=($campaign_file)

    file_content="$(cat <<EOF
{
  "name": "${campaign_name}",
  "resources": "resource_id=1",
  "exec_file": "${exec_file}",
  "heaviness": ${heaviness},
  "test_mode": "false",
  "clusters": {
    "cluster_0": {
      "type": "best-effort",
      "walltime": "300"
    }
  },
  "prologue": [
    "mkdir $HOME/workdir",
    "cd $HOME/workdir",
    "touch prologue_works"
  ],
  "epilogue": [
    "cd $HOME/workdir",
    "touch epilogue_works"
  ],
  "params": [
    $(for i in $(seq "$(($number_of_jobs - 1))"); do echo -e "\t\"param$i $i $size_of_file\",";done)
    $(echo -e "\t\"param$number_of_jobs $number_of_jobs $size_of_file\"")
  ]
}
EOF
)"
    CAMPAIGN_CONTENT_ARRAY+=($file_content)
    echo "${file_content}" > ${campaign_file}

done



###############################################################################
## get the hash of the commit

# CIGRI
cd ~/NIX/cigri
git checkout ${CTRL_CIGRI_BRANCH}
CIGRI_COMMIT=$(git rev-parse --verify HEAD)

# BIG-DATA-HPC-G5K-EXPE-TOOLS
cd ~/big-data-hpc-g5k-expe-tools
EXPE_TOOLS_COMMIT=$(git rev-parse --verify HEAD)

###############################################################################
## Setup the env
source ~/env37/bin/activate

###############################################################################
## Deploy
python ~/big-data-hpc-g5k-expe-tools/examples/augu5te/oar_cigri_expe.py ${DEPLOY_CONFIG}


## Save the names of the nodes
CIGRI_SERVER=$(oarstat -u -J | jq -r 'to_entries[].value.assigned_network_address[0]')
OAR_SERVER=$(oarstat -u -J | jq -r 'to_entries[].value.assigned_network_address[1]')
#TODO: Also fileserver

###############################################################################
## Setup CiGri
# Copying all the code
BASENAME_SRC=$HOME/NIX/cigri
BASENAME_DES=/usr/local/share/cigri
cd ${BASENAME_SRC}
# TODO: will also list the files not committed .... how big of an issue is that ?
# We should always be using a commited version of the codebase
# TODO: We could also print the output of git diff ?
for file_to_copy in $(git diff master --name-only | grep -e "lib/" -e "modules/"); do
    ssh root@${CIGRI_SERVER}  "cp ${BASENAME_SRC}/${file_to_copy} ${BASENAME_DES}/$(dirname ${file_to_copy})"
done
# ssh root@${CIGRI_SERVER}  "cp $HOME/NIX/cigri/modules/runner.rb /usr/local/share/cigri/modules"
# ssh root@${CIGRI_SERVER}  "cp $HOME/NIX/cigri/lib/cigri-control.rb /usr/local/share/cigri/lib"
# ssh root@${CIGRI_SERVER}  "cp $HOME/NIX/cigri/lib/cigri-joblib.rb /usr/local/share/cigri/lib"
# ssh root@${CIGRI_SERVER}  "cp $HOME/NIX/cigri/lib/cigri-colombolib.rb /usr/local/share/cigri/lib"
# Copying the conf file
ssh root@${CIGRI_SERVER}  "cp ${CIGRI_CONFIG} /etc/cigri/cigri.conf"
# Path for the logs
ssh root@${CIGRI_SERVER}  "echo 'LOG_CTRL_FILE=\"/tmp/log.txt\"' >> /etc/cigri/cigri.conf"
# Config for the controller
ssh root@${CIGRI_SERVER}  "echo 'CTRL_CIGRI_CONFIG_FILE=\"${CTRLR_CONFIG}\"' >> /etc/cigri/cigri.conf"
# Creating the log file
ssh root@${CIGRI_SERVER}  "touch /tmp/log.txt; chmod 777 /tmp/log.txt"
# Stopping CiGri
ssh root@${CIGRI_SERVER}  "/etc/init.d/cigri force-stop"
# Restarting CiGri
ssh root@${CIGRI_SERVER}  "systemctl restart cigri"

###############################################################################
## Submit a Campaign

for campaign_file in $CAMPAIGN_NAMES_ARRAY; do
    ssh ${CIGRI_SERVER} -o StrictHostKeyChecking=no "gridsub -f ${campaign_file}"
done


###############################################################################
## Wait until Campaign is over
#TODO: Only work for the first campaign
# status=$(gridstat -c 1 | sed -n 's/State:*\([^ ]*\)/\1/p' | sed -e 's/^[ \t]*//' | sed -e 's/[ \t]*$//')

get_status() {
    ssh ${CIGRI_SERVER} -o StrictHostKeyChecking=no "gridstat -c 1 > /tmp/output_gridstat"
    scp -o StrictHostKeyChecking=no  ${CIGRI_SERVER}:/tmp/output_gridstat /tmp/output_gridstat
    cat /tmp/output_gridstat | sed -n 's/State:*\([^ ]*\)/\1/p' | sed -e 's/^[ \t]*//' | sed -e 's/[ \t]*$//'
}

status=$( get_status )

while [ "$status" != "terminated" ]
do
	sleep 15
	# status=$(gridstat -c 1 | sed -n 's/State:*\([^ ]*\)/\1/p' | sed -e 's/^[ \t]*//' | sed -e 's/[ \t]*$//')
	status=$( get_status )
done

###############################################################################
## Get back the logs
log_file=$HOME/logs/log_$(date +"%s").csv
scp -o StrictHostKeyChecking=no  ${CIGRI_SERVER}:/tmp/log.txt ${log_file}

###############################################################################
## Release the resources from the Grid
oardel $(oarstat -u -J | jq "to_entries[].value.Job_Id")



###############################################################################
## Generate the org document
##
ORG_DOC_CONTENT=$(cat <<EOF
#+TITLE: Experiemental Notebook
#+AUTHOR: $(whoami)

* TODO Hypothesis
  Write your hypothesis and comments here
* Experimental Setup
** Version CiGri
*** Branch
The branch used for this experiment was *${CTRL_CIGRI_BRANCH}*
*** Commit
The commit used for this experiment was:
#+NAME: cigri_commit
#+BEGIN_EXAMPLE
${CIGRI_COMMIT}
#+END_EXAMPLE
**** Revert to this commit
#+BEGIN_SRC sh :var cigri_commit=cigri_commit
cd ~/cigri
git checkout \${cigri_commit}
#+END_SRC

**** Revert to latest commit
#+BEGIN_SRC sh
cd ~/cigri
git checkout ${CTRL_CIGRI_BRANCH}
#+END_SRC

** Version Big-data-hpc-g5k-expe-tools
*** Branch
The branch used for this experiment was **
*** Commit
The commit used for this experiment was:
#+NAME: hpc_commit
#+BEGIN_EXAMPLE
${HPC_COMMIT}
#+END_EXAMPLE
**** Revert to this commit
#+BEGIN_SRC sh :var hpc_commit=hpc_commit
cd ~/big-data-hpc-g5k-expe-tools
git checkout ${hpc_commit}
#+END_SRC
**** Revert to latest commit
#+BEGIN_SRC sh
cd ~/big-data-hpc-g5k-expe-tools
git checkout PLOP
#+END_SRC

** Deploy Setup
#+NAME: deploy_config
#+BEGIN_EXAMPLE yaml
$(cat ${DEPLOY_CONFIG})
#+END_EXAMPLE

** Names of the nodes
CiGri server was on: ${CIGRI_SERVER}
OAR server was on: ${OAR_SERVER}

** CiGri Config
#+NAME: cigri_config
#+BEGIN_EXAMPLE
$(cat ${CIGRI_CONFIG})
#+END_EXAMPLE

** Controller Config
#+NAME: ctrl_config
#+BEGIN_EXAMPLE
$(cat ${CTRLR_CONFIG})
#+END_EXAMPLE
** Campaign
*** Exec file
#+NAME: exec_file
#+BEGIN_EXAMPLE
$(cat ${EXEC_FILE})
#+END_EXAMPLE
*** Campaign file
#+NAME: campaign
#+BEGIN_EXAMPLE
$(cat ${CAMPAIGN_FILE})
#+END_EXAMPLE

* Experimental Results
** Log file
#+NAME: results
#+BEGIN_EXAMPLE
$(cat ${log_file})
#+END_EXAMPLE
** R code
#+BEGIN_SRC R :var data=result

#+END_SRC
** TODO Analysis and comments
   Write you analysis and comments here
* Redo this Experiment
Just C-c C-c all the code blocks
** Version CiGri
#+BEGIN_SRC shell :session s1 :var cigri_commit=cigri_commit
cd ~/cigri
git checkout \${cigri_commit}
#+END_SRC
** Version Big-data-hpc-g5k-expe-tools
#+BEGIN_SRC shell :session s1 :var hpc_commit=hpc_commit
cd ~/big-data-hpc-g5k-expe-tools
git checkout \${hpc_commit}
#+END_SRC
** Setup environment
#+BEGIN_SRC shell :session s1
source ~/env37/bin/activate
#+END_SRC
** Deploy
#+BEGIN_SRC shell :session s1 :var deploy_config_content=deploy_config
echo "\${deploy_config_content}" > /tmp/config.yml
cd ~/big-data-hpc-g5k-expe-tools
python oar_cigri_expe.py /tmp/config.yml
#+END_SRC
** Save the names of the nodes
#+BEGIN_SRC shell :session s1
SERVER_CIGRI=\$(oarstat -u -J | jq -r 'to_entries[].value.assigned_network_address[0]')
#+END_SRC
** Setup CiGri
#+BEGIN_SRC shell :session s1 :var cigri_config=cigri_config :var ctrl_config=ctrl_config
# Copying all the code
ssh -t root@\${SERVER_CIGRI} -o StricHostKeyChecking=no "cp -r \$HOME/cigri /usr/local/share/cigri"
# Copying the conf file
echo "\$cigri_config" > /tmp/cigri.conf
scp -o StricHostKeyChecking=no /tmp/cigri.conf root@\${SERVER_CIGRI}:/etc/cigri/cigri.conf
# Path for the logs (not usefull as in the code: TODO make it in the conf)
# ssh -t root@\${SERVER_CIGRI} -o StricHostKeyChecking=no "echo 'LOG_CTRL_FILE="$HOME/logs/log_\$(time).txt" >> /etc/cigri/cigri.conf"
# Config for the controller
echo "\$ctrl_config" > /tmp/ctrl_cigri.json
scp -o StricHostKeyChecking=no /tmp/ctrl_cigri.json \${SERVER_CIGRI}/tmp/ctrl_cigri.json
ssh -t root@\${SERVER_CIGRI} -o StricHostKeyChecking=no "echo 'CTRL_CIGRI_CONFIG_FILE=\"/tmp/ctrl_cigri.json\" >> /etc/cigri/cigri.conf"

# Stopping CiGri
ssh -t root@\${SERVER_CIGRI} -o StricHostKeyChecking=no "/etc/init.d/cigri force-stop"
# Sleeping a bit to make sure we do not start CiGri while it is trying to shutdown
sleep 5
# Restarting CiGri
ssh -t root@\${SERVER_CIGRI} -o StricHostKeyChecking=no "systemctl restart cigri"
#+END_SRC
** Sumbit a Campaign
#+BEGIN_SRC shell :session s1 :var campaign_file=campaign_file
echo "\$campaign_file" > /tmp/campaign_file.json
scp -t root@\${SERVER_CIGRI} -o StricHostKeyChecking=no /tmp/campaign_file.json /tmp/campaign_file.json
ssh \${SERVER_CIGRI} -o StrictHostKeyChecking=no "gridsub -f /tmp/campaign_file.json"
#+END_SRC
** Wait for the experiement to finish
Just wait ...
Go to the CiGri node and run 'gridstat'
** Get back the logs
#+BEGIN_SRC shell :session s1
log_file=\$HOME/logs/log_\$(date +"%s").csv
scp -o StrictHostKeyChecking=no  \${SERVER_CIGRI}:/tmp/log.txt ${log_file}
#+END_SRC
** Release the resources from the Grid
#+BEGIN_SRC shell :session s1
oardel \$(oarstat -u -J | jq "to_entries[].value.Job_Id")
#+END_SRC
EOF
	       )

ORG_DOC=~/notebook_$(date +"%s").org
echo "$ORG_DOC_CONTENT" > ${ORG_DOC}


