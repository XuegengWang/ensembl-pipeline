#
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

Bio::EnsEMBL::Pipeline::Runnable::AlignFeature

=head1 SYNOPSIS

    my $obj = Bio::EnsEMBL::Pipeline::Runnable::AlignFeature->new(
                                             -genomic    => $genseq,
					     -features   => $features,			  
					     -seqfetcher => $seqfetcher,
                                             );
    or
    
    my $obj = Bio::EnsEMBL::Pipeline::Runnable::AlignFeature->new(-genomic => $seq);


    foreach my $f (@features) {
	$obj->addFeature($f);
    }

    $obj->run

    my @newfeatures = $obj->output;


=head1 DESCRIPTION

=head1 CONTACT

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

# Let the code begin...

package Bio::EnsEMBL::Pipeline::Runnable::AlignFeature;

use vars qw(@ISA);
use strict;

# Object preamble - inherits from Bio::EnsEMBL::Root;
use Bio::EnsEMBL::Pipeline::Runnable::Est2Genome;
use Bio::EnsEMBL::Pipeline::MiniSeq;
use Bio::EnsEMBL::FeaturePair;
use Bio::EnsEMBL::SeqFeature;
use Bio::EnsEMBL::Analysis;
use Bio::DB::RandomAccessI;
use Bio::EnsEMBL::Root;

#compile time check for executable
use Bio::EnsEMBL::Analysis::Programs qw(est2genome); 
use Bio::PrimarySeqI;
use Bio::SeqIO;

use Data::Dumper;

@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableI);

sub new {
    my ($class,@args) = @_;
    my $self = $class->SUPER::new(@args);    
           
    $self->{'_fplist'} = []; #create key to an array of feature pairs
    
    my( $genomic, $features, $seqfetcher ) = $self->_rearrange(['GENOMIC',
						   'FEATURES',
						   'SEQFETCHER'], @args);

    $self->throw("No genomic sequence input") unless defined($genomic);
    $self->throw("[$genomic] is not a Bio::PrimarySeqI") unless $genomic->isa("Bio::PrimarySeqI");
    $self->genomic_sequence($genomic) if $genomic; 

    $self->{'_features'} = [];

    if (defined($features)) {
      if (ref($features) eq "ARRAY") {
	my @f = @$features;
	
	foreach my $f (@f) {
	  if ($f->isa("Bio::EnsEMBL::FeaturePair")) {
	    $self->addFeature($f);
	  } else {
	    $self->warn("Can't add feature [$f]. Not a Bio::EnsEMBL::FeaturePair");
	  }
	}
      } else {
	$self->throw("[$features] is not an array ref.");
      }
    }
    
    $self->throw("No seqfetcher provided")           
      unless defined($seqfetcher);
    $self->throw("[$seqfetcher] is not a Bio::DB::RandomAccessI") 
      unless $seqfetcher->isa("Bio::DB::RandomAccessI");
    $self->seqfetcher($seqfetcher) if defined($seqfetcher);
    
    return $self; 
}

=head2 genomic_sequence

    Title   :   genomic_sequence
    Usage   :   $self->genomic_sequence($seq)
    Function:   Get/set method for genomic sequence
    Returns :   Bio::Seq object
    Args    :   Bio::Seq object

=cut

sub genomic_sequence {
    my( $self, $value ) = @_;    
    if ($value) {
        #need to check if passed sequence is Bio::Seq object
        $value->isa("Bio::PrimarySeqI") || $self->throw("Input isn't a Bio::PrimarySeqI");
        $self->{'_genomic_sequence'} = $value;
    }
    return $self->{'_genomic_sequence'};
}

=head2 seqfetcher

    Title   :   seqfetcher
    Usage   :   $self->seqfetcher($seqfetcher)
    Function:   Get/set method for SeqFetcher
    Returns :   Bio::DB::RandomAccessI object
    Args    :   Bio::DB::RandomAccessI object

=cut

sub seqfetcher {
    my( $self, $value ) = @_;    
    if ($value) {
        #need to check if passed sequence is Bio::DB::RandomAccessI object
        $value->isa("Bio::DB::RandomAccessI") || $self->throw("Input isn't a Bio::DB::RandomAccessI");
        $self->{'_seqfetcher'} = $value;
    }
    return $self->{'_seqfetcher'};
}

