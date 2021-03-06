#!/usr/bin/env perl
# Copyright (c) 2007, Genome Research Ltd (GRL).
# # All rights reserved.
# # Author: Michael Han <mh6@sanger.ac.uks>
# #
# # Redistribution and use in source and binary forms, with or without
# # modification, are permitted provided that the following conditions
# # are met:
# #     * Redistributions of source code must retain the above copyright
# #       notice, this list of conditions and the following disclaimer.
# #     * Redistributions in binary form must reproduce the above
# #       copyright notice, this list of conditions and the following
# #       disclaimer in the documentation and/or other materials
# #       provided with the distribution.
# #     * Neither the name of the <organization> nor the
# #       names of its contributors may be used to endorse or promote
# #       products derived from this software without specific prior
# #       written permission.
# #
# # THIS SOFTWARE IS PROVIDED BY GRL ``AS IS'' AND ANY EXPRESS OR
# # IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# # WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# # ARE DISCLAIMED.  IN NO EVENT SHALL GRL BE LIABLE FOR ANY DIRECT,
# # INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# # (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# # SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# # HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# # STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# # ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
# # OF THE POSSIBILITY OF SUCH DAMAGE.

use strict;
use lib $ENV{'CVS_DIR'};
use lib "$ENV{CVS_DIR}/Modules";
use map_Alleles;
use Wormbase;
use Getopt::Long;
use IO::File;              
use Ace;

sub print_usage{
print  <<USAGE;
map_Allele.pl options:
	-debug USER_NAME    sets email address and debug mode
	-store FILE_NAME    use a Storable wormbase configuration file
	-outdir DIR_NAME    print allele_mapping_VERSION.ace to DIR_NAME
        -outfile FILE_NAME  write results to given file name
	-allele ALLELE_NAME check only ALLELE_NAME instead of all
	-noload             dont update AceDB
	-noupdate           same as -noload
	-database	    DATABASE_DIRECTORY use a different db for sanity checking Variations.
	-weak_checks        relax sequence sanity checks
        -maponly            Only generate coords - do not generate gene associations and consequence info
        -noremap            If a var fails to map using flanks, do not attempt to remap it using Remap_Sequence
	-help               print this message
	-test               use the test database
	-idfile             use ids from an input file (one id per line)
	-species SPECIES_NAME use species as reference
USAGE

exit 1;	
}

my ( $debug, $species, $store, $outdir,$acefile,$allele ,$noload,$database,$weak_checks,$help,$test,$idfile,$nofilter,$map_only,$no_remap);

GetOptions(
	   'species=s'   => \$species,
	   'debug=s'     => \$debug,
	   'store=s'     => \$store,
	   'outdir=s'    => \$outdir,
	   'outfile=s'   => \$acefile,
	   'allele=s'    => \$allele,
	   'noload'      => \$noload,
	   'noupdate'    => \$noload,
	   'database=s'  => \$database,
	   'weak_checks' => \$weak_checks,
           'maponly'     => \$map_only,
	   'help'        => \$help,
	   'test'        => \$test,
	   'nofilter'    => \$nofilter,
	   'idfile=s'    => \$idfile,
           'noremap'     => \$no_remap,
	  ) or &print_usage();

&print_usage if $help;

my $maintainer = 'All';
my $wb;

if ($store) {
  $wb = Storable::retrieve($store)
      or croak("cannot restore wormbase from $store");
}
else { 
  $wb = Wormbase->new( -debug => $debug, 
                       -test => $test, 
                       -organism => $species, 
                       -autoace => $database ); 
}

my $log = Log_files->make_build_log($wb);
my $ace = Ace->connect( -path => $wb->autoace ) or 
    $log->log_and_die("Could not create AcePerl connection\n");

MapAlleles::setup($log,$wb,$ace);

my $release=$wb->get_wormbase_version;
if ($outdir and $acefile) {
  $log->log_and_die("Should not give -outdir and -outfile - choose one");
}
if (not $acefile) {
  $outdir = $wb->acefiles if not $outdir;
  $acefile = "$outdir/allele_mapping.WS${release}.$$.ace";
}
print "Creating $acefile\n" if ($debug);


if ($debug) {
  print STDERR "DEBUG \"$debug\"\n\n";
  $log->{DEBUG} = $debug;
}


my $alleles;
if ($allele){
  $log->write_to("Fetching single allele $allele...\n") if $debug;
  $alleles= MapAlleles::get_allele($allele);
}elsif ($idfile){
  $log->log_and_die("Idfile $idfile does not exist\n") if not -e $idfile;
  $log->write_to("Fetching alleles listed in $idfile...\n") if $debug;
  $alleles= MapAlleles::get_alleles_fromFile($idfile);
}else{
  $log->write_to("Fetching ALL alleles...\n") if $debug;
  $alleles= MapAlleles::get_all_alleles();
}

