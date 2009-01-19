#!/usr/local/ensembl/bin/perl -w

use lib $ENV{'CVS_DIR'};

use strict;
use Getopt::Long;
use GDBM_File;
use Wormbase;
use Log_files;

my $verbose;
my $list_all;
my $output;
my $species;
my ($store, $test, $debug);

GetOptions ( "verbose"   => \$verbose,
	     "list=s"    => \$list_all,
	     "output=s"  => \$output,
	     "species=s" => \$species,
	     "store:s"   => \$store,
	     "test"      => \$test,
	     "debug:s"   => \$debug,
	   );

my $wormbase;
if ( $store ) {
  $wormbase = Storable::retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
                             -test    => $test,
			     );
}

my $log = Log_files->make_build_log($wormbase);

my $wormpipe_dump = $wormbase->farm_dump;
my $acc2db   = "$wormpipe_dump/acc2db.dbm";
my $desc     = "$wormpipe_dump/desc.dbm";
my $peptide  = "$wormpipe_dump/peptide.dbm";
my $database = "$wormpipe_dump/databases.dbm";

my @ipi_hits_files = glob("$wormpipe_dump/*ipi_hits_list_x $wormpipe_dump/*ipi_hits_list");

$list_all = "$wormpipe_dump/ipi_hits_all" unless $list_all;
$output   = "$wormpipe_dump/ipi_hits.ace" unless $output;

my $flat_files = join (" ",@ipi_hits_files);

system("cat $flat_files | sort -u > $list_all");


unless (-s "$acc2db" and -s "$desc"  and -s "$peptide") {
  $log->log_and_die("problem with the dbm files - expecting :\n$acc2db\n$desc\n$peptide\n\n");
}

# These databases are written by parse_SWTREns_proteins.pl whenever a new data set is used
tie my %ACC2DB,'GDBM_File', "$acc2db",&GDBM_WRCREAT,     0666 or $log->log_and_die("cannot open $acc2db\n");
tie my %DESC,'GDBM_File', "$desc",&GDBM_WRCREAT,         0666 or $log->log_and_die("cannot open DBM file $desc\n");
tie my %PEPTIDE,'GDBM_File', "$peptide",&GDBM_WRCREAT,   0666 or $log->log_and_die("cant open DBM file $peptide\n");
tie my %DATABASE,'GDBM_File', "$database",&GDBM_WRCREAT, 0666 or $log->log_and_die("cant open DBM file $database\n");

# These are a couple of helper data sets to add in swissprot ids and SWALL / ENSEMBL gene names

my %swiss_id2gene;
my %acc2id;
&getSwissGeneName(\%swiss_id2gene, \%acc2id);

my %ENSpep_gene;  
#&makeENSgenes( \%ENSpep_gene);

# This list is of the proteins to dump - generated by Dump_new_prot_only.pl during the dumping of similarity data
open (LIST, "<$list_all") or die "cant open $list_all\n";
open (ACE, ">$output") or die "cant open $output\n";

# Description goes in "Title" field for old style model 
my $title_desc = "Description";

while (<LIST>) {
  chomp;
  my $id = $_;
  my $prefix = $ACC2DB{$id};
  if( $prefix ) {
    print ACE "\nProtein : \"$prefix:$id\"\n";
    print ACE "Peptide \"$prefix:$id\"\n";
    print ACE "$title_desc \"$DESC{$id}\"\n" if $DESC{$id};
    print ACE "Species \"Homo sapiens\"\n";
  
    # write database lines
    my @databases = split (/\s+/,$DATABASE{$id}) if ( $DATABASE{$id} );

    # this is for new protein model

    # SwissProt_ID
    # SwissProt_AC
    # TrEMBL_AC
    # FlyBase_gn
    # Gadfly_ID
    # SGD_systematic
    # SGDID
    # ENSEMBL_geneID
    # ENSEMBL_proteinID
    # WORMPEP_ID 

    foreach (@databases) {
      my ($DB,$ID) = split(/:/, $_);
      if( "$DB" eq "ENSEMBL" ){
	print ACE "Database ENSEMBL ENSEMBL_proteinID $ID\n";
	#no longer get gene IDs from ensembl due to change in their fasta header
	print ACE "Database ENSEMBL ENSEMBL_geneID $ENSpep_gene{$ID}\n" if ($ENSpep_gene{$ID});
      }
      elsif( "$DB" eq "SWISS-PROT" or "$DB" eq "TREMBL"){ 
	my $othername = $acc2id{$ID} if $acc2id{$ID};
	print ACE "Database UniProt UniProt_AC $ID\n";
	print ACE "Database UniProt UniProtID $acc2id{$ID}\n" if $acc2id{$ID};

	print ACE "Gene_name \"$swiss_id2gene{$othername}\"\n" if $swiss_id2gene{$othername};

      }
    }

    # This is the same for each
    print ACE "\nPeptide : \"$prefix:$id\"\n";
    print ACE "$PEPTIDE{$id}\n";
  } else {
    print "no prefix for $id\n" if ($verbose);
  }
}

untie %ACC2DB;
untie %DESC;
untie %PEPTIDE;
untie %DATABASE;

$log->mail();

exit(0);

sub getSwissGeneName
  {
    my $s2g = shift;
    my $a2i = shift;    
    open (MF,"/software/pubseq/bin/mfetch -f \"id acc gen\" -i \"org:human\" |") or $log->log_and_die("cant mfetch $!\n");
    my ($id, $acn, $gene, $backup_gene);
    my %counts;
    while (<MF>) {
      #print $_;
      chomp;
      if( /^ID\s+(\S+)/ ) {
	# before we move on to next protein check if the previous one received a gene name
	# if not use $backup_gene from the GN line rather than the Genew one
		unless( $id and $$s2g{$id} ) {
	  		if( $backup_gene ) {
	    		$$s2g{$id} = $backup_gene;
	  		}
	  		else {
	    		print "Can't find a gene (GN field) for $id\n" if ($verbose);
	  		}
		}
		$id = $1;
		undef $acn; undef $gene;undef $backup_gene;
		
		$counts{ids}++;
     }
    elsif( /^AC\s+(\S+);/) {
    	next if $acn; # sometime mfetch return 2 lines of acc
		$acn = $1;
		$acn =~ s/;//g;
		$$a2i{"$acn"} = $id; 
		$counts{acn}++;
	}
    elsif( (/GN\s+Name=(\S+)[\s+\.];$/) || (/GN\s+Name=(\S+);/ )){
		# DR   Genew; HGNC:989; BCL10
		$gene = $1;
		$$s2g{$id} = $gene;
		$counts{genes}++;
	}
   }
    foreach (keys %$s2g ) {
      print "ERROR: \t\t$_\n" unless $$s2g{$_};
    }
    foreach (keys %counts) {
      print "$_ $counts{$_}\n";
    }
  }

sub makeENSgenes 
  {
    my $p2g = shift;
    open (ENS, "/usr/local/ensembl/bin/getz -f \"ID Gene\" \"[ensemblpep_human-ID:*]\" | ");
    #>ENSP00000329982 pep:known chromosome:NCBI35:1:660959:661897:-1 gene:ENSG00000185097 transcript:ENST00000332831
    #>ENSP00000263506 pep:novel chromosome:NCBI35:1:16764182:16779878:-1 gene:ENSG00000116219 transcript:ENST00000263506
    while (<ENS>) {
      if( />(ENSP\d+).*gene:(ENSG\d+)/ ) {
	$$p2g{$1} = $2;
      }
    }
  }
