#!/nfs/team71/worm/mh6/bin/perl
#===============================================================================
#
#         FILE:  fix_gff.pl
#
#        USAGE:  ./fix_gff.pl
#
#  DESCRIPTION:  to fix gffs with interpolated map positions
#
#      OPTIONS:  -help, -test, -debug USER, -snps, -genes, -clones, -all, -store FILE
# REQUIREMENTS:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  $Author: mh6 $
#      COMPANY:
#      VERSION:  1.0
#      CREATED:  13/02/06 09:37:00 GMT
#     REVISION:  $Revision: 1.31 $
# includes code by: $Author: mh6 $
#===============================================================================

# BACS / SNPS / GENEs

use strict;
use lib $ENV{'CVS_DIR'};
use Modules::Physical_map;
use Wormbase;
use Getopt::Long;
use IO::File;
use File::Basename;

my $errors = 0;    # store globally errors

my $args = "@ARGV";    #to store the argv
my (
    $store,  $test, $prep, $debug,    $alleles, $genes,
    $clones, $all,  $help, $wormbase, $chromosome, $gff3,
);                     #options

GetOptions(
    'help'         => \$help,
    'test'         => \$test,
    'debug:s'      => \$debug,
    'alleles'      => \$alleles,
    'genes'        => \$genes,
    'clones'       => \$clones,
    'all'          => \$all,
    'store:s'      => \$store,
    'chromosome:s' => \$chromosome,
    'prepare'      => \$prep,
  'gff3'           => \$gff3,
) || die `perldoc $0`;

die `perldoc $0` if $help;

if ($store) {
    $wormbase = Storable::retrieve($store)
      or croak("Can't restore wormbase from $store\n");
}
else { $wormbase = Wormbase->new( -debug => $debug, -test => $test ) }

my $log = Log_files->make_build_log($wormbase) ;# prewarning will be misused in a global way
my ($scriptname) = fileparse($0);
$log->{SCRIPT} = "$scriptname : [$args]";

my $maintainer = $debug ? "$debug\@sanger.ac.uk" : 'All';
my $acedb      = $wormbase->{'autoace'};
my $chromdir   = $wormbase->{'gff_splits'};
my $outdir     = "$acedb/acefiles/";
##############################################################################################
#generate a new mapper based on the files (also needs to point to better gene/gene files)

unlink "$acedb/logs/rev_physicals.yml" if ($prep);

my $mapper = Physical_mapper->new( $acedb, glob("$chromdir/".($wormbase->chromosome_prefix)."*_gene.gff") );

# check the mappings
if ($prep) {
    $mapper->check_mapping( $log, $acedb );
    $mapper->save("$acedb/logs/rev_physicals.yml");

    if ($errors) {
        $log->mail( $maintainer,"ERROR REPORT: interpolate_gff.pl -prepare had $errors ERRORS");
    }
    else { $log->mail( $maintainer, 'BUILD REPORT: interpolate_gff.pl' ) }

    exit(0);
}

###############################################################################################
my $rev_genes = Map_func::get_phys($acedb);    # hash of all rev_map genes

# snp/gene/whatever loop over gff
$log->write_to("\n\ngenerating acefiles:\n");
$log->make_line;

my $cprefix=$wormbase->chromosome_prefix();
my @chromosomes = $wormbase->get_chromosome_names(-prefix => 1);
@chromosomes = ( "${cprefix}${chromosome}", ) if $chromosome;

# specifies the Allele Methods, that should get parsed/dumped/interpolated
my @alleMethods = ('Allele','Deletion_allele','Insertion_allele','Deletion_and_Insertion_allele','Substitution_allele','Transposon_insertion');