=head2 addFeature 

    Title   :   addFeature
    Usage   :   $self->addFeature($f)
    Function:   Adds a feature to the object for realigning
    Returns :   Bio::EnsEMBL::FeaturePair
    Args    :   Bio::EnsEMBL::FeaturePair

=cut

sub addFeature {
    my( $self, $value ) = @_;
    
    if ($value) {
        $value->isa("Bio::EnsEMBL::FeaturePair") || $self->throw("Input isn't a Bio::EnsEMBL::FeaturePair");
	push(@{$self->{'_features'}},$value);
    }
}


=head2 get_all_FeaturesbyId

    Title   :   get_all_FeaturesById
    Usage   :   $hash = $self->get_all_FeaturesById;
    Function:   Returns a ref to a hash of features.
                The keys to the hash are distinct feature ids
    Returns :   ref to hash of Bio::EnsEMBL::FeaturePair
    Args    :   none

=cut

sub get_all_FeaturesById {
    my( $self) = @_;
    
    my  %idhash;

    FEAT: foreach my $f ($self->get_all_Features) {
#	print STDERR ("Feature is $f " . $f->seqname . "\t" . $f->hseqname ."\n");
    if (!(defined($f->hseqname))) {
#	    $self->warn("No hit name for " . $f->seqname . "\n");
	    next FEAT;
	} 
	if (defined($idhash{$f->hseqname})) {
	    push(@{$idhash{$f->hseqname}},$f);
	} else {
	    #$idhash{$f->id} = []; #shouldn't this be hseqname not id
	    $idhash{$f->hseqname} = [];
        push(@{$idhash{$f->hseqname}},$f);
	}
    }

    return (\%idhash);
}


=head2 get_all_Features

    Title   :   get_all_Features
    Usage   :   @f = $self->get_all_Features;
    Function:   Returns the array of features
    Returns :   @Bio::EnsEMBL::FeaturePair
    Args    :   none

=cut


sub get_all_Features {
    my( $self, $value ) = @_;
    
    return (@{$self->{'_features'}});
}


=head2 get_all_FeatureIds

  Title   : get_all_FeatureIds
  Usage   : my @ids = get_all_FeatureIds
  Function: Returns an array of all distinct feature hids 
  Returns : @string
  Args    : none

=cut

sub get_all_FeatureIds {
    my ($self) = @_;

    my %idhash;

    foreach my $f ($self->get_all_Features) {
	if (defined($f->hseqname)) {
	    $idhash{$f->hseqname} = 1;
	} else {
	    $self->warn("No sequence name defined for feature. " . $f->seqname . "\n");
	}
    }

    return keys %idhash;
}


=head2 parse_Header

  Title   : parse_Header
  Usage   : my $newid = $self->parse_Header($id);
  Function: Parses different sequence headers
  Returns : string
  Args    : none

=cut

sub parse_Header {
    my ($self,$id) = @_;

    if (!defined($id)) {
	$self->throw("No id input to parse_Header");
    }

    my $newid = $id;

    if ($id =~ /^(.*)\|(.*)\|(.*)/) {
        if ($2 eq "UG") {
            my($ug) = $id =~ m{/ug=(.*?)\ };
            if (length $ug > 0) {
                $newid = $ug;
            }
            else {
                $newid = $3;
            }
        } else {
	  $newid = $2;
        }
	$newid =~ s/(.*)\..*/$1/;
	
    } elsif ($id =~ /^..\:(.*)/) {
	$newid = $1;
    }
    $newid =~ s/ //g;
    return $newid;
}


