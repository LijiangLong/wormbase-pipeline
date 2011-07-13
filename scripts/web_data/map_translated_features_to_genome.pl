#!/usr/bin/env perl

# This script maps translated features to genomic coordinates
use strict;
use Getopt::Long;

use Wormbase;
use Ace;
use Log_files;

use Bio::EnsEMBL::Registry;

# GFF Constants
use constant SOURCE       => 'translated_feature';
use constant METHOD       => 'motif_segment';
use constant SCORE        => '.';
use constant PHASE        => '.';

# Top-level feature for aggregation
use constant TOP_SOURCE   => 'translated_feature';
use constant TOP_METHOD   => 'Motif';


my ($acedb,
    $species,
    $store,
    $dbh,
    $help,
    $debug,
    $format,
    $test,
    $filter,
    $wormbase, 
    $ens_regconf,
    $gff3,
    $out_file,
    $outfh,
    @testgene,
    $count,
    );

GetOptions ('database=s'      => \$acedb,
            'store=s'         => \$store,
            'species=s'       => \$species,
            'ensreg=s'        => \$ens_regconf,
            'regconf=s'       => \$ens_regconf,
            'debug=s'         => \$debug,
            'test'            => \$test,
	    'filter'          => \$filter,
            'format=s'        => \$format,
            'gff3'            => \$gff3,
            'outfile=s'       => \$out_file,
            'genetest=s@'     => \@testgene,
           );


$format = 'segmented' if not defined $format;
$filter = 1;

if ($store) { 
  $wormbase = Storable::retrieve($store) or croak("cant restore wormbase from $store\n"); 
}
else { 
  $wormbase = Wormbase->new( -debug => $debug, 
                             -test => $test, 
                             -organism => $species); 
}

$acedb ||= $wormbase->autoace;
$dbh = Ace->connect(-path => $acedb );
$species = $wormbase->species;

my $log = Log_files->make_build_log($wormbase);

my $reg = "Bio::EnsEMBL::Registry";
$reg->load_all($ens_regconf);
my $ens_tadap = $reg->get_adaptor($species, 'Core', 'Transcript'); 

my ($iterator, @test_genes);
if (@testgene) {
  foreach my $gid (@testgene) {
    my ($g) = $dbh->fetch(-query => 'Find Gene WHERE Sequence_name = "' .$gid .'"');
    push @test_genes, $g;
  }
} else {
  $iterator = $dbh->fetch_many(-query => 'Find Gene WHERE Live AND Sequence_name AND Species = "'. $wormbase->full_name . '"');
}

if ($out_file) {
  open $outfh, ">$out_file" or $log->log_and_die("Could not open $out_file for writing\n");
} else {
  $outfh = \*STDOUT;
}

while (my $gene = &get_next_gene) {
  my (%seen, $id);
  my @cds = $gene->Corresponding_CDS;

  foreach my $cds (@cds) {
    next if /.*\:wp.*/;
    my $protein = $cds->Corresponding_protein;
    next unless $protein;
    # my $protein = $DB->fetch(Protein=>$prot);
    next if $cds->Sequence eq 'MTCE';

    # Safe the public_name of the gene in case we are filtering
    my $public_name = $gene->Public_name;
    
    $count++;

    if ($debug) {
      $log->write_to("++++++++++++++++++\n");
      $log->write_to("Analyzing $protein $cds\n");
      $log->write_to("++++++++++++++++++\n");
    }
    if ($count % 100 == 0) {
      $log->write_to("Analyzing $protein $cds : ($count)...\n");
    }
    
    my %motifs_by_type = fetch_motifs($protein);
    my $transcript = $ens_tadap->fetch_by_stable_id($cds);
    my @exons = @{$transcript->get_all_Exons};
    $log->log_and_die("No translation for $cds\n") if not $transcript->translation;

    # Now, for each motif, fetch the genomic coordinates of the span
    #print DEBUG "Fetching motif positions...\n";
    #print DEBUG join("\t,",qw/ID motif_start motif_stop msg/),"\n";
    foreach my $type (keys %motifs_by_type) {
      foreach my $motif (@{$motifs_by_type{$type}}) {
	my ($motif_start,$motif_stop,$desc) = @{$motif};

        my @gen_coords = $transcript->pep2genomic($motif_start, $motif_stop);        
	@gen_coords = grep { $_->isa('Bio::EnsEMBL::Mapper::Coordinate') } @gen_coords;
        my ($start, $end, $first_exon, $last_exon);
        foreach my $c (@gen_coords) {
          $start = $c->start if not defined $start or $c->start < $start;
          $end = $c->end if not defined $end or $c->end > $end;
          for(my $i=0; $i < @exons; $i++) {
            if ($c->start >= $exons[$i]->start and $c->start <= $exons[$i]->end) {
              if (not defined $first_exon) {
                $first_exon = $i+1;
              }
              $last_exon = $i+1;
            }
          }
        }

	if ($filter) { 
          my $hashkey = join(":", map { $_->start, $_->end, $_->strand } sort { $a->start <=> $b->start } @gen_coords);

	  if (defined $seen{$type}->{$hashkey}) {
	    next;
	  }
	  $seen{$type}->{$hashkey} = $cds;
	}
	$id++;
	
        my $motif = {
          chrom       => $transcript->slice->seq_region_name,
          strand      => $gen_coords[0]->strand,
          public_name => $public_name,
          protein     => $protein,
          cds         => $cds,
          type        => $type,
          start       => $start,
          stop         => $end,
          aa_start    => $motif_start,
          aa_stop     => $motif_stop,
          score       => '',
          id          => $id,
          exons       => ($first_exon eq $last_exon) ? $first_exon : "${first_exon}-${last_exon}",
          desc        => $desc,
          segs        => \@gen_coords,
        };

	&generate_gff($motif);
      }
    }
  }
}