foreach my $chrom (@chromosomes) {
###################################################################################
    # $chrom,$chromdir,$snps,$genes,$clones,$rev_genes
    #
    # hmm .... log?
    #
    # SHOULD really go into a method/function
    #

    # Input files
    my @data;
    @data = @alleMethods if ( $alleles || $all );
    push( @data, 'gene' )      if ( $genes  || $all );
    push( @data, 'clone_acc' ) if ( $clones || $all );
    foreach my $file (@data) {
        $file = "$chromdir/${chrom}_$file.gff";
        $chrom =~ /$cprefix(.*)$/;

        &dump_alleles( $wormbase, $1 ) if ( $alleles && ( !-e $file ) );

        my $fh = IO::File->new( $file, "r" ) || ( $log->write_to("cannot find: $file\n") && next );
        $file =~ /${chrom}_(allele|gene|clone)/;    # hmpf
        my $of = IO::File->new("> $outdir/interpolated_$1_$chrom.ace");

        $log->write_to("writing to: interpolated_$1_$chrom.ace\n");

        while (<$fh>) {
            next if /\#/;
            s/\"//g;
            my @fields = split(/\t+/, $_);

            my ( $chr, $source, $feature) = ( $fields[0], $fields[1], $fields[2]);

            my ($id, $ctag);
            if ($gff3) {              
              my ($first) = split(/;/, $fields[8]);
              ($ctag, $id) = $first =~ /^ID:(\S+):(\S+)/;
            } else {
              ($ctag, $id) = $fields[8] =~ /^(\S+)\s+(\S+)/;
            }

            my $class;
            if ( $source eq 'Genomic_canonical' && $feature eq 'region' ) {
                $class = 'Sequence';
            }
            elsif ( $source eq 'Allele' && $ctag eq 'Variation' ) {
                $class = 'Variation';
            }
            elsif ( $source eq 'gene' && $feature eq 'gene' ) {
                $class = 'Gene';
                next if $rev_genes ->{$id}    # need to check for existing reverse maps for genes
            }
            else { next }

            my $pos = ( $fields[3] + $fields[4] ) / 2;    # average map position
            my $aceline = $mapper->x_to_ace( $id, $pos, $chr, $class );

            print $of $aceline if $aceline ; # mapper returns undef if it cannot be mapped (like on the telomers)
            $log->write_to( "cannot map $class : $id (might be on a telomer) - phys.pos $chr : $pos\n"
            ) if ( !$aceline );    #--
        }

        close $of;
        close $fh;
    }
}
###########################################################################################
$log->mail();

exit 0;

###############################
# only takes Genes
# if it is supposed to take Variation alleles too, uncomment the 2 lines
sub dump_alleles {
    my ( $wormbase, $chromosome ) = @_;

    my $meth=join(',',@alleMethods);
    my $cmd = "GFF_method_dump.pl -database ".$wormbase->autoace." -method $meth -dump_dir ".$wormbase->autoace."/GFF_SPLITS -chromosome ${cprefix}${chromosome} -giface ${\$wormbase->giface}";
    $wormbase->run_script($cmd);
}

package Log_files;

sub make_line {
    my ($self) = @_;
    $self->write_to("-----------------------------------\n");
}

package Physical_mapper;

sub x_to_ace {
    my ( $self, $id, $map, $chr, $x ) = @_;
    $chr =~ s/$cprefix//;
    my $mpos = $self->map( $map, $chr );
    if ($mpos) {
        return "$x : \"$id\"\nInterpolated_map_position \"$chr\" $mpos\n\n";
    }
}

sub save {
	my($self,$file)=@_;
	YAML::DumpFile( $file, %{$self->{pmap}} );
}