if (not $nofilter) {
  $log->write_to("Filtering alleles...\n") if $debug;
  $alleles = MapAlleles::filter_alleles( $alleles );
}

# map them
my $mapped_alleles = MapAlleles::map($alleles, ($no_remap) ? 0 : 1);
undef $alleles;# could theoretically undef the alleles here 

$log->write_to("Removing insanely mapped alleles...\n") if $debug;
MapAlleles::remove_insanely_mapped_alleles($mapped_alleles);

$log->write_to("Writing basic position information...\n") if $debug;
my $fh = new IO::File ">$acefile" || die($!);
# create mapping Ace file
while( my($key,$allele)=each %$mapped_alleles){
  if ($debug) {
    print $fh "\n// Mapped position of $key : $allele->{chromosome} $allele->{start} $allele->{stop}\n\n";
  }
  print $fh "Sequence : \"$allele->{clone}\"\nAllele $key $allele->{clone_start} $allele->{clone_stop}\n\n";
}

if ($map_only or $database) {
  close($fh) or $log->log_and_die("Could not close $acefile after writing\n");
  &finish();
}

#
# Now calculate feature associations and consequences
#

# get overlaps with genes
# gene_name->[allele_names,...]
$log->write_to("Loading/indexing gene/CDS data...\n") if $debug;
MapAlleles::load_genes_and_cds;

$log->write_to("Getting gene mappings...\n") if $debug;
my $genes=MapAlleles::get_genes($mapped_alleles);

# create the gene Ace file

$log->write_to("Printing gene mappings...\n") if $debug;
my $inversegenes=MapAlleles::print_genes($genes,$fh);

# compare old<->new genes
$log->write_to("Comparing old mappings to new...\n") if $debug;
MapAlleles::compare($mapped_alleles,$inversegenes);

# get overlaps with CDSs (intron,exon,coding_exon,cds)
# cds_name->allele_name->type
$log->write_to("Getting CDS mappings...\n") if $debug;
my $cds=MapAlleles::get_cds($mapped_alleles);
$log->write_to("Printing CDS mappings...\n") if $debug;
MapAlleles::print_cds($cds,$fh);

# get overlaps with Transcripts                        
# transcript_name->allele_name->type
$log->write_to("Getting UTR mappings...\n") if $debug;
my $utrs=MapAlleles::load_utr;
my $hit_utrs=MapAlleles::search_utr($mapped_alleles,$utrs);
$log->write_to("Printing UTR mappings...\n") if $debug;
MapAlleles::print_utr($hit_utrs,$fh);
$utrs = $hit_utrs = undef; # cleanup memory

# get overlaps with Pseudogenes                        
# pseudogene_name->allele_name->1
$log->write_to("Getting Pseudogene mappings...\n") if $debug;
my $pgenes=MapAlleles::load_pseudogenes;
my $hit_pgenes=MapAlleles::search_pseudogenes($mapped_alleles,$pgenes);
$log->write_to("Printing Pseudogene mappings...\n") if $debug;
MapAlleles::print_pseudogenes($hit_pgenes,$fh);
$pgenes = $hit_pgenes = undef; # cleanup memory

# get overlaps with non-coding transcripts                        
# transcript_name->allele_name->1
$log->write_to("Getting ncRNA mappings...\n") if $debug;
my $nc_rnas=MapAlleles::load_ncrnas;
my $hit_ncrnas=MapAlleles::search_ncrnas($mapped_alleles,$nc_rnas);
$log->write_to("Printing ncRNA mappings...\n") if $debug;
MapAlleles::print_ncrnas($hit_ncrnas,$fh);
$nc_rnas = $hit_ncrnas = undef; # cleanup memory
 
# load to ace and close filehandle
close($fh) or $log->log_and_die("Could not successfully close $acefile after writing\n");
if (not $noload) {
  $wb->load_to_database($wb->autoace,
                        $acefile,
                        'map_Alleles',
                        $log);
}

&finish();

# send the report
sub finish {
  $ace->close();

  if (MapAlleles::get_errors()){
    $log->mail( $maintainer, "BUILD REPORT: map_Alleles.pl ${\MapAlleles::get_errors()} ERRORS" );
  }
  else {
    $log->mail( $maintainer, 'BUILD REPORT: map_Alleles.pl');
  }
  exit 0;
}
