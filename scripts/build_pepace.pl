#!/usr/local/bin/perl5.8.0 -w
#
# build_pepace.pl
#
# by Anthony Rogers
#
# This creates an acefile that can be loaded in to an empty
# database to completely recreate what was pepace. This is based
# solely in the wormpep.history file.
#
#
# Last updated by: $Author: mh6 $
# Last updated on: $Date: 2008-01-17 13:54:34 $

use strict;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Carp;
use Log_files;
use Storable;

######################################
# variables and command-line options #
######################################

my ( $help, $debug, $test, $verbose, $store, $wormbase, $species );

GetOptions(
    "help"    => \$help,
    "debug=s" => \$debug,
    "test"    => \$test,
    "verbose" => \$verbose,
    "store:s" => \$store,
    "species" => \$species
);

if ($store) {
    $wormbase = retrieve($store)
      or croak("Can't restore wormbase from $store\n");
}
else {
    $wormbase = Wormbase->new(
        -debug => $debug,
        -test  => $test,
        -organism => $species
    );
}

# Display help if required
&usage("Help") if ($help);

# establish log file.
my $log = Log_files->make_build_log($wormbase);

##############
# variables  #
##############

my $ace_dir    = $wormbase->autoace;                  # AUTOACE DATABASE DIR
my $wormpepdir = $wormbase->wormpep;                  # CURRENT WORMPEP
my $ver        = $wormbase->get_wormbase_version();
my $PEP_PREFIX = $wormbase->pep_prefix;
my $PEPDIR 	   = $wormbase->pepdir_prefix;
# read history file
our ( $gene, $CE, $in, $out );
my %CE_history;
# hash of hashes of hashes!  eg CE00100 => 8  => gene1.1 => Created
#                                                gene3.4 => Removed
#
#                                          16 => gene1.1 => converted to isoform
#                                                gene3.4 => Reappeared

# hash of arrays eg  CE00100 => (gene1.1  gene3.4 gene2.1)  - contains all genes in history
my %CE_gene;
my %gene_CE;
my %CE_live;
# hash of arrays eg  CE00100 => (gene1.1   gene2.1)  - contains only genes of Live peptides
my %CE_corr_CDS;
my %CE_sequence;

my $stem;
my $isoform;
my $existingCE;
my $existingGene;
my %multicodedPeps;

my $handled = 0;
my $pepcount;
my $count;

my %mw = (
    'A', '71.0788',  'R', '156.1876', 'D', '115.0886', 'N', '114.1039',
    'C', '103.1448', 'E', '129.1155', 'Q', '128.1308', 'G', '57.0520',
    'H', '137.1412', 'I', '113.1595', 'L', '113.1595', 'K', '128.1742',
    'M', '131.1986', 'F', '147.1766', 'P', '97.1167',  'S', '87.0782',
    'T', '101.1051', 'W', '186.2133', 'Y', '163.1760', 'V', '99.1326',
    'U', '150.050'
);

#Amino acids
my $A = "";
my $R = "";
my $D = "";
my $N = "";
my $C = "";
my $E = "";
my $Q = "";
my $G = "";
my $H = "";
my $I = "";
my $L = "";
my $K = "";
my $M = "";
my $F = "";
my $P = "";
my $S = "";
my $T = "";
my $W = "";
my $Y = "";
my $V = "";
my $U = "";

