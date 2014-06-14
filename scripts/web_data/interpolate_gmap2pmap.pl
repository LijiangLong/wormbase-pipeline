#!/usr/bin/env perl

# This script interpolates genetic positions onto the physical map.

use strict;
use Getopt::Long;

use Bio::SeqIO;

use Wormbase;
use Log_files;

my ($acedb, $test, $debug, $store, $gff3, $wormbase);

GetOptions (
  'test'       => \$test,
  'debug=s'    => \$debug,
  'store=s'    => \$store,
  'database=s' => \$acedb,
  'gff3'       => \$gff3,
    );


if ($store) { 
  $wormbase = Storable::retrieve($store) or croak("cant restore wormbase from $store\n"); 
}
else { 
  $wormbase = Wormbase->new( -debug => $debug, 
                             -test => $test);
}

$acedb ||= $wormbase->autoace;
my $db = Ace->connect(-path => $acedb);

my $log = Log_files->make_build_log($wormbase);

# Fetch all Gene markers with both a map position and a sequence
# association

my $chr_prefix = $wormbase->chromosome_prefix;

my $chr_lengths = fetch_chromosome_lengths();
my $markers = fetch_markers();
my $to_map  = fetch_genes_lacking_pmap_coords();

##################################################################
# sorting gmap positions of marker loci from left tip to right tip
##################################################################