sub make_miniseq {
    my ($self,@features) = @_;

    my $strand = $features[0]->strand;
    my $seqname = $features[0]->seqname;;
    @features = sort {$a->start <=> $b->start} @features;
    
    my $count  = 0;
    my $mingap = $self->minimum_intron;

    my $pairaln  = new Bio::EnsEMBL::Analysis::PairAlign;

    my @genomic_features;

    my $prevend     = 0;
    my $prevcdnaend = 0;
    
    foreach my $f (@features) {
    # print STDERR "Found feature - " . $f->hseqname . "\t" . $f->start . "\t" . $f->end . "\t" . $f->strand . "\n"; 
	if ($f->strand != $strand) {
	    $self->throw("Mixed strands in features set");
	}

	my $start = $f->start;
	my $end   = $f->end;

	$start = $f->start - $self->exon_padding;
	$end   = $f->end   + $self->exon_padding;

        if ($start < 1) { $start = 1;}
        if ($end   > $self->genomic_sequence->length) {$end = $self->genomic_sequence->length;}

	my $gap     =    ($start - $prevend);
	my $cdnagap = abs($f->hstart - $prevcdnaend);

#	print STDERR "Feature hstart is " . $f->hstart . "\t" . $prevcdnaend . "\n";
#	print STDERR "Padding feature - new start end are $start $end ($cdnagap)\n";

#	print STDERR "Count is $count : $mingap " . $gap  . "\n";

#	if ($count > 0 && (($gap <  $mingap) || ($cdnagap > 20))) {
	if ($count > 0 && ($gap < $mingap)) {
#	    print(STDERR "Merging exons in " . $f->hseqname . " - resetting end to $end\n");
	    
	    $genomic_features[$#genomic_features]->end($end);
	    $prevend     = $end;
	    $prevcdnaend = $f->hend;
	} else {
	
	    my $newfeature = new Bio::EnsEMBL::SeqFeature;

        $newfeature->seqname ($f->hseqname);
        $newfeature->start     ($start);
	    $newfeature->end       ($end);
	    $newfeature->strand    (1);
	    $newfeature->attach_seq($self->genomic_sequence);

	    push(@genomic_features,$newfeature);
	    
	    #print(STDERR "Added feature $count: " . $newfeature->start  . "\t"  . 
	#	                                    $newfeature->end    . "\t " . 
	#	                                    $newfeature->strand . "\n");

	    $prevend = $end;
	    $prevcdnaend = $f->hend; 
	#    print STDERR "New end is " . $f->hend . "\n";

	}
	$count++;
    }

    # Now we make the cDNA features

    my $current_coord = 1;
    
    if ($strand == 1) {
	@genomic_features = sort {$a->start <=> $b->start } @genomic_features;
    } elsif ($strand == -1) {
#	print STDERR "Reverse strand - reversing coordinates\n";

	@genomic_features = sort {$b->start <=> $a->start } @genomic_features;
    } else {
	$self->throw("Invalid value for strand [$strand]");
    }

    foreach my $f (@genomic_features) {
	$f->strand(1);
	my $cdna_start = $current_coord;
	my $cdna_end   = $current_coord + ($f->end - $f->start);
	
	my $tmp = new Bio::EnsEMBL::SeqFeature(
                           -seqname => $f->seqname.'.cDNA',
                           -start => $cdna_start,
					       -end   => $cdna_end,
					       -strand => $strand);
	
	my $fp  = new Bio::EnsEMBL::FeaturePair(-feature1 => $f,
						-feature2 => $tmp);
	
	$pairaln->addFeaturePair($fp);
	
	$self->print_FeaturePair($fp);

	$current_coord = $cdna_end+1;
    }
	
    #changed id from 'Genomic' to seqname
    my $miniseq = new Bio::EnsEMBL::Pipeline::MiniSeq(
                               -id        => $seqname,
                              #-id        => 'Genomic',
						      -pairalign => $pairaln);

    my $newgenomic = $miniseq->get_cDNA_sequence;
 #   print ("New genomic sequence is " . $newgenomic->seq . "\n");
    return $miniseq;

}

sub minimum_intron {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{'_minimum_intron'} = $arg;
    }

    return $self->{'_minimum_intron'} || 1000;
}

    
sub exon_padding {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->{'_padding'} = $arg;
    }

    return $self->{'_padding'} || 20;
}

sub print_FeaturePair {
    my ($self,$nf) = @_;
    #changed $nf->id to $nf->seqname
    print(STDERR "FeaturePair is " . $nf->seqname    . "\t" . 
	  $nf->start . "\t" . 
	  $nf->end   . "\t(" . 
	  $nf->strand . ")\t" .
	  $nf->hseqname  . "\t" . 
	  $nf->hstart   . "\t" . 
	  $nf->hend     . "\t(" .
	  $nf->hstrand  . ")\n");
}

=head2 get_Sequence

  Title   : get_Sequence
  Usage   : my $seq = get_Sequence($id)
  Function: Fetches sequences with id $id
  Returns : Bio::PrimarySeq
  Args    : none

=cut

sub get_Sequence {
    my ($self,$id) = @_;

    if (defined($self->{'_seq_cache'}{$id})) {
      return $self->{'_seq_cache'}{$id};
    } 

    my $seq;
    eval{
      $seq = $self->seqfetcher->get_Seq_by_acc($id);
    };
    if( $@ ) {
      $self->throw("Problem fetching sequence for [$id]: [$@]\n");
    }

    if (!defined($seq)) {
      $self->throw("Couldn't find sequence for [$id]");
    }
    
    return $seq;
}

