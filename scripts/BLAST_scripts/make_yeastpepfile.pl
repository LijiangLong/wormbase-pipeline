#!/usr/local/ensembl/bin/perl -w
#
# make_yeastpepfile.pl
#
# by Keith Bradnam
# 
# Converts yeastX.pep file to ace file, copies to wormsrv2, adds SGD as Accession field
#
# Last edited by: $Author: mh6 $
# Last edited on: $Date: 2008-01-30 15:12:35 $


use strict;
use Getopt::Long;

my $version;
my $verbose;

GetOptions (
            "version:s"  => \$version,
            "verbose"    => \$verbose,
            );


my $blastdir    = "/lustre/work1/ensembl/wormpipe/BlastDB";
my $acedir      = "/lustre/work1/ensembl/wormpipe/ace_files";
my $source_file = "$blastdir/yeast${version}.pep";
my $acefile     = "$acedir/yeast.ace";
# output initally goes to tmp file
my $pepfile  = "$blastdir/yeast${version}.pep.tmp"; 


# this bit creates a DBM database of ORF => description
use GDBM_File;

my $DB_dir = "/tmp";
# DBM files 
my $ace_info_dbm = "$DB_dir/ace_info.dbm";
my %ACE_INFO;

if( -e $ace_info_dbm ) {  #make sure starting with new dbase
  `rm -f $ace_info_dbm` && die "cant remove $ace_info_dbm: $!\n";
}
my %YEAST_DESC;
tie  (%YEAST_DESC ,'GDBM_File',"$ace_info_dbm", &GDBM_WRCREAT,0777) or die "cant open $ace_info_dbm :$!\n";

# get the latest info
`wget -O $DB_dir/yeast ftp://genome-ftp.stanford.edu/yeast/data_download/gene_registry/registry.genenames.tab`;
open (YEAST , "<$DB_dir/yeast");
my $linecount;
while (<YEAST>) {
  $linecount++;
  chomp;
  my @info = split(/\t/,$_);
  my $desc;
  if("$info[2]" eq "" ) {
    #check $info[3]
    if("$info[3]" ne "" ) {
      $desc = $info[3];
    }
  }
  else {
    $desc = $info[2];
  }
  next unless $desc;
  if( (defined $info[5]) and (defined $desc) ){
    $YEAST_DESC{$info[5]} = "$desc";
    $YEAST_DESC{$info[5]} =~ s/"/'/g;
  }
}

# now extract info from main FASTA file and write ace file
open (SOURCE,"<$source_file");
open (PEP,">$pepfile");
open (ACE,">$acefile");

while (<SOURCE>) {
  if( />/ ) { 
    if (/>(\S+)\s+(\S+)\s+SGDID:(\w+)/) {
      my $ID = $1;
      print ACE "\nProtein : \"SGD:$ID\"\n";
      print ACE "Peptide \"SGD:$ID\"\n";
      print ACE "Species \"Saccharomyces cerevisiae\"\n";
      print ACE "Gene_name  \"$2\"\n";
      print ACE "Database \"SGD\" \"SGD_systematic_name\" \"$ID\"\n";
      print ACE "Database \"SGD\" \"SGDID\" \"$3\"\n";
      print ACE "Description \"$YEAST_DESC{$ID}\"\n" if $YEAST_DESC{"$ID"};

      print ACE "\nPeptide : \"SGD:$ID\"\n"; 	
      
      print PEP "\>$ID\n";
    }
    else {
      print $_;
    }
  }
  else { 
    print PEP $_;
    print ACE $_;
  }
}

close(SOURCE);
close(PEP);
close(ACE);

print "\n$source_file is now converted to $pepfile..\n" if ($verbose);


# Now overwrite source file with newly formatted file
system("mv $pepfile $source_file") && die "Couldn't overwrite original peptide file\n";


untie %YEAST_DESC;
exit(0);

