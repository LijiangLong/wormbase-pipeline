#!/usr/local/bin/perl5.8.0 -w
#
# inherit_GO_terms.pl
#
# map GO_terms to ?Sequence objects from ?Motif and ?Phenotype
#
# Last updated by: $Author: ar2 $     
# Last updated on: $Date: 2006-06-29 15:40:35 $      

use strict;
use warnings;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use IO::Handle;
use Getopt::Long;
use Ace;

##############################
# Script variables (run)     #
##############################

my ($help, $debug, $motif, $phenotype,$store);
my $verbose;             # for toggling extra output
my $maintainers = "All"; # who receives emails from script
my $noload;              # generate results but do not load to autoace
my $database;

##############################
# command-line options       #
##############################

GetOptions ("help"      => \$help,
            "debug=s"   => \$debug,
			    "phenotype" => \$phenotype,
	   		 "motif"     => \$motif,
	    		"noload"    => \$noload,
    	    	"store:s"   => \$store,
    	    	"database:s" => \$database
    	);

# Display help if required
&usage("Help") if ($help);

# recreate configuration 
my $wb;
if ($store) { $wb = Storable::retrieve($store) or croak("cant restore wormbase from $store\n") }
else { $wb = Wormbase->new( -debug => $debug, -test => $debug, ) }

# Variables Part II (depending on $wb) 
$debug = $wb->debug if $wb->debug;    # Debug mode, output only goes to one user

my $log=Log_files->make_build_log($wb);

##############################
# Paths etc                  #
##############################

my $tace      = $wb->tace;      # tace executable path
my $dbpath    = $database or wb->autoace;                                      # Database path

my $out=$wb->acefiles."/inherited_GO_terms.ace";
open (OUT,">$out");

########################################
# Connect with acedb server            #
########################################

my $db = Ace->connect(-path=>$dbpath,
                      -program =>$tace) || do { print "Connection failure: ",Ace->error; die();};



&motif($db)     if ($motif);
&phenotype($db) if ($phenotype);

close OUT;

##############################
# read acefiles into autoace #
##############################

$wb->load_to_database($dbpath,$out,'inherit_GO_terms', $log) unless ($noload || $debug) ;

##############################
# mail $maintainer report    #
##############################
$log->mail();

##############################
# hasta luego                #
##############################

$db->close;
exit(0);


########################################################################################
####################################   Subroutines   ###################################
########################################################################################

########################################################################################
# motif to sequence mappings                                                           #
########################################################################################

sub motif {
    my $db = shift;
    
    my ($motif,$obj,$term,$protein,$match,$pepobj) = "";
    my (@GO_terms,@pep_homols,@CDS) = "";

    my $i = $db->fetch_many(-query=> 'find Motif "INTERPRO*"');  
    while ($obj = $i->next) {
	$motif = $obj;
	@GO_terms = $obj->GO_term;
	@pep_homols = $obj->Pep_homol;
	
	print "\nMotif : $motif\n";
	foreach $term (@GO_terms) {
	    print "contains GO_term : $term with " . scalar (@pep_homols) . " attached Protein objects\n" if ($debug);
	    
	    foreach $protein (@pep_homols) {
		print "maps to Protein: $protein " if ($debug);
		my $pepobj = $db->fetch(Protein=>$protein);
		@CDS = $pepobj->Corresponding_CDS;
		
		foreach $match (@CDS) {
		    print "== $match\n" if ($debug);
		    print OUT "\nCDS : \"$match\"\nGO_term $term IEA Inferred_automatically\n";
		} # CDS
	    }     # Protein
	}         # GO_term
    }             # Motif object
}

########################################################################################
# phenotype to sequence mappings                                                       #
########################################################################################

sub phenotype {
  my $db = shift;
  
  my $def = &write_phenotype_def;
  my $tm_query = $wb->table_maker_query($dbpath,$def);
  #my $acefile = $wb->acefiles."/inherit_GO_terms.ace";
  #open ACE,">$acefile" or $log->log_and_die("cant write $acefile: $!\n");
  while(<$tm_query>) {
  		s/\"//g;  #remove "
  		next if (/acedb/ or /\/\//);
		my @data = split;
	  	my ($cds, $phenotype,$go) = ($data[0], $data[2], $data[3]);
	  	if($phenotype =~ /WBPheno/) {
	  		$phenotype = &get_phenotype_name($phenotype);
	  	}
	  	else {next;}
  		unless($cds and $phenotype and $go) {
  			$log->write_to("bad data $_");
  			next;
  		}
		print OUT "\nCDS : \"$cds\"\nGO_term \"$go\" IMP Inferred_automatically $phenotype\n" ;
	}
	#close ACE;
	#tidy up
	$wb->run_command("rm -f $def", $log);
}


######################################################################


sub usage {
  my $error = shift;

  if ($error eq "Help") {
    # Normal help menu
    system ('perldoc',$0);
    exit (0);
  }
}

sub get_phenotype_name {
	my $id = shift;
	my $obj = $db->fetch('Phenotype' => $id);
	my $name = $obj->Primary_name;
	return $name or $id;
}

# this will write out an acedb tablemaker defn to a temp file
sub write_phenotype_def {
	my $def = '/tmp/inherit_GO.def';
	open TMP,">$def" or $log->log_and_die("cant write $def: $!\n");
	my $txt = <<END;
Sortcolumn 1

Colonne 1
Width 12
Optional
Visible
Class
Class elegans_CDS
From 1

Colonne 2
Width 12
Mandatory
Visible
Class
Class RNAi
From 1
Tag RNAi_result

Colonne 3
Width 20
Optional
Visible
Class
Class Phenotype
From 2
Tag Phenotype

Colonne 4
Width 12
Null
Visible
Show_Tag
Right_of 3
Tag  HERE  # Not

Colonne 5
Width 12
Mandatory
Visible
Class
Class GO_term
From 3
Tag GO_term
END

	print TMP $txt;
	close TMP;
	return $def;
}

__END__

=pod

=head2   NAME - inherit_GO_terms.pl


=head1 USAGE

=over 4

=item inherit_GO_terms.pl [-options]

=back

inherit_GO_terms.pl assigns GO terms to sequences based on Interpro motifs
and RNAi phenotypes. The resulting acefile will be loaded into the database
as part of the script run (default database is autoace).

inherit_GO_terms.pl mandatory arguments:

=over 4

=item none, (but it won\'t do anything)

=back

inherit_GO_terms.pl OPTIONAL arguments:

=over 4

=item -motif, parse Interpro motif data

=item -phenotype, parse phenotype data

=item -noload, do not upload results to autoace

=item -debug, debug (results not loaded into autoace)

=item -help, help

=item -verbose, toggle extra output to screen

=item -store <storable_file>, specifiy stored commandline options

=back

=cut
