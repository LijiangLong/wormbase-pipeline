#!/usr/local/ensembl/bin/perl

# Author: Marc Sohrmann (ms2@sanger.ac.uk)
# Copyright (c) Marc Sohrmann, 2001
# You may distribute this code under the same terms as perl itself

# wrapper around Richard Durbin's pmatch code (fast protein matcher).

use strict;
use Getopt::Std;
use vars qw($opt_q $opt_t $opt_l $opt_w $opt_s $opt_c $opt_o $opt_d);

getopts ("q:t:l:wsco:d");

my $usage = "pmatch.pl\n";
$usage .= "-q [query fasta db]\n";
$usage .= "-t [target fasta db] OR -l [file listing target fasta db's] OR -w to create tmp file of all worm pep's from SWALL\n";
$usage .= "-o [out file]\n";
$usage .= "-s to calculate the best path of non-overlapping pmatch matches for each query-target pair  OPTIONAL\n";
$usage .= "-c to classify the matches (relative to the query sequence)   OPTIONAL\n";
$usage .= "-d to keep the intermediate tmp files   OPTIONAL\n";

unless ($opt_q && ($opt_t || $opt_l || $opt_w) && $opt_o) {
    die "$usage";
}

#################################

my $query = $opt_q;
my $target = $opt_t;

#################################
# make worm-specific protein set from SWALL if ($opt_w)

if ($opt_w) {
    print STDERR "extract worm sequences from SWALL...\n";
    my $getz = "getz -f seq -sf fasta \'[swall-org:Caenorhabditis elegans]\' > $$.swall";
    system "$getz";
    $target = "$$.swall";
}

#################################
# run pmatch (Richard Durbin's fast protein matcher, rd@sanger.ac.uk)

print STDERR "run pmatch...\n";
if ($opt_l) {
    my @files;
    open (DB , "$opt_l") || die "cannot read $opt_l\n";
    while (<DB>) {
        chomp;
        my @a = split /\s+/;
        push (@files , @a);
    }
    close DB;        
    foreach my $file (@files) {
        my $pmatch = "pmatch -T 14 $file $query >> $$.pmatch";
        system "$pmatch";
    }
}
else {
    my $pmatch = "pmatch -T 14 $target $query > $$.pmatch";
    system "$pmatch";
}

if ($opt_w && !$opt_d) {
    unlink "$$.swall";
}

#################################
# sort the pmatch output file, based on query and target name
# (necessary since not all the matches relating to a query-target pair cluster)