foreach my $chrom (sort keys %$chr_lengths) {

  my $fname = $wormbase->gff_splits . "/${chr_prefix}${chrom}_gmap2pmap";
  $fname .= ($gff3) ? ".gff3" : ".gff";
  open(my $out_fh, ">$fname") or $log->log_and_die("Could not open $fname for writing\n");

  if (exists $markers->{$chrom}) {

    # Sort all markers on the chromosome according to their genetic map position
    $log->write_to("Doing chrom $chrom\n");
    my @sorted_markers = sort { $a->{gmap} <=> $b->{gmap} } @{$markers->{$chrom}};
    
    my %markers_by_pos;  # hash that relates markers to the position in the sorted array
    my $c = 0;
    foreach (@sorted_markers) {
      $markers_by_pos{$_->{name}} = $c;
      $c++;
    }
    
    # Maximal markers used for calculating the map
    my $left  = $sorted_markers[0];
    my $right = $sorted_markers[-1];
    
    # Calculate the total number of genetic units per chromosome
    # This isn't completely accurate...
    my $units = $right->{gmap} - $left->{gmap};
    
    # calculate the bp per genetic unit
    # This is used as the baseline for the interpolated map outside of the maximal markers
    my $bp_per_unit = $chr_lengths->{$chrom} / abs($units);
    
    $log->write_to("Chrom $chrom: " . $left->{name} . ' (' . $left->{mean_pos} . '); '
                   . $right->{name} . ' (' . $right->{mean_pos} . ")\n");
    $log->write_to("\tTotal genetic units: $units ($bp_per_unit bp per unit)\n");
    
    # Maximal extents for the left and right sides
    my $minimal_left_gmap  = $left->{gmap};
    my $maximal_right_gmap = $right->{gmap};
    
    # Interpolate all the desired features into intervals
    my $leftmost_marker;
    foreach my $feature (sort { $a->{gmap} <=> $b->{gmap} } @{$to_map->{$chrom}},@{$markers->{$chrom}}) {
      my ($position,$fpmap_center,$fpmap_lower,$fpmap_upper,$lname,$lgmap,$lpmap,$rname,$rgmap,$rpmap);
      my $fname = $feature->{name};
      my $fgmap = $feature->{gmap};
      my $ftype = $feature->{type};
      my $ferror = $feature->{error};
      
      if ($ftype eq 'marker') {
        # Set the left edge to this marker for internal features
        $leftmost_marker = $feature;
        # Ignore those that are markers - no need to recalc a position!
        
      } elsif ($fgmap <= $minimal_left_gmap) {
        # First, deal with features that are before or after maximal markers
        # Will calculate map positions in relation to these markers
        
        # Calculate the pmap position
        my $diff  = $minimal_left_gmap - $fgmap;
        $fpmap_center = $left->{mean_pos} - ($diff * $bp_per_unit);
        
        # This assumes that both positions are left of the marker
        #      $fpmap_lower = $left->{mean_pos} - (($minimal_left_gmap - $feature->{lower}) * $bp_per_unit);
        #      $fpmap_upper = $left->{mean_pos} - (($minimal_left_gmap - $feature->{upper}) * $bp_per_unit);
        $fpmap_lower = $fpmap_center - ($feature->{error} * $bp_per_unit);
        $fpmap_upper = $fpmap_center + ($feature->{error} * $bp_per_unit);
        
        # The "left" marker is really to the right
        $position = 'LEFT';
        $rname    = $left->{name};
        $rpmap    = $left->{mean_pos};
        $rgmap    = $left->{gmap};
        
        # Deal with features residing to the right of the maximal extent
      } elsif ($fgmap >= $maximal_right_gmap) {
        my $diff      = $fgmap - $maximal_right_gmap;
        $fpmap_center = $right->{mean_pos} + ($diff * $bp_per_unit);
        
        # Assuming both values are to the right of the maximal mean which might not be true
        # This approach will come in handy for interpolating three factor crosses.
        # $fpmap_lower  = $fmap_center - (abs(($feature->{lower} - $maximal_right_gmap)) * $bp_per_unit);
        # $fpmap_upper  = $right->{mean_pos} - (abs(($feature->{upper} - $maximal_right_gmap)) * $bp_per_unit);
        
        $fpmap_lower = $fpmap_center - ($feature->{error} * $bp_per_unit);
        $fpmap_upper = $fpmap_center + ($feature->{error} * $bp_per_unit);
        
        # The "right" marker is really to the left in these cases
        $position = 'RIGHT';
        $lname    = $right->{name};
        $lpmap    = $right->{mean_pos};
        $lgmap    = $right->{gmap};
      } else {
        # Calculate the interpolated position of markers flanked by two markers
        # What is the position of the current leftmost marker?
        my $pos = $markers_by_pos{$leftmost_marker->{name}};
        my $rightmost_marker = $sorted_markers[$pos+1];
        
        # What is the gmap range between these two markers?
        # Are we straddling the center of the chromosome?
        $lname  = $leftmost_marker->{name};
        $lgmap  = $leftmost_marker->{gmap} || '0';
        $lpmap  = $leftmost_marker->{mean_pos};
        
        $rname  = $rightmost_marker->{name};
        $rgmap  = $rightmost_marker->{gmap} || '0';
        $rpmap  = $rightmost_marker->{mean_pos};
        
        my $grange = $rgmap - $lgmap;
        my $prange = $rpmap - $lpmap;
        
        if ($grange == 0) { # No genetic difference between markers - set it equal to one of the markers
          $fpmap_center = $lpmap;
        } else {
          # Calculate the scale for this interval
          my $scale = $prange / $grange;
          # And then the difference between the current feature and the leftmost marker
          my $diff = $fgmap - $lgmap;
          $fpmap_center    = ($diff * $scale) + $lpmap;
        }
        
        $fpmap_lower = $fpmap_center - ($feature->{error} * $bp_per_unit);
        $fpmap_upper = $fpmap_center + ($feature->{error} * $bp_per_unit);
        
        # Simple error checking. The calculated pmap should be between the two markers
        unless ($fpmap_center >= $lpmap && $fpmap_center <= $rpmap) {
          $log->log_and_die("Calculated gmap not in range: $lname $fname $rname - $lgmap ($lpmap) $fgmap ($fpmap_center) $rgmap ($rpmap)\n");
        }
        $position = 'INNER';
      }
      
      $fpmap_center = int $fpmap_center;
      $fpmap_lower  = int $fpmap_lower;
      $fpmap_upper  = int $fpmap_upper;
      
      $fgmap = sprintf("%8.4f",$fgmap);
      $log->write_to(sprintf("DEBUG: %-6s %-4s %-15s %-15s %-15s %-10s %-10s %-10s %-9s %-9s %-9s\n",
                             $position,$chrom,
                             $lname || '-',$fname,$rname || '-',
                             $lpmap || '-',$fpmap_center,$rpmap || '-',
                             $lgmap || '-',$fgmap,$rgmap || '-')) if $debug;
      
      # Generate the GFF file
      my ($status,$source);
      if ($ftype eq 'marker') {
        $fpmap_lower = $feature->{start};
        $fpmap_upper = $feature->{stop};
        $status = 'cloned';
        $source = 'absolute_pmap_position';
      } else {
        $status = 'uncloned';
        $source = 'interpolated_pmap_position';
      }
      
      my $public = $fname->Public_name;
      $ferror ||= '0.00';
      $ferror = sprintf("%2.2f",$ferror);
      
      # Adjust absurd coordinates
      $fpmap_lower = 1 if $fpmap_lower < 1;
      $fpmap_upper = 1 if $fpmap_upper < 1;

      $fpmap_lower = $chr_lengths->{$chrom} if $fpmap_lower > $chr_lengths->{$chrom};
      $fpmap_upper = $chr_lengths->{$chrom} if $fpmap_upper > $chr_lengths->{$chrom};

      # Flip coords on the minus strand
      ($fpmap_lower,$fpmap_upper) = ($fpmap_upper,$fpmap_lower) if ($fpmap_upper < $fpmap_upper);
      print $out_fh join("\t",$chr_prefix . $chrom, $source,'gene',$fpmap_lower,$fpmap_upper,'.','.','.');
      if (not $gff3) {
        print $out_fh "\tGMap $public ; Note \"$fgmap cM (+/- $ferror cM)\"; Note \"$status\"\n";
      } else {
        print $out_fh "\tID=gmap:$public;gmap=$public;status=$status;Note=$fgmap cM (+/- $ferror cM)\n";
      }
    }
  } else {
    $log->write_to("No markers for $chrom - nothing to do\n");
  }

  close($out_fh);
}

