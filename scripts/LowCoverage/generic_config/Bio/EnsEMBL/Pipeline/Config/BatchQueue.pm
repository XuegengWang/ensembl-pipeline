=head1 LICENSE

  Copyright (c) 1999-2012 The European Bioinformatics Institute and
  Genome Research Limited.  All rights reserved.

  This software is distributed under a modified Apache license.
  For license details, please see

    http://www.ensembl.org/info/about/code_licence.html

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=cut

=head1 NAME

Bio::EnsEMBL::Pipeline::Config::BatchQueue

=head1 SYNOPSIS

    use Bio::EnsEMBL::Pipeline::Config::BatchQueue;
    use Bio::EnsEMBL::Pipeline::Config::BatchQueue qw();

=head1 DESCRIPTION

Configuration for pipeline batch queues. Specifies per-analysis
resources and configuration, e.g. so that certain jobs are run
only on certain nodes.

It imports and sets a number of standard global variables into the
calling package. Without arguments all the standard variables are set,
and with a list, only those variables whose names are provided are set.
The module will die if a variable which doesn\'t appear in its
C<%Config> hash is asked to be set.

The variables can also be references to arrays or hashes.

Edit C<%Config> to add or alter variables.
All the variables are in capitals, so that they resemble environment variables.

To run a job only on a certain host, you have to add specific resource-requirements. This
can be useful if you have special memory-requirements, if you like to run the job only on
linux 64bit machines or if you want to run the job only on a specific host group.
The commands bmgroups and lsinfo show you certain host-types / host-groups.

Here are some example resource-statements / sub_args statements:

 sub_args => '-m bc_hosts',                 # only use hosts of host-group 'bc_hosts' (see bmgroup)
 sub_args => '-m bc1_1',                    # only use hosts of host-group 'bc1_1'

 resource => '-R "select[type=LINUX64]" ',  # use Linux 64 bit machines only
 resource => '"select[type=LINUX64]" ',     # same as above
 resource => '"select[model=IBMBC2800]" ',  # only run on IBMBC2800 hosts

 resource => 'alpha',                       # only run on DEC alpha
 resource => 'linux',                       # only run on linux machines


Database throtteling :
This runs a job on a linux host, throttles ecs4:3350 to not have more than 300 cative connections, 10 connections per
job in the duration of the first 10 minutes when the job is running (means 30 hosts * 10 connections = 300 connections):

    resource =>'select[linux && ecs4my3350 <=300] rusage[ecs4my3350=10:duration=10]',


Running on 'linux' hosts with not more than 200 active connections for myia64f and myia64g, 10 connections per job to each
db-instance for the first 10 minutes :

    resource =>'select[linux && myia64f <=200 && myia64g <=200] rusage[myia64f=10:myia64g=10:duration=10]',


Running on hosts of model 'IBMBC2800' hosts with not more than 200 active connections to myia64f;
10 connections per job for the first 10 minutes:

   resource =>'select[model==IBMBC2800 && myia64f<=200] rusage[myia64f=10:duration=10]',



Running on hosts of host_group bc_hosts with not more than 200 active connections to myia64f;
10 connections per job for the first 10 minutes:

   resource =>'select[myia64f<=200] rusage[myia64f=10:duration=10]',
   sub_args =>'-m bc_hosts'


=cut


package Bio::EnsEMBL::Pipeline::Config::BatchQueue;

use strict;
use LowCoverageGeneBuildConf;
use vars qw(%Config);