print STDERR "sort the pmatch output file...\n";
my (@a , @q , @t);
open (TMP , ">$$.sort") || die "cannot create $$.sort\n";
open (PMATCH , "$$.pmatch") || die "cannot read $$.pmatch\n";
while (<PMATCH>) {
    my @f = split /\t/;
    push @a, $_;
    push @q, $f[1];
    push @t, $f[6];
}
foreach my $i (sort { $q[$a] cmp $q[$b] or $t[$a] cmp $t[$b] } 0..$#a) { print TMP $a[$i] }
close PMATCH;
close TMP;
rename ("$$.sort" , "$$.pmatch");

#################################
# determine the best path of non-overlapping matching substrings (if $opt_s)

if ($opt_s) {
    print STDERR "stitch pmatch substrings...\n";
    open (STITCH , ">$$.stitch") || die "cannot create $$.stitch\n";
    my @match_list = ();
    my $old_query;
    my $old_target;
    my $old_qlen;
    my $old_tlen;
    my $previous_line;
    open (PMATCH , "$$.pmatch") || die "cannot read $$.pmatch\n";
    while (<PMATCH>) {
        chomp;
        my @a = split /\t/;
        my $query = $a[1];
        my $qstart = $a[2];
        my $qend = $a[3];
        my $qlen = $a[5];
        my $target = $a[6];
        my $tstart = $a[7];
        my $tend = $a[8];
        my $tlen = $a[10];

        # new set of query/target 
        if (($query ne $old_query || $target ne $old_target) && @match_list) {
            if (@match_list == 1) {
                print STITCH "$previous_line\n";
            }
            else {
                my ($max , $trace) = stitch_matches (@match_list);
                my $qperc = sprintf ("%.1f" , ($max/$old_qlen)*100);
                my $tperc = sprintf ("%.1f" , ($max/$old_tlen)*100);
                my $num = @$trace-1;
                print STITCH "$max\t$old_query\t$trace->[1]->{QSTART}\t$trace->[$num]->{QEND}\t$qperc\t$old_qlen\t";
                print STITCH "$old_target\t$trace->[1]->{TSTART}\t$trace->[$num]->{TEND}\t$tperc\t$old_tlen\t($num)\n";
	    }
            @match_list = ();
            my $match = Pmatch->new('QSTART'=>$qstart,'QEND'=>$qend,'TSTART'=>$tstart,'TEND'=>$tend);
            push (@match_list , $match);
            $old_query = $query;
            $old_target = $target;
            $old_qlen = $qlen;
            $old_tlen = $tlen;
            $previous_line = $_;
        }
        # last line 
        elsif (eof) {
            unless (@match_list) {
                $old_query = $query;
                $old_target = $target;
                $old_qlen = $qlen;
                $old_tlen = $tlen;
            }
            my $match = Pmatch->new('QSTART'=>$qstart,'QEND'=>$qend,'TSTART'=>$tstart,'TEND'=>$tend);
            push (@match_list , $match);
            my ($max , $trace) = stitch_matches (@match_list);
            my $num = @$trace-1;
            my $qperc = sprintf ("%.1f" , ($max/$old_qlen)*100);
            my $tperc = sprintf ("%.1f" , ($max/$old_tlen)*100);
            print STITCH "$max\t$old_query\t$trace->[1]->{QSTART}\t$trace->[$num]->{QEND}\t$qperc\t$old_qlen\t"; 
            print STITCH "$old_target\t$trace->[1]->{TSTART}\t$trace->[$num]->{TEND}\t$tperc\t$old_tlen\t($num)\n";
        }
        # else
        else {
            my $match = Pmatch->new('QSTART'=>$qstart,'QEND'=>$qend,'TSTART'=>$tstart,'TEND'=>$tend);
            push (@match_list , $match);
            $old_query = $query;
            $old_target = $target;
            $old_qlen = $qlen;
            $old_tlen = $tlen;
            $previous_line = $_;
        }
    }
    close PMATCH;
    close STITCH;
}

##########################################
# process the matches, classifying them into several categories

if ($opt_c) {
    print STDERR "process matches...\n";
    # get first a list of all query id's
    my @queries;
    open (ID , "$query") || die "cannot read $query\n";
    while (<ID>) {
        chomp;
        if (/^\>(\S+)/) {
            push (@queries , $1);
        }
    }
    close ID;

    # process the matches
    my $input;
    if ($opt_s) {
        $input = "$$.stitch";
    }
    else {
        $input = "$$.pmatch";
    }
    open (PROCESS , ">$$.process") || die "cannot create $$.process\n";
    open (IN , "$input") || die "cannot read $input\n";
    process_matches (*IN , *PROCESS , \@queries);
    close IN;
    close PROCESS;
}

#########################################
# delete some tmp files, and move the appropriate results to the out file unless ($opt_d)

unless ($opt_d) {
    if ($opt_c) {
        rename ("$$.process" , "$opt_o");
        unlink "$$.pmatch";
        if ($opt_s) {
            unlink "$$.stitch";
	}
    }
    elsif ($opt_s) {
        rename ("$$.stitch" , "$opt_o");
        unlink "$$.pmatch";        
    }
    else {
        rename ("$$.pmatch" , "$opt_o");
    }
}

exit 0;

########################
# subroutines
########################
sub stitch_matches {
    my @match_list = @_;
    my $DEBUG = 0;
    my $TRACE = 1;

    # sort the matches, based on the start coordinate, and keep them in the @sort array
    # !! does not explicitly deal with cases where match boundaries overlap
    #    (like qstart1 < qstart2 and tstart1 > tstart2). But since we only
    #    chain non-overlapping matches, this should be ok (the order of the matches
    #    within the clusters of overlapping matches does not matter)
    my @sort = ();
    foreach my $match (@match_list) {
        unless (@sort) {
            push (@sort , $match_list[0]);
            next;
        }
        my $element_num = @sort;
        my $switch = 0;
        for (my $i = 0 ; $i < $element_num ; $i++) {
            my $sorted_match = $sort[$i];
            if ($match->{QSTART} < $sorted_match->{QSTART} && $match->{TSTART} < $sorted_match->{TSTART}) {
                $switch = 1;
                # insert the new match into the list (kind of linked list)
                my @tmp = splice (@sort , $i);
                push (@sort , $match);
                push (@sort , @tmp);
                last;
            }
        }
        unless ($switch) {
            push (@sort , $match);
            $switch = 0;
	}
    }
    
    if ($DEBUG) {
        foreach (@sort) {
            print STITCH "\tsort: $_->{QSTART}  $_->{QEND}  $_->{TSTART}  $_->{TEND}\n";
	}
    }

    # loop over all the matches, always calculating the best score up to this point
    # (some kind of dynamic programming):
    #     - accept only non-overlaping matches
    #     - use the length of the uniquely matching sequence as score
    #       (not really necessary with pmatch, since it only returns exact matches)
    #       # my $q = $sort[$j]->{QEND} - $sort[$j]->{QSTART} + 1;
    #       # my $t = $sort[$j]->{TEND} - $sort[$j]->{TSTART} + 1;
    #       # my $tmp_score = $score[$i] + (($q < $t) ? $q : $t);
    #       my $tmp_score = $score[$i] + $sort[$j]->{QEND} - $sort[$j]->{QSTART} + 1;
    my $max = 0;
    my $max_index = 0;
    my @score;
    my @trace;
    my $tmp_trace;

    # define the (starting) boundary condition, and make this match the first element of @sort
    my $boundary = Pmatch->new('QSTART'=>0,'QEND'=>0,'TSTART'=>0,'TEND'=>0);
    unshift (@sort , $boundary);
    $score[0] = 0;
    push (@{$trace[0]} , $sort[0]);

    # loop over all the matches, always calculating the best score up to this point
    # (some kind of dynamic programming)
    for (my $j = 1 ; $j < @sort ; $j++) {
        $score[$j] = 0;
        for (my $i = 0 ; $i < $j ; $i++) {
            # accept only non-overlaping matches
            if ($sort[$i]->{QEND} < $sort[$j]->{QSTART} && $sort[$i]->{TEND} < $sort[$j]->{TSTART}) {
                my $tmp_score = $score[$i] + $sort[$j]->{QEND} - $sort[$j]->{QSTART} + 1;
                # keep the best score, and the trace pointer
                if ($tmp_score > $score[$j]) {
                    $score[$j] = $tmp_score;
                    $tmp_trace = $i;
                }
            }
        }
        # make the trace update
        if ($TRACE) {
            push (@{$trace[$j]} , @{$trace[$tmp_trace]});
            push (@{$trace[$j]} , $sort[$j]);
	}
        # recalculate the max score
        if ($score[$j] > $max) {
            $max = $score[$j];
            $max_index = $j;
        }
    }

    if ($DEBUG) {
        for (my $j = 1 ; $j < @score ; $j++) {
            print STITCH "match $j (score $score[$j]):\n";
            for (my $i = 1 ; $i < @{$trace[$j]} ; $i++) {
                print STITCH "\ttrace $trace[$j]->[$i]->{QSTART}  $trace[$j]->[$i]->{QEND}  $trace[$j]->[$i]->{TSTART}  $trace[$j]->[$i]->{TEND}\n";
	    }
        }
    }
    if ($TRACE) {
        return ($max , $trace[$max_index]);    
    }
    else {
        return ($max);
    }
}

####################
sub process_matches {
    local *IN = shift;
    local *OUT = shift;
    my $query_ids = shift;

    # define some variables:
    # to keep track of the quality of the matches
    my %match;
    my %partial;
    my %candidate;
    my %target_match;

    # for the parsing
    my %percent;
    my $old_qid = "";
    my $old_tid = "";
    my $best_qperc = 0; 

    # to count how often the different match classes occurred
    my $count_match = 0;
    my $count_partial_match = 0;
    my $count_partial = 0;
    my $count_candidate = 0;
    my $count_orphan = 0;

    # read the pmatch output file,
    # and keep the "percent matching" in a 2D hash, indexed by query and target sequence
    while (<IN>) {
        chomp;
        my ($len,$qid,$qstart,$qend,$qperc,$qlen,$tid,$tstart,$tend,$tperc,$tlen) = split /\t/;
        # we only consider the best match per query-target pair. Use the -s option to
        # get the total matching sequence (pmatch gives multiple hits either due to e.g.
        # introns, or to internal repeats (we don't want the latter))
        if ($qid ne $old_qid || $tid ne $old_tid) {
            $percent{$qid}->{$tid} = $qperc."\t".$tperc;
            $best_qperc = $qperc;
	}
        elsif ($qid eq $old_qid && $tid eq $old_tid && $qperc > $best_qperc) {
            $percent{$qid}->{$tid} = $qperc."\t".$tperc;
            $best_qperc = $qperc;
	}
        $old_qid = $qid;
        $old_tid = $tid;
    }

    # classify the matches
    foreach my $query_id (sort {$a cmp $b} keys %percent) {
        my @matches = ();
        my @partial_query = ();
        my @partial_target = ();
        my @candidates = ();
        my @best = ();   
        # loop over all targets, having the matches sorted (descending) based on the query percent coverage ($qperc)
        # and populate the different arrays of types of matches
        foreach my $target_id (sort {$percent{$query_id}{$b} <=> $percent{$query_id}{$a}} keys %{$percent{$query_id}}) {
            my ($qperc , $tperc) = split (/\t/ , $percent{$query_id}->{$target_id});
            # if the 2 proteins are identical
            if ($qperc == 100 && $tperc == 100) {
                $target_match{$target_id} = 1;
		push (@matches , "$query_id\t$target_id");
	    }
            elsif (($qperc < 100 || $tperc < 100) && @matches) {
                last;
	    }
            # partial target
            elsif ($qperc == 100 && $tperc < 100) {
                push (@partial_target , "$query_id\t$target_id\tpartial_target\t$qperc\t$tperc");
	    }
            # partial query
            elsif ($qperc < 100 && $tperc == 100) {
                push (@partial_query , "$query_id\t$target_id\tpartial_query\t$qperc\t$tperc");
	    }
            # candidate match
            elsif ($qperc > 66 && $tperc > 66) {
                push (@candidates , "$query_id\t$target_id\tcandidate\t$qperc\t$tperc");
	    }
            else {
                last;
	    }
	}
        # check what we've got, and keep the results in the appropriate hash
        if (@matches) {
            # one perfect match
            if ((my $num = @matches) == 1) {
                $match{$query_id} =  "$matches[0]\tmatch";
	    }
            # several perfect matches
            else { 
                $match{$query_id} = "$matches[0]\trepeat";
	    }
	}
        elsif (@partial_query) {
            $partial{$query_id} = "$partial_query[0]";
	}
        elsif (@partial_target) {
            $partial{$query_id} = "$partial_target[0]";
	}
        elsif (@candidates) {
            $candidate{$query_id} = "$candidates[0]";
	}
    }

    # loop over all the query proteins, printing to OUT
    foreach my $pep (@$query_ids) {
        # exact match
        if (exists $match{$pep}) {
            print OUT "$match{$pep}\n";
            $count_match++;
	}
        # partial match (distinguish candidate target proteins that do have
        # an exact match to another worm protein from the ones that don't
        elsif (exists $partial{$pep}) {
            my @a = split (/\t/ , $partial{$pep});
            # the matching target protein has already an exactly matching query protein
            if (exists $target_match{$a[1]}) {
                print OUT "$partial{$pep}\n";
                $count_partial++;
	    }
            # the matching target protein does not have an exactly matching query protein
            else {
                $a[2] .= "_match";
                my $line = join ("\t" , @a);
                print OUT "$line\n";
                $count_partial_match++;
	    }
	}
        # candidate match
        elsif (exists $candidate{$pep}) {
            my @a = split (/\t/ , $candidate{$pep});
            # accept only if the candidate target protein does not have an exactly matching query protein
            unless (exists $target_match{$a[1]}) {
                print OUT "$candidate{$pep}\n";
                $count_candidate++;
	    }
	}
        else {
            print OUT "$pep\torphan\n";
            $count_orphan++;
	}
    }

    # print some numbers...
    my $number = @$query_ids;
    print STDERR "$number\tproteins in total:\n";
    print STDERR "$count_match\tproteins have an exact match [match]\n";
    print STDERR "$count_partial_match\tproteins have an overlapping match [partial_query_match or partial_target_match]\n";
    print STDERR "$count_partial\tproteins overlap with a peptide that has been mapped to another query protein [partial_query or partial_target]\n";
    print STDERR "$count_candidate\tproteins partially match a peptide that has not been mapped to another target protein [candidate]\n";
    print STDERR "$count_orphan\tproteins do not match anything [orphan]\n";
}

##########################################
# some OO stuff:
##########################################

package Pmatch;

# constructor
sub new {
    my $class = shift;
    my $self = {};
    bless ($self , $class);
    $self->_init(@_);  # call _init to initialise some attributes
                       # interpret the remaining args as key-value pairs
    return $self;
}

# _init method, initialising some attributes,
# and interpreting the remaining args as key-value pairs

sub _init {
    my $self = shift;
    my %extra = @_;
    @$self{keys %extra} = values %extra;
}

1;
##########################################
