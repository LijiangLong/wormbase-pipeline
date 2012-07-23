#!/nfs/team71/worm/mh6/bin/perl
#####################################################
# put interpolate snps jobs on queue and waits for them to exit
#
####################################################
use strict;
use warnings;
use lib $ENV{'CVS_DIR'};
use lib '/software/worm/lib/site_perl/';
use Wormbase;
use Getopt::Long;
use LSF RaiseError => 0, PrintError => 1, PrintOutput => 0;
use LSF::JobManager;

##############################
# Script variables (run)     #
##############################

my ( $help, $debug, $test, $store );
my $verbose;    # for toggling extra output
my $maintainers = "All";    # who receives emails from script
my $noload;                 # generate results but do not load to autoace
my $nopseudo;               # prevent running of make_pseudo_map_positions.pl

##############################
# command-line options       #
##############################

GetOptions(
    "help"    => \$help,
    "debug=s" => \$debug,
    "test"    => \$test,
    "noload"  => \$noload,
    "store:s" => \$store,
    "no_pseudo"=>\$nopseudo
);

# recreate configuration ##########
my $wb;
my $flags = "";
if ($store) {
    $wb = Storable::retrieve($store) or croak("cant restore wormbase from $store\n");
    $flags = "-store $store";
}
else {
    $wb = Wormbase->new( -debug => $debug, -test => $debug );
    $flags .= "-debug $debug " if $debug;
    $flags .= "-test "         if $test;
}

# Variables Part II (depending on $wb)
$debug = $wb->debug if $wb->debug;    # Debug mode, output only goes to one user

my $log = Log_files->make_build_log($wb);

####################################

my $m      = LSF::JobManager->new();
my @bsub_opts = (-M => 4000000,
                 -R => 'select[mem>=4000] rusage[mem=4000]');
my $mother = $m->submit(@bsub_opts, "perl $ENV{CVS_DIR}/interpolate_gff.pl -prep $flags");
my $myid   = $mother->id;

push @bsub_opts, (-w => "ended($myid)");
foreach my $i ($wb->get_chromosome_names) {
    $m->submit( @bsub_opts, "perl $ENV{CVS_DIR}/interpolate_gff.pl -chrom $i $flags -allele" );
    $m->submit( @bsub_opts, "perl $ENV{CVS_DIR}/interpolate_gff.pl -chrom $i $flags -gene" );
    $m->submit( @bsub_opts, "perl $ENV{CVS_DIR}/interpolate_gff.pl -chrom $i $flags -clone" );
}

$m->wait_all_children( history => 1 );
print "All children have completed!\n";

############################
for my $job ( $m->jobs ) {    # much quicker if history is pre-cached
    $log->write_to("$job exited non zero\n") if $job->history->exit_status != 0;
}
$m->clear;                    # clear out the job manager to reuse.

#################
if ( !$noload ) {
    my $acedir = $wb->autoace . "/acefiles";
    foreach my $file ( glob("$acedir/interpolated_allele_*.ace") ) {
      $wb->load_to_database( $wb->autoace, $file, "interpolate_alleles", $log );
    }
    foreach my $file ( glob("$acedir/interpolated_gene_*.ace") ) {
      $wb->load_to_database( $wb->autoace, $file, "interpolate_genes", $log );
    }
    foreach my $file ( glob("$acedir/interpolated_clone_*.ace") ) {
      $wb->load_to_database( $wb->autoace, $file, "interpolate_clones", $log );
    }
    if (-e "$acedir/genetic_map_fixes.ace"){
      my $backup = 0; # we don't need to backup the database
      my $accept_large_differences = 1; # but we do want to accept variations in the number pf map fixes loaded in compared to the previous Build
      $wb->load_to_database($wb->autoace,"$acedir/genetic_map_fixes.ace","genetic_map_corrections",$log, $backup, $accept_large_differences);
    }
}

$wb->run_script("make_pseudo_map_positions.pl -load", $log) unless $nopseudo;
$log->mail();
