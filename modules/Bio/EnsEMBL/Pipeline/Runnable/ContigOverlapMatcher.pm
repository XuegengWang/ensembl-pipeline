
=head1 NAME - Bio::EnsEMBL::Pipeline::Runnable::ContigOverlapMatcher

=head1 SYNOPSIS

    my $matcher = Bio::EnsEMBL::Pipeline::Runnable::ContigOverlapMatcher->new();
    
    # @contig_list is a list of Bio::EnsEMBL::DB::ContigI
    # compliant objects.
    foreach my $c (@contig_list) {
        $matcher->add_Contig($c);
    }
    
    # Use phrap to detect overlaps
    $matcher->run;
    
    # Get the list of ContigOverlap objects made
    my @contig_overlaps = $matcher->get_all_ContigOverlaps;
    
    # Get a hash of;
    #    contig name => name of contig containing it
    # (if any).
    my %redundant = $matcher->redundant_contigs;

=head1 DESCRIPTION

Takes a list of Bio::EnsEMBL::DB::ContigI
compliant objects, and uses C<phrap> (or rather
C<phrap.longreads>, a version of phrap compiled
to allow reads over 64kbp) to detect overlaps
between contigs, and generates
Bio::EnsEMBL::ContigOverlap objects.  The
ContigOverlap objects are given the source
"phrap".

=head1 METHODS

Private methods are prefixed by an underscore ("_").

=cut

package Bio::EnsEMBL::Pipeline::Runnable::ContigOverlapMatcher;

use strict;
use Bio::EnsEMBL::Pipeline::RunnableI;
use Bio::EnsEMBL::Analysis::Programs 'phrap.longreads';
use Bio::EnsEMBL::ContigOverlap;
use Bio::SeqIO;
use File::Path 'rmtree';
use vars '@ISA';

@ISA = 'Bio::EnsEMBL::Pipeline::RunnableI';

=head2 new

Returns a new
Bio::EnsEMBL::Pipeline::Runnable::ContigOverlapMatcher
object.

=cut

sub _initialize {
    my( $self, @args ) = @_;
    my $make = $self->SUPER::_initialize(@_);
    
    $self->{'_contig_by_id'} = {};
    $self->{'_contig_overlap'} = [];
    
    $self->sequence_list(@args) if @args;
}

=head2 add_Contig

    $matcher->add_Contig($contig);

Adds a C<Bio::EnsEMBL::DB::ContigI> compliant
object to the matcher object.

=cut

{
    my $obj_type = 'Bio::EnsEMBL::DB::ContigI';

    sub add_Contig {
        my( $self, $contig ) = @_;

        my( $is_contig );
        eval{
            $is_contig = $contig->isa($obj_type);
        };
        unless ($is_contig) {
            $self->throw("Argument '$contig' is not a $obj_type compliant object");
        }
        my $id = $contig->id
            or $self->throw("Contig didn't return an ID");
        $self->{'_contig_by_id'}{$id} = $contig;
    }
}

=head2 get_all_Contigs

    @contigs = $matcher->get_all_Contigs;

Returns a list of all the Contig objects from
the matcher object, in no particular order.

=cut

sub get_all_Contigs {
    my( $self ) = @_;
    
    return values %{$self->{'_contig_by_id'}};
}

=head2 get_Contig_by_ID

    $contig = $matcher->get_Contig_by_ID($id);

Given the ID of a contig, fetches it from the
matcher object.

=cut

sub get_Contig_by_ID {
    my( $self, $id ) = @_;
    
    my $contig = $self->{'_contig_by_id'}{$id};
    if ($contig) {
        return $contig;
    } else {
        $self->throw("Can't get contig with ID='$id'");
    }
}

=head2 add_ContigOverlap

    $matcher->add_ContigOverlap($overlap);

Adds a C<Bio::EnsEMBL::ContigOverlap> object to
the matcher's internal list.

=cut

{
    my $obj_type = 'Bio::EnsEMBL::ContigOverlap';

    sub add_ContigOverlap {
        my( $self, $overlap ) = @_;

        my( $is_valid );
        eval{
            $is_valid = $overlap->isa($obj_type);
        };
        unless ($is_valid) {
            $self->throw("Argument '$overlap' is not a $obj_type object");
        }
        push(@{$self->{'_contig_overlap'}}, $overlap);
    }
}


=head2 get_all_ContigOverlaps

    @overlaps = $matcher->get_all_ContigOverlaps;

Fetches a list of all the ContigOverlap objects
generated by the matcher object.

=cut