=head2 get_all_Sequences

  Title   : get_all_Sequences
  Usage   : my $seq = get_all_Sequences(@id)
  Function: Fetches sequences with ids in @id
  Returns : nothing, but $self->{'_seq_cache'}{$id} has a Bio::PrimarySeq for each $id in @id
  Args    : array of ids

=cut

sub get_all_Sequences {
    my ($self,@id) = @_;

 SEQ: foreach my $id (@id) {
    my $seq = $self->get_Sequence($id);
    if(defined $seq) {
      $self->{'_seq_cache'}{$id} = $seq;
    }
  }
}

=head2 run

  Title   : run
  Usage   : $self->run()
  Function: Runs est2genome on each distinct feature id
  Returns : none
  Args    : 

=cut

sub run {
    my ($self) = @_;
    

    my @ids = $self->get_all_FeatureIds;

#    $self->get_all_Sequences(@ids);

    foreach my $id (@ids) {
	my $hseq = $self->get_Sequence(($id));

	if (!defined($hseq)) {
	    $self->throw("Can't fetch sequence for id [$id]\n");
	}

	my $eg = new Bio::EnsEMBL::Pipeline::Runnable::Est2Genome(-genomic => $self->genomic_sequence,
								  -est     => $hseq);

	$eg->run;

	my @f = $eg->output;

	foreach my $f (@f) {
	    print("Aligned output is " . $id . "\t" . $f->start . "\t" . $f->end . "\t" . $f->score . "\n");

	}

	push(@{$self->{'_output'}},@f);

    }
    1;
}

sub minirun {
    my ($self) = @_;

    my $idhash = $self->get_all_FeaturesById;
    
    my @ids    = keys %$idhash;
    print ("here\n");
   # $self->get_all_Sequences(@ids);

    ID: foreach my $id (@ids) {

	my $features = $idhash->{$id};
	my @exons;

	print(STDERR "Processing $id\n");
	print(STDERR "Features = " . scalar(@$features) . "\n");

	next ID unless (scalar(@$features) > 1);

	eval {
	    my $miniseq = $self->make_miniseq(@$features);
	    my $hseq    = $self->get_Sequence($id);
#	    print("Hseq $id " . $hseq->seq . "\n");
	    if (!defined($hseq)) {
		$self->throw("Can't fetch sequence for id [$id]\n");
	    }
	    my $eg = new Bio::EnsEMBL::Pipeline::Runnable::Est2Genome(  -genomic => $miniseq->get_cDNA_sequence,
								                                    -est     => $hseq);
	    
	    $eg->run;
	    
	    my @f = $eg->output;
        my @newf;
	    
	    foreach my $f (@f) {
#		print(STDERR "Aligned output is " . $f->id    . "\t" . 
#		      $f->start      . "\t" . 
#		      $f->end        . "\t(" . 
#		      $f->strand     . ")\t" .
#		      $f->hseqname   . "\t" . 
#		      $f->hstart     . "\t" . 
#		      $f->hend       . "\t(" .
#		      $f->hstrand    . ")\n");
		
        #BUG: Bio::EnsEMBL::Analysis seems to lose seqname for feature1 
		my @newfeatures = $miniseq->convert_FeaturePair($f);         
		push(@newf,@newfeatures);
		
		foreach my $nf (@newf) {
        #BUGFIX: This should probably be fixed in Bio::EnsEMBL::Analysis
		  $nf->seqname($f->seqname);
          $nf->hseqname($id);
        #end BUGFIX
#		    print(STDERR "Realigned output is " . $nf->id    . "\t" . 
#			  $nf->start     . "\t" . 
#			  $nf->end       . "\t(" . 
#			  $nf->strand    . ")\t" .
#			  $nf->hseqname  . "\t" . 
#			  $nf->hstart    . "\t" . 
#			  $nf->hend      . "\t(" .
#			  $nf->hstrand   . ")\n");
		    
		}
	    }
	    
	    push(@{$self->{'_output'}},@newf);
	    foreach my $nf (@newf) {
        #changed $nf->id to $nf->seqname
        print(STDERR "Realigned output is " . $nf->seqname    . "\t" . 
		    $nf->start     . "\t" . 
		    $nf->end       . "\t(" . 
		    $nf->strand    . ")\t" .
		    $nf->hseqname  . "\t" . 
		    $nf->hstart    . "\t" . 
		    $nf->hend      . "\t(" .
		    $nf->hstrand   . ")\n");
	    }
	};
	if ($@) {
	    print STDERR "Error running est2genome for " . $features->[0]->hseqname . " [$@]\n";
	}
    }
}

