#!/usr/bin/perl

# This program launch the jobs on remote clusters

use strict;
use Data::Dumper;
use IO::Socket::INET;
BEGIN {
	my ($scriptPathTmp) = $0 =~ m!(.*/*)!s;
	my ($scriptPath) = readlink($scriptPathTmp);
	if (!defined($scriptPath)){
		$scriptPath = $scriptPathTmp;
	}
	# Relative path of the package
	my @relativePathTemp = split(/\//, $scriptPath);
	my $relativePath = "";
	for (my $i = 0; $i < $#relativePathTemp; $i++){
		$relativePath = $relativePath.$relativePathTemp[$i]."/";
	}
	$relativePath = $relativePath."../";
	# configure the path to reach the lib directory
	unshift(@INC, $relativePath."lib");
	unshift(@INC, $relativePath."Net");
	unshift(@INC, $relativePath."Iolib");
	unshift(@INC, $relativePath."Colombo");
    unshift(@INC, $relativePath."ClusterQuery");
}
use iolibCigri;
use SSHcmdClient;
use NetCommon;
use jobSubmit;

my $base = iolibCigri::connect() ;

# Get active cluster names
my %clusterNames = iolibCigri::get_cluster_names_batch($base);
my %job;
foreach my $j (keys(%clusterNames)){
    print("[RUNNER] check for cluster $j\n");
    while (iolibCigri::get_cluster_job_toLaunch($base,$j,\%job) == 0){
        print("[Runner] Launch the job $job{id} on the node $job{nodeId}\n");
        print(Dumper(%job));

        my $jobId = $job{id};
        my $tmpRemoteFile = "cigri.tmp.$jobId";
        my $resultFile = "~/".iolibCigri::get_cigri_remote_file_name($jobId);

        print("[RUNNER] The job $jobId is in treatment...\n");

        # command to launch on the frontal of the cluster
        my @cmdSSH = (	"echo \\#\\!/bin/sh > ~/$tmpRemoteFile;",
					    "echo \"echo \\\"BEGIN_DATE=\\\"\\`date +\%Y-\%m-\%d\\ \%H:\%M:\%S\\` >> $resultFile\" >> ~/$tmpRemoteFile;",
                        "echo $job{cmd} $job{param} >> ~/$tmpRemoteFile;",
                        "echo CODE=\\\$? >> ~/$tmpRemoteFile;",
                        "echo \"echo \\\"END_DATE=\\\"\\`date +\%Y-\%m-\%d\\ \%H:\%M:\%S\\` >> $resultFile\" >> ~/$tmpRemoteFile;",
                        "echo \"echo \\\"RET_CODE=\\\$CODE\\\" >> $resultFile\" >> ~/$tmpRemoteFile;",
                        "echo \"echo \\\"FINISH=1\\\" >> $resultFile\" >> ~/$tmpRemoteFile;",
                        "echo rm ~$job{user}/$tmpRemoteFile >> ~/$tmpRemoteFile;",
                        "chmod +x ~/$tmpRemoteFile ;",
                        "cd ~$job{user} ;",
                        "sudo -u $job{user} /bin/cp ~/$tmpRemoteFile . ;",
                        "rm ~/$tmpRemoteFile ;"
                        #"sudo -u $job{user} $qsubCommand{$job{batch}} -l nodes=1 -q besteffort `pwd`/$tmpRemoteFile;"
                   );

        my $cmdString = join(" ", @cmdSSH);
        my %cmdResult = SSHcmdClient::submitCmd($job{clusterName},$cmdString);
        if ($cmdResult{STDERR} ne ""){
            print("[RUNNER_STDERR] $cmdResult{STDERR}");
            # test if this is a ssh error
            if (NetCommon::checkSshError($base,$job{clusterName},$cmdResult{STDERR}) != 1){
                iolibCigri::set_job_state($base,$jobId,"Event");
                # treate the SSH error
                colomboCigri::add_new_job_event($base,$jobId,"RUNNER_SUBMIT",$cmdResult{STDERR});
            }
            exit(66);
        }else{
            my $retCode = jobSubmit::jobSubmit($job{clusterName},$job{user},$tmpRemoteFile);
            if ($retCode < 0){
                if ($retCode == -2){
                    print("[RUNNER] There is a mistake, the job $jobId state = ERROR, bad remote batch id\n");
                    iolibCigri::set_job_state($base, $jobId, "Event");
                    colomboCigri::add_new_job_event($base,$jobId,"RUNNER_JOBID_PARSE","There is a mistake, the job $jobId state = ERROR, bad remote batch id");
                }
                exit(66);
            }else{
                iolibCigri::set_job_batch_id($base,$jobId,$retCode);
                iolibCigri::set_job_state($base,$jobId,"Running");
            }
        }
    }
}

iolibCigri::disconnect($base);

exit(0)
