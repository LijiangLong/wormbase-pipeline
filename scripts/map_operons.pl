#!/usr/local/bin/perl5.8.0 -w
#
# map_operons.pl

# Last edited by: $Author: pad $
# Last edited on: $Date: 2011-10-17 11:47:40 $

use strict;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use IO::Handle;
use Data::Dumper;
use Getopt::Long;
use File::Copy;
use Ace;
use Log_files;

my ($quicktest, $debug, $store, $test, $noload);

GetOptions(
	   'debug=s'   => \$debug,
	   'store=s'   => \$store,
	   'test'      => \$test,
	   'noload'    => \$noload,
	   'quicktest' => \$quicktest,
);

############################
# recreate configuration   #
############################
my $wb;
if ($store) { $wb = Storable::retrieve($store) or croak("cant restore wormbase from $store\n") }
else { $wb = Wormbase->new( -debug => $debug, -test => $test, ) }

my $log = Log_files->make_build_log($wb);
my $acefile = $wb->acefiles."/operon_coords.ace";

my @chromosomes = $quicktest ? qw(III) : qw(I II III IV V X);
my %gene_span;
foreach (@chromosomes){
  open (GS,"<".$wb->gff_splits."/CHROMOSOME_${_}_gene.gff") or $log->log_and_die("Cant open ".$wb->gff_splits."/CHROMOSOME_${_}_gene.gff :$!\n");
  while (<GS>) {
    # CHROMOSOME_III  gene    gene    16180   17279   .       +       .       Gene "WBGene00019182"
    next if /^\#/;
    my @data = split;
    next unless ($data[2] eq 'gene');
    $data[9] =~ s/\"//g;#"
    my $gene = $data[9];
    $gene_span{$gene}->{'chrom'} = $data[0];
    $gene_span{$gene}->{'start'} = $data[3];
    $gene_span{$gene}->{'end'}   = $data[4];
    $gene_span{$gene}->{'strand'}= $data[6];
  }
}

open (OUT,">$acefile") or $log->log_and_die("cant open $acefile : $!\n");
my $db = Ace->connect(-path => $wb->autoace) or $log->log_and_die("cant connect to ".$wb->autoace." :".Ace->error."\n");
my @operons = $db->fetch('Operon' => '*');
foreach my $operon(@operons) {
  next if ($operon->Method eq "history");
  my @genes = map($_->name, $operon->Contains_gene);
  my ($op_start, $op_end, $op_strand, $op_chrom);
  foreach my $gene (@genes) {
    if (!exists $gene_span{$gene}) {
      if ($operon->Method eq "Deprecated_operon") {
	$log->write_to ("Warning:Operon $operon (method \"".$operon->Method."\") contains $gene which does not have a span defined meaning the Old operon doesn't appear as it once did\n\n"); }
      else {
	$log->write_to ("ERROR:Operon $operon (method \"".$operon->Method."\") contains $gene which does not have a span defined!\nPlease refer this back to the Operon curation team\n\n"); }
    }
    next if (!exists $gene_span{$gene}); # some Deprecated_operons contain Transposon_CDSs which won't have a gene-span
    $op_start =  $gene_span{$gene}->{'start'} if (!(defined $op_start) or $op_start > $gene_span{$gene}->{'start'});
    $op_end   =  $gene_span{$gene}->{'end'}   if (!(defined $op_end)   or $op_end   < $gene_span{$gene}->{'end'});
    $op_strand = $gene_span{$gene}->{'strand'}if(!(defined $op_strand) or $op_strand eq $gene_span{$gene}->{'strand'});
    $op_chrom  = $gene_span{$gene}->{'chrom'} if $gene_span{$gene}->{'chrom'};
  }
  
  if (defined $op_chrom && defined $op_start && defined $op_end) { # some Deprecated_operons only contain Transposon_CDSs, not genes
    print OUT "\nSequence : $op_chrom\nOperon $operon ";
    ($op_strand eq '+') ? print OUT "$op_start $op_end" : print OUT "$op_end $op_start";
    print OUT "\n";
  }
}
$db->close;
$wb->load_to_database($wb->autoace, "$acefile", 'operon_span', $log) unless $noload;

$log->mail;
exit(0);
