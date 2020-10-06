#! /run/current-system/sw/bin/bash

#TODO: gerer les params
CIGRI_CONFIG=$1
CTRLR_CONFIG=$2
CAMPAIGN_FILE=$3
CAMPAIGN_EXEC_FILE=$4
DEPLOY_CONFIG=$5

CTRL_CIGRI_BRANCH=$6

ORG_DOC=notebook_$(date +"%s").org

###############################################################################
## Get the hash of the commit

# CIGRI
cd ~/cigri
git checkout ${CTRL_CIGRI_BRANCH}
CIGRI_COMMIT=$(git rev-parse --verify HEAD)

# BIG-DATA-HPC-G5K-EXPE-TOOLS
cd ~/big-data-hpc-g5k-expe-tools
EXPE_TOOLS_COMMIT=$(git rev-parse --verify HEAD)

###############################################################################
## Setup the env
source ~/env37/bin/activate
cd ~/big-data-hpc-g5k-expe-tools

###############################################################################
## Deploy
python oar_cigri_expe.py ${DEPLOY_CONFIG}


## Save the names of the nodes
CIGRI_SERVER=$(oarstat -u -J | jq -r 'to_entries[].value.assigned_network_address[0]')
OAR_SERVER=$(oarstat -u -J | jq -r 'to_entries[].value.assigned_network_address[1]')
#TODO: Also fileserver

###############################################################################
## Setup CiGri
# Copying all the code
ssh -t root@${CIGRI_SERVER} -o StricHostKeyChecking=no "cp -r $HOME/cigri /usr/local/share/cigri"
# Copying the conf file
ssh -t root@${CIGRI_SERVER} -o StricHostKeyChecking=no "cp ${CIGRI_CONFIG} /etc/cigri/cigri.conf"
# Path for the logs (not usefull as in the code: TODO make it in the conf)
# ssh -t root@${CIGRI_SERVER} -o StricHostKeyChecking=no "echo 'LOG_CTRL_FILE="$HOME/logs/log_$(time).txt" >> /etc/cigri/cigri.conf"
# Config for the controller
ssh -t root@${CIGRI_SERVER} -o StricHostKeyChecking=no "echo 'CTRL_CIGRI_CONFIG_FILE=\"${CTRLR_CONFIG}\" >> /etc/cigri/cigri.conf"

# Stopping CiGri
ssh -t root@${CIGRI_SERVER} -o StricHostKeyChecking=no "/etc/init.d/cigri force-stop"
# Restarting CiGri
ssh -t root@${CIGRI_SERVER} -o StricHostKeyChecking=no "systemctl restart cigri"

###############################################################################
## Submit a Campaign
ssh ${CIGRI_SERVER} -o StrictHostKeyChecking=no "gridsub -f ${CAMPAIGN_FILE}"


###############################################################################
## Wait until Campaign is over
#TODO: Only work for the first campaign
# status=$(gridstat -c 1 | sed -n 's/State:*\([^ ]*\)/\1/p' | sed -e 's/^[ \t]*//' | sed -e 's/[ \t]*$//')

get_status() {
    ssh ${CIGRI_SERVER} -o StrictHostKeyChecking=no "gridstat -c 1 > /tmp/output_gridstat"
    scp -o StrictHostKeyChecking=no  ${CIGRI_SERVER}:/tmp/output_gridstat /tmp/output_gridstat
    cat /tmp/output/gridstat | sed -n 's/State:*\([^ ]*\)/\1/p' | sed -e 's/^[ \t]*//' | sed -e 's/[ \t]*$//'
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
org_doc_content=$(cat <<EOF
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
** Campaign File
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
echo "$ORG_DOC_CONTENT" > ${ORG_DOC}


