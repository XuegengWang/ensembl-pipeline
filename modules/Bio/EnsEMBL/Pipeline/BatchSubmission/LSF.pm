# Ensembl Pipeline module for handling job submission via Platform LSF 
# load sharing software
#
# Cared for by Laura Clarke 
#
# Copyright Laura Clarke 
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod

=head1 NAME

Bio::EnsEMBL::Pipeline::BatchSubmission::LSF

=head1 SYNOPSIS

my $batchjob = Bio::EnsEMBL::Pipeline::BatchSubmission::LSF->new(
             -STDOUT     => $stdout_file,
             -STDERR     => $stderr_file,
             -PARAMETERS => @args,
             -PRE_EXEC   => $pre_exec,
             -QUEUE      => $queue,
             -JOBNAME    => $jobname,
             -NODES      => $nodes,
             -RESOURCE   => $resource
             );

$batch_job->construct_command_line('test.pl');
$batch_job->open_command_line();

=head1 DESCRIPTION

This module provides an interface to the Platform LSF load sharing software and
its commands. It implements the method construct_command_line which is not 
defined in the base class and which enables the pipeline to submit jobs in a 
distributed environment using LSF.

See base class Bio::EnsEMBL::Pipeline::BatchSubmission for more info

=head1 CONTACT

Post general queries to B<ensembl-dev@ebi.ac.uk>

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal 
methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Pipeline::BatchSubmission::LSF;


use Bio::EnsEMBL::Pipeline::BatchSubmission;
use vars qw(@ISA);
use strict;

@ISA = qw(Bio::EnsEMBL::Pipeline::BatchSubmission);


sub new{
  my ($class, @args) = @_;
  my $self = $class->SUPER::new(@args);

  $self->{'bsub'} = undef;
  
  return $self;
 
}


##################
#accessor methods#
##################

sub bsub{
  my($self, $arg) = @_;

  if(defined($arg)){
    $self->{'bsub'} = $arg;
  }

  return $self->{'bsub'};

}

##other accessor are in base class##

######################
#command line methods#
######################

sub construct_command_line{
  my($self, $command, $stdout, $stderr) = @_; 
#command must be the first argument then if stdout or stderr aren't definhed the objects own can be used
  
  if(!$command){
    $self->throw("cannot create bsub if nothing to submit to it : $!\n");
  }
  my $bsub_line;
  $self->command($command);
  if($stdout){
    $bsub_line = "bsub -o ".$stdout;
  }else{
    $bsub_line = "bsub -o ".$self->stdout_file;
  }
  if($self->nodes){
    my $nodes = $self->nodes;
    # $nodes needs to be a space-delimited list
    $nodes =~ s/,/ /;
    $nodes =~ s/ +/ /;
    # undef $nodes unless $nodes =~ m{(\w+\ )*\w};
    $bsub_line .= " -m '".$nodes."' ";
  }
  if(my $res = $self->resource){
    $res = qq{-R '$res'} unless $res =~ /^-R/;
    $bsub_line .= " $res ";
  }
  $bsub_line .= " -q ".$self->queue    if $self->queue;
  $bsub_line .= " -J ".$self->jobname  if $self->jobname;
  $bsub_line .= " ".$self->parameters." "  if defined $self->parameters;
  if($stderr){
    $bsub_line .= " -e ".$stderr;
  }else{
    $bsub_line .= " -e ".$self->stderr_file;
  }
  $bsub_line .= " -E \"".$self->pre_exec."\"" if defined $self->pre_exec; 
  ## must ensure the prexec is in quotes ##
  $bsub_line .= " ".$command;
  $self->bsub($bsub_line);
  
}