sub get_all_ContigOverlaps {
    my( $self ) = @_;
        
    unless ($self->_was_run) {
        $self->throw("Can't provide any ContigOverlaps without having been run");
    }

    return @{$self->{'_contig_overlap'}};
}

=cut

=head2 sequence_list

    my @seq_list = $matcher->sequence_list;

Gets a list of C<Bio::PrimarySeq> objects
(contigs) which will be phrap'ed from the
Contig objects.

=cut

sub sequence_list {
    my($self, @seqs) = @_;
    
    return map $_->primary_seq, $self->get_all_Contigs;
}

=head2 get_Contig_sequence_length

    my $length = $matcher->get_Contig_sequence_length($id);

Given the ID of a contig, returns the length of
its PrimarySeq object.

=cut

sub get_Contig_sequence_length {
    my( $self, $id ) = @_;
    
    return $self->get_Contig_by_ID($id)->primary_seq->length;
}

=head2 redundant_contigs

    %redundant = $matcher->redundant_contigs;

Returns a hash describing the redundant contigs
found by C<phrap>.  Each key of the hash is the
name of a redundant contig, and the value is the
name of the contig whose sequence completely
subsumes the sequence of the redundant contig.

=cut

sub redundant_contigs {
    my($self) = @_;
    
    unless ($self->_was_run) {
        $self->throw("Can't list redundant contigs without having been run");
    }
    
    if ($self->{'_redundant_contigs'}) {
        return %{$self->{'_redundant_contigs'}};
    } else {
        return;
    }
}

=head2 _add_redundant_contigs

    $matcher->_add_redundant_contigs(%contig_name_hash);

Adds C<%contig_name_hash> to the hash of
redundant contigs described in the
C<redundant_contigs> method.

=cut

sub _add_redundant_contigs {
    my($self, @names) = @_;
    
    $self->throw("Odd number of arguments: ". join(',', map "'$_'", @names))
        if @names % 2;
    my %n = @names;
    while (my($redundant, $parent) = each %n) {
        $self->{'_redundant_contigs'}{$redundant} = $parent;
    }
}

=head2 _tmp_dir_name

Returns a name for a temporary directory in
C</tmp>, which is needed by C<phrap> to store
fasta and output files.

=cut

{
    my( $tmp_dir_name );

    sub _tmp_dir_name {
        $tmp_dir_name ||= "/tmp/ContigOverlapMatcher.$$";
        return $tmp_dir_name;
    }
}

=head2 _write_seqs_to_file

    $matcher->_write_seqs_to_file($file);

Creates a multiple fasta format file, C<$file>,
from all the PrimarySeq objects in C<$matcher>.

=cut

sub _write_seqs_to_file {
    my( $self, $file ) = @_;
    
    my $seq_out = Bio::SeqIO->new('-FILE' => "> $file", '-FORMAT' => 'fasta');
    my @seqs = $self->sequence_list
        or $self->throw("No sequences to write");
    foreach my $s (@seqs) {
        $seq_out->write_seq($s);
    }
}

=head2 _make_seq_length_hash

Returns a ref to a hash with keys contig names,
and values contig lengths.

=cut

sub _make_seq_length_hash {
    my( $self ) = @_;
    
    my %seq_lengths = map {$_->id, $_->length} $self->sequence_list;
    return \%seq_lengths;
}

=head2 run

    $matcher->run;

Runs C<phrap.longreads> on all of the contigs,
and parses the output.  A list of ContigOverlap
objects is stored in the object, which can be
accessed via the C<output> method.  Contigs which
are completely subsumed within other contigs in
the set can be accessed via the
C<redundant_contigs> method.  Any errors will
cause an exception to be thrown.

=cut

sub run {
    my( $self ) = @_;
    
    if ($self->_was_run) {
        $self->throw("ContigOverlapMatcher objects can only be run once");
    }
    
    my $tmp_dir = $self->_tmp_dir_name;
    eval{
        mkdir($tmp_dir, 0755) or die "Can't mkdir('$tmp_dir') : $!";
        my $seq_file = "$tmp_dir/contig.seq";
        $self->_write_seqs_to_file($seq_file);
        my $command = "cd $tmp_dir; phrap.longreads -ace -default_qual 90 -minmatch 30 -maxmatch 30 $seq_file >/dev/null 2>&1";
        system($command) == 0
            or $self->throw("phrap command '$command' failed");
        
        # Parse the ace file, and create ContigOverlap objects
        my $ace_file = "$seq_file.ace";
        $self->_process_ace_file($ace_file);
    };
        
    rmtree($tmp_dir);
    $self->_was_run(1);
    
    if ($@) {
        $self->throw($@);
    } else {
        return 1;
    }
}