=head2 output

  Title   : output
  Usage   : $self->output
  Function: Returns results of est2genome as array of FeaturePair
  Returns : An array of Bio::EnsEMBL::FeaturePair
  Args    : none

=cut

sub output {
    my ($self) = @_;
    if (!defined($self->{'_output'})) {
	$self->{'_output'} = [];
    }
    return @{$self->{'_output'}};
}

sub _createfeatures {
    my ($self, $f1score, $f1start, $f1end, $f1id, $f2start, $f2end, $f2id,
        $f1source, $f2source, $f1strand, $f2strand, 
	$f1primary, $f2primary) = @_;
    
    #create analysis object
    my $analysis_obj    = new Bio::EnsEMBL::Analysis
	('-db'              => undef,
	 '-db_version'      => undef,
	 '-program'         => "est_genome",
	 '-program_version' => "unknown",
	 '-gff_source'      => $f1source,
	 '-gff_feature'     => $f1primary,);
    
    #create features
    my $feat1 = new Bio::EnsEMBL::SeqFeature ('-start'   => $f1start,
                                              '-end'     => $f1end,
                                              '-seqname' => $f1id,
                                              '-strand'  => $f1strand,
                                              '-score'   => $f1score,
                                              '-source'  => $f1source,
                                              '-primary' => $f1primary,
                                              '-analysis'=> $analysis_obj );
 
     my $feat2 = new Bio::EnsEMBL::SeqFeature ('-start'   => $f2start,
                                               '-end'     => $f2end,
					       '-seqname' => $f2id,
					       '-strand'  => $f2strand,
					       '-score'   => undef,
					       '-source'  => $f2source,
					       '-primary' => $f2primary,
					       '-analysis'=> $analysis_obj );
    #create featurepair
    my $fp = new Bio::EnsEMBL::FeaturePair  ('-feature1' => $feat1,
                                             '-feature2' => $feat2) ;
 
    $self->_growfplist($fp); 
}

sub _growfplist {
    my ($self, $fp) =@_;
    
    #load fp onto array using command _grow_fplist
    push(@{$self->{'_fplist'}}, $fp);
}

sub _createfiles {
    my ($self, $genfile, $estfile, $dirname)= @_;
    
    #check for diskspace
    my $spacelimit = 0.1; # 0.1Gb or about 100 MB
    my $dir ="./";
    unless ($self->_diskspace($dir, $spacelimit)) 
    {
        $self->throw("Not enough disk space ($spacelimit Gb required)");
    }
            
    #if names not provided create unique names based on process ID    
    $genfile = $self->_getname("genfile") unless ($genfile);
    $estfile = $self->_getname("estfile") unless ($estfile);    
    #create tmp directory    
    mkdir ($dirname, 0777) or $self->throw ("Cannot make directory '$dirname' ($?)");
    chdir ($dirname) or $self->throw ("Cannot change to directory '$dirname' ($?)"); 
    return ($genfile, $estfile);
}
    

sub _getname {
    my ($self, $typename) = @_;
    return  $typename."_".$$.".fn"; 
}

sub _diskspace {
    my ($self, $dir, $limit) =@_;
    my $block_size; #could be used where block size != 512 ?
    my $Gb = 1024 ** 3;
    
    open DF, "df $dir |" or $self->throw ("Can't open 'du' pipe");
    while (<DF>) 
    {
        if ($block_size) 
        {
            my @L = split;
            my $space_in_Gb = $L[3] * 512 / $Gb;
            return 0 if ($space_in_Gb < $limit);
            return 1;
        } 
        else 
        {
            ($block_size) = /(\d+).+blocks/i
                || $self->throw ("Can't determine block size from:\n$_");
        }
    }
    close DF || $self->throw("Error from 'df' : $!");
}


sub _deletefiles {
    my ($self, $genfile, $estfile, $dirname) = @_;
    unlink ("$genfile") or $self->throw("Cannot remove $genfile ($?)\n");
    unlink ("$estfile") or $self->throw("Cannot remove $estfile ($?)\n");
    chdir ("../");
    rmdir ($dirname) or $self->throw("Cannot remove $dirname \n");
}

1;