$db->close();

$log->mail;
exit(0);


########################################################
# Fetch all genes that lack pmap coordinates
# Will start here for simplicity
# This will only include genes that have two factor mapping data.
# Genes that only have three-factor data will not have a calculated position.
########################################################
sub fetch_genes_lacking_pmap_coords {
  my $genes = {};
  $log->write_to("Fetching genes lacking physical map coordinates...\n");
  my @genes = $db->fetch(-query=>qq{find Gene where Species="Caenorhabditis elegans" AND !Sequence_name});
  foreach (@genes) {
    my ($chrom,undef,$position,undef,$error) = eval{$_->Map(1)->row} or next;
    next unless $position;
    $position ||= '0.0000';
    push(@{$genes->{$chrom}},{ name   => $_,
			       chrom  => $chrom,
			       gmap   => $position,
			       error  => $error,
			       upper  => $position + $error,
			       lower  => $position - $error,
			       type   => 'uncloned',
			     });
  }
  return $genes;
}

########################################################
# Fetch marker loci with both a gmap and pmap position
########################################################
sub fetch_markers {
  $log->write_to("Fetching markers with known genetic position...\n");
  my $markers = {};
  my $pmapped_genes = {};
  my $total;

  my $split_dir = $wormbase->gff_splits;

  foreach my $chr_name (keys %$chr_lengths) {
    my $gene_gff_file = "$split_dir/${chr_prefix}${chr_name}_gene.gff";

    open my $gene_gff_fh, $gene_gff_file or $log->log_and_die("Could not open $gene_gff_file for reading\n");
    while(<$gene_gff_fh>) {
      /^\#/ and next;
      my @l = split(/\t/, $_);
      if ($l[1] eq 'gene' and $l[2] eq 'gene') {
        my $chrom    = $chr_name;
        my ($geneid) = $l[8] =~ /Gene\s+\"(\S+)\"/;
        my $start    = $l[3];
        my $stop     = $l[4];
        my $mean     = abs($start + $stop) / 2;

        $pmapped_genes->{$geneid} = {          
          chrom => $chrom,
          start => $start,
          stop => $stop,
          mean_pos => $mean,
        };
      }
    }
  }
  
  my @loci = $db->fetch(-query=>qq{find Gene where Map AND (Species="Caenorhabditis elegans")});
  
  foreach my $locus (@loci) {
    
    my ($chrom,undef,$position,undef,$error) = eval{$locus->Map(1)->row} or next;
    
    if (exists $pmapped_genes->{$locus}) {
      my $entry = $pmapped_genes->{$locus};
      $entry->{name} = $locus,
      $entry->{gmap} = $position || '0.0000';
      $entry->{type} = 'marker';
      $entry->{error} = $error;
      
      push @{$markers->{$entry->{chrom}}}, $entry;
      
      $total++;
    }
  }

  $log->write_to("\ttotal genetic markers fetched: $total\n");
  return $markers;
}

########################################################
# Fetch the chromosome lengths
########################################################
sub fetch_chromosome_lengths {

  my %chr_lengths;

  $log->write_to("Fetching chromosome lengths...\n");

  foreach my $chr_name ($wormbase->get_chromosome_names(-mito => 1)) {
    my $dna_file = $wormbase->chromosomes . "/${chr_prefix}${chr_name}.dna";
    if (not -e $dna_file) {
      $log->log_and_die("Could not find DNA file for $chr_name (expecting $dna_file)\n");
    }

    my $seqio = Bio::SeqIO->new(-file => $dna_file,
                                -format => 'fasta');
    while(my $seq = $seqio->next_seq) {
      $chr_lengths{$chr_name} = $seq->length;
    }
  }

  return \%chr_lengths;
}

1;