=head2 _was_run

    $matcher->_was_run(1);
    $already_run = $matcher->_was_run;

The ContigOverlapMatcher object is only supposed
to be run once.  C<_was_run> is used internally
to check ensure that it is only run once, and
also that it has been run by methods which return
post-run output.

=cut

sub _was_run {
    my( $self, $flag ) = @_;
    
    # Can only set to TRUE
    if ($flag) {
        $self->{'_was_run'} = $flag;
    }
    return $self->{'_was_run'};
}

=head2 output

    @contig_overlaps = $matcher->output;

Same as calling C<get_all_ContigOverlaps>.

=cut

sub output {
    my( $self ) = @_;
    
    $self->get_all_ContigOverlaps(@_);
}

=head2 _process_ace_file

    $matcher->_process_ace_file($ace_file);

Parses the B<ace> file created by phrap.  The DNA
objects are inspected, and those which correspond
to input contigs are checked to make sure that
their length hasn't been altered by C<phrap>
(which may happen according to Rob Davies).

The B<Base_segment> lines, which show the contigs
which contributed to the new consensus, are
parsed and used to create ContigOverlap objects. 
(B<Base_segment> lines in the phrap B<ace> file
show the coordinates in each contig without
taking any upsteam padding characters into
account.  In contrast, B<Base_segment*> lines,
which we ignore, show the coordinates in the
padded sequence.)

=cut

sub _process_ace_file {
    my( $self, $ace_file ) = @_;
    
    local *PHRAP_ACE;
    local $/ = "";  # Split input into blank line separated blocks
    open PHRAP_ACE, $ace_file
        or $self->throw("Can't open file '$ace_file' : $!");
    while (<PHRAP_ACE>) {
        # Look at DNA objects in the ace file
        if (my ($contig_name, $dna) = /^DNA ([^\n]+)(.+)/s) {
            # Here I'm being paranoid that phrap might have
            # shortened the contig.
            $contig_name =~ s/\.comp$//;
            my( $orig_len );
            eval{
                $orig_len = $self->get_Contig_sequence_length($contig_name);
            };
            unless ($orig_len) {
                # Skip the DNA for the consensus
                warn "No sequence length for $contig_name\n";
                next;
            }
            $dna =~ s/[\s\*]//g;
            my $dna_len = length($dna);
            unless ($dna_len == $orig_len) {
                $self->throw("Contig '$contig_name' was $orig_len before, $dna_len after phrap");
            }
        }
        # Look at base segments
        elsif (my @base_segments = map {[split]} /^Base_segment (.+)/mg) {
            my @sorted_span = $self->_make_sorted_spans(@base_segments);
            $self->_remove_redundant_contigs(\@sorted_span);
            $self->_make_overlap_helpers(@sorted_span);
            #print map {join("\t", @$_), "\n"} @sorted_span;
        }
    }
    close PHRAP_ACE;
}

=head2 _make_sorted_spans

    @sorted_spans = _make_sorted_spans(@base_segments);

Takes the arrays of Base_segment data from the
phrap .ace file, and returns a list of arrays
which show the extent of each contig in the
assembly, and the name and postion it matches in
its overlapping contig.

=cut

sub _make_sorted_spans {
    my( $self, @base_segments ) = @_;
    
    # We can just sort on the start position of each
    # contig in the consensus, since each position in the
    # consensus can only occur once.
    @base_segments = sort {$a->[0] <=> $b->[0]} @base_segments;

    my( %span );
    for (my $i = 0; $i < @base_segments; $i++) {
        my(
            $cs,    # 0 Start position in consensus
            $ce,    # 1 End position in consensus
            $name,  # 2 Name of contig
            $rs,    # 3 Start position in contig
            $re,    # 4 End position in contig
            ) = @{$base_segments[$i]};
        if ($span{$name}) {
            # We already know about $name, so just
            # extend the span
            $span{$name}->[1] = $ce;
            $span{$name}->[4] = $re;
        } else {
            # Make a new span
            #               0    1    2      3    4
            $span{$name} = [$cs, $ce, $name, $rs, $re];
        }
        
        # Store the name and position in the matching contig. This is
        # the next contig which contibutes to the consensus, and
        # the matching position is the start coordinate in the next contig
        # minus 1.  If, however, the start position in this next contig
        # is 1, then we adjust increase the length of the current
        # span by 1.
        # $next won't exist if this is the last contig in the assembly.
        if (my $next = $base_segments[$i+1]) {
            my( $j_name, $j_start ) = @{$next}[2,3];
            if ($j_start == 1) {
                $span{$name}->[1]++;
                $span{$name}->[4]++;
            } else {
                $j_start--;
            }
            $span{$name}->[5] = $j_name;
            $span{$name}->[6] = $j_start;
        }
    }
    my @sorted_span = sort {$a->[0] <=> $b->[0]} values %span;
    
    # Increase the length of overlapping sequences by 1
    for (my $i = 0; $i < (@sorted_span - 1); $i++) {
        $sorted_span[$i][1]++;
        $sorted_span[$i][4]++;
    }
    print STDERR map {join("\t", @$_),"\n"} @sorted_span;
    return @sorted_span;
}