sub open_command_line{
  my ($self, $verbose)= @_;
  
  my $lsf = '';
  
  if (open(my $pipe, '-|')) {
    while (<$pipe>) {
      if (/Job <(\d+)>/) {
        $lsf = $1;
      } else {
        $self->warn("DEBUG: unexpected from bsub: '$_'");
      }	  
    }
    if (close $pipe) {
      if ( ($? >> 8) == 0 ){
        if ($lsf) {
          $self->id($lsf);
        } else {
          $self->warn("Bsub worked but returned no job ID. Weird");
        }
      } else {
        $self->throw("Bsub failed : exit status " . $? >> 8 . "\n");
      }
    } else {
      $self->throw("Could not close bsub pipe : $!\n");
    }      
  } else {      
    # We want STDERR and STDOUT merged for the bsub process
    # open STDERR, '>&STDOUT'; 
    # probably better to do with shell redirection as above can fail
    exec($self->bsub .' 2>&1') || $self->throw("Could not run bsub");
  }  
}


sub get_pending_jobs {
  my($self, $verbose) = @_;

  my $cmd = "bjobs";
  $cmd .= " | grep -c PEND ";

  print STDERR "$cmd\n" if($verbose);

  my $pending_jobs = 0;
  if( my $pid = open (my $fh, '-|') ){
      eval{
	  local $SIG{ALRM} = sub { kill 9, $pid; };
	  alarm(60);
	  while(<$fh>){
	      chomp;
	      $pending_jobs = $_;
	  }
	  close $fh;
	  alarm 0;
      }
  }else{
      exec( $cmd );
      die q{Something went wrong here $!: } . $! . "\n";
  }
  print STDERR "FOUND $pending_jobs jobs pending\n" if $verbose;
  return $pending_jobs;
}



sub get_job_time{
  my ($self) = @_;
  my $command = "bjobs -l";
  #print $command."\n";
  my %id_times;
  open(BJOB, "$command |") or $self->throw("couldn't open pipe to bjobs");
  my $job_id;
  while(<BJOB>){
    chomp;
    if(/Job\s+\<(\d+)\>/){
      $job_id = $1;
    }elsif(/The CPU time used/){
      my ($time) = $_ =~ /The CPU time used is (\d+)/;
      $id_times{$job_id} = $time;
    }
  }
  close(BJOB);
  #or $self->throw("couldn't close pipe to bjobs");
  return \%id_times;
}

sub check_existance{
  my ($self, $id_hash, $verbose) = @_;
  my %job_submission_ids = %$id_hash;
  my $command = "bjobs";
  open(BJOB, "$command 2>&1 |") or 
    $self->throw("couldn't open pipe to bjobs");
  my %existing_ids;
 LINE:while(<BJOB>){
    print STDERR if($verbose);
    chomp;
    if ($_ =~ /No unfinished job found/) {
      last LINE;
    }
    my @values = split;
    if($values[0] =~ /\d+/){
      if($values[2] eq 'UNKWN'){
        next LINE;
      }
      $existing_ids{$values[0]} = 1;
    }
  }
  my @awol_jobs;
  foreach my $job_id(keys(%job_submission_ids)){
    if(!$existing_ids{$job_id}){
      push(@awol_jobs, @{$job_submission_ids{$job_id}});
    }
  }
  close(BJOB);
  #or $self->throw("Can't close pipe to bjobs");
  return \@awol_jobs;
}


#sub check_existance{
#  my ($self, $id, $verbose) = @_;
#  if(!$id){
#    die("Can't run without an LSF id");
#  }
#  my $command = "bjobs ".$id."\n";
#  #print STDERR "Running ".$command."\n";
#  my $flag = 0; 
#  open(BJOB, "$command 2>&1 |") or $self->throw("couldn't open pipe to bjobs");
#  while(<BJOB>){
#    print STDERR if($verbose);
#    chomp;
#    if ($_ =~ /No unfinished job found/) {
#      #print "Set flag\n";
#      $flag = 1;
#    } 
#    my @values = split;
#    if($values[0] =~ /\d+/){
#      return $values[0];
#    }
#  }
#  close(BJOB);
#  print STDERR "Have lost ".$id."\n" if($verbose);
#  return undef;
#}


sub kill_job{
  my ($self, $job_id) = @_;

  my $command = "bkill ".$job_id;
  system($command);
}