%Config = (
  QUEUE_MANAGER       => 'LSF',
  DEFAULT_BATCH_SIZE  => 10,
  DEFAULT_RETRIES     => 3,
  DEFAULT_BATCH_QUEUE => '', # put in the queue  of your choice, eg. 'acari'
  DEFAULT_OUTPUT_DIR  => $LC_scratchDIR."/raw_computes/",
  DEFAULT_CLEANUP     => 'no',	
  DEFAULT_VERBOSITY   => 'WARNING',
  DEFAULT_RESOURCE    => 'linux',

  AUTO_JOB_UPDATE     => 1,
  JOB_LIMIT => 100000, # at this number of jobs RuleManager will sleep for 
                      # a certain period of time if you effectively want this never to run set 
                      # the value to very high ie 100000 for a certain period of time
  JOB_STATUSES_TO_COUNT => ['PEND'], # these are the jobs which will be
                                     # counted
                                     # valid statuses for this array are RUN, PEND, SSUSP, EXIT, DONE   
  MARK_AWOL_JOBS      => 0,
  MAX_JOB_SLEEP       => 3600, # the maximun time to sleep for when job limit 
                               # reached
  MIN_JOB_SLEEP      => 120, # the minimum time to sleep for when job limit reached
  SLEEP_PER_JOB      => 30, # the amount of time to sleep per job when job limit 
                            # reached
  DEFAULT_RUNNABLEDB_PATH => 'Bio/EnsEMBL/Analysis/RunnableDB',      

  DEFAULT_RUNNER => '',

  DEFAULT_RETRY_QUEUE => 'long',
  DEFAULT_RETRY_SUB_ARGS => '',
  DEFAULT_RETRY_RESOURCE => 'linux',

  DEFAULT_SUB_ARGS => '',

  QUEUE_CONFIG       => [
    {
      logic_name => 'RepeatMask',
      batch_size => 100,
      resource   => 'select[linux && my$LC_DBHOST<800] rusage[my$LC_DBHOST=10:duration=10:decay=1]',
      retries    => 4,
      sub_args   => '',
      runner     => '',
      queue      => 'normal',   
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',
    },
    {
      logic_name => 'Supp_RepeatMask',
      batch_size => 100,
      # For running the tail
      resource   => 'select[linux && my$LC_DBHOST<800] rusage[my$LC_DBHOST=10:duration=10:decay=1]',
      retries    => 4,
      sub_args   => '',
      runner     => '',
      queue      => 'normal',   
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',
    },
    {
      logic_name => 'Ab_initio_RepeatMask',
      batch_size => 100,
      # For running the tail      
      resource   => 'select[linux && my$LC_DBHOST<800] rusage[my$LC_DBHOST=10:duration=10:decay=1]',
      retries    => 4,
      sub_args   => '',
      runner     => '',
      queue      => 'normal',   
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',
    },
    {
      logic_name => 'Genscan',        
      batch_size => 200,
      resource   => 'select[linux && my$LC_DBHOST<800] rusage[my$LC_DBHOST=10:duration=10:decay=1]',
      retries    => 4,
      sub_args   => '',
      runner     => '',
      queue      => 'normal',    
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',
    },
    {
      logic_name => 'Uniprot',        
      batch_size => 200,
      # For finishing off      
      resource   => 'select[linux && my$LC_DBHOST<800] rusage[my$LC_DBHOST=10:duration=10:decay=1]',
      retries    => 4,
      sub_args   => '',
      runner     => '',
      queue      => 'long',
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',
    },
    {
      logic_name => 'Vertrna',        
      batch_size => 200,
      # For finishing off      
      resource   => 'select[linux && my$LC_DBHOST<800] rusage[my$LC_DBHOST=10:duration=10:decay=1]',
      retries    => 4,
      sub_args   => '',
      runner     => '',
      queue      => 'long',
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',
    },
    {
      logic_name => 'Unigene',        
      batch_size => 200,
      # For finishing off      
      resource   => 'select[linux && my$LC_DBHOST<800] rusage[my$LC_DBHOST=10:duration=10:decay=1]',
      retries    => 4,
      sub_args   => '',
      runner     => '',
      queue      => 'long', 
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',
    },
    {
      logic_name => 'CpG',
      batch_size => 500,
      resource   => 'select[linux && my$LC_DBHOST<800] rusage[my$LC_DBHOST=10:duration=10:decay=1]',
      retries    => 4,
      sub_args   => '',
      runner     => '',
      queue      => 'normal',
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',
    },
    {
      logic_name => 'Dust',
      batch_size => 500,
      resource   => 'select[linux && my$LC_DBHOST<800] rusage[my$LC_DBHOST=10:duration=10:decay=1]',
      retries    => 4,
      sub_args   => '',
      runner     => '',
      queue      => 'normal',
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',
    },
    {
      logic_name => 'tRNAscan',
      batch_size => 500,
      resource   => 'select[linux && my$LC_DBHOST<800] rusage[my$LC_DBHOST=10:duration=10:decay=1]',
      retries    => 4,
      sub_args   => '',
      runner     => '',
      queue      => 'normal',
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',
    },
    {
      logic_name => 'TRF',
      batch_size => 500,
      resource   => 'select[linux && my$LC_DBHOST<800] rusage[my$LC_DBHOST=10:duration=10:decay=1]',
      retries    => 4,
      sub_args   => '',
      runner     => '',
      queue      => 'normal',
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',
    },
    {
      logic_name => 'Eponine',        
      batch_size => 200,
      resource   => 'select[linux && my$LC_DBHOST<800] rusage[my$LC_DBHOST=10:duration=10:decay=1]',
      retries    => 4,
      sub_args   => '',
      runner     => '',
      queue      => 'normal',
      runnabledb_path => 'Bio/EnsEMBL/Analysis/RunnableDB',    
    },
  ]
);

sub import {
    my ($callpack) = caller(0); # Name of the calling package
    my $pack = shift; # Need to move package off @_

    # Get list of variables supplied, or else all
    my @vars = @_ ? @_ : keys(%Config);
    return unless @vars;

    # Predeclare global variables in calling package
    eval "package $callpack; use vars qw("
         . join(' ', map { '$'.$_ } @vars) . ")";
    die $@ if $@;


    foreach (@vars) {
	if (defined $Config{ $_ }) {
            no strict 'refs';
	    # Exporter does a similar job to the following
	    # statement, but for function names, not
	    # scalar variables:
	    *{"${callpack}::$_"} = \$Config{ $_ };
	} else {
	    die "Error: Config: $_ not known\n";
	}
    }
}

1;