=head2 _remove_redundant_contigs

    $self->_remove_redundant_contigs(\@sorted_span);

Removes contigs from the list of spans (created
by C<_make_sorted_spans>), which are completely
contained within other contigs, storing the names
of the redundant contigs in the object.

=cut

sub _remove_redundant_contigs {
    my( $self, $span ) = @_;
    
    my( %removed );
    for (my $i = 1; $i < @$span;) {
        # Get the start, end and name of the previous contig in the assembly
        my($p_start, $p_end, $p_name) = @{$span->[$i-1]};
        # Get the start, end and name of the current contig in the assembly
        my($start, $end, $name)       = @{$span->[$i]};
        
        # Remove the current contig if it is completely overlapped
        # by the previous contig in the assembly
        if ($start <= $p_start and $end >= $p_end) {
            $removed{$name} = $p_name;
            splice(@$span, $i, 1);
            # Don't move pointer if we've removed an element
        } else {
            # Move pointer to next element
            $i++;
        }
    }
    $self->_add_redundant_contigs(%removed);
}

=head2 _make_overlap_helpers

    $self->_make_overlap_helpers(@sorted_span);

Takes an array of arrays made from the parsed and
processed phrap output (after 
C<_make_sorted_spans> and
C<_remove_redundant_contigs>), and creates
ContigOverlap objects, storing them in the
object.

This 5 contig assembly illustrates the four
possible overlap types:

    5'--A------->3'
            5'--B------->3'
                    3'<-------C--5'
                            3'<-------D--5'
                                    5'--E------->3'

Which are as follows:

=over 4

=item *

Contig A to Contig B = right2left

=item *

Contig B to Contig C = right2right

=item *

Contig C to Contig D = left2right

=item *

Contig D to Contig E = left2left

=back

=cut

{
    my %overlap_type = (
        'fwd-fwd'   => 'right2left',    # See A to B above
        'fwd-rev'   => 'right2right',   # See B to C above
        'rev-rev'   => 'left2right',    # See D to E above
        'rev-fwd'   => 'left2left',     # See A to F above
        );

    sub _make_overlap_helpers {
        my( $self, @span ) = @_;

        my( @overlap );
        # Loop through every element but the last one
        # (which is the trailing contig, and doesn't 
        # therefore overlap anything).
        for (my $i = 0; $i < (@span - 1); $i++) {
            # Get the data that we're interested in from the row
            my($a_name, $a_pos, $b_name, $b_pos) = @{$span[$i]}[2,4,5,6];

            # Get the direction of each sequence
            my $a_dir = ($a_name =~ s/\.comp$//) ? 'rev' : 'fwd';
            my $b_dir = ($b_name =~ s/\.comp$//) ? 'rev' : 'fwd';

            # Look up overlap type in static hash
            my $type = $overlap_type{"$a_dir-$b_dir"};

            # Correct coordinates for reverse sequences
            if ($a_dir eq 'rev') {
                my $a_len = $self->get_Contig_sequence_length($a_name);
                $a_pos = $a_len - $a_pos + 1;
            }
            if ($b_dir eq 'rev') {
                my $b_len = $self->get_Contig_sequence_length($b_name);
                $b_pos = $b_len - $b_pos + 1;
            }

            # Make an new ContigOverlap object
            my $ovrlp = Bio::EnsEMBL::ContigOverlap->new(
                '-contiga'      => $self->get_Contig_by_ID($a_name),
                '-contigb'      => $self->get_Contig_by_ID($b_name),
                '-positiona'    => $a_pos,
                '-positionb'    => $b_pos,
                '-overlap_type' => $type,
                '-source'       => 'phrap',
                );
            $self->add_ContigOverlap($ovrlp);
        }
    }
}

1;


__END__

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