=head2 stdout_file and stderr_file

Unless explicitly set, these default to the file
B</dev/zero>.  Thus bsub is given the arguments:

  -o /dev/zero -e /dev/zero

when the job is submitted.  We copy the stderr
and stdout output to the designated output files
after the job has finished with the
B<copy_output> method which uses B<lsrcp> (to
avoid the use of NFS).  bsub then copies the
files to /dev/zero, which (on most systems)
allows writes and will discard any input.

We cannot use B</dev/null> as the arguments to -e
and -o, because LSF will notice this and send
data directly to /dev/null instead of creating
the output files in /tmp.

=cut

sub stdout_file{
   my ($self, $arg) = @_;

   if($arg){
     $self->{'stdout'} = $arg;
   }

   if(!$self->{'stdout'}){
     $self->{'stdout'} ='/dev/zero'
   }
   return $self->{'stdout'};
}



sub stderr_file{
   my ($self, $arg) = @_;

   if ($arg){
     $self->{'stderr'} = $arg;
   }
   if(!$self->{'stderr'}){
     $self->{'stderr'} ='/dev/zero'
   }
   return $self->{'stderr'};
}



sub temp_filename{
  my ($self) = @_;

  $self->{'lsf_jobfilename'} = $ENV{'LSB_JOBFILENAME'};
  return $self->{'lsf_jobfilename'};
}


sub temp_outfile{
  my ($self) = @_;

  $self->{'_temp_outfile'} = $self->temp_filename.".out";

  return $self->{'_temp_outfile'};
}

sub temp_errfile{
  my ($self) = @_;

  $self->{'_temp_errfile'} = $self->temp_filename.".err";
  

  return $self->{'_temp_errfile'};
}


sub submission_host{
  my ($self) = @_;

  $self->{'_submission_host'} = $ENV{'LSB_SUB_HOST'};
  

  return $self->{'_submission_host'};
}

sub lsf_user{
  my ($self) = @_;

 
  $self->{'_lsf_user'} = $ENV{'LSFUSER'};
  

  return $self->{'_lsf_user'};
}

=head2 copy_output

copy_output is used to copy the job's STDOUT and
STDERR files using B<lsrcp>.  This avoids using NFS'.

=cut

sub copy_output {
    my ($self, $dest_err, $dest_out) = @_;

    $dest_err ||= $self->stderr_file;
    $dest_out ||= $self->stdout_file;

    if (! $self->temp_filename) {
        my ($p, $f, $l) = caller;
        $self->warn("The lsf environment variable LSB_JOBFILENAME is not defined".
                    " we can't copy the output files which don't exist $f:$l");
        return;
    }
    
    # Unbuffer STDOUT so that data gets flushed to file
    # (It is OK to leave it unbuffered because this method
    # gets called after the job is finished.)
    my $old_fh = select(STDOUT);
    $| = 1;
    select($old_fh);
    
    my $temp_err = $self->temp_errfile;
    my $temp_out = $self->temp_outfile;

    my $command = $self->copy_command;
    my $remote = $self->lsf_user . '@' . $self->submission_host;
    foreach my $set ([$temp_out, $dest_out], [$temp_err, $dest_err]) {
        my( $temp, $dest ) = @$set;
        if (-e $temp) {
            my $err_copy = "$command $temp $remote:$dest";
            unless (system($err_copy) == 0) {
                warn "Error: copy '$err_copy' failed exit($?)";
            }
        } else {
            warn "No such file '$temp' to copy\n";
        }
    }
}

sub delete_output{
  my ($self) = @_;
  
  unlink $self->temp_errfile if(-e $self->temp_errfile);
  unlink $self->temp_outfile if(-e $self->temp_outfile);
}

sub copy_command{
  my ($self, $arg) = @_;

  if($arg){
    $self->{'_copy_command'} = $arg;
  }

  return $self->{'_copy_command'} || 'lsrcp ';
}


1;