open( HISTORY, "$wormpepdir/${PEPDIR}pep.history$ver" ) or $log->log_and_die("cant open wormpep.history$ver $!\n");
while (<HISTORY>) {
    my @data = split( /\s+/, $_ );
    ( $gene, $CE, $in, $out ) = @data;

    if ( defined( $CE_gene{$CE} ) ) {
        $handled = 0;
        my $i;
        for $i ( 0 .. $#{ $CE_gene{$CE} } ) {
            $existingGene = $CE_gene{$CE}[$i];
            if ( "$gene" eq "$existingGene" ) {
                $handled = &reappearedPeptide;
                last;
            }

            #is this an isoform of a pre-exisiting gene?
            elsif ( $gene =~ m/(\w+\.\d+)(\w*)/ ) {
                $stem    = $1;    #eg FK177.8
                $isoform = $2;    #eg a

                #if nothing matches $2 = '' so is defined
                if ( $existingGene =~ m/^($stem)(\w*)/ ) {

                    #$gene is isoform
                    my $existingIform = $2;
                    if ( $existingIform =~ m/\w/ ) {

# Existing peptide is coded for by isoform of same gene
# This may occur due to curation changes as well actual genes doing this
# Do nothing! Let this fall thru to multiply coded peptides
                    }
                    else {
                        if ( $CE_live{$CE} == 1 ) {

                            #Became isoform
                            # ZK177.8  CE02097 8
                            # ZK177.8a CE02097 11
                            $handled = &becameIsoform;
                            last;
                        }
                        else {
                            #Reappeared as isoform to
                            # ZK177.8  CE02097 8 11
                            # ZK177.8a CE02097 12
                            $handled = &reappearedAsIsoform;
                            last;
                        }
                    }
                }
            }
            else {
                if ( &oldStyleName($gene) ) {
                    if ( $CE_live{$CE} == 1 ) {
                        #peptide coded by multiple genes
                        #drop thru
                    }
                    else {
                        #peptide was previously coded by a different gene
                        $handled = &changePepGene;
                        last;
                    }
                }
            }
        }
        if ( $handled == 0 ) {

# the peptide has a previous entry but none of the above circumstances can account for it
# must be another gene coding for the same peptide.
            if ( $CE_live{$CE} == 1 ) {
                &addNewPeptide;
            }
            else {
                #peptide was previously coded by a different gene
                &changePepGene;
            }
        }
    }

    #processing entry where CE not known
    else {
        $pepcount++;
        if ( defined( $gene_CE{$gene} ) ) {

            # if peptide coded by >1 genes
            # do something clever
            # else
            $existingCE = $gene_CE{$gene};
            &replacePeptide;
            &addNewPeptide;
        }
        else {
            if ( $gene =~ m/((\w+\.\d+)\w*)/ ) {
                $stem    = $2;    #eg FK177.8
                $isoform = $1;    #eg FK177.8a
                if ( defined( $gene_CE{$stem} ) ) {

                    #$gene is isoform of already entered gene
                    &addNewPeptide;
                    $existingCE = $gene_CE{$stem};

                    #add to history of $CE that it is isoform og $existingCE
                }
                else {
                    &addNewPeptide;
                }
            }
            else {
# one of the pain in the arse old named genes eg Y53F4B.AA orY5823F4B.A - both exist!
                if ( $gene =~ m/\w+\.\w+/ ) {
                    &addNewPeptide;    #just add it
                }
            }
        }
    }
    $count++;
}
close HISTORY;

# get the sequence from the .fasta file
open (FASTA, "<$wormpepdir/${PEPDIR}pep.fasta$ver") or $log->log_and_die("cant open $wormpepdir/${PEPDIR}pep.fasta $!\n");
print "reading $wormpepdir/${PEPDIR}pep.fasta$ver\n\n";

my $fasta_pep;
while (<FASTA>) {

    #chomp;
    if ( $_ =~ /$PEP_PREFIX\d{5}/ ) {
        $fasta_pep = $&;
        print "$fasta_pep\n";
    }
    else {
        if ( defined($fasta_pep) ) {
            $CE_sequence{$fasta_pep} .= "$_";
        }
    }
}
close FASTA;

# write ace file
my $ii;
my $acefile = "$ace_dir/acefiles/pepace.ace";

open( ACE, ">$acefile" ) || die "cant write $acefile\n";

if($wormbase->species eq 'elegans') {
	$CE_live{'CE25872'} =1;# hard coded as this history is confused. Remove if CE25873 no longer valid
	push( @{ $CE_corr_CDS{'CE25872'} }, "F36D3.1" );
}

#ace file for new Protein model (with History)
foreach my $key ( sort keys %CE_history ) {
	unless ($CE_sequence{$key}) {
		$log->error("$key has no sequence in fasta file \n");
		next;
	}
    print ACE "Protein : \"$PEP_PREFIX:$key\"\n";

    ## Write histories
    foreach my $release ( sort byRelease keys %{ $CE_history{$key} } ) {
        foreach my $genehis ( sort keys %{ $CE_history{$key}{$release} } ) {
            print ACE "History \"$release\" \"$CE_history{$key}{$release}{$genehis}\" \"$genehis\"\n";
        }
    }

    print ACE "Database \"WORMPEP\" WORMPEP_ID \"$PEP_PREFIX:$key\"\n";
    print ACE "Molecular_weight ", &get_mol_weight( $CE_sequence{$key} )," Inferred_automatically \"build_pepace.pl\"\n";
    print ACE "Species \"Caenorhabditis elegans\"\n";
    print ACE "Wormpep\n";

    if ( $CE_live{$key} == 1 ) {
        print ACE "Live\n";
        for $ii ( 0 .. $#{ $CE_corr_CDS{$key} } ) {
            print ACE "Corresponding_CDS \"$CE_corr_CDS{$key}[$ii]\"\n";
        }
    }
    print ACE "\n";
    print ACE "Peptide : \"$PEP_PREFIX:$key\"\n";
    print ACE "$CE_sequence{$key}\n";
}
close ACE;
$log->write_to("written $acefile - to be loaded in to autoace\n");

