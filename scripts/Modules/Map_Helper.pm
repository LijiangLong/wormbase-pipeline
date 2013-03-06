
package Map_Helper;

use strict;

########################
sub new {
  my $class = shift;

  my $self = {
    _features         => {},
    _indexed_features => {},
  };
  bless $self, $class;

  return $self;
}



# stores genes to a bdb
sub register_segment {
  my ($self, $seq,$start,$end,$strand,$name)=@_;

  my $feats = $self->_features;

  if (exists $feats->{$name}) {
    foreach my $seg (@{$feats->{$name}}) {
      if ($seg->{seq} ne $seq) {
        die "Could feature $name cannot be registered to two different sequences\n";
      } elsif ($seg->{start} <= $end and
               $seg->{end}   >= $start) {
        die "Attempt to register overlapping segments for the same feature $name\n";
      }
    }
  }

  push @{$feats->{$name}}, {
    seq    => $seq,
    start  => $start,
    end    => $end,
    strand => $strand,
    name   => $name,
  };

}

##################################
sub build_index{
  my ($self) = @_;

  my $feats = $self->_features;
  my $indexed_feats = $self->_indexed_features;

  foreach my $fid (keys %$feats) {
    my @segs = sort { $a->{start} <=> $b->{start} } @{$feats->{$fid}};
    $feats->{$fid} = \@segs;

    push @{$indexed_feats->{$segs[0]->{seq}}}, {
      start => $segs[0]->{start},
      end   => $segs[-1]->{end},
      strand => $segs[0]->{strand},
      name   => $fid,
    };
  }

  foreach my $seq (keys %$indexed_feats) {
    my @tmp = sort {$a->{start}<=>$b->{start} or $a->{end} <=> $b->{end}} @{$indexed_feats->{$seq}};
    my $max_end = -1;
    for(my $i=0; $i < scalar(@tmp); $i++) {
      if ($tmp[$i]->{end} > $max_end) {
        $max_end = $tmp[$i]->{end};
      }
      $tmp[$i]->{max_end_left} = $max_end;
    }
    $indexed_feats->{$seq} = \@tmp;
  }
}


#################################
sub search_feature_spans {
  my ($self,$chromosome,$start,$end,$strand)=@_;

  my @list = @{$self->_indexed_features->{$chromosome}}; 
  my @hits = @{$self->_bin_search($chromosome, $start, $end, \@list)};

  if (defined $strand) {
    @hits = grep { $_->{strand} eq $strand } @hits;
  }

  return [map  { $_->{name} } @hits];
}

###############################
sub search_feature_segments {
  my ($self,$chromosome,$start,$end,$strand)=@_;

  my @list; 
  if (exists $self->_indexed_features->{$chromosome}) {
    @list = @{$self->_indexed_features->{$chromosome}} 
  }

  my @hits = @{$self->_bin_search($chromosome, $start, $end, \@list)};


  if (defined $strand) {
    @hits = grep { $_->{strand} eq $strand } @hits;
  }

  my @seg_hits;

  if (@hits) {

    foreach my $hit (@hits) {

      my $match = 0;

     foreach my $seg (@{$self->_features->{$hit->{name}}}) {
       if ($start <= $seg->{end} and $end >= $seg->{start}) {
          $match = 1;
          last;
        }
      }

      if ($match) {
        push @seg_hits, $hit; 
      }
    }
  }

  return [map { $_->{name} } @seg_hits];
  
}


#################################
sub populate_from_GFF {
  my ($self, $file, $method, $type, $name_regexp) = @_;
  
  open(my $fh, $file) or die "Could not open $file for reading\n";

  while(<$fh>) {
    next if /^\#/;
    my @l = split(/\t+/, $_);
    
    next if defined $type and $type ne $l[2];
    next if defined $method and $method ne $l[1];
    
    my ($fid) = ($l[8] =~ /$name_regexp/);
    
    next if not defined $fid;

    $self->register_segment($l[0], $l[3], $l[4], $l[6], $fid); 

  }
}  

#################################
sub _bin_search {
  my ($self, $chromosome, $start, $end, $list) = @_;

  my ($low, $high) = (0, scalar(@$list));
  while($low < $high) {
    my $mid = int(($low + $high) / 2);

    if ($list->[$mid]->{start} <= $end) {
      $low = $mid + 1;
    } else {
      $high = $mid;
    }
  }

  my @hits;
  for(my $i=$low-1; $i >= 0 and $list->[$i]->{max_end_left} >= $start; $i--) {
    if ($start <= $list->[$i]->{end} and $end >= $list->[$i]->{start}) {
      push @hits, $list->[$i];
    }
  }

  return \@hits;
}

##########################
sub _features {
  my ($self) = @_;

  return $self->{_features};
}

##########################
sub _indexed_features {
  my ($self) = @_;

  return $self->{_indexed_features};
}



1;
