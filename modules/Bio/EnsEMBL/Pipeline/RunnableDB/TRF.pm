#
#
# Written by Simon Potter
#
# Copyright GRL/EBI
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Pipeline::RunnableDB::TRF

=head1 SYNOPSIS

my $db      = Bio::EnsEMBL::DBLoader->new($locator);
my $trf = Bio::EnsEMBL::Pipeline::RunnableDB::TRF->new(
    -dbobj      => $db,
    -input_id   => $input_id
    -analysis   => $analysis
);
$trf->fetch_input();
$trf->run();
$trf->output();
$trf->write_output(); #writes to DB

=head1 DESCRIPTION

This object wraps Bio::EnsEMBL::Pipeline::Runnable::TRF to add
functionality to read and write to databases. The appropriate
Bio::EnsEMBL::Analysis object must be passed for extraction of
parameters. A Bio::EnsEMBL::Pipeline::DBSQL::Obj is required
for databse access.

=head1 CONTACT

Post general queries to B<ensembl-dev@ebi.ac.uk>

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Pipeline::RunnableDB::TRF;

use strict;
use Bio::EnsEMBL::Pipeline::RunnableDB;
use Bio::EnsEMBL::Pipeline::Runnable::TRF;
use vars qw(@ISA);
@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableDB);

=head2 new

    Title   :   new
    Usage   :   $self->new(-DBOBJ       => $db
                           -INPUT_ID    => $id
                           -ANALYSIS    => $analysis);
                           
    Function:   creates a Bio::EnsEMBL::Pipeline::RunnableDB::TRF object
    Returns :   A Bio::EnsEMBL::Pipeline::RunnableDB::TRF object
    Args    :     -dbobj     A Bio::EnsEMBL::DB::Obj, 
                  -input_id  Contig input id , 
                  -analysis  A Bio::EnsEMBL::Analysis

=cut

sub new {
    my ($class, @args) = @_;
    my $self = $class->SUPER::new(@args);
    
    $self->{'_fplist'}      = [];
    $self->{'_genseq'}      = undef;
    $self->{'_runnable'}    = undef;
    
    $self->throw("Analysis object required") unless ($self->analysis);
    
    $self->runnable('Bio::EnsEMBL::Pipeline::Runnable::TRF');
    return $self;
}

=head2 fetch_input

=cut

sub fetch_input {
    my( $self) = @_;
    
    $self->throw("No input id") unless defined($self->input_id);
    
    my $contigid  = $self->input_id;
    my $contig    = $self->dbobj->get_Contig($contigid);
    my $genseq    = $contig->primary_seq()
     or $self->throw("Unable to fetch contig");
    $self->genseq($genseq);
}

#get/set for runnable and args
sub runnable {
    my ($self, $runnable) = @_;
    my $arguments = "";
    
    if ($runnable)
    {
        #extract parameters into a hash
        my ($parameter_string) = $self->parameters() ;
        my %parameters;
        if ($parameter_string)
        {
            $parameter_string =~ s/\s+//g;
            my @pairs = split (/,/, $parameter_string);
            
            foreach my $pair (@pairs)
            {
                my ($key, $value) = split (/=>/, $pair);
		if ($key && $value) {
		    $parameters{$key} = $value;
		}
		else {
		    $arguments .= " $key ";
		}
            }
        }
        $parameters{'-trf'} = $self->analysis->program_file || undef;
        #creates empty Bio::EnsEMBL::Runnable::TRF object
        $self->{'_runnable'} = $runnable->new(%parameters);;
    }
    return $self->{'_runnable'};
}

1;