#while we have crap predictions this can be skipped.
if( $wormbase->species eq "elegans") {
	my $live_peps  = `grep -c Live $acefile`;
	my $table_peps = `/software/worm/bin/wublast/nrdb $wormpepdir/${PEPDIR}pep$ver.pep |grep -c '>'`;
	chomp $live_peps;
	chomp $table_peps;

	$log->write_to("This file has $live_peps live peptides\n");
	$log->write_to("${PEPDIR}pep$ver.pep suggests there should be $table_peps\n");

	if ( ($live_peps) == $table_peps ) {
   		$log->write_to("\nso thats OK!\ntaking in to account 1 known problem - CE25872 -hard coded as live in the script\n");
	}
	else {
    	$log->write_to("\n\n! ! ! ! THIS NEEDS ATTENTION ! ! ! !\n\n\n");
    	$log->write_to("\n1 known problem - CE25872 is hard coded as LIVE in $0\n Check this is still valid sequence F36D3.1");
	}
}
#load files in to autoace.
$wormbase->load_to_database( $wormbase->autoace, "$ace_dir/acefiles/pepace.ace", 'pepace', $log );

# update common data
$wormbase->run_script("update_Common_data.pl --build --cds2wormpep", $log);

$log->mail();
exit(0);

##############################################################
#
# Subroutines
#
##############################################################

##########################################

sub usage {
    my $error = shift;

    if ( $error eq "Help" ) {
        # Normal help menu
        system( 'perldoc', $0 );
        exit(0);
    }
}

##########################################

sub get_mol_weight {
    my $pep = shift;
    $A = $pep =~ tr/A/A/;    # count the number of each amino acids in peptide.
    $R = $pep =~ tr/R/R/;
    $D = $pep =~ tr/D/D/;
    $N = $pep =~ tr/N/N/;
    $C = $pep =~ tr/C/C/;
    $E = $pep =~ tr/E/E/;
    $Q = $pep =~ tr/Q/Q/;
    $G = $pep =~ tr/G/G/;
    $H = $pep =~ tr/H/H/;
    $I = $pep =~ tr/I/I/;
    $L = $pep =~ tr/L/L/;
    $K = $pep =~ tr/K/K/;
    $M = $pep =~ tr/M/M/;
    $F = $pep =~ tr/F/F/;
    $P = $pep =~ tr/P/P/;
    $S = $pep =~ tr/S/S/;
    $T = $pep =~ tr/T/T/;
    $W = $pep =~ tr/W/W/;
    $Y = $pep =~ tr/Y/Y/;
    $V = $pep =~ tr/V/V/;
    $U = $pep =~ tr/U/U/;

    #Calculate the Total Mw of the peptide by summing the subunits.
    my $sum =
        ( ( $A * $mw{A} ) +
          ( $R * $mw{R} ) +
          ( $D * $mw{D} ) +
          ( $N * $mw{N} ) +
          ( $C * $mw{C} ) +
          ( $E * $mw{E} ) +
          ( $Q * $mw{Q} ) +
          ( $G * $mw{G} ) +
          ( $H * $mw{H} ) +
          ( $I * $mw{I} ) +
          ( $L * $mw{L} ) +
          ( $K * $mw{K} ) +
          ( $M * $mw{M} ) +
          ( $F * $mw{F} ) +
          ( $P * $mw{P} ) +
          ( $S * $mw{S} ) +
          ( $T * $mw{T} ) +
          ( $W * $mw{W} ) +
          ( $Y * $mw{Y} ) +
          ( $V * $mw{V} ) +
          ( $U * $mw{U} ) ) / 1000;
    my $result = sprintf "%.1f", $sum;
    return $result;
}

sub byRelease {
    # used by sort
    $a <=> $b;
}

sub addNewPeptide {

    # 1st occurance of peptide
    $CE_history{$CE}{$in}{$gene} = "created";    #.= "Created $in\t" ;
                                                 #$CE_gene{$CE} .= "$gene ";
    push( @{ $CE_corr_CDS{$CE} }, "$gene" );
    push( @{ $CE_gene{$CE} },     "$gene" );
    $CE_live{$CE}   = 1;     #assume live when put in unless explicitly killed
    $gene_CE{$gene} = $CE;
    if ( defined($out) ) {
        if ( &multiCoded == 0 ) {
            $CE_live{$CE} = 0;
        }
        $CE_history{$CE}{$out}{$gene} = "removed";
        &removeGeneCorrCDS;
    }
    return 1;
}

sub replacePeptide {
    if ( &multiCoded($existingCE) == 0 ) {

       #this is to make sure that Im not killing a peptide coded by another gene
        if ( $CE_live{$existingCE} == 1 ) {
            if ( "$CE_corr_CDS{$existingCE}[0]" eq "$gene" ) {
                $CE_live{$existingCE} = 0;
            }
        }
    }
    $CE_history{$existingCE}{$in}{$gene} = "replaced by $CE";
    $CE_history{$CE}{$in}{$gene}         = "Created to replace $existingCE";
}