$log->mail;
exit(0);

sub generate_gff {
  my ($motif) = @_;

  my ($refseq,$protein,$cds,$type,$mstart,$mstop,$start, $stop, $strand,$score,$id,$desc,$public_name, $exons) =
    map { $motif->{$_} } qw/chrom protein cds type aa_start aa_stop start stop strand score id desc public_name exons/;
  my @segs = @{$motif->{segs}};

  $strand = ($strand == -1 or $strand eq '-') ? "-" : "+";
  $score  ||= SCORE;

  my $aarange = $mstart . '-' . $mstop;

  # Change the name of the group if filtering duplicates
  # Doesn't make sense to identify these by their protein name
  my $motif_name = ($filter) ? "$public_name-${type}.$id" : "$protein-$type.$id";
  $motif_name =~ s/[;:]/_/g;
  my $motif_id = "motif:$motif_name";

  my ($group, $full_group);
  if ($gff3) {
    $group =  "ID=$motif_id";
    $full_group = "$group;CDS=$cds;Type=$type;Range=$aarange;Exons=$exons;Protein=$protein";
    if ($desc) {
      $desc =~ s/[\;]/\%3B/g;
      $desc =~ s/[\=]/\%2C/g;
      $desc =~ s/[\,]/\%3D/g;
      $full_group .= qq{;Description=$desc};
    }
  } else {
    $group = qq(Motif "$motif_name");
    $full_group = qq{$group ; Note "CDS=$cds" ; Note "Type=$type" ; Note "Range=$aarange" ; Note "Exons=$exons" ; Note "Protein=$protein"};
    if ($desc) {
      $full_group .= qq{ ; Note "Description=$desc"};
    }
  }

  if ($format eq 'segmented') {
    # Create a top-level entry to ensure aggregation
    print_gff($refseq,TOP_SOURCE,TOP_METHOD,$start,$stop,$score,$strand,PHASE,$full_group);
    my $seg_count = 1;
    foreach my $seg (sort { $a->start <=> $b->start } @segs) {
      my $child_group;
      if ($gff3) {
        my $seg_id = $motif_id . "." . $seg_count++;
        $child_group = "ID=$seg_id;Parent=$motif_id";
      } else {
        $child_group = qq(Motif "$motif_name");
      }
      print_gff($refseq,SOURCE,METHOD,$seg->start,$seg->end,$score,$strand,PHASE,$child_group);
    }
  } else {
    print_gff($refseq,SOURCE,METHOD,$start,$stop,$score,$strand,PHASE,$full_group);
  }
}


################################
sub get_next_gene {
  if ($iterator) {
    return $iterator->next;
  } elsif (@test_genes) {
    return shift @test_genes;
  } else {
    return undef;
  }
}

#################################
sub print_gff {
  my ($ref,$source,$method,$start,$stop,@rest) = @_;
  ($start,$stop) = ($stop,$start) if ($start > $stop);
  print $outfh join("\t",$ref,$source,$method,$start,$stop,@rest),"\n";
}


#################################
sub fetch_motifs {
  my $protein = shift;
  my %motifs;

  ## Structural motifs (this returns a list of feature types)
  # I should also grab the score when appropriate

  # Structural features
  my @features = $protein->Feature;
  # Visit each of the features, pushing into an array based on its name
  foreach my $type (@features) {
    my %positions = map {$_ => $_->right(1)} $type->col;
    foreach my $start (keys %positions) {
      push (@{$motifs{$type}},[$start,$positions{$start}]);
    }
  }

  # Now deal with the Motif_homol features
  my @motif_homol = $protein->Motif_homol;
  foreach my $feature (@motif_homol) {
    my $title = eval {$feature->Title};
    my $type  = $feature->right or next;
    next if $type =~ /INTERPRO/;
    my @coord = $feature->right->col;
    my $name  = $title ? "$title ($feature)" : $feature;
    my ($start,$stop);
    for my $segment (@coord) {
      ($start,$stop) = $segment->right->row;
      $start = int $start;
      $stop  = int $stop;
      push (@{$motifs{$type}},[$start,$stop,$name]);
    }
  }
  return %motifs;
}