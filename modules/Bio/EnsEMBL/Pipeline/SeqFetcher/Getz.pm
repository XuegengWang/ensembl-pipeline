#
# Cared for by EnsEMBL  <ensembl-dev@ebi.ac.uk>
#
# Copyright GRL & EBI
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

  Bio::EnsEMBL::Pipeline::SeqFetcher::Getz

=head1 SYNOPSIS

    my $obj = Bio::EnsEMBL::Pipeline::SeqFetcher::Getz->new(
							    '-executable' => $exe,
							    '-library'        => $lib,
							   );
    my $seq = $obj->get_Seq_by_acc($acc);

=head1 DESCRIPTION

  Object to retrieve sequences as Bio::Seq, using getz.

=head1 CONTACT

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

# Let the code begin...
package Bio::EnsEMBL::Pipeline::SeqFetcher::Getz;

use strict;
use Bio::Root::RootI;
use Bio::DB::RandomAccessI;
use Bio::Seq;

use vars qw(@ISA);

@ISA = qw(Bio::Root::RootI Bio::DB::RandomAccessI);

sub new {
  my ($class, @args) = @_;
  my $self = bless {}, $class;

  my ($exe, $lib) = $self->_rearrange([
				       'EXECUTABLE', 
				       'LIBRARY'], @args);

  if (!defined $exe) {
    $exe = 'getz';
  }
  $self->executable($exe);
  
  
  if (defined $lib) {
    $self->library($lib);
  }  
  return $self; # success - we hope!
}

=head2 executable

  Title   : executable
  Usage   : $self->executable('/path/to/executable');
  Function: Get/set for the path to the executable being used by the module. If not set, the executable is looked for in $PATH.
  Returns : string
  Args    : string

=cut

sub executable {
  my ($self, $exe) = @_;
  if ($exe)
    {
      $self->{'_exe'} = $exe;
    }
  return $self->{'_exe'};  
}

=head2 library

  Title   : library
  Usage   : $self->library('embl');
  Function: Get/set for a library/libraries to search in 
  Returns : string
  Args    : string

=cut

sub library {
  my ($self, $lib) = @_;
  if ($lib) {
      $self->{'_lib'} = $lib;
    }
  return $self->{'_lib'};  
}


=head2 get_Seq_by_acc

  Title   : get_Seq_by_acc
  Usage   : $self->get_Seq_by_acc($accession);
  Function: Does the sequence retrieval via getz
  Returns : Bio::Seq
  Args    : 

=cut

sub  get_Seq_by_acc {
  my ($self, $acc) = @_;
  my $libs = $self->library;

  if (!defined($acc)) {
    $self->throw("No id input");
  }  

  if (!defined($libs)) {
    $self->throw("No search libs specified");
  }  
  
  my $seqstr;
  my $seq;
  my $getz     = $self->executable;
  
  open(IN, "$getz  -d -sf fasta '[libs={$libs}-AccNumber:$acc]' |") 
    or $self->throw("Error running getz for id [$acc]: $getz");
  
  my $format = 'fasta';
  
  my $fh = Bio::SeqIO->new(-fh   => \*IN, "-format"=>$format);
  
  $seq = $fh->next_seq();
  close IN;

  $self->throw("Could not getz sequence for [$acc]\n") unless defined $seq;
  $seq->display_id($acc);
  $seq->accession_number($acc);

  return $seq;
}

1;