sub reappearedPeptide {
    $CE_live{$CE} = 1;
    $CE_history{$CE}{$in}{$gene} = "reappeared";    #.= "$in Reappeared\t";
    if ($out) {
        if ( &multiCoded == 0 ) {
            $CE_live{$CE} = 0;
        }
        $CE_history{$CE}{$out}{$gene} = "removed";    # .= "$out Removed\t";
    }
    else {
        push( @{ $CE_corr_CDS{$CE} }, "$gene" );
    }
    return 1;
    #gene is same as was previously if this routine called
}

sub reappearedAsIsoform {
    $CE_live{$CE} = 1;

#check if becoming isoform is same release as removal - if so modify history to show conversion rather than reappearance
    if ( defined( $CE_history{$CE}{$in}{$stem} ) ) {
        if (   ( "$CE_history{$CE}{$in}{$stem}" eq "removed" ) || ( $CE_history{$CE}{$in}{$stem} =~ m/replaced/ ) ) {
            $CE_history{$CE}{$in}{$stem} = "converted to isoform $gene";
        }
        else {
            $CE_history{$CE}{$in}{$stem} = "reappeared as isoform $gene";
        }
    }
    else {
        $CE_history{$CE}{$in}{$stem} = "reappeared as isoform $gene";
    }

    push( @{ $CE_gene{$CE} }, "$gene" );
    $gene_CE{$CE} = $CE;
    if ( defined $out ) {
        if ( &multiCoded == 0 ) {
            $CE_live{$CE} = 0;
        }
        $CE_history{$CE}{$out}{$gene} = "removed";    # .= "$out Removed\t";
    }
    else {
        push( @{ $CE_corr_CDS{$CE} }, "$gene" );
    }
    return 1;
}

sub becameIsoform {
    $CE_live{$CE} = 1;
    $CE_history{$CE}{$in}{$gene} = "became isoform to $stem";#.= "$in became isoform to $stem \t";
    &removeGeneCorrCDS($stem);
    push( @{ $CE_gene{$CE} }, "$gene" );
    $gene_CE{$CE} = $CE;
    if ($out) {
        if ( &multiCoded == 0 ) {
            $CE_live{$CE} = 0;
        }
        $CE_history{$CE}{$out}{$gene} = "removed";#.="$out Removed\t";
    }
    else {
        push( @{ $CE_corr_CDS{$CE} }, "$gene" );
    }
    return 1;
}

sub changePepGene {
    $CE_live{$CE} = 1;
    my $oldgene = $CE_gene{$CE};

    #$CE_gene{$CE} = $gene;
    push( @{ $CE_gene{$CE} }, "$gene" );
    $CE_history{$CE}{$in}{$gene} = "reappeared coded by another gene"
      ;    # .= "$in reappeared coded by another gene\t";
    if ($out) {
        if ( &multiCoded == 0 ) {
            $CE_live{$CE} = 0;
        }
        $CE_history{$CE}{$out}{$gene} = "removed";    # .= "$out Removed\t";
    }
    else {
        push( @{ $CE_corr_CDS{$CE} }, "$gene" );
    }
    return 1;
}

sub oldStyleName {
    if ( $gene =~ m/\w+\.\p{IsAlpha}+/ ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub multiCoded {

    # if the peptide is coded by multiple genes returns 1 else 0
    my $loop = 0;
    my $mul  = $CE_corr_CDS{$CE}[0];
    while ( defined( $CE_corr_CDS{$CE}[$loop] ) ) {
        $loop++;
        $mul = $CE_corr_CDS{$CE}[0];
    }
    if ( $loop > 1 ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub removeGeneCorrCDS {
    my $g;
    my $gene_to_remove = shift;
    unless ( defined($gene_to_remove) ) {
        $gene_to_remove = $gene;
    }
    foreach $g ( 0 .. $#{ $CE_corr_CDS{$CE} } ) {
        if ( "$gene_to_remove" eq "$CE_corr_CDS{$CE}[$g]" ) {
            splice( @{ $CE_corr_CDS{$CE} }, $g, 1 );    # remove gene
        }
    }
}

__END__

=pod

=head2 NAME - build_pepace.pl

=head1 USAGE 

=over 4

=item build_pepace.pl

=back

This creates an acefile that can be loaded in to an empty 
database to completely recreate what was pepace. This is based
solely in the wormpep.history file.

build_pepace.pl MANDATORY arguments:

=over 4

=item none

=back

build_pepace.pl  OPTIONAL arguments:

=over 4

=item none

=back

=head1 REQUIREMENTS

=over 4

=item None known.

=back

=head1 AUTHOR

=over 4

=item Anthony Rogers (ar2@sanger.ac.uk)

=back

=cut