sub check_mapping {
    my ( $self, $logger, $acedir ) = @_;

    # print it to some dark place
    my $revh = IO::File->new( "$acedir/logs/rev_phys.log", "w" );
    $logger->write_to("writing genetic map fixes to $acedir/acefiles/genetic_map_fixes.ace\n");
    my $acefile = IO::File->new("$acedir/acefiles/genetic_map_fixes.ace",'w');
    $logger->write_to("have a look at $acedir/logs/rev_phys.log to resolve:\n");
    $logger->make_line;

    foreach my $key ( keys %{ $self->{pmap} } ) {    # chromosomes

        ## Gary's code ##
        # need to build a @genes list [chromosome,ppos,gpos,geneid]

        my @genes;

          foreach my $i ( @{ $self->{smap}->{$key} } )
          {    # sorted pmap positions of the chromosome
            push @genes,
            (
                [
                    $key,
                    $i,
                    $self->{pmap}->{$key}->{$i}->[0],
                    $self->{pmap}->{$key}->{$i}->[1],
                    $self->{pmap}->{$key}->{$i}->[0]
                ]
            )
          }

        # call genetic fix function

        &fix_gmap( \@genes );       

        foreach my $col (@genes) {
          next if $col->[2] == $col->[4];
          $self->{pmap}->{$key}->{ $col->[1] }->[0] = $col->[2]; # change gmap
          my $_chrom = $key;
	  my $_pos   = $col->[2];
	  my $_gene  = $col->[3];

          # create acefile
	  print $acefile "\n";
	  print $acefile "Gene : $_gene\n";
	  print $acefile "Map $_chrom Position $_pos\n";
        }

        ##

        my $last;
        foreach my $i ( @{ $self->{smap}->{$key} } ) {   # sorted pmap positions
            if (
                $last
                && ( $self->{pmap}->{$key}->{$i}->[0] <
                    $self->{pmap}->{$key}->{$last}->[0] )
              )
            {
                print $revh "----------------------------------\n";
                print $revh "$key: $i\t", $self->{pmap}->{$key}->{$i}->[0],
                  "\t", $self->{pmap}->{$key}->{$i}->[1],
                  " ERROR (conflict with last line) \n";
                $logger->write_to( "$key: $i\t"
                      . $self->{pmap}->{$key}->{$i}->[0] . "\t"
                      . $self->{pmap}->{$key}->{$i}->[1]
                      . " ERROR (conflict with last line) \n" );
                print $revh "----------------------------------\n";
                $errors++;
            }
            else {
                print $revh "$key: $i\t", $self->{pmap}->{$key}->{$i}->[0],
                  "\t", $self->{pmap}->{$key}->{$i}->[1], "\n";
            }

            $last = $i;
        }
    }
}

# class functions for Physical_mapper

sub fix_gmap {
    my ($genes) = @_;

    my $changed_in_this_iteration;
    do {
        $changed_in_this_iteration = 0;
        my $prev_chrom = "";
        my $prev_pos;
        my $next_pos;
        for ( my $i = 0 ; $i < @$genes ; $i++ ) {
            my $chrom = $$genes[$i]->[0];
            my $pos   = $$genes[$i]->[2];
            if ( $prev_chrom ne $chrom ) {
                $prev_pos   = $pos;
                $prev_chrom = $chrom;
                next;    # always skip the first gene in the chromosome
            }

            # get the next position
            # are we at the end of the array or end of the chromosome?
            if ( $i + 1 < @$genes && $$genes[ $i + 1 ]->[0] eq $chrom ) {
                $next_pos = $$genes[ $i + 1 ]->[2];
            }
            else {
                $next_pos = $pos + 0.5;
            }

   			# should this position be changed? Test for this position less than previous.
            if ( $prev_pos > $pos ) {

                # get the difference between the previous and next positions
                my $diff = $next_pos - $prev_pos;
                if ( $diff > 0.0005 ) {
                    $$genes[$i]->[2] = $prev_pos + ( $diff / 2 );
                }
                else {
                    $$genes[$i]->[2] = $prev_pos + 0.0005;
                }
                $pos                       = $$genes[$i]->[2];
                $changed_in_this_iteration = 1;
            }

     		# should this position be changed? Test for this position greater than next
            if ( $pos > $next_pos && $next_pos > $prev_pos ) {

                # get the difference between the previous and next positions
                my $diff = $next_pos - $prev_pos;
                if ( $diff > 0.0005 ) {
                    $$genes[$i]->[2] = $prev_pos + ( $diff / 2 );
                }
                else {
                    $$genes[$i]->[2] = $prev_pos + 0.0005;
                }
                $pos                       = $$genes[$i]->[2];
                $changed_in_this_iteration = 1;
            }
            $prev_pos = $pos;
        }
    } while ($changed_in_this_iteration);
}

__END__

=head1 NAME

=head1 DESCRIPTION

creates mapping files in AceDB format for alleles, clones and genes by using 
the physical and genetic position of reference genes.

=head1 USAGE 

=over 2

=item * -prep checks and prepares the reverse physical mapping

=item * -help

=item * -test

=item * -debug NAME

=item * -alleles

=item * -genes

=item * -clones

=item * -all	all of the above snp+genes+clones

=item * -store FILENAME	specifies a stored Wormbase configuration

=item * -chromosome [I II III IV V X] specify ONE chromosome to process

=back 

=head1 DEPENDENCIES

=over 2

=item * Modules::Physical_map

=item * Wormbase

=back 




